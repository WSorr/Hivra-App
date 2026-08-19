import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'application_documents_directory.dart';
import 'atomic_file_write_service.dart';

class UserVisibleDataDirectoryService {
  static const String _legacyContainerBundleId = 'com.hivra.hivraApp';
  static const String _rootName = 'Hivra';
  static const String _backupsDirName = 'Backups';
  static const String _ledgerExportsDirName = 'Ledger Exports';
  static const String _pluginsDirName = 'Plugins';
  static const String _capsulesDirName = 'capsules';
  static const String _cardsFileName = 'capsule_contact_cards.json';
  static const String _runtimeMigrationDoneFile =
      '.documents_runtime_migration_v1.done';
  static const List<String> _runtimeDirectoryNames = <String>[
    _capsulesDirName,
    _pluginsDirName,
    'logs',
    'Developer Cache',
  ];
  static const List<String> _runtimeFileNames = <String>[
    _cardsFileName,
    'bingx_futures_credentials.json',
  ];
  static Future<void> _migrationTail = Future<void>.value();
  static String? _testHomeOverride;

  final String? _homeOverride;
  final AtomicFileWriteService _atomicWrites;

  const UserVisibleDataDirectoryService({
    String? homeOverride,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _homeOverride = homeOverride,
       _atomicWrites = atomicWrites;

  static String? get testHomeOverride => _testHomeOverride;

  static void setTestHomeOverride(String? path) {
    _testHomeOverride = path;
  }

  Future<Directory> rootDirectory({bool create = false}) async {
    final root = await _runtimeRootDirectory();
    await _serializeMigration(() => _migrateRuntimeDataIfNeeded(root));

    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> userVisibleRootDirectory({bool create = false}) async {
    final home = _resolvedHome;
    Directory root;

    if (home != null && home.isNotEmpty) {
      root = Directory('$home/Documents/$_rootName');
    } else {
      final docs = await resolveApplicationDocumentsDirectory();
      root = Directory('${docs.path}/$_rootName');
    }

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
    final root = await userVisibleRootDirectory(create: create);
    final dir = Directory('${root.path}/$_backupsDirName');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> ledgerExportsDirectory({bool create = false}) async {
    final root = await userVisibleRootDirectory(create: create);
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

  Future<Directory> _runtimeRootDirectory() async {
    final home = _resolvedHome;
    if ((_homeOverride != null ||
            _testHomeOverride != null ||
            Platform.isMacOS) &&
        home != null &&
        home.isNotEmpty) {
      return Directory('$home/Library/Application Support/$_rootName');
    }

    final docs = await resolveApplicationDocumentsDirectory();
    return Directory('${docs.path}/$_rootName');
  }

  Future<void> _migrateRuntimeDataIfNeeded(Directory targetRoot) async {
    final marker = File('${targetRoot.path}/$_runtimeMigrationDoneFile');
    if (await marker.exists()) return;

    final visibleRoot = await userVisibleRootDirectory();
    final sources = <Directory>[];
    if (await _hasRuntimeData(visibleRoot)) {
      // Documents/Hivra was the latest canonical location before this move.
      // Do not merge an older sandbox copy over it.
      sources.add(visibleRoot);
    } else {
      final legacyDocs = await _legacyContainerDocumentsDirectory();
      if (legacyDocs != null) {
        final legacyRoot = Directory('${legacyDocs.path}/$_rootName');
        if (await _hasRuntimeData(legacyRoot)) {
          sources.add(legacyRoot);
        } else if (await _hasRuntimeData(legacyDocs)) {
          sources.add(legacyDocs);
        }
      }
    }

    var foundRuntimeData = false;
    for (final source in sources) {
      if (_samePath(source.path, targetRoot.path) || !await source.exists()) {
        continue;
      }
      foundRuntimeData =
          await _mergeRuntimeData(source, targetRoot) || foundRuntimeData;
    }

    final targetHasRuntimeData = await _hasRuntimeData(targetRoot);
    if (!foundRuntimeData && !targetHasRuntimeData) {
      return;
    }

    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }
    await _atomicWrites.writeString(
      marker,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<bool> _mergeRuntimeData(
    Directory sourceRoot,
    Directory targetRoot,
  ) async {
    var found = false;
    for (final name in _runtimeDirectoryNames) {
      final source = Directory('${sourceRoot.path}/$name');
      if (!await source.exists()) continue;
      found = true;
      await _mergeDirectoryChecked(
        source,
        Directory('${targetRoot.path}/$name'),
      );
    }
    for (final name in _runtimeFileNames) {
      final source = File('${sourceRoot.path}/$name');
      if (!await source.exists()) continue;
      found = true;
      final target = File('${targetRoot.path}/$name');
      if (name == _cardsFileName) {
        await _mergeCardsFileChecked(source, target);
      } else {
        await _copyFileChecked(source, target);
      }
    }
    return found;
  }

  Future<bool> _hasRuntimeData(Directory root) async {
    if (!await root.exists()) return false;
    for (final name in _runtimeDirectoryNames) {
      if (await Directory('${root.path}/$name').exists()) return true;
    }
    for (final name in _runtimeFileNames) {
      if (await File('${root.path}/$name').exists()) return true;
    }
    return false;
  }

  Future<void> _mergeDirectoryChecked(
    Directory source,
    Directory target,
  ) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    await for (final entity in source.list(followLinks: false)) {
      final name =
          entity.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .lastOrNull;
      if (name == null || name.isEmpty) continue;
      if (entity is Directory) {
        await _mergeDirectoryChecked(entity, Directory('${target.path}/$name'));
      } else if (entity is File) {
        await _copyFileChecked(entity, File('${target.path}/$name'));
      }
    }
  }

  Future<void> _copyFileChecked(File source, File target) async {
    final sourceBytes = await source.readAsBytes();
    if (await target.exists()) {
      final targetBytes = await target.readAsBytes();
      if (!_sameBytes(sourceBytes, targetBytes)) {
        throw StateError(
          'Runtime storage migration conflict for ${target.path}',
        );
      }
      return;
    }
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await _atomicWrites.writeBytes(target, sourceBytes);
    final persistedBytes = await target.readAsBytes();
    if (!_sameBytes(sourceBytes, persistedBytes)) {
      throw StateError('Runtime storage migration verification failed');
    }
  }

  Future<void> _mergeCardsFileChecked(File source, File target) async {
    if (!await target.exists()) {
      await _copyFileChecked(source, target);
      return;
    }
    final sourceMap = _parseJsonMap(await source.readAsString());
    final targetMap = _parseJsonMap(await target.readAsString());
    if (sourceMap == null || targetMap == null) {
      throw StateError('Contact-card migration source is unreadable');
    }
    var changed = false;
    for (final entry in sourceMap.entries) {
      if (!targetMap.containsKey(entry.key)) {
        targetMap[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) {
      await _atomicWrites.writeString(
        target,
        const JsonEncoder.withIndent('  ').convert(targetMap),
      );
    }
  }

  Future<T> _serializeMigration<T>(Future<T> Function() operation) {
    final previous = _migrationTail;
    final release = Completer<void>();
    _migrationTail = release.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    }();
  }

  bool _samePath(String a, String b) =>
      Directory(a).absolute.path == Directory(b).absolute.path;

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<Directory?> _legacyContainerDocumentsDirectory() async {
    final home = _resolvedHome;
    if (home == null || home.isEmpty) return null;
    return Directory(
      '$home/Library/Containers/$_legacyContainerBundleId/Data/Documents',
    );
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  String? get _resolvedHome =>
      _homeOverride ?? _testHomeOverride ?? Platform.environment['HOME'];
}
