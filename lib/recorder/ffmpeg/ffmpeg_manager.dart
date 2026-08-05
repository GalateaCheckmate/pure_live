import 'dart:async';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';

class FFmpegManager {
  FFmpegManager._internal();
  static final FFmpegManager _instance = FFmpegManager._internal();
  static FFmpegManager get to => _instance;

  final StreamController<FFmpegEvent> _eventController = StreamController.broadcast();
  Stream<FFmpegEvent> get stream => _eventController.stream;

  final FFmpegService _ffmpeg = FFmpegService.to;

  Future<void> start({
    required String taskId,
    required String operationId,
    required String command,
  }) async {
    await _ffmpeg.start(
      taskId: taskId,
      operationId: operationId,
      command: command,
      onEvent: _eventController.add,
    );
  }

  Future<void> stop(String taskId, {String? operationId}) async {
    await _ffmpeg.stop(taskId, operationId: operationId);
  }

  bool isRunning(String taskId, {String? operationId}) {
    return _ffmpeg.isRunning(taskId, operationId: operationId);
  }

  FFmpegRecordSession? getSession(String taskId) {
    return _ffmpeg.getSession(taskId);
  }
}
