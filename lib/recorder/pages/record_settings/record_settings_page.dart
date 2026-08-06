import 'dart:io';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/utils/player_consts.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:pure_live/recorder/models/record_storage_snapshot.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:remixicon/remixicon.dart';

class RecordSettingsPage extends GetView<RecordSettingsController> {
  const RecordSettingsPage({super.key});

  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final minutes = seconds / 60;
      return '${minutes.toStringAsFixed(minutes.truncateToDouble() == minutes ? 0 : 1)}m';
    }
    final hours = seconds / 3600;
    return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)}h';
  }

  String _formatMergeDuration(int seconds) {
    return seconds <= 0 ? '无上限' : _formatDuration(seconds);
  }

  String _formatSizeMB(double sizeMB) {
    if (sizeMB >= 1024) {
      return '${(sizeMB / 1024).toStringAsFixed(2)} GB';
    }
    return '${sizeMB.toStringAsFixed(2)} MB';
  }

  String _formatBytes(int bytes) {
    return _formatSizeMB(bytes / 1024 / 1024);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n('record_settings'))),
      body: Obx(
        () => ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          children: [
            context.buildGroupTitle(i18n('basic_config')),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.hd_line,
                title: i18n('default_record_quality'),
                subtitle: controller.defaultQuality.value,
                onTap: _showQualityDialog,
              ),
              context.buildSwitchTile(
                icon: Remix.translate_2,
                title: i18n('use_pinyin_folder'),
                subtitle: i18n('use_pinyin_folder_desc'),
                value: controller.usePinyinForFolder,
              ),
            ]),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                context.buildGroupTitle(i18n('cache_management')),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: () => FileUtils.openFileOrUrl(
                      controller.recordSavePath.value,
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: theme.colorScheme.primary,
                    ),
                    icon: const Icon(Remix.folder_open_line, size: 18),
                    label: Text(
                      i18n('recorder_open_folder'),
                      style: AppTextStyles.t14.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.folder_video_line,
                title: i18n('storage_directory'),
                subtitle: controller.recordSavePath.value,
                onTap: controller.pickRecordDir,
              ),
              context.buildSwitchTile(
                icon: Remix.exchange_box_line,
                title: i18n('enable_cache_limit'),
                subtitle: i18n('enable_cache_limit_desc'),
                value: controller.enableCacheLimit,
              ),
              if (controller.enableCacheLimit.value)
                context.buildTile(
                  icon: Remix.database_2_line,
                  title: i18n('cache_limit'),
                  subtitle: '${controller.maxCacheMB.value} MB',
                  onTap: _showCacheDialog,
                ),
              context.buildTile(
                icon: Remix.file_2_line,
                title: '临时文件',
                subtitle: controller.isStorageScanning.value
                    ? '正在扫描…'
                    : _formatSizeMB(controller.temporaryFileSizeMB.value),
                onTap: controller.isStorageScanning.value
                    ? null
                    : () => controller.refreshStorageStats(forceScan: true),
              ),
              context.buildTile(
                icon: Remix.movie_2_line,
                title: '录制视频',
                subtitle: controller.isStorageScanning.value
                    ? '正在扫描…'
                    : _formatSizeMB(controller.recordedVideoSizeMB.value),
              ),
              context.buildTile(
                icon: Remix.delete_bin_6_line,
                title: '可清理',
                subtitle: controller.isStorageScanning.value
                    ? '正在计算…'
                    : _formatSizeMB(controller.cleanableSizeMB.value),
              ),
              context.buildTile(
                icon: Remix.delete_bin_4_line,
                title: '清理临时文件',
                subtitle: controller.isCleaning.value
                    ? '正在清理…'
                    : '不会删除录制视频；正在录制和整理的批次会被保护',
                onTap: controller.isCleaning.value ||
                        controller.isStorageScanning.value
                    ? null
                    : _showCleanupPreview,
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('record_performance_quality')),
            context.buildModernCard([
              context.buildSwitchTile(
                icon: Remix.video_download_line,
                title: i18n('prefer_best_stream'),
                subtitle: i18n('prefer_best_stream_desc'),
                value: controller.preferBestStream,
              ),
              context.buildTile(
                icon: Remix.timer_flash_line,
                title: i18n('rw_timeout'),
                subtitle: '${controller.rwTimeout.value}s',
                onTap: _showRwTimeoutDialog,
              ),
              context.buildTile(
                icon: Remix.speed_mini_line,
                title: i18n('queue_size'),
                subtitle: '${controller.threadQueueSize.value}',
                onTap: _showQueueSizeDialog,
              ),
              context.buildSliderTile(
                context,
                icon: Remix.film_line,
                title: i18n('segment_duration'),
                value: controller.segmentTime.value.toDouble(),
                min: 60,
                max: 3600,
                displayValue: _formatDuration(controller.segmentTime.value),
                onChanged: (value) =>
                    controller.updateSegmentTime(value.toInt()),
              ),
              context.buildTile(
                icon: Remix.movie_line,
                title: '单个 MP4 最长时长',
                subtitle: _formatMergeDuration(
                  controller.maxMergeDurationSeconds.value,
                ),
                onTap: _showMergeDurationDialog,
              ),
              context.buildTile(
                icon: Remix.task_line,
                title: i18n('max_record_tasks'),
                subtitle: '${controller.maxTaskCount.value}',
                onTap: _showMaxTaskDialog,
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('auto_reconnect')),
            context.buildModernCard([
              context.buildSwitchTile(
                icon: Remix.refresh_line,
                title: i18n('auto_reconnect_switch'),
                subtitle: i18n('auto_reconnect_desc'),
                value: controller.autoReconnect,
              ),
              if (controller.autoReconnect.value)
                context.buildSliderTile(
                  context,
                  icon: Remix.loop_left_line,
                  title: i18n('max_retry_count'),
                  value: controller.maxRetryCount.value.toDouble(),
                  min: 1,
                  max: 20,
                  displayValue: '${controller.maxRetryCount.value}',
                  onChanged: (value) =>
                      controller.updateMaxRetryCount(value.toInt()),
                ),
              context.buildSliderTile(
                context,
                icon: Remix.time_line,
                title: i18n('retry_delay'),
                value: controller.retryDelay.value.toDouble(),
                min: 5,
                max: 120,
                displayValue: '${controller.retryDelay.value}s',
                onChanged: (value) =>
                    controller.updateRetryDelay(value.toInt()),
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('polling_detection')),
            context.buildModernCard([
              context.buildSwitchTile(
                icon: Remix.radar_line,
                title: i18n('enable_polling'),
                subtitle: i18n('enable_polling_desc'),
                value: controller.enablePolling,
              ),
              if (controller.enablePolling.value) ...[
                context.buildSliderTile(
                  context,
                  icon: Remix.time_line,
                  title: i18n('check_interval'),
                  value: controller.liveCheckInterval.value.toDouble(),
                  min: 10,
                  max: 300,
                  displayValue: '${controller.liveCheckInterval.value}s',
                  onChanged: (value) =>
                      controller.updateLiveCheckInterval(value.toInt()),
                ),
                context.buildSwitchTile(
                  icon: Remix.line_chart_line,
                  title: i18n('enable_backoff'),
                  subtitle: i18n('enable_backoff_desc'),
                  value: controller.enableBackoff,
                ),
                if (controller.enableBackoff.value)
                  context.buildSliderTile(
                    context,
                    icon: Remix.hourglass_2_line,
                    title: i18n('max_check_interval'),
                    value: controller.maxCheckInterval.value.toDouble(),
                    min: 300,
                    max: 3600,
                    displayValue: _formatDuration(
                      controller.maxCheckInterval.value,
                    ),
                    onChanged: (value) =>
                        controller.updateMaxCheckInterval(value.toInt()),
                  ),
                context.buildSwitchTile(
                  icon: Remix.shut_down_line,
                  title: i18n('auto_start_boot'),
                  subtitle: i18n('auto_start_boot_desc'),
                  value: controller.autoStartOnBoot,
                ),
              ],
            ]),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Future<void> _showCleanupPreview() async {
    final RecordCleanupPreview preview =
        await controller.prepareCleanupPreview();
    if (Get.context == null) return;

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          '清理临时文件',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('临时文件：${_formatSizeMB(preview.temporaryMB)}'),
            const SizedBox(height: 8),
            Text('录制视频：${_formatSizeMB(controller.recordedVideoSizeMB.value)}'),
            const SizedBox(height: 8),
            Text('可清理：${_formatSizeMB(preview.cleanableMB)}'),
            const SizedBox(height: 14),
            Text('将清理 ${preview.cleanableBatchCount} 个临时批次。'),
            if (preview.protectedBatchCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${preview.protectedBatchCount} 个正在录制或整理的批次已被保护，不会删除。',
              ),
            ],
            const SizedBox(height: 8),
            const Text('MP4 等录制视频不会被删除。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(Get.context!).pop(false),
            child: Text(i18n('cancel')),
          ),
          ElevatedButton(
            onPressed: preview.cleanableBytes <= 0
                ? null
                : () => Navigator.of(Get.context!).pop(true),
            child: Text(i18n('clear')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final deletedBytes = await controller.clearCache();
    Get.snackbar(
      i18n('done'),
      '已清理 ${_formatBytes(deletedBytes)} 临时文件，录制视频未受影响。',
      snackPosition: SnackPosition.bottom,
    );
  }

  void _showMergeDurationDialog() {
    final minimumMinutes = (controller.segmentTime.value / 60).ceil();
    final current = controller.maxMergeDurationSeconds.value;
    final textController = TextEditingController(
      text: current <= 0 ? '' : (current / 60).round().toString(),
    );
    var unlimited = current <= 0;
    final quickMinutes = <int>{
      minimumMinutes,
      30,
      60,
      90,
      120,
      180,
      240,
      360,
    }.where((value) => value >= minimumMinutes).toList()..sort();

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              '单个 MP4 最长时长',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('无上限'),
                  subtitle: const Text('本次录播可以合成为一个完整 MP4'),
                  value: unlimited,
                  onChanged: (value) {
                    setState(() {
                      unlimited = value;
                      if (value) textController.clear();
                    });
                  },
                ),
                if (!unlimited) ...[
                  TextField(
                    controller: textController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '最长时长（分钟）',
                      helperText:
                          '不能小于 TS 分段时长（$minimumMinutes 分钟）',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickMinutes.map((minutes) {
                      final selected =
                          int.tryParse(textController.text) == minutes;
                      return ChoiceChip(
                        label: Text(_formatDuration(minutes * 60)),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            unlimited = false;
                            textController.text = minutes.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(Get.context!).pop(),
                child: Text(i18n('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  if (unlimited) {
                    controller.updateMaxMergeDurationSeconds(0);
                    Navigator.of(Get.context!).pop();
                    return;
                  }

                  final minutes = int.tryParse(textController.text);
                  if (minutes == null || minutes < minimumMinutes) return;
                  controller.updateMaxMergeDurationSeconds(minutes * 60);
                  Navigator.of(Get.context!).pop();
                },
                child: Text(i18n('confirm')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRwTimeoutDialog() {
    final theme = Get.theme;
    final Map<int, String> timeoutOptions = {
      15: i18n('timeout_fast'),
      30: i18n('timeout_balanced'),
      60: i18n('timeout_safe'),
    };

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          i18n('rw_timeout'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: RadioGroup<int>(
          groupValue: controller.rwTimeout.value,
          onChanged: (value) {
            if (value != null) controller.updateRwTimeout(value);
            Navigator.pop(Get.context!);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: timeoutOptions.entries.map((entry) {
              return RadioListTile<int>(
                title: Text(
                  '${entry.key}s',
                  style: AppTextStyles.t16.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(entry.value, style: AppTextStyles.t12),
                value: entry.key,
                activeColor: theme.colorScheme.primary,
                selected: controller.rwTimeout.value == entry.key,
                selectedTileColor:
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showQueueSizeDialog() {
    final theme = Get.theme;
    final List<int> queueOptions = [512, 1024, 2048, 4096, 8192];

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          i18n('queue_size'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: RadioGroup<int>(
          groupValue: controller.threadQueueSize.value,
          onChanged: (value) {
            if (value != null) controller.updateThreadQueueSize(value);
            Navigator.pop(Get.context!);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: queueOptions.map((value) {
              String subtitle;
              if (value <= 512) {
                subtitle = i18n('power_saving_mode');
              } else if (value == 1024) {
                subtitle = i18n('hd_recommend');
              } else if (value == 2048) {
                subtitle = i18n('fhd_recommend');
              } else {
                subtitle = i18n('extreme_performance');
              }

              return RadioListTile<int>(
                title: Text(
                  '$value',
                  style: AppTextStyles.t16.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(subtitle, style: AppTextStyles.t12),
                value: value,
                activeColor: theme.colorScheme.primary,
                selected: controller.threadQueueSize.value == value,
                selectedTileColor:
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showMaxTaskDialog() {
    final theme = Get.theme;
    final textController = TextEditingController(
      text: controller.maxTaskCount.value.toString(),
    );
    final options = List.generate(10, (index) => index + 1);

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              i18n('max_record_tasks'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: i18n('manual_input'),
                    hintText: i18n('input_range'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    i18n('quick_select'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((value) {
                      final selected =
                          int.tryParse(textController.text) == value;
                      return ChoiceChip(
                        label: Text('$value'),
                        selected: selected,
                        onSelected: (_) {
                          textController.text = '$value';
                          setState(() {});
                        },
                        selectedColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(Get.context!).pop(),
                child: Text(i18n('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = int.tryParse(textController.text);
                  if (value == null || value < 1) return;
                  controller.updateMaxTask(value);
                  Navigator.of(Get.context!).pop();
                },
                child: Text(i18n('confirm')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQualityDialog() {
    final theme = Get.theme;

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          i18n('default_record_quality'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: RadioGroup<String>(
          groupValue: controller.defaultQuality.value,
          onChanged: (value) {
            if (value != null) controller.updateDefaultQuality(value);
            Navigator.pop(Get.context!);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlayerConsts.resolutions.map((quality) {
              return RadioListTile<String>(
                title: Text(
                  quality,
                  style: AppTextStyles.t16.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: quality,
                activeColor: theme.colorScheme.primary,
                selected: controller.defaultQuality.value == quality,
                selectedTileColor:
                    theme.colorScheme.primary.withValues(alpha: 0.05),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showCacheDialog() {
    final textController = TextEditingController(
      text: controller.maxCacheMB.value.toString(),
    );

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          i18n('set_max_cache'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          style: AppTextStyles.t18,
          decoration: InputDecoration(
            hintText: i18n('please_input_number'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Get.theme.colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(Get.context!),
            child: Text(i18n('cancel'), style: AppTextStyles.t16),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(textController.text);
              if (value != null) controller.updateMaxCache(value);
              Navigator.pop(Get.context!);
            },
            child: Text(i18n('confirm'), style: AppTextStyles.t16),
          ),
        ],
      ),
    );
  }
}
