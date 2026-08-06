import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/models/record_storage_snapshot.dart';
import 'package:pure_live/recorder/services/path_helper.dart';

class CacheService extends GetxService {
  static CacheService get to => Get.find();

  static const Duration _indexCalibrationInterval = Duration(minutes: 30);

  RecordStorageSnapshot? _snapshot;
  List<TemporaryRecordingBatch> _temporaryBatches = const [];
  Completer<RecordStorageSnapshot>? _scanCompleter;
  int _temporaryDeltaBytes = 0;
  int _recordedVideoDeltaBytes = 0;

  final Map<String, Set<String>> _protectionOwners = {};

  Future<Directory> getRecordDir() async {
    final customPath = HivePrefUtil.getString(RecorderKeys.recordSavePath);
    Directory recordDir;
    if (customPath != null && customPath.isNotEmpty) {
      recordDir = Directory(customPath);
    } else {
      recordDir = await AppPathManager().getDir(AppPathManager.dirRecords);
    }
    if (!await recordDir.exists()) {
      await recordDir.create(recursive: true);
    }
    return recordDir;
  }

  Future<RecordStorageSnapshot> getStorageSnapshot({bool forceScan = false}) async {
    final current = _snapshot;
    final isStale = current == null ||
        DateTime.now().difference(current.scannedAt) >=
            _indexCalibrationInterval;

    if (forceScan || isStale) {
      await calibrateStorageIndex();
    }

    final base = _snapshot ??
        RecordStorageSnapshot(
          temporaryBytes: 0,
          recordedVideoBytes: 0,
          scannedAt: DateTime.now(),
        );

    return base.copyWith(
      temporaryBytes: max(0, base.temporaryBytes + _temporaryDeltaBytes),
      recordedVideoBytes:
          max(0, base.recordedVideoBytes + _recordedVideoDeltaBytes),
    );
  }

  Future<RecordStorageSnapshot> calibrateStorageIndex() async {
    final activeScan = _scanCompleter;
    if (activeScan != null) return activeScan.future;

    final completer = Completer<RecordStorageSnapshot>();
    _scanCompleter = completer;

    try {
      final root = await getRecordDir();
      final raw = await Isolate.run<Map<String, dynamic>>(
        () => _scanRecordStorageSync(root.path),
      );

      final batches = <TemporaryRecordingBatch>[];
      for (final item in (raw['batches'] as List<dynamic>? ?? const [])) {
        final map = Map<String, dynamic>.from(item as Map);
        batches.add(
          TemporaryRecordingBatch(
            directoryPath: map['directoryPath'] as String,
            batchId: map['batchId'] as String,
            filePaths: List<String>.from(map['filePaths'] as List),
            totalBytes: map['totalBytes'] as int,
            oldestModified: DateTime.fromMillisecondsSinceEpoch(
              map['oldestModifiedMs'] as int,
            ),
            newestModified: DateTime.fromMillisecondsSinceEpoch(
              map['newestModifiedMs'] as int,
            ),
          ),
        );
      }

      _temporaryBatches = batches;
      _temporaryDeltaBytes = 0;
      _recordedVideoDeltaBytes = 0;
      _snapshot = RecordStorageSnapshot(
        temporaryBytes: raw['temporaryBytes'] as int? ?? 0,
        recordedVideoBytes: raw['recordedVideoBytes'] as int? ?? 0,
        scannedAt: DateTime.now(),
      );
      completer.complete(_snapshot!);
    } catch (error, stackTrace) {
      developer.log(
        'Record storage scan failed: $error',
        name: 'CacheService',
        stackTrace: stackTrace,
      );
      final fallback = _snapshot ??
          RecordStorageSnapshot(
            temporaryBytes: 0,
            recordedVideoBytes: 0,
            scannedAt: DateTime.now(),
          );
      completer.complete(fallback);
    } finally {
      _scanCompleter = null;
    }

    return completer.future;
  }

  void invalidateStorageIndex() {
    _snapshot = null;
    _temporaryBatches = const [];
    _temporaryDeltaBytes = 0;
    _recordedVideoDeltaBytes = 0;
  }

  void noteTemporaryBytes(int deltaBytes) {
    _temporaryDeltaBytes += deltaBytes;
  }

  void noteRecordedVideoBytes(int deltaBytes) {
    _recordedVideoDeltaBytes += deltaBytes;
  }

  Future<double> getCacheSize() async {
    final snapshot = await getStorageSnapshot();
    return snapshot.temporaryMB;
  }

  void protectPath(String path, String owner) {
    if (path.isEmpty || owner.isEmpty) return;
    final normalized = _normalizePath(path);
    _protectionOwners.putIfAbsent(normalized, () => <String>{}).add(owner);
  }

  void releasePath(String path, String owner) {
    if (path.isEmpty || owner.isEmpty) return;
    final normalized = _normalizePath(path);
    final owners = _protectionOwners[normalized];
    owners?.remove(owner);
    if (owners == null || owners.isEmpty) {
      _protectionOwners.remove(normalized);
    }
  }

  bool isPathProtected(String path) {
    final candidate = _normalizePath(path);
    for (final protectedPath in _protectionOwners.keys) {
      if (candidate == protectedPath ||
          p.isWithin(protectedPath, candidate) ||
          p.isWithin(candidate, protectedPath)) {
        return true;
      }
    }
    return false;
  }

  Future<RecordCleanupPreview> getCleanupPreview({
    bool forceScan = true,
  }) async {
    final snapshot = await getStorageSnapshot(forceScan: forceScan);
    var cleanableBytes = 0;
    var cleanableBatchCount = 0;
    var protectedBatchCount = 0;

    for (final batch in _temporaryBatches) {
      if (isPathProtected(batch.directoryPath)) {
        protectedBatchCount++;
      } else {
        cleanableBatchCount++;
        cleanableBytes += batch.totalBytes;
      }
    }

    return RecordCleanupPreview(
      temporaryBytes: snapshot.temporaryBytes,
      cleanableBytes: cleanableBytes,
      cleanableBatchCount: cleanableBatchCount,
      protectedBatchCount: protectedBatchCount,
    );
  }

  Future<int> clearTemporaryFiles() async {
    await getStorageSnapshot(forceScan: true);
    var deletedBytes = 0;

    final batches = [..._temporaryBatches]
      ..sort((a, b) => a.oldestModified.compareTo(b.oldestModified));

    for (final batch in batches) {
      if (isPathProtected(batch.directoryPath)) continue;
      deletedBytes += await _deleteBatchFiles(batch);
    }

    await _deleteEmptyDirectories();
    await calibrateStorageIndex();
    return deletedBytes;
  }

  Future<void> clearAll() async {
    await clearTemporaryFiles();
  }

  Future<void> deleteOldest() async {
    await getStorageSnapshot(forceScan: _snapshot == null);
    final candidates = _temporaryBatches
        .where((batch) => !isPathProtected(batch.directoryPath))
        .toList()
      ..sort((a, b) => a.oldestModified.compareTo(b.oldestModified));
    if (candidates.isEmpty) return;

    final deleted = await _deleteBatchFiles(candidates.first);
    if (deleted > 0) {
      noteTemporaryBytes(-deleted);
      _temporaryBatches = _temporaryBatches
          .where((batch) => !identical(batch, candidates.first))
          .toList(growable: false);
      await _deleteEmptyDirectories();
    }
  }

  Future<void> enforceLimit({double maxMB = 2048}) async {
    final snapshot = await getStorageSnapshot();
    final maxBytes = (maxMB * 1024 * 1024).round();
    var estimatedBytes = snapshot.temporaryBytes;
    if (estimatedBytes <= maxBytes) return;

    final candidates = _temporaryBatches
        .where((batch) => !isPathProtected(batch.directoryPath))
        .toList()
      ..sort((a, b) => a.oldestModified.compareTo(b.oldestModified));

    final deletedKeys = <String>{};
    var deletedBytes = 0;
    for (final batch in candidates) {
      if (estimatedBytes <= maxBytes) break;
      final deleted = await _deleteBatchFiles(batch);
      if (deleted <= 0) continue;
      deletedBytes += deleted;
      estimatedBytes = max(0, estimatedBytes - deleted);
      deletedKeys.add('${batch.directoryPath}|${batch.batchId}');
    }

    if (deletedBytes > 0) {
      noteTemporaryBytes(-deletedBytes);
      _temporaryBatches = _temporaryBatches
          .where(
            (batch) => !deletedKeys.contains(
              '${batch.directoryPath}|${batch.batchId}',
            ),
          )
          .toList(growable: false);
      await _deleteEmptyDirectories();
    }
  }

  Future<List<RecoverableRecordingBatch>> findRecoverableBatches({
    bool forceScan = true,
  }) async {
    await getStorageSnapshot(forceScan: forceScan);
    final result = <RecoverableRecordingBatch>[];

    for (final batch in _temporaryBatches) {
      if (isPathProtected(batch.directoryPath)) continue;

      final tsFiles = <String>[];
      var totalBytes = 0;
      for (final path in batch.filePaths) {
        if (p.extension(path).toLowerCase() != '.ts') continue;
        final file = File(path);
        try {
          final length = file.lengthSync();
          if (length < 188) continue;
          tsFiles.add(path);
          totalBytes += length;
        } catch (_) {}
      }
      if (tsFiles.isEmpty) continue;

      tsFiles.sort();
      result.add(
        RecoverableRecordingBatch(
          directoryPath: batch.directoryPath,
          batchId: batch.batchId,
          tsFilePaths: tsFiles,
          totalBytes: totalBytes,
          startTime: batch.oldestModified,
          endTime: batch.newestModified,
        ),
      );
    }

    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  Future<RecordDiskSpaceInfo?> getDiskSpaceInfo([String? path]) async {
    if (!Platform.isWindows) return null;

    try {
      final target = path == null || path.isEmpty
          ? (await getRecordDir()).path
          : path;
      final root = p.rootPrefix(Directory(target).absolute.path);
      if (root.isEmpty) return null;
      final escapedRoot = root.replaceAll("'", "''");
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "[System.IO.DriveInfo]::new('$escapedRoot').AvailableFreeSpace",
        ],
      );
      if (result.exitCode != 0) return null;
      final bytes = int.tryParse(result.stdout.toString().trim());
      if (bytes == null) return null;
      return RecordDiskSpaceInfo(rootPath: root, availableBytes: bytes);
    } catch (error) {
      developer.log(
        'Disk space query failed: $error',
        name: 'CacheService',
      );
      return null;
    }
  }

  Future<void> clearSystemTemp() async {
    if (!Platform.isWindows) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final systemTemp = tempDir.parent;
      if (await systemTemp.exists()) {
        for (final entity in systemTemp.listSync()) {
          final name = p.basename(entity.path);
          if (name.toLowerCase().startsWith('pure_live')) {
            try {
              await entity.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<String> getDisplayPath() async {
    final dir = await getRecordDir();
    return dir.path;
  }

  Future<Directory> createRoomDir(String roomId) async {
    final base = await getRecordDir();
    final roomDir = Directory(p.join(base.path, roomId));
    if (!await roomDir.exists()) {
      await roomDir.create(recursive: true);
    }
    return roomDir;
  }

  Future<Directory> getRoomDir({
    required String platform,
    required String nick,
    bool usePinyinForFolder = false,
  }) async {
    final base = await getRecordDir();
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}-'
        '${now.second.toString().padLeft(2, '0')}';
    final safePlatform =
        usePinyinForFolder ? PathHelper.toSafePinyin(platform) : platform;
    final safeNick =
        usePinyinForFolder ? PathHelper.toSafePinyin(nick) : nick;
    final dir = Directory(
      p.join(base.path, safePlatform, safeNick, date, time),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<int> _deleteBatchFiles(TemporaryRecordingBatch batch) async {
    var deletedBytes = 0;
    for (final path in batch.filePaths) {
      final file = File(path);
      try {
        if (!file.existsSync()) continue;
        final length = file.lengthSync();
        file.deleteSync();
        deletedBytes += length;
      } catch (_) {}
    }
    return deletedBytes;
  }

  Future<void> _deleteEmptyDirectories() async {
    final root = await getRecordDir();
    if (!root.existsSync()) return;

    final directories = root
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));

    for (final directory in directories) {
      if (isPathProtected(directory.path)) continue;
      try {
        if (directory.listSync().isEmpty) {
          directory.deleteSync();
        }
      } catch (_) {}
    }
  }

  static String _normalizePath(String value) {
    return p.normalize(p.absolute(value)).toLowerCase();
  }
}

Map<String, dynamic> _scanRecordStorageSync(String rootPath) {
  final root = Directory(rootPath);
  var temporaryBytes = 0;
  var recordedVideoBytes = 0;
  final batches = <String, Map<String, dynamic>>{};

  if (!root.existsSync()) {
    return {
      'temporaryBytes': 0,
      'recordedVideoBytes': 0,
      'batches': <Map<String, dynamic>>[],
    };
  }

  List<FileSystemEntity> entities;
  try {
    entities = root.listSync(recursive: true, followLinks: false);
  } catch (_) {
    entities = const [];
  }

  for (final entity in entities) {
    if (entity is! File) continue;

    try {
      final length = entity.lengthSync();
      final path = entity.path;
      if (_isTemporaryFile(path)) {
        temporaryBytes += length;
        final identity = _temporaryBatchIdentity(path);
        final stat = entity.statSync();
        final modifiedMs = stat.modified.millisecondsSinceEpoch;
        final batch = batches.putIfAbsent(
          identity.key,
          () => {
            'directoryPath': identity.directoryPath,
            'batchId': identity.batchId,
            'filePaths': <String>[],
            'totalBytes': 0,
            'oldestModifiedMs': modifiedMs,
            'newestModifiedMs': modifiedMs,
          },
        );
        (batch['filePaths'] as List<String>).add(path);
        batch['totalBytes'] = (batch['totalBytes'] as int) + length;
        batch['oldestModifiedMs'] =
            min(batch['oldestModifiedMs'] as int, modifiedMs);
        batch['newestModifiedMs'] =
            max(batch['newestModifiedMs'] as int, modifiedMs);
      } else if (_isRecordedVideoFile(path)) {
        recordedVideoBytes += length;
      }
    } catch (_) {}
  }

  return {
    'temporaryBytes': temporaryBytes,
    'recordedVideoBytes': recordedVideoBytes,
    'batches': batches.values.toList(growable: false),
  };
}

bool _isTemporaryFile(String path) {
  final name = p.basename(path).toLowerCase();
  final extension = p.extension(name);
  return extension == '.ts' ||
      extension == '.partial' ||
      extension == '.tmp' ||
      name.contains('.partial.') ||
      name == 'list.txt' ||
      name.endsWith('_list.txt');
}

bool _isRecordedVideoFile(String path) {
  const extensions = {'.mp4', '.mkv', '.mov', '.m4v', '.flv'};
  return extensions.contains(p.extension(path).toLowerCase());
}

_TemporaryBatchIdentity _temporaryBatchIdentity(String path) {
  final directoryPath = p.dirname(path);
  final name = p.basename(path);
  final segmentMatch = RegExp(
    r'^(.+)_s\d{3}_\d{5}\.ts$',
    caseSensitive: false,
  ).firstMatch(name);
  if (segmentMatch != null) {
    final batchId = segmentMatch.group(1)!;
    return _TemporaryBatchIdentity(
      key: '${directoryPath.toLowerCase()}|$batchId',
      directoryPath: directoryPath,
      batchId: batchId,
    );
  }

  final listMatch = RegExp(
    r'^(.+)_list\.txt$',
    caseSensitive: false,
  ).firstMatch(name);
  if (listMatch != null) {
    final batchId = listMatch.group(1)!;
    return _TemporaryBatchIdentity(
      key: '${directoryPath.toLowerCase()}|$batchId',
      directoryPath: directoryPath,
      batchId: batchId,
    );
  }

  final legacyId = 'legacy_${p.basename(directoryPath)}';
  return _TemporaryBatchIdentity(
    key: '${directoryPath.toLowerCase()}|$legacyId',
    directoryPath: directoryPath,
    batchId: legacyId,
  );
}

class _TemporaryBatchIdentity {
  final String key;
  final String directoryPath;
  final String batchId;

  const _TemporaryBatchIdentity({
    required this.key,
    required this.directoryPath,
    required this.batchId,
  });
}
