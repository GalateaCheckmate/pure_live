import 'dart:io';
import 'dart:developer';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';

class AudioStreamLoader {
  String? _currentTaskId;
  String? _currentOperationId;
  String? _currentAudioUrl;

  Future<int> _getAvailablePort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (e) {
      log('AudioStreamLoader: 获取空闲端口失败，使用保底端口: $e');
      return 8080;
    }
  }

  void startAudioStream({
    required String remoteStreamUrl,
    required String uniqueId,
    required Function(String audioUrl) onAudioReady,
    Function(FFmpegEvent event)? onFFmpegEvent,
    required String platform,
  }) async {
    await stop();

    final nonce = DateTime.now().microsecondsSinceEpoch;
    final taskId = 'audio_only_${uniqueId}_$nonce';
    final operationId = '$taskId:$nonce';
    _currentTaskId = taskId;
    _currentOperationId = operationId;

    final port = await _getAvailablePort();
    if (!_isCurrent(taskId, operationId)) return;

    final audioUrl = 'http://localhost:$port/live.ts';
    _currentAudioUrl = audioUrl;
    log('AudioStreamLoader: 分配空闲端口 -> $port, URL -> $audioUrl');

    final headers = await FFmpegHeaderFactory.build(platform: platform);
    if (!_isCurrent(taskId, operationId)) return;

    final command = FFmpegCommandBuilder.buildAudioStreamCommand(
      headers: headers,
      remoteStreamUrl: remoteStreamUrl,
      port: port,
    );

    try {
      await FFmpegService.to.start(
        taskId: taskId,
        operationId: operationId,
        command: command,
        onEvent: (event) {
          if (!_isCurrent(taskId, operationId) || event.operationId != operationId) return;
          onFFmpegEvent?.call(event);

          if (event.type == FFmpegEventType.started) {
            log('AudioStreamLoader: FFmpeg 本地服务器已在端口 $port 启动监听');
            onAudioReady(audioUrl);
          } else if (event.type == FFmpegEventType.complete || event.type == FFmpegEventType.error) {
            _clearCurrent(taskId, operationId);
          }
        },
      );
    } catch (e, stackTrace) {
      if (_isCurrent(taskId, operationId)) {
        _clearCurrent(taskId, operationId);
        log('AudioStreamLoader: 启动音频流失败: $e', stackTrace: stackTrace);
      }
    }
  }

  Future<void> stop() async {
    final taskId = _currentTaskId;
    final operationId = _currentOperationId;
    if (taskId == null || operationId == null) return;

    log('AudioStreamLoader: 正在停止任务 -> $taskId');
    _clearCurrent(taskId, operationId);
    await FFmpegService.to.stop(taskId, operationId: operationId);
  }

  bool _isCurrent(String taskId, String operationId) {
    return _currentTaskId == taskId && _currentOperationId == operationId;
  }

  void _clearCurrent(String taskId, String operationId) {
    if (!_isCurrent(taskId, operationId)) return;
    _currentTaskId = null;
    _currentOperationId = null;
    _currentAudioUrl = null;
  }

  String? get currentTaskId => _currentTaskId;
  String? get currentAudioUrl => _currentAudioUrl;
}
