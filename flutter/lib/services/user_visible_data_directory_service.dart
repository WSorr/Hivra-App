import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UserVisibleDataDirectoryService {
  static const String _legacyContainerBundleId = 'com.hivra.hivraApp';
  static const String _rootName = 'Hivra';
  static const String _backupsDirName = 'Backups';
  static const String _ledgerExportsDirName = 'Ledger Exports';
  static const String _pluginsDirName = 'Plugins';
  static const String _capsulesDirName = 'capsules';
  static const String _cardsFileName = 'capsule_contact_cards.json';

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

    await _migrateLegacyDocumentsIfNeeded(root);

    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> capsulesDirectory({bool create = false}) async {
    final root = await rootDirectory(create: create);
    final dir = Directory('${root.path}/$_capsulesDirName');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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

  Future<Directory?> legacyContainerDocumentsDirectory() async {
    return _legacyContainerDocumentsDirectory();
  }

  Future<void> _migrateLegacyDocumentsIfNeeded(Directory targetRoot) async {
    final legacyDocs = await _legacyContainerDocumentsDirectory();
    if (legacyDocs == null || !await legacyDocs.exists()) return;

    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    await _mergeDirectory(
      Directory('${legacyDocs.path}/$_rootName'),
      targetRoot,
    );
    await _mergeDirectory(
      Directory('${legacyDocs.path}/$_capsulesDirName'),
      Directory('${targetRoot.path}/$_capsulesDirName'),
    );
    await _copyFileIfMissing(
      File('${legacyDocs.path}/$_cardsFileName'),
      File('${targetRoot.path}/$_cardsFileName'),
    );
    await _migrateFlatLegacyCardsIfNeeded(targetRoot);
  }

  Future<void> _migrateFlatLegacyCardsIfNeeded(Directory targetRoot) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final legacyFlatCards = File('$home/Documents/$_cardsFileName');
    if (!await legacyFlatCards.exists()) return;

    final canonicalCards = File('${targetRoot.path}/$_cardsFileName');
    if (!await canonicalCards.exists()) {
      await _copyFileIfMissing(legacyFlatCards, canonicalCards);
    } else {
      final merged = await _mergeCardsFile(legacyFlatCards, canonicalCards);
      if (merged != null) {
        await canonicalCards.writeAsString(
          const JsonEncoder.withIndent('  ').convert(merged),
        );
      }
    }

    try {
      await legacyFlatCards.delete();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _mergeCardsFile(
    File legacyFlatCards,
    File canonicalCards,
  ) async {
    try {
      final legacyRaw = await legacyFlatCards.readAsString();
      final canonicalRaw = await canonicalCards.readAsString();
      final legacyDecoded = jsonDecode(legacyRaw);
      final canonicalDecoded = jsonDecode(canonicalRaw);

      final legacyMap = legacyDecoded is Map
          ? Map<String, dynamic>.from(legacyDecoded)
          : <String, dynamic>{};
      final canonicalMap = canonicalDecoded is Map
          ? Map<String, dynamic>.from(canonicalDecoded)
          : <String, dynamic>{};

      for (final entry in legacyMap.entries) {
        canonicalMap.putIfAbsent(entry.key, () => entry.value);
      }
      return canonicalMap;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _legacyContainerDocumentsDirectory() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return Directory(
      '$home/Library/Containers/$_legacyContainerBundleId/Data/Documents',
    );
  }

  Future<void> _mergeDirectory(Directory source, Directory target) async {
    if (!await source.exists()) return;
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name == null || name.isEmpty) continue;

      if (entity is Directory) {
        await _mergeDirectory(entity, Directory('${target.path}/$name'));
      } else if (entity is File) {
        await _copyFileIfMissing(entity, File('${target.path}/$name'));
      }
    }
  }

  Future<void> _copyFileIfMissing(File source, File target) async {
    if (!await source.exists() || await target.exists()) return;
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await source.copy(target.path);
  }
}
