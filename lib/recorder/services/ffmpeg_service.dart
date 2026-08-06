import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:pure_live/plugins/locale_helper.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

class FFmpegRecordSession {
  final String taskId;
  final String operationId;
  int? sessionId;
  bool manualStop = false;
  int recordedSeconds = 0;
  int fileSize = 0;
  double bitrate = 0;
  double speed = 0;
  double fps = 0;
  DateTime lastUpdate = DateTime.now();
  FFmpegSession? session;

  FFmpegRecordSession({required this.taskId, required this.operationId});
}

class FFmpegService {
  FFmpegService._internal();

  static final FFmpegService _instance = FFmpegService._internal();
  static FFmpegService get to => _instance;

  final Map<String, FFmpegRecordSession> _sessions = {};

  static void initInIsolate(RootIsolateToken token) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  Future<void> start({
    required String taskId,
    required String operationId,
    required String command,
    required void Function(FFmpegEvent event) onEvent,
  }) async {
    if (_sessions.containsKey(taskId)) {
      throw StateError('FFmpeg session already active for task $taskId');
    }

    final ffmpegSession = FFmpegKit.createSession(command);
    final session = FFmpegRecordSession(taskId: taskId, operationId: operationId)
      ..session = ffmpegSession
      ..sessionId = ffmpegSession.getSessionId();
    _sessions[taskId] = session;

    onEvent(
      FFmpegEvent(
        taskId: taskId,
        operationId: operationId,
        type: FFmpegEventType.started,
      ),
    );

    ffmpegSession.setStatisticsCallback((statistics) {
      session
        ..recordedSeconds = statistics.time ~/ 1000
        ..fileSize = statistics.size
        ..bitrate = statistics.bitrate
        ..speed = statistics.speed
        ..fps = statistics.videoFps
        ..lastUpdate = DateTime.now();

      onEvent(
        FFmpegEvent(
          taskId: taskId,
          operationId: operationId,
          type: FFmpegEventType.progress,
          data: {
            'time': statistics.time,
            'size': statistics.size,
            'bitrate': statistics.bitrate,
            'speed': statistics.speed,
            'fps': statistics.videoFps,
          },
        ),
      );
    });

    ffmpegSession.setCompleteCallback((completedSession) async {
      final code = completedSession.getReturnCode();
      final isNormalExit = session.manualStop || code == 0;

      log(
        'FFmpeg complete => taskId: $taskId; operationId: $operationId; '
        'code: $code; manual: ${session.manualStop}',
      );

      String userFriendlyMessage = '录制遇到未知错误 (代码: $code)';
      final Map<String, dynamic> eventData = {
        'code': code,
        'manualStop': session.manualStop,
        'retryable': true,
      };

      if (!isNormalExit) {
        try {
          final logs = completedSession.getLogs() ?? '';
          log('FFmpeg 原始错误日志:\n$logs');
          final lowerLogs = logs.toLowerCase();
          eventData['raw_logs'] = lowerLogs;

          if (code == -2 || lowerLogs.contains('no such file') || lowerLogs.contains('permission denied')) {
            userFriendlyMessage = i18n('path_or_permission_error');
            eventData['retryable'] = false;
          } else if (lowerLogs.contains('server returned 404') || lowerLogs.contains('http error 404')) {
            userFriendlyMessage = i18n('url_expired_404');
          } else if (lowerLogs.contains('server returned 403') || lowerLogs.contains('http error 403')) {
            userFriendlyMessage = i18n('url_forbidden_403');
          } else if (lowerLogs.contains('connection timed out') || lowerLogs.contains('timed out')) {
            userFriendlyMessage = i18n('timeout');
          } else if (lowerLogs.contains('invalid argument')) {
            userFriendlyMessage = i18n('param_error');
            eventData['retryable'] = false;
          } else if (lowerLogs.contains('unable to open')) {
            userFriendlyMessage = i18n('invalid_stream_format');
            eventData['retryable'] = false;
          } else if (logs.trim().isNotEmpty) {
            final lastLogLine = logs.trim().split('\n').last;
            userFriendlyMessage = i18n('unknown_error', args: {'error_log': lastLogLine});
          }
        } catch (error) {
          log('解析 FFmpeg 日志时发生异常: $error');
        }
        eventData['message'] = userFriendlyMessage;
      }

      onEvent(
        FFmpegEvent(
          taskId: taskId,
          operationId: operationId,
          type: isNormalExit ? FFmpegEventType.complete : FFmpegEventType.error,
          data: eventData,
        ),
      );

      if (identical(_sessions[taskId], session)) {
        _sessions.remove(taskId);
      }
    });

    try {
      await ffmpegSession.executeAsync();
    } catch (_) {
      if (identical(_sessions[taskId], session)) {
        _sessions.remove(taskId);
      }
      rethrow;
    }
  }

  Future<void> stop(String taskId, {String? operationId}) async {
    final session = _sessions[taskId];
    if (session == null) return;
    if (operationId != null && session.operationId != operationId) return;

    session.manualStop = true;
    final ffmpegSession = session.session;
    if (ffmpegSession == null) return;

    log('FFmpeg stop => $taskId (${session.operationId})');
    FFmpegKit.cancel(ffmpegSession);
  }

  FFmpegRecordSession? getSession(String taskId) => _sessions[taskId];

  bool isRunning(String taskId, {String? operationId}) {
    final session = _sessions[taskId];
    if (session == null) return false;
    return operationId == null || session.operationId == operationId;
  }
}
