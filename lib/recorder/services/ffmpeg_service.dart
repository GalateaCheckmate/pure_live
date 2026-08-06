import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/plugins/locale_helper.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';

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

    final outputMetrics = _SegmentOutputMetrics.fromCommandOrNull(command);
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
      final now = DateTime.now();
      final measured = outputMetrics?.measure(now);
      final measuredSize = measured?.bytes ?? 0;
      final measuredBitrate = measured?.bitrateKbps ?? 0;
      final actualSize = measuredSize > 0 ? measuredSize : statistics.size;
      final actualBitrate =
          measuredBitrate > 0 ? measuredBitrate : statistics.bitrate;

      session
        ..recordedSeconds = statistics.time ~/ 1000
        ..fileSize = actualSize
        ..bitrate = actualBitrate
        ..speed = statistics.speed
        ..fps = statistics.videoFps
        ..lastUpdate = now;

      onEvent(
        FFmpegEvent(
          taskId: taskId,
          operationId: operationId,
          type: FFmpegEventType.progress,
          data: {
            'time': statistics.time,
            'size': actualSize,
            'bitrate': actualBitrate,
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

          if (code == -2 ||
              lowerLogs.contains('no such file') ||
              lowerLogs.contains('permission denied')) {
            userFriendlyMessage = i18n('path_or_permission_error');
            eventData['retryable'] = false;
          } else if (lowerLogs.contains('server returned 404') ||
              lowerLogs.contains('http error 404')) {
            userFriendlyMessage = i18n('url_expired_404');
          } else if (lowerLogs.contains('server returned 403') ||
              lowerLogs.contains('http error 403')) {
            userFriendlyMessage = i18n('url_forbidden_403');
          } else if (lowerLogs.contains('connection timed out') ||
              lowerLogs.contains('timed out')) {
            userFriendlyMessage = i18n('timeout');
          } else if (lowerLogs.contains('invalid argument')) {
            userFriendlyMessage = i18n('param_error');
            eventData['retryable'] = false;
          } else if (lowerLogs.contains('unable to open')) {
            userFriendlyMessage = i18n('invalid_stream_format');
            eventData['retryable'] = false;
          } else if (logs.trim().isNotEmpty) {
            final lastLogLine = logs.trim().split('\n').last;
            userFriendlyMessage = i18n(
              'unknown_error',
              args: {'error_log': lastLogLine},
            );
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
          type: isNormalExit
              ? FFmpegEventType.complete
              : FFmpegEventType.error,
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

class _SegmentOutputMetrics {
  static const Duration _minimumSampleInterval = Duration(milliseconds: 900);

  final Directory directory;
  final String filePrefix;

  DateTime? _lastSampleAt;
  int _lastBytes = 0;
  _MeasuredOutput _cached = const _MeasuredOutput(bytes: 0, bitrateKbps: 0);

  _SegmentOutputMetrics({
    required this.directory,
    required this.filePrefix,
  });

  factory _SegmentOutputMetrics.fromCommand(String command) {
    final outputEnd = command.lastIndexOf('.ts"');
    if (outputEnd < 0) {
      throw const FormatException('No segmented TS output pattern');
    }

    final outputStart = command.lastIndexOf('"', outputEnd);
    if (outputStart < 0) {
      throw const FormatException('Invalid segmented TS output pattern');
    }

    final outputPattern = command.substring(outputStart + 1, outputEnd + 3);
    if (!outputPattern.contains('%')) {
      throw const FormatException('TS output is not segmented');
    }

    final fileName = p.basename(outputPattern);
    final sequenceMarker = fileName.indexOf('%');
    if (sequenceMarker <= 0) {
      throw const FormatException('Invalid segmented TS output pattern');
    }

    return _SegmentOutputMetrics(
      directory: Directory(p.dirname(outputPattern)),
      filePrefix: fileName.substring(0, sequenceMarker),
    );
  }

  static _SegmentOutputMetrics? fromCommandOrNull(String command) {
    try {
      return _SegmentOutputMetrics.fromCommand(command);
    } catch (_) {
      return null;
    }
  }

  _MeasuredOutput measure(DateTime now) {
    final previousSampleAt = _lastSampleAt;
    if (previousSampleAt != null &&
        now.difference(previousSampleAt) < _minimumSampleInterval) {
      return _cached;
    }

    var totalBytes = 0;
    try {
      if (directory.existsSync()) {
        for (final entity in directory.listSync(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (!name.startsWith(filePrefix) || !name.endsWith('.ts')) {
            continue;
          }
          try {
            totalBytes += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {
      return _cached;
    }

    var bitrateKbps = _cached.bitrateKbps;
    if (previousSampleAt != null && totalBytes >= _lastBytes) {
      final elapsedSeconds =
          now.difference(previousSampleAt).inMicroseconds / 1000000;
      final deltaBytes = totalBytes - _lastBytes;
      if (elapsedSeconds > 0 && deltaBytes > 0) {
        final instantKbps = deltaBytes * 8 / elapsedSeconds / 1000;
        bitrateKbps = bitrateKbps <= 0
            ? instantKbps
            : bitrateKbps * 0.65 + instantKbps * 0.35;
      }
    }

    _lastSampleAt = now;
    _lastBytes = totalBytes;
    _cached = _MeasuredOutput(
      bytes: totalBytes,
      bitrateKbps: bitrateKbps,
    );
    return _cached;
  }
}

class _MeasuredOutput {
  final int bytes;
  final double bitrateKbps;

  const _MeasuredOutput({
    required this.bytes,
    required this.bitrateKbps,
  });
}
