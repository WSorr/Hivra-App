import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UserVisibleDataDirectoryService {
  static const String _rootName = 'Hivra';
  static const String _backupsDirName = 'Backups';
  static const String _ledgerExportsDirName = 'Ledger Exports';
  static const String _pluginsDirName = 'Plugins';

  const UserVisibleDataDirectoryService();

  Future<Directory> rootDirectory({bool create = false}) async {
    final home = Platform.environment['HOME'];
    Directory root;

    if (home != null && home.isNotEmpty) {
      root = Directory('$home/Documents/$_rootName');
    } else {
      final docs = await getApplicationDocumentsDirectory();
      root = Directory('${docs.path}/$_rootName');
    }

    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> backupsDirectory({bool create = false}) async {
    final root = await rootDirectory(create: create);
    final dir = Directory('${root.path}/$_backupsDirName');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> ledgerExportsDirectory({bool create = false}) async {
    final root = await rootDirectory(create: create);
    final dir = Directory('${root.path}/$_ledgerExportsDirName');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> pluginsDirectory({bool create = false}) async {
    final root = await rootDirectory(create: create);
    final dir = Directory('${root.path}/$_pluginsDirName');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
