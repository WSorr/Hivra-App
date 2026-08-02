import 'dart:io';

import 'package:share_plus/share_plus.dart';

typedef BackupPathExporter = Future<String?> Function(String targetPath);
typedef BackupFileSharer = Future<void> Function(String path);
typedef TemporaryDirectoryCreator = Future<Directory> Function(String prefix);

class TemporaryBackupShareService {
  final TemporaryDirectoryCreator _createTemporaryDirectory;
  final BackupFileSharer _shareFile;

  TemporaryBackupShareService({
    TemporaryDirectoryCreator? createTemporaryDirectory,
    BackupFileSharer? shareFile,
  }) : _createTemporaryDirectory =
           createTemporaryDirectory ?? Directory.systemTemp.createTemp,
       _shareFile = shareFile ?? _shareBackupFile;

  Future<bool> share({required BackupPathExporter exportToPath}) async {
    final directory = await _createTemporaryDirectory('hivra-backup-share-');
    try {
      final targetPath = '${directory.path}/capsule-backup.hivra.json';
      final exportedPath = await exportToPath(targetPath);
      if (exportedPath == null) return false;
      await _shareFile(exportedPath);
      return true;
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
