import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/wasm_plugin_models.dart';
import 'atomic_file_write_service.dart';
import 'user_visible_data_directory_service.dart';
import 'wasm_plugin_package_preflight_service.dart';

class WasmPluginRegistryService {
  static const String _registryFileName = 'registry.json';
  static Future<void> _mutationTail = Future<void>.value();
  final UserVisibleDataDirectoryService _dataDirs;
  final WasmPluginPackagePreflightService _preflight;
  final AtomicFileWriteService _atomicWrites;

  const WasmPluginRegistryService({
    UserVisibleDataDirectoryService dataDirs =
        const UserVisibleDataDirectoryService(),
    WasmPluginPackagePreflightService preflight =
        const WasmPluginPackagePreflightService(),
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _dataDirs = dataDirs,
       _preflight = preflight,
       _atomicWrites = atomicWrites;

  Future<Directory> pluginsDirectory({bool create = false}) async {
    return _dataDirs.pluginsDirectory(create: create);
  }

  Future<File> _registryFile({bool createDir = false}) async {
    final dir = await pluginsDirectory(create: createDir);
    return File('${dir.path}/$_registryFileName');
  }

  Future<List<WasmPluginRecord>> loadPlugins() async {
    return _serialized(() => _loadPluginsUnlocked());
  }

  Future<List<WasmPluginRecord>> _loadPluginsUnlocked({
    bool failClosed = false,
  }) async {
    final file = await _registryFile();
    if (!await file.exists()) {
      await _cleanupUnreferencedFiles(const <WasmPluginRecord>[]);
      return const <WasmPluginRecord>[];
    }

    try {
      final decoded = _parseJsonList(await file.readAsString());
      if (decoded == null) {
        throw const FormatException('Plugin registry must be a JSON list');
      }
      final records =
          decoded
              .map(_coerceJsonMap)
              .whereType<Map<String, dynamic>>()
              .map(WasmPluginRecord.fromJson)
              .toList()
            ..sort((a, b) => b.installedAtIso.compareTo(a.installedAtIso));
      final deduped = _dedupeByPluginId(records);
      final existingOnly = await _filterRecordsWithStoredFile(deduped);
      if (existingOnly.length != records.length) {
        final stale =
            records
                .where(
                  (record) => !existingOnly.any((kept) => kept.id == record.id),
                )
                .toList();
        await _writeRegistry(existingOnly);
        await _deleteStoredFilesForRecords(stale);
      }
      await _cleanupUnreferencedFiles(existingOnly);
      return existingOnly;
    } catch (_) {
      if (failClosed) rethrow;
      return const <WasmPluginRecord>[];
    }
  }

  Future<void> _writeRegistry(List<WasmPluginRecord> records) async {
    final file = await _registryFile(createDir: true);
    final payload = records.map((record) => record.toJson()).toList();
    await _atomicWrites.writeString(file, jsonEncode(payload));
  }

  Future<WasmPluginRecord> installPluginFromFile(
    File sourceFile, {
    FutureOr<void> Function(WasmPluginRecord record)? validateRecord,
  }) async {
    return _serialized(
      () => _installPluginFromFileUnlocked(
        sourceFile,
        validateRecord: validateRecord,
      ),
    );
  }

  Future<WasmPluginRecord> _installPluginFromFileUnlocked(
    File sourceFile, {
    FutureOr<void> Function(WasmPluginRecord record)? validateRecord,
  }) async {
    final sourceName = _fileNameOnly(sourceFile.path);
    final extension = _fileExtension(sourceName).toLowerCase();
    if (extension != '.wasm' && extension != '.zip') {
      throw const FormatException(
        'Only .wasm or .zip plugin packages are supported',
      );
    }
    final pluginsDir = await pluginsDirectory(create: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storedFileName = '$id$extension';
    final storedFile = File('${pluginsDir.path}/$storedFileName');
    var registryCommitted = false;
    try {
      final existing = await _loadPluginsUnlocked(failClosed: true);
      await _atomicWrites.writeBytes(
        storedFile,
        await sourceFile.readAsBytes(),
      );
      final preflight = await _preflight.inspect(storedFile);
      final resolvedVersion = _resolvePluginVersion(
        preflightVersion: preflight.pluginVersion,
        sourceFileName: sourceName,
      );
      final replaced = _recordsToReplace(
        existing: existing,
        incomingPluginId: preflight.pluginId,
      );
      final record = WasmPluginRecord(
        id: id,
        displayName: _displayNameFromFile(
          preflight.pluginId?.isNotEmpty == true
              ? preflight.pluginId!
              : sourceName,
        ),
        originalFileName: sourceName,
        storedFileName: storedFileName,
        sizeBytes: await storedFile.length(),
        installedAtIso: DateTime.now().toUtc().toIso8601String(),
        packageKind: preflight.packageKind,
        pluginId: preflight.pluginId,
        pluginVersion: resolvedVersion,
        contractKind: preflight.contractKind,
        runtimeAbi: preflight.runtimeAbi,
        runtimeEntryExport: preflight.runtimeEntryExport,
        runtimeModulePath: preflight.runtimeModulePath,
        capabilities: preflight.capabilities,
      );
      await validateRecord?.call(record);
      final kept =
          existing
              .where((entry) => !replaced.any((stale) => stale.id == entry.id))
              .toList();
      await _writeRegistry(<WasmPluginRecord>[record, ...kept]);
      registryCommitted = true;
      await _deleteStoredFilesForRecords(replaced);
      await _cleanupUnreferencedFiles(<WasmPluginRecord>[record, ...kept]);
      return record;
    } catch (_) {
      if (!registryCommitted) {
        await _deleteFileIfPresent(storedFile);
      }
      rethrow;
    }
  }

  Future<void> removePlugin(String id) async {
    return _serialized(() => _removePluginUnlocked(id));
  }

  Future<void> _removePluginUnlocked(String id) async {
    final records = await _loadPluginsUnlocked(failClosed: true);
    final kept = <WasmPluginRecord>[];
    final removed = <WasmPluginRecord>[];

    for (final record in records) {
      if (record.id != id) {
        kept.add(record);
        continue;
      }
      removed.add(record);
    }

    await _writeRegistry(kept);
    await _deleteStoredFilesForRecords(removed);
    await _cleanupUnreferencedFiles(kept);
  }

  String _fileNameOnly(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return '';
    return fileName.substring(dot);
  }

  String _displayNameFromFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return stem
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<WasmPluginRecord> _dedupeByPluginId(List<WasmPluginRecord> records) {
    final kept = <WasmPluginRecord>[];
    final seenKeys = <String>{};
    for (final record in records) {
      final key = _dedupeKey(record);
      if (key == null) {
        kept.add(record);
        continue;
      }
      if (seenKeys.contains(key)) {
        continue;
      }
      seenKeys.add(key);
      kept.add(record);
    }
    return kept;
  }

  String? _dedupeKey(WasmPluginRecord record) {
    final pluginId = _normalizeOptional(record.pluginId);
    if (pluginId == null) return null;
    return pluginId;
  }

  String? _resolvePluginVersion({
    required String? preflightVersion,
    required String sourceFileName,
  }) {
    final normalized = _normalizeOptional(preflightVersion);
    if (normalized != null) return normalized;
    return _extractVersionFromFileName(sourceFileName);
  }

  List<WasmPluginRecord> _recordsToReplace({
    required List<WasmPluginRecord> existing,
    required String? incomingPluginId,
  }) {
    final pluginId = _normalizeOptional(incomingPluginId);
    if (pluginId == null) {
      return const <WasmPluginRecord>[];
    }
    return existing.where((record) {
      final recordPluginId = _normalizeOptional(record.pluginId);
      return recordPluginId == pluginId;
    }).toList();
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String? _extractVersionFromFileName(String fileName) {
    final match = RegExp(r'-([0-9]+(?:\.[0-9]+){1,3})\.').firstMatch(fileName);
    if (match == null) return null;
    final raw = match.group(1)?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  Future<void> _deleteStoredFilesForRecords(
    List<WasmPluginRecord> records,
  ) async {
    if (records.isEmpty) return;
    try {
      final dir = await pluginsDirectory();
      for (final record in records) {
        final file = File('${dir.path}/${record.storedFileName}');
        await _deleteFileIfPresent(file);
      }
    } on FileSystemException {
      // Registry commit is authoritative; orphan cleanup retries on next load.
    }
  }

  Future<void> _cleanupUnreferencedFiles(List<WasmPluginRecord> records) async {
    try {
      final dir = await pluginsDirectory();
      if (!await dir.exists()) return;
      final referenced = records.map((record) => record.storedFileName).toSet();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _fileNameOnly(entity.path);
        if (name == _registryFileName || referenced.contains(name)) continue;
        final isPackage = name.endsWith('.wasm') || name.endsWith('.zip');
        final isAtomicTemp =
            name.startsWith('$_registryFileName.tmp.') ||
            name.contains('.wasm.tmp.') ||
            name.contains('.zip.tmp.');
        if (isPackage || isAtomicTemp) {
          await _deleteFileIfPresent(entity);
        }
      }
    } on FileSystemException {
      // Registry commit is authoritative; orphan cleanup retries on next load.
    }
  }

  Future<void> _deleteFileIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Registry commit is authoritative; orphan cleanup retries on next load.
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    return (() async {
      try {
        await previous;
      } catch (_) {
        // A failed transaction must not poison the process-wide queue.
      }
      try {
        return await operation();
      } finally {
        release.complete();
      }
    })();
  }

  List<dynamic>? _parseJsonList(String rawJson) {
    final decoded = jsonDecode(rawJson);
    return decoded is List ? decoded : null;
  }

  Map<String, dynamic>? _coerceJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<List<WasmPluginRecord>> _filterRecordsWithStoredFile(
    List<WasmPluginRecord> records,
  ) async {
    if (records.isEmpty) {
      return const <WasmPluginRecord>[];
    }
    final dir = await pluginsDirectory();
    final kept = <WasmPluginRecord>[];
    for (final record in records) {
      final fileName = record.storedFileName.trim();
      if (fileName.isEmpty) {
        continue;
      }
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        kept.add(record);
      }
    }
    return kept;
  }
}
