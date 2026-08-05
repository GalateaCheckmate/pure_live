import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/services/recorder_task_codec.dart';

void main() {
  group('RecorderTaskCodec', () {
    test('round trips valid recorder tasks', () {
      final task = LiveRecordTask(
        taskId: 'bilibili_123',
        roomId: '123',
        platform: 'bilibili',
        title: 'title',
        nick: 'nick',
        avatar: '',
        cover: '',
        createTime: DateTime.utc(2026, 8, 5),
        liveStatus: LiveStatus.live,
      );

      final decoded = RecorderTaskCodec.decode(RecorderTaskCodec.encode([task]));

      expect(decoded, hasLength(1));
      expect(decoded.single.taskId, task.taskId);
      expect(decoded.single.roomId, task.roomId);
      expect(decoded.single.platform, task.platform);
    });

    test('skips damaged entries while keeping valid entries', () {
      final valid = LiveRecordTask(
        taskId: 'douyu_456',
        roomId: '456',
        platform: 'douyu',
        title: 'title',
        nick: 'nick',
        avatar: '',
        cover: '',
        createTime: DateTime.utc(2026, 8, 5),
      ).toJson();

      final payload = jsonEncode([
        valid,
        {'taskId': '', 'roomId': '', 'platform': ''},
        'not-a-map',
        {'taskId': 'broken', 'roomId': '1', 'platform': 'x', 'status': 999},
      ]);

      final decoded = RecorderTaskCodec.decode(payload);

      expect(decoded, hasLength(1));
      expect(decoded.single.taskId, 'douyu_456');
    });

    test('rejects non-list payloads', () {
      expect(
        () => RecorderTaskCodec.decode('{"taskId":"x"}'),
        throwsFormatException,
      );
    });
  });
}
