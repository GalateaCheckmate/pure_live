import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/recorder/consts/recorder_config.dart';
import 'package:pure_live/recorder/models/record_storage_snapshot.dart';
import 'package:pure_live/recorder/services/cache_service.dart';

class RecordSettingsController extends GetxController {
  final defaultQuality = RecorderConfig.defaultQuality.obs;
  final recordSavePath = RecorderConfig.recordSavePath.obs;
  final maxCacheMB = RecorderConfig.maxCacheMB.obs;
  final enableCacheLimit = RecorderConfig.enableCacheLimit.obs;

  final temporaryFileSizeMB = 0.0.obs;
  final recordedVideoSizeMB = 0.0.obs;
  final cleanableSizeMB = 0.0.obs;
  final cleanableBatchCount = 0.obs;
  final protectedBatchCount = 0.obs;
  final isStorageScanning = false.obs;
  final isCleaning = false.obs;

  /// 兼容旧界面调用：现在只代表临时文件大小。
  final cacheSizeMB = 0.0.obs;

  final segmentTime = RecorderConfig.segmentTime.obs;
  final maxMergeDurationSeconds =
      RecorderConfig.maxMergeDurationSeconds.obs;
  final maxTaskCount = RecorderConfig.maxTaskCount.obs;
  final preferBestStream = RecorderConfig.preferBestStream.obs;
  final rwTimeout = RecorderConfig.rwTimeout.obs;
  final threadQueueSize = RecorderConfig.threadQueueSize.obs;

  final autoReconnect = RecorderConfig.autoReconnect.obs;
  final maxRetryCount = RecorderConfig.maxRetryCount.obs;
  final retryDelay = RecorderConfig.retryDelay.obs;

  final enablePolling = RecorderConfig.enablePolling.obs;
  final liveCheckInterval = RecorderConfig.liveCheckInterval.obs;
  final enableBackoff = RecorderConfig.enableBackoff.obs;
  final maxCheckInterval = RecorderConfig.maxCheckInterval.obs;
  final autoStartOnBoot = RecorderConfig.autoStartOnBoot.obs;
  final usePinyinForFolder = RecorderConfig.usePinyinForFolder.obs;

  @override
  void onInit() {
    super.onInit();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await initRecordPath();
    await refreshStorageStats(forceScan: true);
  }

  Future<void> refreshStorageStats({bool forceScan = false}) async {
    if (isStorageScanning.value) return;
    isStorageScanning.value = true;
    try {
      final snapshot = await CacheService.to.getStorageSnapshot(
        forceScan: forceScan,
      );
      temporaryFileSizeMB.value = snapshot.temporaryMB;
      recordedVideoSizeMB.value = snapshot.recordedVideoMB;
      cacheSizeMB.value = snapshot.temporaryMB;

      final preview = await CacheService.to.getCleanupPreview(
        forceScan: false,
      );
      _applyCleanupPreview(preview);
    } finally {
      isStorageScanning.value = false;
    }
  }

  Future<void> refreshCacheSize() async {
    await refreshStorageStats();
  }

  Future<RecordCleanupPreview> prepareCleanupPreview() async {
    isStorageScanning.value = true;
    try {
      final preview = await CacheService.to.getCleanupPreview(
        forceScan: true,
      );
      _applyCleanupPreview(preview);
      final snapshot = await CacheService.to.getStorageSnapshot();
      temporaryFileSizeMB.value = snapshot.temporaryMB;
      recordedVideoSizeMB.value = snapshot.recordedVideoMB;
      cacheSizeMB.value = snapshot.temporaryMB;
      return preview;
    } finally {
      isStorageScanning.value = false;
    }
  }

  void _applyCleanupPreview(RecordCleanupPreview preview) {
    cleanableSizeMB.value = preview.cleanableMB;
    cleanableBatchCount.value = preview.cleanableBatchCount;
    protectedBatchCount.value = preview.protectedBatchCount;
  }

  Future<void> updateEnableCacheLimit(bool value) async {
    enableCacheLimit.value = value;
    await RecorderConfig.setEnableCacheLimit(value);
  }

  Future<int> clearCache() async {
    if (isCleaning.value) return 0;
    isCleaning.value = true;
    try {
      final deletedBytes = await CacheService.to.clearTemporaryFiles();
      await refreshStorageStats(forceScan: true);
      return deletedBytes;
    } finally {
      isCleaning.value = false;
    }
  }

  Future<void> updateSegmentTime(int value) async {
    final normalized = value.clamp(60, 3600).toInt();
    segmentTime.value = normalized;
    await RecorderConfig.setSegmentTime(normalized);

    final mergeLimit = maxMergeDurationSeconds.value;
    if (mergeLimit > 0 && mergeLimit < normalized) {
      await updateMaxMergeDurationSeconds(normalized);
    }
  }

  Future<void> updateMaxMergeDurationSeconds(int value) async {
    final normalized = value <= 0
        ? 0
        : value.clamp(segmentTime.value, 24 * 3600).toInt();
    maxMergeDurationSeconds.value = normalized;
    await RecorderConfig.setMaxMergeDurationSeconds(normalized);
  }

  Future<void> updateMaxTask(int value) async {
    maxTaskCount.value = value;
    await RecorderConfig.setMaxTaskCount(value);
  }

  Future<void> updateAutoReconnect(bool value) async {
    autoReconnect.value = value;
    await RecorderConfig.setAutoReconnect(value);
  }

  Future<void> updateMaxRetryCount(int value) async {
    maxRetryCount.value = value;
    await RecorderConfig.setMaxRetryCount(value);
  }

  Future<void> updateRetryDelay(int value) async {
    retryDelay.value = value;
    await RecorderConfig.setRetryDelay(value);
  }

  Future<void> updateLiveCheckInterval(int value) async {
    liveCheckInterval.value = value;
    await RecorderConfig.setLiveCheckInterval(value);
  }

  Future<void> updateMaxCheckInterval(int value) async {
    maxCheckInterval.value = value;
    await RecorderConfig.setMaxCheckInterval(value);
  }

  Future<void> updateEnablePolling(bool value) async {
    enablePolling.value = value;
    await RecorderConfig.setEnablePolling(value);
  }

  Future<void> updateEnableBackoff(bool value) async {
    enableBackoff.value = value;
    await RecorderConfig.setEnableBackoff(value);
  }

  Future<void> pickRecordDir() async {
    final result = await FilePicker.getDirectoryPath();
    if (result == null) return;

    recordSavePath.value = result;
    await RecorderConfig.setRecordSavePath(result);
    CacheService.to.invalidateStorageIndex();
    await refreshStorageStats(forceScan: true);
  }

  Future<void> updateDefaultQuality(String value) async {
    defaultQuality.value = value;
    await RecorderConfig.setDefaultQuality(value);
  }

  Future<void> updateMaxCache(int value) async {
    maxCacheMB.value = value;
    await RecorderConfig.setMaxCacheMB(value);
  }

  Future<void> updatePreferBestStream(bool value) async {
    preferBestStream.value = value;
    await RecorderConfig.setPreferBestStream(value);
  }

  Future<void> updateRwTimeout(int value) async {
    rwTimeout.value = value;
    await RecorderConfig.setRwTimeout(value);
  }

  Future<void> updateThreadQueueSize(int value) async {
    threadQueueSize.value = value;
    await RecorderConfig.setThreadQueueSize(value);
  }

  Future<void> updateAutoStartOnBoot(bool value) async {
    autoStartOnBoot.value = value;
    await RecorderConfig.setAutoStartOnBoot(value);
  }

  Future<void> updateUsePinyinForFolder(bool value) async {
    usePinyinForFolder.value = value;
    await RecorderConfig.setUsePinyinForFolder(value);
  }

  Future<void> initRecordPath() async {
    if (recordSavePath.value.isNotEmpty) return;
    final Directory recordDir =
        await AppPathManager().getDir(AppPathManager.dirRecords);
    recordSavePath.value = recordDir.path;
    await RecorderConfig.setRecordSavePath(recordDir.path);
    CacheService.to.invalidateStorageIndex();
  }
}
