import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/recorder/models/record_status.dart';

class LiveRecordTask {
  final String taskId;
  final String roomId;
  final String platform;

  String title;
  String nick;
  String avatar;
  String cover;
  LiveStatus liveStatus;
  String watching;
  String followers;
  bool isRecord;

  String? currentUrl;
  String? selectedLine;
  String? selectedQuality;
  String? outputDir;

  int recordedSeconds;
  int fileSize;
  double recordSpeed;
  double bitrate;
  double fps;
  int lastFrame;
  DateTime? lastUpdate;

  DateTime? recordingStartedAt;
  String? recordingBatchId;
  int recordingSessionIndex;
  int accumulatedSeconds;
  int currentSessionSeconds;
  int accumulatedFileSize;
  int currentSessionFileSize;

  RecordStatus status;
  bool autoReconnect;
  int retryCount;
  DateTime createTime;
  DateTime? lastFailTime;
  bool wasStoppedByUser;

  LiveRecordTask({
    required this.taskId,
    required this.roomId,
    required this.platform,
    required this.title,
    required this.nick,
    required this.avatar,
    required this.cover,
    required this.createTime,
    this.liveStatus = LiveStatus.unknown,
    this.watching = '0',
    this.followers = '0',
    this.isRecord = false,
    this.currentUrl,
    this.selectedLine,
    this.selectedQuality,
    this.outputDir,
    this.recordedSeconds = 0,
    this.fileSize = 0,
    this.recordSpeed = 0,
    this.bitrate = 0,
    this.fps = 0,
    this.lastFrame = 0,
    this.lastUpdate,
    this.recordingStartedAt,
    this.recordingBatchId,
    this.recordingSessionIndex = 0,
    this.accumulatedSeconds = 0,
    this.currentSessionSeconds = 0,
    this.accumulatedFileSize = 0,
    this.currentSessionFileSize = 0,
    this.status = RecordStatus.waitingLive,
    this.autoReconnect = true,
    this.retryCount = 0,
    this.wasStoppedByUser = false,
    this.lastFailTime,
  });

  factory LiveRecordTask.fromRoom(LiveRoom room) {
    final roomId = room.roomId ?? '';
    final platform = room.platform ?? '';

    return LiveRecordTask(
      taskId: '${platform}_$roomId',
      roomId: roomId,
      platform: platform,
      title: room.title ?? '',
      nick: room.nick ?? '',
      avatar: room.avatar ?? '',
      cover: room.cover ?? '',
      watching: room.watching ?? '0',
      followers: room.followers ?? '0',
      liveStatus: room.liveStatus ?? LiveStatus.unknown,
      isRecord: room.isRecord ?? false,
      createTime: DateTime.now(),
    );
  }

  void updateFromRoom(LiveRoom room) {
    title = room.title ?? title;
    nick = room.nick ?? nick;
    avatar = room.avatar ?? avatar;
    cover = room.cover ?? cover;
    watching = room.watching ?? watching;
    followers = room.followers ?? followers;
    liveStatus = room.liveStatus ?? liveStatus;
    isRecord = room.isRecord ?? isRecord;
  }

  void beginNewRecordingBatch() {
    final now = DateTime.now();
    recordingStartedAt = now;
    recordingBatchId = _formatBatchId(now);
    recordingSessionIndex = 0;
    accumulatedSeconds = 0;
    currentSessionSeconds = 0;
    accumulatedFileSize = 0;
    currentSessionFileSize = 0;
    recordedSeconds = 0;
    fileSize = 0;
    recordSpeed = 0;
    bitrate = 0;
    fps = 0;
    lastFrame = 0;
    lastUpdate = now;
    currentUrl = null;
    selectedLine = null;
    selectedQuality = null;
    outputDir = null;
  }

  void beginRecordingSession() {
    if (recordingBatchId == null || recordingBatchId!.isEmpty) {
      beginNewRecordingBatch();
    }
    recordingSessionIndex++;
    currentSessionSeconds = 0;
    currentSessionFileSize = 0;
    recordSpeed = 0;
    bitrate = 0;
    fps = 0;
    lastFrame = 0;
    lastUpdate = DateTime.now();
  }

  void applyProgress({
    required int seconds,
    required int sessionFileSize,
    required double speed,
    required double currentBitrate,
    required double currentFps,
    int? frame,
  }) {
    if (seconds > currentSessionSeconds) {
      currentSessionSeconds = seconds;
    }
    if (sessionFileSize > currentSessionFileSize) {
      currentSessionFileSize = sessionFileSize;
    }

    recordedSeconds = accumulatedSeconds + currentSessionSeconds;
    fileSize = accumulatedFileSize + currentSessionFileSize;
    recordSpeed = speed;
    bitrate = currentBitrate;
    fps = currentFps;
    if (frame != null && frame > lastFrame) {
      lastFrame = frame;
    }
    lastUpdate = DateTime.now();
  }

  void finalizeCurrentSession() {
    if (currentSessionSeconds > 0) {
      accumulatedSeconds += currentSessionSeconds;
      currentSessionSeconds = 0;
    }
    if (currentSessionFileSize > 0) {
      accumulatedFileSize += currentSessionFileSize;
      currentSessionFileSize = 0;
    }
    recordedSeconds = accumulatedSeconds;
    fileSize = accumulatedFileSize;
    recordSpeed = 0;
    bitrate = 0;
    fps = 0;
    lastUpdate = DateTime.now();
  }

  bool get hasRecordedData => recordedSeconds > 0 || fileSize > 0;

  bool get isStalled {
    if (status != RecordStatus.running || lastUpdate == null) return false;
    return DateTime.now().difference(lastUpdate!).inSeconds > 30;
  }

  LiveRecordTask cloneForProcessing() {
    return LiveRecordTask(
      taskId: taskId,
      roomId: roomId,
      platform: platform,
      title: title,
      nick: nick,
      avatar: avatar,
      cover: cover,
      createTime: createTime,
      liveStatus: liveStatus,
      watching: watching,
      followers: followers,
      isRecord: isRecord,
      currentUrl: currentUrl,
      selectedLine: selectedLine,
      selectedQuality: selectedQuality,
      outputDir: outputDir,
      recordedSeconds: recordedSeconds,
      fileSize: fileSize,
      recordSpeed: recordSpeed,
      bitrate: bitrate,
      fps: fps,
      lastFrame: lastFrame,
      lastUpdate: lastUpdate,
      recordingStartedAt: recordingStartedAt,
      recordingBatchId: recordingBatchId,
      recordingSessionIndex: recordingSessionIndex,
      accumulatedSeconds: accumulatedSeconds,
      currentSessionSeconds: currentSessionSeconds,
      accumulatedFileSize: accumulatedFileSize,
      currentSessionFileSize: currentSessionFileSize,
      status: status,
      autoReconnect: autoReconnect,
      retryCount: retryCount,
      wasStoppedByUser: wasStoppedByUser,
      lastFailTime: lastFailTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'roomId': roomId,
        'platform': platform,
        'title': title,
        'nick': nick,
        'avatar': avatar,
        'cover': cover,
        'watching': watching,
        'followers': followers,
        'isRecord': isRecord,
        'liveStatus': liveStatus.index,
        'currentUrl': currentUrl,
        'selectedLine': selectedLine,
        'selectedQuality': selectedQuality,
        'outputDir': outputDir,
        'recordedSeconds': recordedSeconds,
        'fileSize': fileSize,
        'recordSpeed': recordSpeed,
        'bitrate': bitrate,
        'fps': fps,
        'lastFrame': lastFrame,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'recordingStartedAt': recordingStartedAt?.toIso8601String(),
        'recordingBatchId': recordingBatchId,
        'recordingSessionIndex': recordingSessionIndex,
        'accumulatedSeconds': accumulatedSeconds,
        'currentSessionSeconds': currentSessionSeconds,
        'accumulatedFileSize': accumulatedFileSize,
        'currentSessionFileSize': currentSessionFileSize,
        'status': status.index,
        'autoReconnect': autoReconnect,
        'retryCount': retryCount,
        'createTime': createTime.toIso8601String(),
        'lastFailTime': lastFailTime?.toIso8601String(),
        'wasStoppedByUser': wasStoppedByUser,
      };

  factory LiveRecordTask.fromJson(Map<String, dynamic> json) {
    final recordedSeconds = json['recordedSeconds'] ?? 0;
    final fileSize = json['fileSize'] ?? 0;

    return LiveRecordTask(
      taskId: json['taskId'] ?? '',
      roomId: json['roomId'] ?? '',
      platform: json['platform'] ?? '',
      title: json['title'] ?? '',
      nick: json['nick'] ?? '',
      avatar: json['avatar'] ?? '',
      cover: json['cover'] ?? '',
      watching: json['watching'] ?? '0',
      followers: json['followers'] ?? '0',
      isRecord: json['isRecord'] ?? false,
      liveStatus: LiveStatus.values[json['liveStatus'] ?? 0],
      currentUrl: json['currentUrl'],
      selectedLine: json['selectedLine'],
      selectedQuality: json['selectedQuality'],
      outputDir: json['outputDir'],
      recordedSeconds: recordedSeconds,
      fileSize: fileSize,
      recordSpeed: (json['recordSpeed'] ?? 0).toDouble(),
      bitrate: (json['bitrate'] ?? 0).toDouble(),
      fps: (json['fps'] ?? 0).toDouble(),
      lastFrame: json['lastFrame'] ?? 0,
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.tryParse(json['lastUpdate'])
          : null,
      recordingStartedAt: json['recordingStartedAt'] != null
          ? DateTime.tryParse(json['recordingStartedAt'])
          : null,
      recordingBatchId: json['recordingBatchId'],
      recordingSessionIndex: json['recordingSessionIndex'] ?? 0,
      accumulatedSeconds: json['accumulatedSeconds'] ?? recordedSeconds,
      currentSessionSeconds: json['currentSessionSeconds'] ?? 0,
      accumulatedFileSize: json['accumulatedFileSize'] ?? fileSize,
      currentSessionFileSize: json['currentSessionFileSize'] ?? 0,
      status: RecordStatus.values[json['status'] ?? 0],
      autoReconnect: json['autoReconnect'] ?? true,
      retryCount: json['retryCount'] ?? 0,
      createTime:
          DateTime.tryParse(json['createTime'] ?? '') ?? DateTime.now(),
      lastFailTime: json['lastFailTime'] != null
          ? DateTime.tryParse(json['lastFailTime'])
          : null,
      wasStoppedByUser: json['wasStoppedByUser'] ?? false,
    );
  }

  static String _formatBatchId(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    String six(int number) => number.toString().padLeft(6, '0');

    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}_'
        '${six(value.microsecond)}';
  }
}
