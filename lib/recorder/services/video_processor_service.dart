import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_storage_snapshot.dart';
import 'package:pure_live/recorder/services/cache_service.dart';

class VideoProcessorService extends GetxService {
  VideoProcessorService._internal();

  static final VideoProcessorService _instance =
      VideoProcessorService._internal();
  static VideoProcessorService get to => _instance;

  static const int _mergeReserveBytes = 512 * 1024 * 1024;

  final FFmpegManager _ffmpeg = FFmpegManager.to;
  final StreamController<VideoProcessEvent> _controller =
      StreamController<VideoProcessEvent>.broadcast();
  final Map<String, StreamSubscription<FFmpegEvent>> _subscriptions = {};
  final Set<String> _processingTasks = {};

  Stream<VideoProcessEvent> get stream => _controller.stream;

  bool isProcessing(String taskId) {
    return _processingTasks.any((key) => key.startsWith('$taskId:'));
  }

  Future<bool> convertToMp4({
    required LiveRecordTask task,
    required int segmentTime,
    required int maxMergeDurationSeconds,
    bool deleteSourceTs = true,
  }) async {
    final batchId = task.recordingBatchId;
    if (batchId == null || batchId.isEmpty) {
      _emitFailed(task.taskId, i18n('video_ts_empty'));
      return false;
    }

    final directory = Directory(task.outputDir ?? '');
    if (!directory.existsSync()) {
      _emitFailed(task.taskId, i18n('video_dir_not_exist'));
      return false;
    }

    final safeBatchId = _safeFilePart(batchId);
    final prefix = '${safeBatchId}_s';
    final files = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) {
          final name = p.basename(file.path);
          try {
            return name.startsWith(prefix) &&
                name.endsWith('.ts') &&
                file.lengthSync() >= 188;
          } catch (_) {
            return false;
          }
        })
        .map(_SegmentFile.fromFile)
        .toList();

    return _convertBatch(
      taskId: task.taskId,
      batchId: safeBatchId,
      directory: directory,
      segments: files,
      segmentTime: segmentTime,
      maxMergeDurationSeconds: maxMergeDurationSeconds,
      deleteSourceTs: deleteSourceTs,
    );
  }

  Future<bool> recoverBatch({
    required RecoverableRecordingBatch batch,
    required int segmentTime,
    required int maxMergeDurationSeconds,
    bool deleteSourceTs = true,
  }) async {
    final segments = <_SegmentFile>[];
    for (final path in batch.tsFilePaths) {
      final file = File(path);
      try {
        if (file.existsSync() && file.lengthSync() >= 188) {
          segments.add(_SegmentFile.fromFile(file));
        }
      } catch (_) {}
    }

    return _convertBatch(
      taskId: 'recovery_${_safeFilePart(batch.batchId)}',
      batchId: _safeFilePart(batch.batchId),
      directory: Directory(batch.directoryPath),
      segments: segments,
      segmentTime: segmentTime,
      maxMergeDurationSeconds: maxMergeDurationSeconds,
      deleteSourceTs: deleteSourceTs,
    );
  }

  Future<bool> _convertBatch({
    required String taskId,
    required String batchId,
    required Directory directory,
    required List<_SegmentFile> segments,
    required int segmentTime,
    required int maxMergeDurationSeconds,
    required bool deleteSourceTs,
  }) async {
    if (segments.isEmpty) {
      _emitFailed(taskId, i18n('video_ts_empty'));
      return false;
    }

    final processKey = '$taskId:$batchId';
    if (!_processingTasks.add(processKey)) return false;

    try {
      segments.sort(_compareSegments);
      final groups = _splitContinuousGroups(
        segments,
        segmentTime: max(1, segmentTime),
        maxMergeDurationSeconds: maxMergeDurationSeconds,
      );
      if (groups.isEmpty) {
        _emitFailed(taskId, i18n('video_ts_empty'));
        return false;
      }

      log(
        '$taskId: ${segments.length} TS files split into ${groups.length} MP4 groups',
        name: 'VideoProcessorService',
      );
      _controller.add(
        VideoProcessEvent(
          taskId: taskId,
          type: VideoProcessEventType.started,
        ),
      );

      var completedGroups = 0;
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        final success = await _convertGroup(
          taskId: taskId,
          batchId: batchId,
          groupIndex: index + 1,
          directory: directory,
          group: group,
          segmentTime: segmentTime,
          deleteSourceTs: deleteSourceTs,
          onProgress: (progress) {
            final overall =
                (completedGroups + progress) / max(1, groups.length);
            _controller.add(
              VideoProcessEvent(
                taskId: taskId,
                type: VideoProcessEventType.progress,
                progress: overall.clamp(0.0, 1.0).toDouble(),
              ),
            );
          },
        );
        if (!success) return false;
        completedGroups++;
      }

      return true;
    } catch (error, stackTrace) {
      log(
        'Video processing failed: $error',
        name: 'VideoProcessorService',
        stackTrace: stackTrace,
      );
      _emitFailed(taskId, error.toString());
      return false;
    } finally {
      _processingTasks.remove(processKey);
    }
  }

  Future<bool> _convertGroup({
    required String taskId,
    required String batchId,
    required int groupIndex,
    required Directory directory,
    required List<_SegmentFile> group,
    required int segmentTime,
    required bool deleteSourceTs,
    required void Function(double progress) onProgress,
  }) async {
    final inputBytes = group.fold<int>(0, (sum, item) => sum + item.length);
    final diskInfo = await CacheService.to.getDiskSpaceInfo(directory.path);
    if (diskInfo != null &&
        diskInfo.availableBytes < inputBytes + _mergeReserveBytes) {
      _emitFailed(taskId, '磁盘剩余空间不足，已保留 TS 临时文件。');
      return false;
    }

    final groupId = groupIndex.toString().padLeft(3, '0');
    final listFile = File(
      p.join(directory.path, '${batchId}_part${groupId}_list.txt'),
    );
    final listBuffer = StringBuffer();
    for (final segment in group) {
      final normalized = segment.file.path
          .replaceAll("'", "'\\''")
          .replaceAll('\\', '/');
      listBuffer.writeln("file '$normalized'");
    }
    await listFile.writeAsString(listBuffer.toString(), flush: true);

    final timeRange = _groupTimeRange(group, segmentTime);
    final finalPath = _uniqueOutputPath(
      directory.path,
      _formatOutputName(timeRange.start, timeRange.end),
    );
    final partialPath = p.setExtension(finalPath, '.partial.mp4');

    final ffmpegTaskId = _safeFilePart(
      'merge_${taskId}_${batchId}_$groupId',
    );
    final operationId =
        '$ffmpegTaskId:${DateTime.now().microsecondsSinceEpoch}';
    final command = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      '"${listFile.path}"',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '"$partialPath"',
    ].join(' ');

    final completer = Completer<bool>();
    await _subscriptions.remove(ffmpegTaskId)?.cancel();

    _subscriptions[ffmpegTaskId] = _ffmpeg.stream.listen((event) {
      if (event.taskId != ffmpegTaskId || event.operationId != operationId) {
        return;
      }

      switch (event.type) {
        case FFmpegEventType.progress:
          final time = (event.data['time'] ?? 0).toDouble();
          final durationMs = max(
            1,
            group.length * max(1, segmentTime) * 1000,
          );
          onProgress((time / durationMs).clamp(0.0, 1.0).toDouble());
          break;
        case FFmpegEventType.complete:
          unawaited(
            _completeGroupSuccess(
              taskId: taskId,
              partialPath: partialPath,
              finalPath: finalPath,
              group: group,
              listFile: listFile,
              deleteSourceTs: deleteSourceTs,
              completer: completer,
            ),
          );
          break;
        case FFmpegEventType.error:
          _emitFailed(taskId, i18n('video_ffmpeg_failed'));
          if (!completer.isCompleted) completer.complete(false);
          break;
        default:
          break;
      }
    });

    try {
      await _ffmpeg.start(
        taskId: ffmpegTaskId,
        operationId: operationId,
        command: command,
      );

      return await completer.future.timeout(
        const Duration(hours: 6),
        onTimeout: () {
          _emitFailed(taskId, i18n('timeout'));
          unawaited(
            _ffmpeg.stop(ffmpegTaskId, operationId: operationId),
          );
          return false;
        },
      );
    } finally {
      await _subscriptions.remove(ffmpegTaskId)?.cancel();
    }
  }

  Future<void> _completeGroupSuccess({
    required String taskId,
    required String partialPath,
    required String finalPath,
    required List<_SegmentFile> group,
    required File listFile,
    required bool deleteSourceTs,
    required Completer<bool> completer,
  }) async {
    try {
      final partial = File(partialPath);
      if (!partial.existsSync() || partial.lengthSync() <= 0) {
        if (!completer.isCompleted) completer.complete(false);
        return;
      }

      final finalFile = await partial.rename(finalPath);
      CacheService.to.noteRecordedVideoBytes(finalFile.lengthSync());

      if (deleteSourceTs) {
        var deletedBytes = 0;
        for (final segment in group) {
          try {
            if (!segment.file.existsSync()) continue;
            deletedBytes += segment.file.lengthSync();
            segment.file.deleteSync();
          } catch (_) {}
        }
        try {
          if (listFile.existsSync()) {
            deletedBytes += listFile.lengthSync();
            listFile.deleteSync();
          }
        } catch (_) {}
        CacheService.to.noteTemporaryBytes(-deletedBytes);
      }

      _controller.add(
        VideoProcessEvent(
          taskId: taskId,
          type: VideoProcessEventType.completed,
          outputPath: finalPath,
        ),
      );
      if (!completer.isCompleted) completer.complete(true);
    } catch (error, stackTrace) {
      log(
        'Finalize MP4 failed: $error',
        name: 'VideoProcessorService',
        stackTrace: stackTrace,
      );
      if (!completer.isCompleted) completer.complete(false);
    }
  }

  List<List<_SegmentFile>> _splitContinuousGroups(
    List<_SegmentFile> files, {
    required int segmentTime,
    required int maxMergeDurationSeconds,
  }) {
    final maxSegments = maxMergeDurationSeconds <= 0
        ? 0
        : max(1, maxMergeDurationSeconds ~/ segmentTime);
    final gapTolerance = Duration(
      seconds: max(segmentTime * 2, segmentTime + 90),
    );
    final groups = <List<_SegmentFile>>[];
    var current = <_SegmentFile>[];

    for (final file in files) {
      var split = false;
      if (current.isNotEmpty) {
        final previous = current.last;
        final hasSessionBoundary = previous.sessionIndex != null &&
            file.sessionIndex != null &&
            file.sessionIndex != previous.sessionIndex;
        final hasIndexGap = previous.sessionIndex != null &&
            file.sessionIndex == previous.sessionIndex &&
            previous.segmentIndex != null &&
            file.segmentIndex != previous.segmentIndex! + 1;
        final hasTimeGap =
            file.modified.difference(previous.modified) > gapTolerance;
        final reachedLimit = maxSegments > 0 && current.length >= maxSegments;
        split = hasSessionBoundary || hasIndexGap || hasTimeGap || reachedLimit;
      }

      if (split) {
        groups.add(current);
        current = <_SegmentFile>[];
      }
      current.add(file);
    }

    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  int _compareSegments(_SegmentFile a, _SegmentFile b) {
    if (a.sessionIndex != null && b.sessionIndex != null) {
      final sessionCompare = a.sessionIndex!.compareTo(b.sessionIndex!);
      if (sessionCompare != 0) return sessionCompare;
      if (a.segmentIndex != null && b.segmentIndex != null) {
        final segmentCompare = a.segmentIndex!.compareTo(b.segmentIndex!);
        if (segmentCompare != 0) return segmentCompare;
      }
    }

    final modifiedCompare = a.modified.compareTo(b.modified);
    if (modifiedCompare != 0) return modifiedCompare;
    return a.file.path.compareTo(b.file.path);
  }

  _TimeRange _groupTimeRange(List<_SegmentFile> group, int segmentTime) {
    final first = group.first;
    final last = group.last;
    final start = first.timestampFromName ??
        first.modified.subtract(Duration(seconds: max(1, segmentTime)));
    final estimatedEnd = start.add(
      Duration(seconds: max(1, segmentTime) * group.length),
    );
    final end = last.modified.isAfter(estimatedEnd)
        ? last.modified
        : estimatedEnd;
    return _TimeRange(start: start, end: end);
  }

  String _formatOutputName(DateTime start, DateTime end) {
    String two(int value) => value.toString().padLeft(2, '0');
    String date(DateTime value) =>
        '${value.year}${two(value.month)}${two(value.day)}';
    String time(DateTime value) =>
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';

    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '${date(start)}_${time(start)}-${time(end)}.mp4';
    }
    return '${date(start)}_${time(start)}-${date(end)}_${time(end)}.mp4';
  }

  String _uniqueOutputPath(String directory, String fileName) {
    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(directory, fileName);
    var suffix = 2;
    while (File(candidate).existsSync() ||
        File(p.setExtension(candidate, '.partial.mp4')).existsSync()) {
      candidate = p.join(
        directory,
        '${baseName}_${suffix.toString().padLeft(2, '0')}$extension',
      );
      suffix++;
    }
    return candidate;
  }

  void _emitFailed(String taskId, String message) {
    if (_controller.isClosed) return;
    _controller.add(
      VideoProcessEvent(
        taskId: taskId,
        type: VideoProcessEventType.failed,
        error: message,
      ),
    );
  }

  static String _safeFilePart(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'recording' : sanitized;
  }

  @override
  void onClose() {
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_controller.close());
    super.onClose();
  }
}

class _SegmentFile {
  final File file;
  final int length;
  final DateTime modified;
  final int? sessionIndex;
  final int? segmentIndex;
  final DateTime? timestampFromName;

  const _SegmentFile({
    required this.file,
    required this.length,
    required this.modified,
    required this.sessionIndex,
    required this.segmentIndex,
    required this.timestampFromName,
  });

  factory _SegmentFile.fromFile(File file) {
    final name = p.basename(file.path);
    final sequence = RegExp(
      r'_s(\d{3})_(\d{5})\.ts$',
      caseSensitive: false,
    ).firstMatch(name);
    final timestamp = RegExp(
      r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.ts$',
      caseSensitive: false,
    ).firstMatch(name);

    DateTime? parsedTimestamp;
    if (timestamp != null) {
      try {
        parsedTimestamp = DateTime(
          int.parse(timestamp.group(1)!),
          int.parse(timestamp.group(2)!),
          int.parse(timestamp.group(3)!),
          int.parse(timestamp.group(4)!),
          int.parse(timestamp.group(5)!),
          int.parse(timestamp.group(6)!),
        );
      } catch (_) {}
    }

    return _SegmentFile(
      file: file,
      length: file.lengthSync(),
      modified: file.lastModifiedSync(),
      sessionIndex:
          sequence == null ? null : int.tryParse(sequence.group(1)!),
      segmentIndex:
          sequence == null ? null : int.tryParse(sequence.group(2)!),
      timestampFromName: parsedTimestamp,
    );
  }
}

class _TimeRange {
  final DateTime start;
  final DateTime end;

  const _TimeRange({required this.start, required this.end});
}

class VideoProcessEvent {
  final String taskId;
  final VideoProcessEventType type;
  final double progress;
  final String? outputPath;
  final String? error;

  const VideoProcessEvent({
    required this.taskId,
    required this.type,
    this.progress = 0,
    this.outputPath,
    this.error,
  });
}

enum VideoProcessEventType { started, progress, completed, failed }
