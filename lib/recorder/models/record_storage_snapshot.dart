class RecordStorageSnapshot {
  final int temporaryBytes;
  final int recordedVideoBytes;
  final DateTime scannedAt;

  const RecordStorageSnapshot({
    required this.temporaryBytes,
    required this.recordedVideoBytes,
    required this.scannedAt,
  });

  double get temporaryMB => temporaryBytes / 1024 / 1024;
  double get recordedVideoMB => recordedVideoBytes / 1024 / 1024;

  RecordStorageSnapshot copyWith({
    int? temporaryBytes,
    int? recordedVideoBytes,
    DateTime? scannedAt,
  }) {
    return RecordStorageSnapshot(
      temporaryBytes: temporaryBytes ?? this.temporaryBytes,
      recordedVideoBytes: recordedVideoBytes ?? this.recordedVideoBytes,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}

class RecordCleanupPreview {
  final int temporaryBytes;
  final int cleanableBytes;
  final int cleanableBatchCount;
  final int protectedBatchCount;

  const RecordCleanupPreview({
    required this.temporaryBytes,
    required this.cleanableBytes,
    required this.cleanableBatchCount,
    required this.protectedBatchCount,
  });

  double get temporaryMB => temporaryBytes / 1024 / 1024;
  double get cleanableMB => cleanableBytes / 1024 / 1024;
}

class TemporaryRecordingBatch {
  final String directoryPath;
  final String batchId;
  final List<String> filePaths;
  final int totalBytes;
  final DateTime oldestModified;
  final DateTime newestModified;

  const TemporaryRecordingBatch({
    required this.directoryPath,
    required this.batchId,
    required this.filePaths,
    required this.totalBytes,
    required this.oldestModified,
    required this.newestModified,
  });
}

class RecoverableRecordingBatch {
  final String directoryPath;
  final String batchId;
  final List<String> tsFilePaths;
  final int totalBytes;
  final DateTime startTime;
  final DateTime endTime;

  const RecoverableRecordingBatch({
    required this.directoryPath,
    required this.batchId,
    required this.tsFilePaths,
    required this.totalBytes,
    required this.startTime,
    required this.endTime,
  });
}

class RecordDiskSpaceInfo {
  final String rootPath;
  final int availableBytes;

  const RecordDiskSpaceInfo({
    required this.rootPath,
    required this.availableBytes,
  });

  double get availableGB => availableBytes / 1024 / 1024 / 1024;
}
