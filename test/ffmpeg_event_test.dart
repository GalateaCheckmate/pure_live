import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';

void main() {
  test('FFmpegEvent preserves operation identity', () {
    const event = FFmpegEvent(
      taskId: 'room-1',
      operationId: 'room-1:2',
      type: FFmpegEventType.progress,
      data: {'time': 1000},
    );

    final restored = FFmpegEvent.fromMap(event.toMap());

    expect(restored.taskId, event.taskId);
    expect(restored.operationId, event.operationId);
    expect(restored.type, event.type);
    expect(restored.data['time'], 1000);
  });
}
