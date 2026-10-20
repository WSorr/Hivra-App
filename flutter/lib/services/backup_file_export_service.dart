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
    required BackupPathExporter exportToPath,
    required bool Function() isCurrent,
  }) async {
    final name = 'capsule-backup-${DateTime.now().millisecondsSinceEpoch}.json';
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
    return _withTemporaryExport(exportToPath, (path) async {
      if (!isCurrent()) return null;
      return HivraFilePickerService.saveExistingJsonDocument(
        sourcePath: path,
        suggestedName: name,
      );
    });
  }

  Future<void> share({required BackupPathExporter exportToPath}) async {
    await _withTemporaryExport(exportToPath, _shareFile);
  }

  Future<T> _withTemporaryExport<T>(
    BackupPathExporter exportToPath,
    Future<T> Function(String) consume,
  ) async {
    final directory = await _createTemporaryDirectory('hivra-backup-share-');
    try {
      final targetPath = '${directory.path}/capsule-backup.hivra.json';
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
