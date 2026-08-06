import 'dart:async';
import 'dart:collection';
import 'dart:developer';

import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_storage_snapshot.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

class VideoProcessingScheduler {
  VideoProcessingScheduler._();

  static final VideoProcessingScheduler instance =
      VideoProcessingScheduler._();

  final Queue<_VideoProcessingJob> _queue = Queue<_VideoProcessingJob>();
  final Set<String> _queuedKeys = <String>{};
  bool _running = false;
  bool _disposed = false;

  int get queuedCount => _queue.length;
  bool get isRunning => _running;

  bool enqueue({
    required LiveRecordTask task,
    required int segmentTime,
    required int maxMergeDurationSeconds,
    required FutureOr<void> Function(bool success) onComplete,
  }) {
    final batchId = task.recordingBatchId;
    final directoryPath = task.outputDir;
    if (_disposed ||
        batchId == null ||
        batchId.isEmpty ||
        directoryPath == null ||
        directoryPath.isEmpty) {
      return false;
    }

    final key = '${task.taskId}:$batchId';
    return _enqueueJob(
      key: key,
      directoryPath: directoryPath,
      runner: () => VideoProcessorService.to.convertToMp4(
        task: task.cloneForProcessing(),
        segmentTime: segmentTime,
        maxMergeDurationSeconds: maxMergeDurationSeconds,
      ),
      onComplete: onComplete,
    );
  }

  bool enqueueRecovery({
    required RecoverableRecordingBatch batch,
    required int segmentTime,
    required int maxMergeDurationSeconds,
    FutureOr<void> Function(bool success)? onComplete,
  }) {
    if (_disposed || batch.tsFilePaths.isEmpty) return false;

    final key = 'recovery:${batch.directoryPath}:${batch.batchId}';
    return _enqueueJob(
      key: key,
      directoryPath: batch.directoryPath,
      runner: () => VideoProcessorService.to.recoverBatch(
        batch: batch,
        segmentTime: segmentTime,
        maxMergeDurationSeconds: maxMergeDurationSeconds,
      ),
      onComplete: onComplete ?? (_) {},
    );
  }

  bool _enqueueJob({
    required String key,
    required String directoryPath,
    required Future<bool> Function() runner,
    required FutureOr<void> Function(bool success) onComplete,
  }) {
    if (!_queuedKeys.add(key)) return false;

    final owner = 'video-processing:$key';
    CacheService.to.protectPath(directoryPath, owner);
    _queue.add(
      _VideoProcessingJob(
        key: key,
        directoryPath: directoryPath,
        protectionOwner: owner,
        runner: runner,
        onComplete: onComplete,
      ),
    );
    unawaited(_drain());
    return true;
  }

  Future<void> _drain() async {
    if (_running || _disposed) return;
    _running = true;

    try {
      while (_queue.isNotEmpty && !_disposed) {
        final job = _queue.removeFirst();
        var success = false;
        try {
          success = await job.runner();
        } catch (error, stackTrace) {
          log(
            'Video processing job failed: $error',
            name: 'VideoProcessingScheduler',
            stackTrace: stackTrace,
          );
        } finally {
          _queuedKeys.remove(job.key);
          CacheService.to.releasePath(
            job.directoryPath,
            job.protectionOwner,
          );
        }

        try {
          await job.onComplete(success);
        } catch (error, stackTrace) {
          log(
            'Video processing completion callback failed: $error',
            name: 'VideoProcessingScheduler',
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _running = false;
      if (_queue.isNotEmpty && !_disposed) {
        unawaited(_drain());
      }
    }
  }

  void clearPending() {
    for (final job in _queue) {
      _queuedKeys.remove(job.key);
      CacheService.to.releasePath(
        job.directoryPath,
        job.protectionOwner,
      );
    }
    _queue.clear();
  }

  void dispose() {
    _disposed = true;
    clearPending();
  }
}

class _VideoProcessingJob {
  final String key;
  final String directoryPath;
  final String protectionOwner;
  final Future<bool> Function() runner;
  final FutureOr<void> Function(bool success) onComplete;

  const _VideoProcessingJob({
    required this.key,
    required this.directoryPath,
    required this.protectionOwner,
    required this.runner,
    required this.onComplete,
  });
}
