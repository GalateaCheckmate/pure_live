import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/recorder_task_codec.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:pure_live/recorder/services/video_processing_scheduler.dart';

class RecorderController extends GetxService {
  static RecorderController get to => Get.find<RecorderController>();

  static const int _diskWarningBytes = 5 * 1024 * 1024 * 1024;
  static const int _diskCriticalBytes = 1 * 1024 * 1024 * 1024;

  final RecordSettingsController settings =
      Get.find<RecordSettingsController>();
  final FFmpegManager ffmpeg = FFmpegManager.to;
  final FFmpegScheduler scheduler = FFmpegScheduler.instance;
  final VideoProcessingScheduler processingScheduler =
      VideoProcessingScheduler.instance;
  final RxList<LiveRecordTask> tasks = <LiveRecordTask>[].obs;

  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _retryTimers = {};
  final Set<String> _pollChecksInFlight = {};
  final Set<String> _startingTasks = {};
  final Set<String> _watchdogRecovering = {};
  final Set<String> _lowDiskStoppedTasks = {};
  final Set<String> _warnedDiskRoots = {};
  final Map<String, Completer<void>> _lifecycleCompleters = {};
  final Map<String, String> _activeOperationIds = {};
  final Map<String, int> _operationCounters = {};
  final Map<String, DateTime> _lastProgressUiUpdate = {};
  final Map<String, DateTime> _lastProgressPersist = {};
  final Map<String, Queue<String>> _streamCandidates = {};
  final Map<String, int> _streamCandidateTotals = {};

  Timer? _resourceMonitor;
  Timer? _persistTimer;
  late final StreamSubscription<FFmpegEvent> _ffmpegSub;

  bool _persistInFlight = false;
  bool _persistAgain = false;
  bool _restoring = false;
  bool _disposed = false;
  bool _resourceCheckInFlight = false;

  int get runningCount => scheduler.runningCount;
  int get queuedCount => scheduler.queuedCount;
  int get processingQueuedCount => processingScheduler.queuedCount;

  @override
  void onInit() {
    super.onInit();
    _resourceMonitor = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_resourceCheckInFlight) unawaited(_checkResources());
    });
    _ffmpegSub = ffmpeg.stream.listen(_onFFmpegEvent);
    unawaited(restoreAndAutoPoll());
  }

  void _onFFmpegEvent(FFmpegEvent event) {
    final task = tasks.firstWhereOrNull(
      (item) => item.taskId == event.taskId,
    );
    if (task == null) return;

    final activeOperationId = _activeOperationIds[event.taskId];
    if (event.operationId.isEmpty || event.operationId != activeOperationId) {
      developer.log(
        'Ignoring stale FFmpeg event for ${event.taskId}: ${event.operationId}',
        name: 'RecorderController',
      );
      return;
    }

    switch (event.type) {
      case FFmpegEventType.started:
        if (!task.wasStoppedByUser) {
          task.status = RecordStatus.running;
          task.lastUpdate = DateTime.now();
          updateTask(task);
        }
        break;
      case FFmpegEventType.progress:
        final previousFileSize = task.fileSize;
        final data = event.data;
        task.applyProgress(
          seconds: (data['time'] ?? 0) ~/ 1000,
          sessionFileSize: data['size'] ?? 0,
          currentBitrate: (data['bitrate'] ?? 0).toDouble(),
          speed: (data['speed'] ?? 0).toDouble(),
          currentFps: (data['fps'] ?? 0).toDouble(),
        );
        final growth = task.fileSize - previousFileSize;
        if (growth > 0) CacheService.to.noteTemporaryBytes(growth);
        _publishProgress(task);
        break;
      case FFmpegEventType.error:
        final errorMessage = event.data['message'] ??
            i18n('unknown_error', args: {'error_log': ''});
        ToastUtil.show(errorMessage);
        unawaited(
          _onFail(
            task,
            operationId: event.operationId,
            shouldRetry: event.data['retryable'] != false,
          ),
        );
        break;
      case FFmpegEventType.complete:
        unawaited(
          _onComplete(
            task,
            operationId: event.operationId,
            manualStop: event.data['manualStop'] == true,
          ),
        );
        break;
      default:
        break;
    }
  }

  void updateTask(
    LiveRecordTask task, {
    bool sort = true,
    bool persist = true,
  }) {
    if (_disposed) return;
    final index = tasks.indexWhere((item) => item.taskId == task.taskId);
    if (index == -1) return;

    tasks[index] = task;
    if (sort) _sortTasks();
    if (persist && !_restoring) schedulePersist();
  }

  void _publishProgress(LiveRecordTask task) {
    final now = DateTime.now();
    final lastUi = _lastProgressUiUpdate[task.taskId];
    if (lastUi == null ||
        now.difference(lastUi) >= const Duration(seconds: 1)) {
      _lastProgressUiUpdate[task.taskId] = now;
      updateTask(task, sort: false, persist: false);
    }

    final lastPersist = _lastProgressPersist[task.taskId];
    if (lastPersist == null ||
        now.difference(lastPersist) >= const Duration(seconds: 15)) {
      _lastProgressPersist[task.taskId] = now;
      schedulePersist(delay: Duration.zero);
    }
  }

  void _sortTasks() {
    tasks.value = [...tasks.value]
      ..sort((a, b) => a.status.order.compareTo(b.status.order));
  }

  void schedulePersist({
    Duration delay = const Duration(milliseconds: 500),
  }) {
    if (_disposed || _restoring) return;
    _persistAgain = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(delay, () => unawaited(_flushPersist()));
  }

  Future<void> _flushPersist() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (_persistInFlight) {
      _persistAgain = true;
      return;
    }

    _persistInFlight = true;
    try {
      do {
        _persistAgain = false;
        final snapshot = RecorderTaskCodec.encode(tasks);
        await HivePrefUtil.setAnyPref(
          RecorderKeys.recorderTasksPending,
          snapshot,
        );

        final current = HivePrefUtil.getString(RecorderKeys.recorderTasks);
        if (current != null && current.isNotEmpty) {
          await HivePrefUtil.setAnyPref(
            RecorderKeys.recorderTasksBackup,
            current,
          );
        }

        await HivePrefUtil.setAnyPref(RecorderKeys.recorderTasks, snapshot);
        await HivePrefUtil.remove(RecorderKeys.recorderTasksPending);
      } while (_persistAgain);
    } catch (error, stackTrace) {
      developer.log(
        'Persist recorder tasks failed: $error',
        name: 'RecorderController',
        stackTrace: stackTrace,
      );
    } finally {
      _persistInFlight = false;
      if (_persistAgain && !_disposed) unawaited(_flushPersist());
    }
  }

  Future<bool> requestStoragePermission() async => true;

  Future<void> addTask({required LiveRoom room}) async {
    if (tasks.any(
      (task) =>
          task.roomId == room.roomId && task.platform == room.platform,
    )) {
      return;
    }

    final task = LiveRecordTask.fromRoom(room);
    tasks.insert(0, task);
    _sortTasks();
    schedulePersist();

    if (room.liveStatus == LiveStatus.live) {
      await startTask(task);
    } else {
      task.status = RecordStatus.waitingLive;
      updateTask(task);
      _startPolling(task);
    }
  }

  Future<void> startTask(LiveRecordTask task) async {
    task.retryCount = 0;
    task.wasStoppedByUser = false;
    task.beginNewRecordingBatch();
    _clearStreamCandidates(task.taskId);
    await _startTask(task);
  }

  Future<void> forceStartTask(LiveRecordTask task) => startTask(task);

  Future<void> _startTask(LiveRecordTask task) async {
    if (_disposed || !tasks.any((item) => item.taskId == task.taskId)) {
      return;
    }
    if (_startingTasks.contains(task.taskId)) {
      ToastUtil.show(i18n('recorder_task_starting'));
      return;
    }
    if (scheduler.isRunning(task.taskId) ||
        scheduler.isQueued(task.taskId)) {
      ToastUtil.show(i18n('recorder_task_already_running'));
      return;
    }

    _startingTasks.add(task.taskId);
    _stopPolling(task.taskId);
    _cancelRetry(task.taskId);

    final operationId = _nextOperationId(task.taskId);
    _activeOperationIds[task.taskId] = operationId;
    task.status = RecordStatus.queued;
    task.wasStoppedByUser = false;
    updateTask(task);

    try {
      final enqueued = scheduler.enqueue(
        taskId: task.taskId,
        taskRunner: (token) => _runTask(task, token, operationId),
      );
      if (!enqueued) {
        _activeOperationIds.remove(task.taskId);
        task.status = RecordStatus.failed;
        updateTask(task);
      }
    } catch (error, stackTrace) {
      developer.log(
        '启动任务异常: $error',
        name: 'RecorderController',
        stackTrace: stackTrace,
      );
      _activeOperationIds.remove(task.taskId);
      task.status = RecordStatus.failed;
      updateTask(task);
      ToastUtil.show(
        i18n('recorder_start_failed', args: {'error': error.toString()}),
      );
    } finally {
      _startingTasks.remove(task.taskId);
    }
  }

  String _nextOperationId(String taskId) {
    final next = (_operationCounters[taskId] ?? 0) + 1;
    _operationCounters[taskId] = next;
    return '$taskId:$next:${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _isOperationActive(String taskId, String operationId) {
    return !_disposed && _activeOperationIds[taskId] == operationId;
  }

  Future<void> _runTask(
    LiveRecordTask task,
    TaskCancelToken token,
    String operationId,
  ) async {
    if (!_isOperationActive(task.taskId, operationId) ||
        token.isCancelled) {
      return;
    }

    task.beginRecordingSession();
    task.status = RecordStatus.preparing;
    updateTask(task);

    final completer = Completer<void>();
    _lifecycleCompleters[task.taskId] = completer;
    String? protectedPath;
    String? protectionOwner;

    try {
      final url = await _nextStreamUrl(task);
      if (!_isOperationActive(task.taskId, operationId) ||
          token.isCancelled) {
        return;
      }

      final Directory dir;
      if (task.outputDir != null && task.outputDir!.isNotEmpty) {
        dir = Directory(task.outputDir!);
      } else {
        dir = await CacheService.to.getRoomDir(
          platform: task.platform,
          nick: task.nick,
          usePinyinForFolder: settings.usePinyinForFolder.value,
        );
        task.outputDir = dir.path;
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      await _verifyDirectoryWritable(dir);

      final diskInfo = await CacheService.to.getDiskSpaceInfo(dir.path);
      if (diskInfo != null &&
          diskInfo.availableBytes < _diskCriticalBytes) {
        task.status = RecordStatus.failed;
        updateTask(task);
        ToastUtil.show(
          '磁盘剩余空间不足 1 GB，无法开始录制。已有临时文件不会被删除。',
        );
        _completeLifecycle(task.taskId, operationId);
        return;
      }
      if (diskInfo != null &&
          diskInfo.availableBytes < _diskWarningBytes &&
          _warnedDiskRoots.add(diskInfo.rootPath.toLowerCase())) {
        ToastUtil.show(
          '录制磁盘仅剩 ${diskInfo.availableGB.toStringAsFixed(1)} GB，请及时清理空间。',
        );
      }

      if (!_isOperationActive(task.taskId, operationId) ||
          token.isCancelled) {
        return;
      }

      protectedPath = dir.path;
      protectionOwner = 'recording:${task.taskId}:$operationId';
      CacheService.to.protectPath(protectedPath, protectionOwner);

      final headers =
          await FFmpegHeaderFactory.build(platform: task.platform);
      final command = FFmpegCommandBuilder.buildRecordCommand(
        headers: headers,
        url: url,
        outputDir: dir.path,
        recordingBatchId: task.recordingBatchId!,
        sessionIndex: task.recordingSessionIndex,
        segmentTime: settings.segmentTime.value,
        preferBestStream: settings.preferBestStream.value,
        rwTimeout: settings.rwTimeout.value,
        threadQueueSize: settings.threadQueueSize.value,
      );

      task.currentUrl = url;
      task.selectedQuality = settings.defaultQuality.value;
      updateTask(task);

      token.onCancel = () async {
        final hadActiveSession = ffmpeg.isRunning(
          task.taskId,
          operationId: operationId,
        );
        await ffmpeg.stop(task.taskId, operationId: operationId);
        if (!hadActiveSession && !completer.isCompleted) {
          completer.complete();
        }
      };

      await ffmpeg.start(
        taskId: task.taskId,
        operationId: operationId,
        command: command,
      );
      await completer.future;
    } on StreamException catch (error) {
      developer.log(
        '解析失败: ${error.message}',
        name: 'RecorderController',
      );
      if (!_isOperationActive(task.taskId, operationId) ||
          token.isCancelled) {
        return;
      }

      ToastUtil.show(
        i18n(
          'recorder_resolve_failed',
          args: {'name': task.nick, 'error': error.message},
        ),
      );
      if (!error.retryable) {
        task.status = RecordStatus.waitingLive;
        updateTask(task);
        _startPolling(task);
        _completeLifecycle(task.taskId, operationId);
        return;
      }
      await _onFail(task, operationId: operationId);
    } catch (error, stackTrace) {
      developer.log(
        '任务运行异常: $error',
        name: 'RecorderController',
        stackTrace: stackTrace,
      );
      if (_isOperationActive(task.taskId, operationId) &&
          !token.isCancelled) {
        ToastUtil.show(
          i18n(
            'recorder_exception',
            args: {'name': task.nick, 'error': error.toString()},
          ),
        );
        await _onFail(task, operationId: operationId);
      }
    } finally {
      if (protectedPath != null && protectionOwner != null) {
        CacheService.to.releasePath(protectedPath, protectionOwner);
      }
      final current = _lifecycleCompleters[task.taskId];
      if (identical(current, completer)) {
        _lifecycleCompleters.remove(task.taskId);
      }
      if (!completer.isCompleted) completer.complete();
      if (_activeOperationIds[task.taskId] == operationId) {
        _activeOperationIds.remove(task.taskId);
      }
    }
  }

  Future<String> _nextStreamUrl(LiveRecordTask task) async {
    var queue = _streamCandidates[task.taskId];
    if (queue == null || queue.isEmpty) {
      final resolved = await StreamResolverService.to.resolveStreamCandidates(
        roomId: task.roomId,
        platform: task.platform,
        preferredQuality: settings.defaultQuality.value,
      );
      queue = Queue<String>.from(resolved.urls);
      _streamCandidates[task.taskId] = queue;
      _streamCandidateTotals[task.taskId] = queue.length;
    }

    final url = queue.removeFirst();
    final total = _streamCandidateTotals[task.taskId] ?? 1;
    final current = total - queue.length;
    task.selectedLine = '$current/$total';
    return url;
  }

  void _clearStreamCandidates(String taskId) {
    _streamCandidates.remove(taskId);
    _streamCandidateTotals.remove(taskId);
  }

  Future<void> _verifyDirectoryWritable(Directory directory) async {
    final probe = File(
      '${directory.path}${Platform.pathSeparator}.pure_live_write_'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  }

  Future<void> stopTask(LiveRecordTask task) async {
    task.wasStoppedByUser = true;
    _stopPolling(task.taskId);
    _cancelRetry(task.taskId);
    _clearStreamCandidates(task.taskId);

    final wasScheduled = scheduler.isRunning(task.taskId) ||
        scheduler.isQueued(task.taskId);
    await scheduler.cancel(task.taskId);

    if (!wasScheduled ||
        (task.status != RecordStatus.completed &&
            task.status != RecordStatus.failed &&
            task.status != RecordStatus.processing)) {
      task.status = RecordStatus.stopped;
      _completeLifecycle(
        task.taskId,
        _activeOperationIds[task.taskId],
      );
      _activeOperationIds.remove(task.taskId);
      updateTask(task);
    }
  }

  Future<void> _onComplete(
    LiveRecordTask task, {
    required String operationId,
    required bool manualStop,
  }) async {
    if (!_isOperationActive(task.taskId, operationId)) return;
    if (task.status == RecordStatus.processing ||
        task.status == RecordStatus.completed) {
      return;
    }

    task.finalizeCurrentSession();

    if (_lowDiskStoppedTasks.remove(task.taskId)) {
      task.status = RecordStatus.stopped;
      updateTask(task);
      _clearStreamCandidates(task.taskId);
      _completeLifecycle(task.taskId, operationId);
      return;
    }

    final finalStatus =
        manualStop ? RecordStatus.stopped : RecordStatus.completed;
    await _enqueueVideoProcessing(task, finalStatus: finalStatus);
    _clearStreamCandidates(task.taskId);
    _completeLifecycle(task.taskId, operationId);
  }

  Future<void> _onFail(
    LiveRecordTask task, {
    required String operationId,
    bool shouldRetry = true,
  }) async {
    if (!_isOperationActive(task.taskId, operationId)) return;

    task.finalizeCurrentSession();
    _completeLifecycle(task.taskId, operationId);

    if (task.wasStoppedByUser) {
      await _enqueueVideoProcessing(
        task,
        finalStatus: RecordStatus.stopped,
      );
      _clearStreamCandidates(task.taskId);
      return;
    }

    task.lastFailTime = DateTime.now();
    if (!shouldRetry ||
        !task.autoReconnect ||
        !settings.autoReconnect.value) {
      task.retryCount = 0;
      await _enqueueVideoProcessing(
        task,
        finalStatus: RecordStatus.failed,
      );
      _clearStreamCandidates(task.taskId);
      return;
    }

    task.retryCount++;
    if (task.retryCount >= settings.maxRetryCount.value) {
      await _enqueueVideoProcessing(
        task,
        finalStatus: RecordStatus.waitingLive,
      );
      _clearStreamCandidates(task.taskId);
      _startPolling(task);
      return;
    }

    task.status = RecordStatus.reconnecting;
    updateTask(task);
    _cancelRetry(task.taskId);

    _retryTimers[task.taskId] = Timer(
      _retryDelay(task.retryCount),
      () {
        _retryTimers.remove(task.taskId);
        if (_disposed ||
            !tasks.any((item) => item.taskId == task.taskId) ||
            task.wasStoppedByUser) {
          return;
        }
        unawaited(_startTask(task));
      },
    );
  }

  Future<void> _enqueueVideoProcessing(
    LiveRecordTask task, {
    required RecordStatus finalStatus,
  }) async {
    final batchId = task.recordingBatchId;
    if (!task.hasRecordedData ||
        task.outputDir == null ||
        batchId == null ||
        batchId.isEmpty) {
      task.status = finalStatus;
      task.retryCount = 0;
      updateTask(task);
      return;
    }

    final snapshot = task.cloneForProcessing();
    task.status = RecordStatus.processing;
    updateTask(task);

    final enqueued = processingScheduler.enqueue(
      task: snapshot,
      segmentTime: settings.segmentTime.value,
      maxMergeDurationSeconds:
          settings.maxMergeDurationSeconds.value,
      onComplete: (success) async {
        await settings.refreshStorageStats();
        if (_disposed) return;

        final current = tasks.firstWhereOrNull(
          (item) => item.taskId == snapshot.taskId,
        );
        if (current == null ||
            current.recordingBatchId != snapshot.recordingBatchId ||
            current.status != RecordStatus.processing) {
          return;
        }

        current.status = success ? finalStatus : RecordStatus.failed;
        current.retryCount = 0;
        updateTask(current);
      },
    );

    if (!enqueued) {
      task.status = RecordStatus.failed;
      updateTask(task);
    }
  }

  Duration _retryDelay(int retryCount) {
    final base = settings.retryDelay.value.clamp(1, 3600).toInt();
    if (!settings.enableBackoff.value) return Duration(seconds: base);

    final exponent = (retryCount - 1).clamp(0, 6).toInt();
    final maxDelay = settings.maxCheckInterval.value
        .clamp(base, 86400)
        .toInt();
    final seconds = (base * (1 << exponent))
        .clamp(base, maxDelay)
        .toInt();
    return Duration(seconds: seconds);
  }

  void _completeLifecycle(String taskId, String? operationId) {
    if (operationId == null ||
        _activeOperationIds[taskId] != operationId) {
      return;
    }
    final completer = _lifecycleCompleters[taskId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _startPolling(LiveRecordTask task) {
    if (_disposed ||
        !settings.enablePolling.value ||
        task.wasStoppedByUser) {
      return;
    }
    if (_pollTimers.containsKey(task.taskId)) return;

    final interval = Duration(
      seconds: settings.liveCheckInterval.value.clamp(5, 86400).toInt(),
    );
    _pollTimers[task.taskId] = Timer.periodic(interval, (_) async {
      if (!_pollChecksInFlight.add(task.taskId)) return;
      try {
        if (_disposed ||
            !tasks.any((item) => item.taskId == task.taskId) ||
            task.wasStoppedByUser) {
          _stopPolling(task.taskId);
          return;
        }

        final room = await Sites.of(task.platform).liveSite.getRoomDetail(
          roomId: task.roomId,
          platform: task.platform,
        );
        if (_disposed ||
            !tasks.any((item) => item.taskId == task.taskId)) {
          return;
        }

        task.updateFromRoom(room);
        updateTask(task);
        if (room.liveStatus == LiveStatus.live) {
          _stopPolling(task.taskId);
          await startTask(task);
        }
      } catch (error) {
        developer.log(
          'Recorder polling failed: $error',
          name: 'RecorderController',
        );
      } finally {
        _pollChecksInFlight.remove(task.taskId);
      }
    });
  }

  void _stopPolling(String taskId) {
    _pollTimers.remove(taskId)?.cancel();
    _pollChecksInFlight.remove(taskId);
  }

  void _cancelRetry(String taskId) {
    _retryTimers.remove(taskId)?.cancel();
  }

  Future<void> _recoverStalledRecordings() async {
    final stalledTasks = tasks
        .where((task) => task.isStalled)
        .toList(growable: false);
    for (final task in stalledTasks) {
      if (!_watchdogRecovering.add(task.taskId)) continue;

      final operationId = _activeOperationIds[task.taskId];
      if (operationId == null ||
          !scheduler.isRunning(task.taskId) ||
          !ffmpeg.isRunning(task.taskId, operationId: operationId)) {
        _watchdogRecovering.remove(task.taskId);
        continue;
      }

      try {
        developer.log(
          'Recorder watchdog restarting stalled task ${task.taskId}',
          name: 'RecorderController',
        );
        await _onFail(
          task,
          operationId: operationId,
          shouldRetry: true,
        );
        _activeOperationIds.remove(task.taskId);
        await ffmpeg.stop(task.taskId, operationId: operationId);
      } catch (error, stackTrace) {
        developer.log(
          'Recorder watchdog recovery failed: $error',
          name: 'RecorderController',
          stackTrace: stackTrace,
        );
      } finally {
        _watchdogRecovering.remove(task.taskId);
      }
    }
  }

  Future<void> _checkDiskSpaceForRunningTasks() async {
    final checkedDirectories = <String>{};
    for (final task in tasks.where(
      (item) => item.status == RecordStatus.running,
    )) {
      final directory = task.outputDir;
      if (directory == null ||
          directory.isEmpty ||
          !checkedDirectories.add(directory.toLowerCase())) {
        continue;
      }

      final info = await CacheService.to.getDiskSpaceInfo(directory);
      if (info == null) continue;

      if (info.availableBytes >= _diskWarningBytes) {
        _warnedDiskRoots.remove(info.rootPath.toLowerCase());
        continue;
      }

      if (_warnedDiskRoots.add(info.rootPath.toLowerCase())) {
        ToastUtil.show(
          '录制磁盘仅剩 ${info.availableGB.toStringAsFixed(1)} GB。',
        );
      }

      if (info.availableBytes >= _diskCriticalBytes) continue;

      final affected = tasks.where(
        (item) =>
            item.status == RecordStatus.running &&
            item.outputDir != null &&
            item.outputDir!.toLowerCase().startsWith(
                  info.rootPath.toLowerCase(),
                ),
      );
      for (final task in affected) {
        if (!_lowDiskStoppedTasks.add(task.taskId)) continue;
        ToastUtil.show(
          '${task.nick} 因磁盘空间不足已安全停止，TS 临时文件已保留。',
        );
        await scheduler.cancel(task.taskId);
      }
    }
  }

  Future<void> _checkResources() async {
    if (_resourceCheckInFlight || _disposed) return;
    _resourceCheckInFlight = true;

    try {
      await _recoverStalledRecordings();
      await _checkDiskSpaceForRunningTasks();

      final snapshot = await CacheService.to.getStorageSnapshot();
      final rssMB = ProcessInfo.currentRss / 1024 / 1024;
      final maxMemoryMB = (Platform.numberOfProcessors * 1024).toDouble();
      developer.log(
        'Temporary: ${snapshot.temporaryMB.toStringAsFixed(2)} MB | '
        'Recordings: ${snapshot.recordedVideoMB.toStringAsFixed(2)} MB | '
        'Memory: ${rssMB.toStringAsFixed(2)} MB',
        name: 'RecorderController',
      );

      if (snapshot.temporaryMB > settings.maxCacheMB.value &&
          settings.enableCacheLimit.value) {
        await CacheService.to.enforceLimit(
          maxMB: settings.maxCacheMB.value.toDouble(),
        );
        await settings.refreshStorageStats();
      }
      if (rssMB > maxMemoryMB * 0.9) {
        developer.log(
          'Memory usage too high',
          name: 'RecorderController',
        );
      }
    } catch (error) {
      developer.log(
        '_checkResources error: $error',
        name: 'RecorderController',
      );
    } finally {
      _resourceCheckInFlight = false;
    }
  }

  Future<void> unRecorder(LiveRecordTask task) async {
    task.wasStoppedByUser = true;
    _stopPolling(task.taskId);
    _cancelRetry(task.taskId);
    _clearStreamCandidates(task.taskId);
    await scheduler.cancel(task.taskId);

    final operationId = _activeOperationIds[task.taskId];
    _completeLifecycle(task.taskId, operationId);
    _activeOperationIds.remove(task.taskId);
    _lifecycleCompleters.remove(task.taskId);
    _lastProgressUiUpdate.remove(task.taskId);
    _lastProgressPersist.remove(task.taskId);
    _watchdogRecovering.remove(task.taskId);
    _lowDiskStoppedTasks.remove(task.taskId);
    tasks.removeWhere((item) => item.taskId == task.taskId);
    _sortTasks();
    schedulePersist();
  }

  Future<void> restoreAndAutoPoll() async {
    _restoring = true;
    try {
      final candidates = [
        HivePrefUtil.getString(RecorderKeys.recorderTasksPending),
        HivePrefUtil.getString(RecorderKeys.recorderTasks),
        HivePrefUtil.getString(RecorderKeys.recorderTasksBackup),
      ];

      List<LiveRecordTask>? restored;
      for (final candidate in candidates) {
        if (candidate == null || candidate.isEmpty) continue;
        try {
          final decoded = RecorderTaskCodec.decode(candidate);
          if (decoded.isNotEmpty || candidate.trim() == '[]') {
            restored = decoded;
            break;
          }
        } catch (error, stackTrace) {
          developer.log(
            'Invalid recorder task snapshot: $error',
            name: 'RecorderController',
            stackTrace: stackTrace,
          );
        }
      }

      if (restored != null) {
        for (final task in restored) {
          if (!task.status.isFinished) task.status = RecordStatus.stopped;
        }
        tasks.value = restored;
        _sortTasks();
      }
    } finally {
      _restoring = false;
    }

    schedulePersist();
    await _recoverInterruptedRecordings();

    if (settings.autoStartOnBoot.value) {
      for (final task in tasks.toList(growable: false)) {
        if (!task.wasStoppedByUser) {
          await refreshTaskStatus(task);
        }
      }
    }
  }

  Future<void> _recoverInterruptedRecordings() async {
    try {
      final recordDir = await CacheService.to.getRecordDir();
      final disk = await CacheService.to.getDiskSpaceInfo(recordDir.path);
      if (disk != null && disk.availableBytes < _diskCriticalBytes) {
        developer.log(
          'Skipping TS recovery because disk space is below 1 GB',
          name: 'RecorderController',
        );
        return;
      }

      final batches = await CacheService.to.findRecoverableBatches(
        forceScan: true,
      );
      for (final batch in batches) {
        processingScheduler.enqueueRecovery(
          batch: batch,
          segmentTime: settings.segmentTime.value,
          maxMergeDurationSeconds:
              settings.maxMergeDurationSeconds.value,
          onComplete: (_) async {
            await settings.refreshStorageStats();
          },
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Interrupted recording recovery failed: $error',
        name: 'RecorderController',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> refreshTaskStatus(LiveRecordTask task) async {
    if (_disposed || task.wasStoppedByUser) return;
    try {
      final room = await Sites.of(task.platform).liveSite.getRoomDetail(
        roomId: task.roomId,
        platform: task.platform,
      );
      if (_disposed ||
          !tasks.any((item) => item.taskId == task.taskId)) {
        return;
      }
      task.updateFromRoom(room);
      updateTask(task);
      if (room.liveStatus == LiveStatus.live) {
        await startTask(task);
      } else {
        task.status = RecordStatus.waitingLive;
        updateTask(task);
        _startPolling(task);
      }
    } catch (error) {
      developer.log(
        'Refresh recorder task failed: $error',
        name: 'RecorderController',
      );
      task.status = RecordStatus.waitingLive;
      updateTask(task);
      _startPolling(task);
    }
  }

  Future<void> openFileDir() async {
    final path = settings.recordSavePath.value;
    if (path.isEmpty) return;
    await Process.run('explorer.exe', [path]);
  }

  @override
  void onClose() {
    _disposed = true;
    _persistTimer?.cancel();
    _resourceMonitor?.cancel();

    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _pollTimers.clear();
    _retryTimers.clear();
    _pollChecksInFlight.clear();
    _watchdogRecovering.clear();
    _lowDiskStoppedTasks.clear();
    _warnedDiskRoots.clear();
    _lastProgressUiUpdate.clear();
    _lastProgressPersist.clear();
    _streamCandidates.clear();
    _streamCandidateTotals.clear();

    for (final completer in _lifecycleCompleters.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _lifecycleCompleters.clear();
    _activeOperationIds.clear();
    processingScheduler.clearPending();

    unawaited(_ffmpegSub.cancel());
    unawaited(scheduler.clearAll());
    unawaited(_flushPersist());
    super.onClose();
  }
}
