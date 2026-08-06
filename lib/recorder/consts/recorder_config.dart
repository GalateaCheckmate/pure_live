import 'recorder_keys.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/models/record_file_item.dart';

class RecorderConfig {
  static const _defaultSegmentTime = 300;
  static const _defaultMaxMergeDurationSeconds = 3600;
  static const _defaultMaxTaskCount = 3;
  static const _defaultAutoReconnect = true;
  static const _defaultMaxCacheMB = 1024;
  static const _defaultEnableCacheLimit = false;
  static const _defaultMaxRetryCount = 5;
  static const _defaultRetryDelay = 30;
  static const _defaultPreferBestStream = true;
  static const _defaultRwTimeout = 15;
  static const _defaultThreadQueueSize = 2048;
  static const _defaultEnablePolling = false;
  static const _defaultLiveCheckInterval = 30;
  static const _defaultEnableBackoff = false;
  static const _defaultMaxCheckInterval = 300;
  static const _defaultAutoStartOnBoot = false;
  static const _defaultUsePinyinForFolder = false;

  static int get segmentTime =>
      HivePrefUtil.getInt(RecorderKeys.segmentTime) ?? _defaultSegmentTime;

  static Future<void> setSegmentTime(int value) =>
      HivePrefUtil.setInt(RecorderKeys.segmentTime, value);

  /// 0 表示不限制单个 MP4 的最长时长。
  static int get maxMergeDurationSeconds =>
      HivePrefUtil.getInt(RecorderKeys.maxMergeDurationSeconds) ??
      _defaultMaxMergeDurationSeconds;

  static Future<void> setMaxMergeDurationSeconds(int value) =>
      HivePrefUtil.setInt(RecorderKeys.maxMergeDurationSeconds, value);

  static int get maxTaskCount =>
      HivePrefUtil.getInt(RecorderKeys.maxTaskCount) ?? _defaultMaxTaskCount;

  static Future<void> setMaxTaskCount(int value) =>
      HivePrefUtil.setInt(RecorderKeys.maxTaskCount, value);

  static bool get autoReconnect =>
      HivePrefUtil.getBool(RecorderKeys.autoReconnect) ?? _defaultAutoReconnect;

  static Future<void> setAutoReconnect(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.autoReconnect, value);

  static int get maxCacheMB =>
      HivePrefUtil.getInt(RecorderKeys.maxCacheMB) ?? _defaultMaxCacheMB;

  static Future<void> setMaxCacheMB(int value) =>
      HivePrefUtil.setInt(RecorderKeys.maxCacheMB, value);

  static String get recordSavePath =>
      HivePrefUtil.getString(RecorderKeys.recordSavePath) ?? '';

  static Future<void> setRecordSavePath(String value) =>
      HivePrefUtil.setString(RecorderKeys.recordSavePath, value);

  static String get defaultQuality =>
      HivePrefUtil.getString(RecorderKeys.defaultQuality) ?? '原画';

  static Future<void> setDefaultQuality(String value) =>
      HivePrefUtil.setString(RecorderKeys.defaultQuality, value);

  static int get maxRetryCount =>
      HivePrefUtil.getInt(RecorderKeys.maxRetryCount) ?? _defaultMaxRetryCount;

  static Future<void> setMaxRetryCount(int value) =>
      HivePrefUtil.setInt(RecorderKeys.maxRetryCount, value);

  static int get retryDelay =>
      HivePrefUtil.getInt(RecorderKeys.retryDelay) ?? _defaultRetryDelay;

  static Future<void> setRetryDelay(int value) =>
      HivePrefUtil.setInt(RecorderKeys.retryDelay, value);

  static bool get enablePolling =>
      HivePrefUtil.getBool(RecorderKeys.enablePolling) ?? _defaultEnablePolling;

  static Future<void> setEnablePolling(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.enablePolling, value);

  static int get liveCheckInterval =>
      HivePrefUtil.getInt(RecorderKeys.liveCheckInterval) ??
      _defaultLiveCheckInterval;

  static Future<void> setLiveCheckInterval(int value) =>
      HivePrefUtil.setInt(RecorderKeys.liveCheckInterval, value);

  static bool get enableBackoff =>
      HivePrefUtil.getBool(RecorderKeys.enableBackoff) ?? _defaultEnableBackoff;

  static Future<void> setEnableBackoff(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.enableBackoff, value);

  static int get maxCheckInterval =>
      HivePrefUtil.getInt(RecorderKeys.maxCheckInterval) ??
      _defaultMaxCheckInterval;

  static Future<void> setMaxCheckInterval(int value) =>
      HivePrefUtil.setInt(RecorderKeys.maxCheckInterval, value);

  static bool get autoStartOnBoot =>
      HivePrefUtil.getBool(RecorderKeys.autoStartOnBoot) ??
      _defaultAutoStartOnBoot;

  static Future<void> setAutoStartOnBoot(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.autoStartOnBoot, value);

  static Future<void> saveRecordHistory(List<RecordFileItem> history) async {
    await HivePrefUtil.setAnyPref(
      RecorderKeys.recordHistory,
      history.map((item) => item.toJson()).toList(),
    );
  }

  static List<dynamic> getRecordHistory() {
    final raw = HivePrefUtil.getAnyPref(RecorderKeys.recordHistory);
    return raw is List ? raw : [];
  }

  static Future<void> clearRecordHistory() async {
    await HivePrefUtil.remove(RecorderKeys.recordHistory);
  }

  static bool get preferBestStream =>
      HivePrefUtil.getBool(RecorderKeys.preferBestStream) ??
      _defaultPreferBestStream;

  static Future<void> setPreferBestStream(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.preferBestStream, value);

  static int get rwTimeout =>
      HivePrefUtil.getInt(RecorderKeys.rwTimeout) ?? _defaultRwTimeout;

  static Future<void> setRwTimeout(int value) =>
      HivePrefUtil.setInt(RecorderKeys.rwTimeout, value);

  static int get threadQueueSize =>
      HivePrefUtil.getInt(RecorderKeys.threadQueueSize) ??
      _defaultThreadQueueSize;

  static Future<void> setThreadQueueSize(int value) =>
      HivePrefUtil.setInt(RecorderKeys.threadQueueSize, value);

  static bool get usePinyinForFolder =>
      HivePrefUtil.getBool(RecorderKeys.folderNamingStrategy) ??
      _defaultUsePinyinForFolder;

  static Future<void> setUsePinyinForFolder(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.folderNamingStrategy, value);

  static bool get enableCacheLimit =>
      HivePrefUtil.getBool(RecorderKeys.enableCacheLimit) ??
      _defaultEnableCacheLimit;

  static Future<void> setEnableCacheLimit(bool value) =>
      HivePrefUtil.setBool(RecorderKeys.enableCacheLimit, value);
}
