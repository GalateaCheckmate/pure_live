import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';

class VideoProcessorService extends GetxService {
  VideoProcessorService._internal();

  static final VideoProcessorService _instance = VideoProcessorService._internal();
  static VideoProcessorService get to => _instance;

  final FFmpegManager _ffmpeg = FFmpegManager.to;
  final StreamController<VideoProcessEvent> _controller = StreamController<VideoProcessEvent>.broadcast();
  final Map<String, StreamSubscription<FFmpegEvent>> _subscriptions = {};
  final Set<String> _processingTasks = {};

  Stream<VideoProcessEvent> get stream => _controller.stream;

  bool isProcessing(String taskId) {
    return _processingTasks.any((key) => key.startsWith('$taskId:'));
  }

  Future<bool> convertToMp4({
    required LiveRecordTask task,
    bool deleteSourceTs = true,
  }) async {
    final taskId = task.taskId;
    final batchId = task.recordingBatchId;
    if (batchId == null || batchId.isEmpty) {
      _emitFailed(taskId, i18n('video_ts_empty'));
      return false;
    }

    final safeBatchId = _safeFilePart(batchId);
    final processKey = '$taskId:$safeBatchId';
    if (!_processingTasks.add(processKey)) return false;

    String? ffmpegTaskId;
    String? operationId;

    try {
      final tsDir = Directory(task.outputDir ?? '');
      if (!tsDir.existsSync()) {
        _emitFailed(taskId, i18n('video_dir_not_exist'));
        return false;
      }

      final filePrefix = '${safeBatchId}_s';
      final files = tsDir
          .listSync()
          .whereType<File>()
          .where((file) {
            final name = p.basename(file.path);
            return name.startsWith(filePrefix) && name.endsWith('.ts') && file.lengthSync() > 0;
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (files.isEmpty) {
        _emitFailed(taskId, i18n('video_ts_empty'));
        return false;
      }

      log('$taskId： ${i18n("video_ts_total", args: {"count": files.length.toString()})}');
      _controller.add(VideoProcessEvent(taskId: taskId, type: VideoProcessEventType.started));

      final listFile = File(p.join(tsDir.path, '${safeBatchId}_list.txt'));
      final buffer = StringBuffer();
      for (final file in files) {
        buffer.writeln("file '${file.path.replaceAll('\\', '/')}'");
      }
      await listFile.writeAsString(buffer.toString(), flush: true);

      final outputPath = p.join(tsDir.path, '$safeBatchId.mp4');
      ffmpegTaskId = _safeFilePart('merge_${taskId}_$safeBatchId');
      operationId = '$ffmpegTaskId:${DateTime.now().microsecondsSinceEpoch}';
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
        '"$outputPath"',
      ].join(' ');

      final completer = Completer<bool>();
      await _subscriptions.remove(ffmpegTaskId)?.cancel();

      _subscriptions[ffmpegTaskId] = _ffmpeg.stream.listen((event) {
        if (event.taskId != ffmpegTaskId || event.operationId != operationId) return;

        switch (event.type) {
          case FFmpegEventType.progress:
            final time = (event.data['time'] ?? 0).toDouble();
            final duration = task.recordedSeconds <= 0 ? 1 : task.recordedSeconds * 1000;
            _controller.add(
              VideoProcessEvent(
                taskId: taskId,
                type: VideoProcessEventType.progress,
                progress: (time / duration).clamp(0.0, 1.0).toDouble(),
              ),
            );
            break;
          case FFmpegEventType.complete:
            _controller.add(
              VideoProcessEvent(
                taskId: taskId,
                type: VideoProcessEventType.completed,
                outputPath: outputPath,
              ),
            );
            if (deleteSourceTs) {
              _deleteBatchFiles(files, listFile, taskId);
            }
            if (!completer.isCompleted) completer.complete(true);
            break;
          case FFmpegEventType.error:
            _emitFailed(taskId, i18n('video_ffmpeg_failed'));
            if (!completer.isCompleted) completer.complete(false);
            break;
          default:
            break;
        }
      });

      await _ffmpeg.start(
        taskId: ffmpegTaskId,
        operationId: operationId,
        command: command,
      );

      return await completer.future.timeout(
        const Duration(hours: 6),
        onTimeout: () {
          _emitFailed(taskId, i18n('timeout'));
          unawaited(_ffmpeg.stop(ffmpegTaskId!, operationId: operationId));
          return false;
        },
      );
    } catch (error, stackTrace) {
      log('Video processing failed: $error', stackTrace: stackTrace);
      _emitFailed(taskId, error.toString());
      return false;
    } finally {
      if (ffmpegTaskId != null) {
        await _subscriptions.remove(ffmpegTaskId)?.cancel();
      }
      _processingTasks.remove(processKey);
    }
  }

  void _deleteBatchFiles(List<File> files, File listFile, String taskId) {
    try {
      log('$taskId： ${i18n("video_delete_temp_files")}');
      for (final file in files) {
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      if (listFile.existsSync()) {
        listFile.deleteSync();
      }
    } catch (error) {
      log('Delete temporary video files failed: $error');
    }
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
