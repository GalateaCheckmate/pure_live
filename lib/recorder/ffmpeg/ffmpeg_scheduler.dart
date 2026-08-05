import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';

class FFmpegScheduler {
  FFmpegScheduler({
    int Function()? maxConcurrentTasksProvider,
    this.minStartInterval = const Duration(seconds: 5),
  }) : _maxConcurrentTasksProvider = maxConcurrentTasksProvider;

  static final FFmpegScheduler instance = FFmpegScheduler();

  final int Function()? _maxConcurrentTasksProvider;
  final Duration minStartInterval;
  final Queue<_SchedulerTask> _taskQueue = Queue();
  final Map<String, _RunningTask> _runningTasks = {};

  DateTime _lastStartTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isScheduling = false;
  bool _disposed = false;
  Timer? _scheduleTimer;

  int get maxConcurrentTasks {
    final provided = _maxConcurrentTasksProvider?.call();
    if (provided != null) return provided.clamp(1, 64);
    if (Get.isRegistered<RecordSettingsController>()) {
      return Get.find<RecordSettingsController>().maxTaskCount.value.clamp(1, 64);
    }
    log('RecordSettingsController not found, using fallback 1', name: 'FFmpegScheduler');
    return 1;
  }

  bool enqueue({
    required String taskId,
    required Future<void> Function(TaskCancelToken token) taskRunner,
  }) {
    if (_disposed || isRunning(taskId) || isQueued(taskId)) {
      return false;
    }

    _taskQueue.add(_SchedulerTask(taskId: taskId, taskRunner: taskRunner));
    log('Task enqueued: $taskId', name: 'FFmpegScheduler');
    _scheduleNext();
    return true;
  }

  Future<bool> cancel(String taskId) async {
    final queuedBefore = _taskQueue.length;
    _taskQueue.removeWhere((task) => task.taskId == taskId);
    final removedQueued = queuedBefore != _taskQueue.length;

    final runningTask = _runningTasks[taskId];
    if (runningTask == null) {
      _scheduleNext();
      return removedQueued;
    }

    if (!runningTask.cancelToken.isCancelled) {
      log('Signalling cancel to task: $taskId', name: 'FFmpegScheduler');
      await runningTask.cancelToken.cancel();
    }

    try {
      await runningTask.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      log('Timed out waiting for task cancellation: $taskId', name: 'FFmpegScheduler');
    }

    _scheduleNext();
    return true;
  }

  Future<void> clearAll() async {
    _taskQueue.clear();
    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    final ids = _runningTasks.keys.toList(growable: false);
    for (final taskId in ids) {
      await cancel(taskId);
    }
  }

  void _scheduleNext() {
    if (_disposed || _isScheduling) return;
    _isScheduling = true;

    try {
      while (_runningTasks.length < maxConcurrentTasks && _taskQueue.isNotEmpty) {
        final remaining = minStartInterval - DateTime.now().difference(_lastStartTime);
        if (remaining > Duration.zero) {
          _scheduleTimer?.cancel();
          _scheduleTimer = Timer(remaining, _scheduleNext);
          return;
        }

        final task = _taskQueue.removeFirst();
        _lastStartTime = DateTime.now();
        _runTask(task);
      }
    } finally {
      _isScheduling = false;
    }
  }

  void _runTask(_SchedulerTask task) {
    final cancelToken = TaskCancelToken();
    late final Future<void> future;

    future = Future<void>(() async {
      try {
        await task.taskRunner(cancelToken);
      } catch (e, stackTrace) {
        log('Task runner failed: $e', name: 'FFmpegScheduler', stackTrace: stackTrace);
      } finally {
        final active = _runningTasks[task.taskId];
        if (active != null && identical(active.cancelToken, cancelToken)) {
          _runningTasks.remove(task.taskId);
        }
        _scheduleNext();
      }
    });

    _runningTasks[task.taskId] = _RunningTask(
      taskId: task.taskId,
      future: future,
      cancelToken: cancelToken,
    );
  }

  bool isRunning(String taskId) => _runningTasks.containsKey(taskId);

  bool isQueued(String taskId) => _taskQueue.any((task) => task.taskId == taskId);

  int get runningCount => _runningTasks.length;
  int get queuedCount => _taskQueue.length;
  int get totalCount => runningCount + queuedCount;

  List<String> get runningTaskIds => _runningTasks.keys.toList(growable: false);
  List<String> get queuedTaskIds => _taskQueue.map((task) => task.taskId).toList(growable: false);

  Future<void> dispose() async {
    if (_disposed) return;
    await clearAll();
    _disposed = true;
    _scheduleTimer?.cancel();
  }
}

class _SchedulerTask {
  final String taskId;
  final Future<void> Function(TaskCancelToken token) taskRunner;

  const _SchedulerTask({required this.taskId, required this.taskRunner});
}

class _RunningTask {
  final String taskId;
  final Future<void> future;
  final TaskCancelToken cancelToken;

  const _RunningTask({
    required this.taskId,
    required this.future,
    required this.cancelToken,
  });
}

class TaskCancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  FutureOr<void> Function()? onCancel;

  Future<void> cancel() async {
    if (_isCancelled) return;
    _isCancelled = true;

    try {
      await onCancel?.call();
    } catch (e, stackTrace) {
      log('Cancel token error: $e', name: 'FFmpegScheduler', stackTrace: stackTrace);
    }
  }
}
