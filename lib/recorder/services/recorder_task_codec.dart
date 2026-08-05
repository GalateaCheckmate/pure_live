import 'dart:convert';
import 'dart:developer';
import 'package:pure_live/recorder/models/live_record_task.dart';

class RecorderTaskCodec {
  const RecorderTaskCodec._();

  static String encode(Iterable<LiveRecordTask> tasks) {
    return jsonEncode(tasks.map((task) => task.toJson()).toList(growable: false));
  }

  static List<LiveRecordTask> decode(String? source) {
    if (source == null || source.trim().isEmpty) return const [];

    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Recorder task payload must be a JSON list');
    }

    final result = <LiveRecordTask>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        final task = LiveRecordTask.fromJson(Map<String, dynamic>.from(entry));
        if (task.taskId.isEmpty || task.roomId.isEmpty || task.platform.isEmpty) {
          continue;
        }
        result.add(task);
      } catch (e, stackTrace) {
        log('Skipping damaged recorder task: $e', name: 'RecorderTaskCodec', stackTrace: stackTrace);
      }
    }
    return result;
  }
}
