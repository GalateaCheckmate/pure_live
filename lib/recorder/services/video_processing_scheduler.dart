import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

class VideoProcessingScheduler {
  VideoProcessingScheduler._();

  static final VideoProcessingScheduler instance = VideoProcessingScheduler._();

  final Queue<_VideoProcessingJob> _queue = Queue<_VideoProcessingJob>();
  final Set<String> _queuedKeys = <String>{};
  bool _running = false;
  bool _disposed = false;

  int get queuedCount => _queue.length;
  bool get isRunning => _running;

  bool enqueue({
    required LiveRecordTask task,
    required FutureOr<void> Function(bool success) onComplete,
  }) {
    if (_disposed) return false;

    final batchId = task.recordingBatchId;
    if (batchId == null || batchId.isEmpty) return false;

    final key = '${task.taskId}:$batchId';
    if (!_queuedKeys.add(key)) return false;

    _queue.add(
      _VideoProcessingJob(
        key: key,
        task: task.cloneForProcessing(),
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
        bool success = false;
        try {
          success = await VideoProcessorService.to.convertToMp4(task: job.task);
        } catch (error, stackTrace) {
          log(
            'Video processing job failed: $error',
            name: 'VideoProcessingScheduler',
            stackTrace: stackTrace,
          );
        } finally {
          _queuedKeys.remove(job.key);
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
  final LiveRecordTask task;
  final FutureOr<void> Function(bool success) onComplete;

  const _VideoProcessingJob({
    required this.key,
    required this.task,
    required this.onComplete,
  });
}
