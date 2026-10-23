import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'hivra_file_picker_service.dart';

typedef BackupPathExporter = Future<String?> Function(String targetPath);
typedef BackupFileSharer = Future<void> Function(String path);
typedef TemporaryDirectoryCreator = Future<Directory> Function(String prefix);

class BackupFileExportService {
  final bool _isAndroid;
  final TemporaryDirectoryCreator _createTemporaryDirectory;
  final BackupFileSharer _shareFile;

  BackupFileExportService({
    bool? isAndroid,
    TemporaryDirectoryCreator? createTemporaryDirectory,
    BackupFileSharer? shareFile,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _createTemporaryDirectory =
           createTemporaryDirectory ?? Directory.systemTemp.createTemp,
       _shareFile = shareFile ?? _shareBackupFile;

  Future<String?> save({
    required String capsuleId,
    required BackupPathExporter exportToPath,
    required bool Function() isCurrent,
  }) async {
    final name = suggestedName(capsuleId);
    if (!_isAndroid) {
      final path = await HivraFilePickerService.saveJsonDocument(
        suggestedName: name,
        confirmButtonText: 'Save Backup',
      );
      if (!isCurrent() || path == null || path.isEmpty) return null;
      final saved = await exportToPath(path);
      if (saved == null) throw StateError('Failed to export capsule backup');
      return saved;
    }
    return _withTemporaryExport(name, exportToPath, (path) async {
      if (!isCurrent()) return null;
      return HivraFilePickerService.saveExistingJsonDocument(
        sourcePath: path,
        suggestedName: name,
      );
    });
  }

  static String suggestedName(String capsuleId, {DateTime? at}) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(capsuleId)) {
      throw const FormatException('A Capsule ID is required for backup');
    }
    final date = (at ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    return 'hivra-capsule-$capsuleId-$date.json';
  }

  Future<void> share({
    required String capsuleId,
    required BackupPathExporter exportToPath,
  }) async {
    await _withTemporaryExport(
      suggestedName(capsuleId),
      exportToPath,
      _shareFile,
    );
  }

  Future<T> _withTemporaryExport<T>(
    String name,
    BackupPathExporter exportToPath,
    Future<T> Function(String) consume,
  ) async {
    final directory = await _createTemporaryDirectory('hivra-backup-share-');
    try {
      final targetPath = '${directory.path}/$name';
      final exportedPath = await exportToPath(targetPath);
      if (exportedPath == null) {
        throw StateError('Failed to export capsule backup');
      }
      return await consume(exportedPath);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  static Future<void> _shareBackupFile(String path) async {
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(path)], text: 'Hivra capsule backup'),
    );
  }
}
