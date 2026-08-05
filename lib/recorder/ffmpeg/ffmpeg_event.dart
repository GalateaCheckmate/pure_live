import 'dart:developer' as developer;
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';

class FFmpegEvent {
  final String taskId;
  final String operationId;
  final FFmpegEventType type;
  final Map<String, dynamic> data;

  const FFmpegEvent({
    required this.taskId,
    required this.type,
    this.operationId = '',
    this.data = const {},
  });

  Map<String, dynamic> toMap() => {
    'taskId': taskId,
    'operationId': operationId,
    'type': type.index,
    'data': data,
  };

  static FFmpegEvent fromMap(Map map) {
    developer.log(map.toString(), name: 'FFmpegEvent');
    return FFmpegEvent(
      taskId: map['taskId'],
      operationId: map['operationId'] ?? '',
      type: FFmpegEventType.values[map['type']],
      data: Map<String, dynamic>.from(map['data'] ?? {}),
    );
  }
}
