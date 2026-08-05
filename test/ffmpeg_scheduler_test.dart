import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';

void main() {
  group('FFmpegScheduler', () {
    test('rejects duplicate task ids', () async {
      final scheduler = FFmpegScheduler(
        maxConcurrentTasksProvider: () => 1,
        minStartInterval: Duration.zero,
      );
      final release = Completer<void>();

      expect(
        scheduler.enqueue(
          taskId: 'room-1',
          taskRunner: (_) => release.future,
        ),
        isTrue,
      );
      expect(
        scheduler.enqueue(
          taskId: 'room-1',
          taskRunner: (_) async {},
        ),
        isFalse,
      );

      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scheduler.dispose();
    });

    test('cancel waits for running task and signals once', () async {
      final scheduler = FFmpegScheduler(
        maxConcurrentTasksProvider: () => 1,
        minStartInterval: Duration.zero,
      );
      final running = Completer<void>();
      final release = Completer<void>();
      var cancelCount = 0;

      scheduler.enqueue(
        taskId: 'room-1',
        taskRunner: (token) async {
          token.onCancel = () {
            cancelCount++;
            if (!release.isCompleted) release.complete();
          };
          running.complete();
          await release.future;
        },
      );

      await running.future;
      expect(scheduler.isRunning('room-1'), isTrue);
      expect(await scheduler.cancel('room-1'), isTrue);
      expect(cancelCount, 1);
      expect(scheduler.isRunning('room-1'), isFalse);

      await scheduler.cancel('room-1');
      expect(cancelCount, 1);
      await scheduler.dispose();
    });

    test('cancelling a queued task prevents execution', () async {
      final scheduler = FFmpegScheduler(
        maxConcurrentTasksProvider: () => 1,
        minStartInterval: Duration.zero,
      );
      final firstRunning = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondRan = false;

      scheduler.enqueue(
        taskId: 'first',
        taskRunner: (_) async {
          firstRunning.complete();
          await releaseFirst.future;
        },
      );
      await firstRunning.future;

      scheduler.enqueue(
        taskId: 'second',
        taskRunner: (_) async {
          secondRan = true;
        },
      );
      expect(scheduler.isQueued('second'), isTrue);
      expect(await scheduler.cancel('second'), isTrue);

      releaseFirst.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(secondRan, isFalse);
      await scheduler.dispose();
    });
  });
}
