import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'dart:developer' as developer;
import 'package:open_filex/open_filex.dart';
import 'package:pure_live/common/index.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/services/recorder_task_codec.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';

class RecorderController extends GetxService {
  static RecorderController get to => Get.find<RecorderController>();

  final RecordSettingsController settings = Get.find<RecordSettingsController>();
  final FFmpegManager ffmpeg = FFmpegManager.to;
  final FFmpegScheduler scheduler = FFmpegScheduler.instance;
  final RxList<LiveRecordTask> tasks = <LiveRecordTask>[].obs;

  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _retryTimers = {};
  final Set<String> _pollChecksInFlight = {};
  final Set<String> _startingTasks = {};
  final Map<String, Completer<void>> _lifecycleCompleters = {};
  final Map<String, String> _activeOperationIds = {};
  final Map<String, int> _operationCounters = {};

  Timer? _resourceMonitor;
  Timer? _persistTimer;
  late final StreamSubscription<FFmpegEvent> _ffmpegSub;

  bool _persistInFlight = false;
  bool _persistAgain = false;
  bool _restoring = false;
  bool _disposed = false;

  int get runningCount => scheduler.runningCount;
  int get queuedCount => scheduler.queuedCount;

  @override
  void onInit() {
    super.onInit();
    _resourceMonitor = Timer.periodic(const Duration(seconds: 30), (_) => _checkResources());
    _ffmpegSub = ffmpeg.stream.listen(_onFFmpegEvent);
    unawaited(restoreAndAutoPoll());
  }

  void _onFFmpegEvent(FFmpegEvent event) {
    final task = tasks.firstWhereOrNull((item) => item.taskId == event.taskId);
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
          updateTask(task);
        }
        break;
      case FFmpegEventType.progress:
        final data = event.data;
        task.recordedSeconds = (data['time'] ?? 0) ~/ 1000;
        task.fileSize = data['size'] ?? 0;
        task.bitrate = (data['bitrate'] ?? 0).toDouble();
        task.recordSpeed = (data['speed'] ?? 0).toDouble();
        task.fps = (data['fps'] ?? 0).toDouble();
        task.lastUpdate = DateTime.now();
        updateTask(task);
        break;
      case FFmpegEventType.error:
        final errorMessage = event.data['message'] ?? i18n('unknown_error', args: {'error_log': ''});
        final errorCode = event.data['code'] ?? 0;
        ToastUtil.show(errorMessage);

        final rawLogs = (event.data['raw_logs'] ?? '').toString();
        final fatalError =
            (errorCode >= -5 && errorCode < 0) ||
            errorCode == -2 ||
            rawLogs.contains('404') ||
            rawLogs.contains('403') ||
            rawLogs.contains('invalid argument') ||
            rawLogs.contains('no such file') ||
            rawLogs.contains('permission denied') ||
            rawLogs.contains('unable to open');
        unawaited(
          _onFail(
            task,
            operationId: event.operationId,
            shouldRetry: !fatalError,
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

  void updateTask(LiveRecordTask task) {
    if (_disposed) return;
    final index = tasks.indexWhere((item) => item.taskId == task.taskId);
    if (index == -1) return;

    tasks[index] = task;
    _sortTasks();
    if (!_restoring) schedulePersist();
  }

  void _sortTasks() {
    tasks.value = [...tasks.value]..sort((a, b) => a.status.order.compareTo(b.status.order));
  }

  void schedulePersist() {
    if (_disposed || _restoring) return;
    _persistAgain = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_flushPersist());
    });
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
        await HivePrefUtil.setAnyPref(RecorderKeys.recorderTasksPending, snapshot);

        final current = HivePrefUtil.getString(RecorderKeys.recorderTasks);
        if (current != null && current.isNotEmpty) {
          await HivePrefUtil.setAnyPref(RecorderKeys.recorderTasksBackup, current);
        }

        await HivePrefUtil.setAnyPref(RecorderKeys.recorderTasks, snapshot);
        await HivePrefUtil.remove(RecorderKeys.recorderTasksPending);
      } while (_persistAgain);
    } catch (e, stackTrace) {
      developer.log('Persist recorder tasks failed: $e', name: 'RecorderController', stackTrace: stackTrace);
    } finally {
      _persistInFlight = false;
      if (_persistAgain && !_disposed) {
        unawaited(_flushPersist());
      }
    }
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        if (await Permission.manageExternalStorage.isGranted) return true;
        return (await Permission.manageExternalStorage.request()).isGranted;
      }
      if (await Permission.storage.isGranted) return true;
      return (await Permission.storage.request()).isGranted;
    } catch (e, stackTrace) {
      developer.log('Storage permission request failed: $e', stackTrace: stackTrace);
      return (await Permission.storage.request()).isGranted;
    }
  }

  Future<void> addTask({required LiveRoom room}) async {
    if (!await requestStoragePermission()) {
      ToastUtil.show(i18n('no_storage'));
      return;
    }

    if (tasks.any((task) => task.roomId == room.roomId && task.platform == room.platform)) return;

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
    await _startTask(task);
  }

  Future<void> forceStartTask(LiveRecordTask task) => startTask(task);

  Future<void> _startTask(LiveRecordTask task) async {
    if (_disposed || !tasks.any((item) => item.taskId == task.taskId)) return;
    if (_startingTasks.contains(task.taskId)) {
      ToastUtil.show(i18n('recorder_task_starting'));
      return;
    }
    if (scheduler.isRunning(task.taskId) || scheduler.isQueued(task.taskId)) {
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
    } catch (e, stackTrace) {
      developer.log('启动任务异常: $e', name: 'RecorderController', stackTrace: stackTrace);
      _activeOperationIds.remove(task.taskId);
      task.status = RecordStatus.failed;
      updateTask(task);
      ToastUtil.show(i18n('recorder_start_failed', args: {'error': e.toString()}));
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
    if (!_isOperationActive(task.taskId, operationId) || token.isCancelled) return;

    task.status = RecordStatus.preparing;
    task.recordedSeconds = 0;
    task.fileSize = 0;
    task.recordSpeed = 0;
    task.bitrate = 0;
    task.fps = 0;
    task.lastUpdate = DateTime.now();
    updateTask(task);

    final completer = Completer<void>();
    _lifecycleCompleters[task.taskId] = completer;

    try {
      final url = await StreamResolverService.to.resolveStream(
        roomId: task.roomId,
        platform: task.platform,
        preferredQuality: settings.defaultQuality.value,
      );
      if (!_isOperationActive(task.taskId, operationId) || token.isCancelled) return;

      final dir = await CacheService.to.getRoomDir(
        platform: task.platform,
        nick: task.nick,
        usePinyinForFolder: settings.usePinyinForFolder.value,
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      await _verifyDirectoryWritable(dir);
      if (!_isOperationActive(task.taskId, operationId) || token.isCancelled) return;

      final headers = await FFmpegHeaderFactory.build(platform: task.platform);
      final command = FFmpegCommandBuilder.buildRecordCommand(
        headers: headers,
        url: url,
        outputDir: dir.path,
        segmentTime: settings.segmentTime.value,
        preferBestStream: settings.preferBestStream.value,
        rwTimeout: settings.rwTimeout.value,
        threadQueueSize: settings.threadQueueSize.value,
      );

      task.currentUrl = url;
      task.selectedQuality = settings.defaultQuality.value;
      task.outputDir = dir.path;
      updateTask(task);

      token.onCancel = () async {
        await ffmpeg.stop(task.taskId, operationId: operationId);
        if (!completer.isCompleted) completer.complete();
      };

      await ffmpeg.start(
        taskId: task.taskId,
        operationId: operationId,
        command: command,
      );
      await completer.future;
    } on StreamException catch (e) {
      developer.log('解析失败: ${e.message}', name: 'RecorderController');
      if (!_isOperationActive(task.taskId, operationId) || token.isCancelled) return;

      ToastUtil.show(i18n('recorder_resolve_failed', args: {'name': task.nick, 'error': e.message}));
      if (!e.retryable) {
        task.status = RecordStatus.waitingLive;
        updateTask(task);
        _startPolling(task);
        _completeLifecycle(task.taskId, operationId);
        return;
      }
      await _onFail(task, operationId: operationId);
    } catch (e, stackTrace) {
      developer.log('任务运行异常: $e', name: 'RecorderController', stackTrace: stackTrace);
      if (_isOperationActive(task.taskId, operationId) && !token.isCancelled) {
        ToastUtil.show(i18n('recorder_exception', args: {'name': task.nick, 'error': e.toString()}));
        await _onFail(task, operationId: operationId);
      }
    } finally {
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

  Future<void> _verifyDirectoryWritable(Directory directory) async {
    final probe = File(
      '${directory.path}${Platform.pathSeparator}.pure_live_write_${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  }

  Future<void> stopTask(LiveRecordTask task) async {
    task.wasStoppedByUser = true;
    _stopPolling(task.taskId);
    _cancelRetry(task.taskId);

    final wasScheduled = scheduler.isRunning(task.taskId) || scheduler.isQueued(task.taskId);
    await scheduler.cancel(task.taskId);

    if (!wasScheduled ||
        (task.status != RecordStatus.completed &&
            task.status != RecordStatus.failed &&
            task.status != RecordStatus.processing)) {
      task.status = RecordStatus.stopped;
      _completeLifecycle(task.taskId, _activeOperationIds[task.taskId]);
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
    if (task.status == RecordStatus.processing || task.status == RecordStatus.completed) return;

    try {
      if (task.outputDir != null && task.recordedSeconds > 0) {
        task.status = RecordStatus.processing;
        updateTask(task);
        final processed = await _processVideo(task);
        if (!_isOperationActive(task.taskId, operationId)) return;
        task.status = processed ? RecordStatus.completed : RecordStatus.failed;
      } else {
        task.status = manualStop ? RecordStatus.stopped : RecordStatus.completed;
      }
      task.retryCount = 0;
      updateTask(task);
    } finally {
      _completeLifecycle(task.taskId, operationId);
    }
  }

  Future<void> _onFail(
    LiveRecordTask task, {
    required String operationId,
    bool shouldRetry = true,
  }) async {
    if (!_isOperationActive(task.taskId, operationId)) return;
    _completeLifecycle(task.taskId, operationId);

    if (task.wasStoppedByUser) {
      task.status = RecordStatus.stopped;
      updateTask(task);
      return;
    }

    task.lastFailTime = DateTime.now();
    if (!shouldRetry || !task.autoReconnect || !settings.autoReconnect.value) {
      task.status = RecordStatus.failed;
      task.retryCount = 0;
      updateTask(task);
      return;
    }

    task.retryCount++;
    if (task.retryCount >= settings.maxRetryCount.value) {
      task.status = RecordStatus.waitingLive;
      updateTask(task);
      _startPolling(task);
      return;
    }

    task.status = RecordStatus.reconnecting;
    updateTask(task);
    _cancelRetry(task.taskId);

    _retryTimers[task.taskId] = Timer(_retryDelay(task.retryCount), () {
      _retryTimers.remove(task.taskId);
      if (_disposed || !tasks.any((item) => item.taskId == task.taskId) || task.wasStoppedByUser) return;
      unawaited(_startTask(task));
    });
  }

  Duration _retryDelay(int retryCount) {
    final base = settings.retryDelay.value.clamp(1, 3600);
    if (!settings.enableBackoff.value) return Duration(seconds: base);

    final exponent = (retryCount - 1).clamp(0, 6);
    final seconds = base * (1 << exponent);
    return Duration(seconds: seconds.clamp(base, settings.maxCheckInterval.value.clamp(base, 86400)));
  }

  void _completeLifecycle(String taskId, String? operationId) {
    if (operationId == null || _activeOperationIds[taskId] != operationId) return;
    final completer = _lifecycleCompleters[taskId];
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<bool> _processVideo(LiveRecordTask task) async {
    if (task.outputDir == null) return false;
    try {
      final success = await VideoProcessorService.to.convertToMp4(task: task);
      await settings.refreshCacheSize();
      return success;
    } catch (e, stackTrace) {
      developer.log('解析视频出错: $e', name: 'RecorderController', stackTrace: stackTrace);
      return false;
    }
  }

  void _startPolling(LiveRecordTask task) {
    if (_disposed || !settings.enablePolling.value || task.wasStoppedByUser) return;
    if (_pollTimers.containsKey(task.taskId)) return;

    final interval = Duration(seconds: settings.liveCheckInterval.value.clamp(5, 86400));
    _pollTimers[task.taskId] = Timer.periodic(interval, (_) async {
      if (!_pollChecksInFlight.add(task.taskId)) return;
      try {
        if (_disposed || !tasks.any((item) => item.taskId == task.taskId) || task.wasStoppedByUser) {
          _stopPolling(task.taskId);
          return;
        }

        final room = await Sites.of(task.platform).liveSite.getRoomDetail(
          roomId: task.roomId,
          platform: task.platform,
        );
        if (_disposed || !tasks.any((item) => item.taskId == task.taskId)) return;

        task.updateFromRoom(room);
        updateTask(task);
        if (room.liveStatus == LiveStatus.live) {
          _stopPolling(task.taskId);
          await startTask(task);
        }
      } catch (e) {
        developer.log('Recorder polling failed: $e', name: 'RecorderController');
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

  Future<void> _checkResources() async {
    try {
      final cacheMB = await CacheService.to.getCacheSize();
      final rssMB = ProcessInfo.currentRss / 1024 / 1024;
      final maxMemoryMB = (Platform.numberOfProcessors * 1024).toDouble();
      developer.log(
        'Cache: ${cacheMB.toStringAsFixed(2)} MB | Memory: ${rssMB.toStringAsFixed(2)} MB',
        name: 'RecorderController',
      );

      if (cacheMB > settings.maxCacheMB.value && settings.enableCacheLimit.value) {
        await CacheService.to.enforceLimit(maxMB: settings.maxCacheMB.value.toDouble());
      }
      if (rssMB > maxMemoryMB * 0.9) {
        developer.log('Memory usage too high', name: 'RecorderController');
      }
    } catch (e) {
      developer.log('_checkResources error: $e', name: 'RecorderController');
    }
  }

  Future<void> unRecorder(LiveRecordTask task) async {
    task.wasStoppedByUser = true;
    _stopPolling(task.taskId);
    _cancelRetry(task.taskId);
    await scheduler.cancel(task.taskId);

    final operationId = _activeOperationIds.remove(task.taskId);
    _completeLifecycle(task.taskId, operationId);
    _lifecycleCompleters.remove(task.taskId);
    tasks.removeWhere((item) => item.taskId == task.taskId);
    _sortTasks();
    schedulePersist();
  }

  Future<void> restoreAndAutoPoll() async {
    _restoring = true;
    try {
      final candidates = [
        HivePrefUtil.getString(RecorderKeys.recorderTasks),
        HivePrefUtil.getString(RecorderKeys.recorderTasksPending),
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
        } catch (e, stackTrace) {
          developer.log('Invalid recorder task snapshot: $e', name: 'RecorderController', stackTrace: stackTrace);
        }
      }

      if (restored == null) return;
      for (final task in restored) {
        if (!task.status.isFinished) task.status = RecordStatus.stopped;
      }
      tasks.value = restored;
      _sortTasks();
    } finally {
      _restoring = false;
    }

    schedulePersist();
    if (settings.autoStartOnBoot.value) {
      for (final task in tasks.toList(growable: false)) {
        if (!task.wasStoppedByUser) {
          await refreshTaskStatus(task);
        }
      }
    }
  }

  Future<void> refreshTaskStatus(LiveRecordTask task) async {
    if (_disposed || task.wasStoppedByUser) return;
    try {
      final room = await Sites.of(task.platform).liveSite.getRoomDetail(
        roomId: task.roomId,
        platform: task.platform,
      );
      if (_disposed || !tasks.any((item) => item.taskId == task.taskId)) return;
      task.updateFromRoom(room);
      updateTask(task);
      if (room.liveStatus == LiveStatus.live) {
        await startTask(task);
      } else {
        task.status = RecordStatus.waitingLive;
        updateTask(task);
        _startPolling(task);
      }
    } catch (e) {
      developer.log('Refresh recorder task failed: $e', name: 'RecorderController');
      task.status = RecordStatus.waitingLive;
      updateTask(task);
      _startPolling(task);
    }
  }

  void openFileDir() async {
    final path = settings.recordSavePath.value;
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else if (Platform.isAndroid) {
      await OpenFilex.open(path);
    }
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

    for (final completer in _lifecycleCompleters.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _lifecycleCompleters.clear();
    _activeOperationIds.clear();

    unawaited(_ffmpegSub.cancel());
    unawaited(scheduler.clearAll());
    unawaited(_flushPersist());
    super.onClose();
  }
}
