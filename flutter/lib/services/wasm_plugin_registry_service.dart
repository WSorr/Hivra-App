import 'dart:convert';
import 'dart:io';

import 'user_visible_data_directory_service.dart';
import 'wasm_plugin_package_preflight_service.dart';

class WasmPluginRecord {
  final String id;
  final String displayName;
  final String originalFileName;
  final String storedFileName;
  final int sizeBytes;
  final String installedAtIso;
  final String packageKind;
  final String? pluginId;
  final String? pluginVersion;
  final String? contractKind;
  final String? runtimeAbi;
  final String? runtimeEntryExport;
  final String? runtimeModulePath;
  final List<String> capabilities;

  const WasmPluginRecord({
    required this.id,
    required this.displayName,
    required this.originalFileName,
    required this.storedFileName,
    required this.sizeBytes,
    required this.installedAtIso,
    required this.packageKind,
    required this.pluginId,
    required this.pluginVersion,
    required this.contractKind,
    required this.runtimeAbi,
    required this.runtimeEntryExport,
    required this.runtimeModulePath,
    required this.capabilities,
  });

  factory WasmPluginRecord.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final capabilities = <String>{};
    if (rawCapabilities is List) {
      for (final value in rawCapabilities) {
        final normalized = value?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          capabilities.add(normalized);
        }
      }
    }
    return WasmPluginRecord(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown plugin',
      originalFileName: json['originalFileName'] as String? ?? 'unknown.wasm',
      storedFileName: json['storedFileName'] as String? ?? 'unknown.wasm',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      installedAtIso: json['installedAtIso'] as String? ?? '',
      packageKind: json['packageKind'] as String? ?? 'unknown',
      pluginId: json['pluginId'] as String?,
      pluginVersion: json['pluginVersion'] as String?,
      contractKind: json['contractKind'] as String?,
      runtimeAbi: json['runtimeAbi'] as String?,
      runtimeEntryExport: json['runtimeEntryExport'] as String?,
      runtimeModulePath: json['runtimeModulePath'] as String?,
      capabilities: (capabilities.toList()..sort()),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'originalFileName': originalFileName,
      'storedFileName': storedFileName,
      'sizeBytes': sizeBytes,
      'installedAtIso': installedAtIso,
      'packageKind': packageKind,
      'pluginId': pluginId,
      'pluginVersion': pluginVersion,
      'contractKind': contractKind,
      'runtimeAbi': runtimeAbi,
      'runtimeEntryExport': runtimeEntryExport,
      'runtimeModulePath': runtimeModulePath,
      'capabilities': capabilities,
    };
  }
}

class WasmPluginRegistryService {
  static const String _registryFileName = 'registry.json';
  final UserVisibleDataDirectoryService _dataDirs;
  final WasmPluginPackagePreflightService _preflight;

  const WasmPluginRegistryService({
    UserVisibleDataDirectoryService dataDirs =
        const UserVisibleDataDirectoryService(),
    WasmPluginPackagePreflightService preflight =
        const WasmPluginPackagePreflightService(),
  })  : _dataDirs = dataDirs,
        _preflight = preflight;

  Future<Directory> pluginsDirectory({bool create = false}) async {
    return _dataDirs.pluginsDirectory(create: create);
  }

  Future<File> _registryFile({bool createDir = false}) async {
    final dir = await pluginsDirectory(create: createDir);
    return File('${dir.path}/$_registryFileName');
  }

  Future<List<WasmPluginRecord>> loadPlugins() async {
    final file = await _registryFile();
    if (!await file.exists()) return const <WasmPluginRecord>[];

    try {
      final decoded = _parseJsonList(await file.readAsString());
      if (decoded == null) return const <WasmPluginRecord>[];
      final records = decoded
          .map(_coerceJsonMap)
          .whereType<Map<String, dynamic>>()
          .map(WasmPluginRecord.fromJson)
          .toList()
        ..sort((a, b) => b.installedAtIso.compareTo(a.installedAtIso));
      final deduped = _dedupeByPluginVersion(records);
      final existingOnly = await _filterRecordsWithStoredFile(deduped);
      if (existingOnly.length != records.length) {
        final stale = records
            .where(
                (record) => !existingOnly.any((kept) => kept.id == record.id))
            .toList();
        await _deleteStoredFilesForRecords(stale);
        await _writeRegistry(existingOnly);
      }
      return existingOnly;
    } catch (_) {
      return const <WasmPluginRecord>[];
    }
  }

  Future<void> _writeRegistry(List<WasmPluginRecord> records) async {
    final file = await _registryFile(createDir: true);
    final payload = records.map((record) => record.toJson()).toList();
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<WasmPluginRecord> installPluginFromFile(File sourceFile) async {
    final sourceName = _fileNameOnly(sourceFile.path);
    final extension = _fileExtension(sourceName).toLowerCase();
    if (extension != '.wasm' && extension != '.zip') {
      throw const FormatException(
          'Only .wasm or .zip plugin packages are supported');
    }
    final preflight = await _preflight.inspect(sourceFile);
    final existing = await loadPlugins();
    final resolvedVersion = _resolvePluginVersion(
      preflightVersion: preflight.pluginVersion,
      sourceFileName: sourceName,
    );
    final replaced = _recordsToReplace(
      existing: existing,
      incomingPluginId: preflight.pluginId,
      incomingPluginVersion: resolvedVersion,
    );

    final pluginsDir = await pluginsDirectory(create: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storedFileName = '$id$extension';
    final storedFile = File('${pluginsDir.path}/$storedFileName');
    await sourceFile.copy(storedFile.path);
    final sizeBytes = await storedFile.length();

    final record = WasmPluginRecord(
      id: id,
      displayName: _displayNameFromFile(
        preflight.pluginId?.isNotEmpty == true
            ? preflight.pluginId!
            : sourceName,
      ),
      originalFileName: sourceName,
      storedFileName: storedFileName,
      sizeBytes: sizeBytes,
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

    for (final stale in replaced) {
      final staleFile = File('${pluginsDir.path}/${stale.storedFileName}');
      if (await staleFile.exists()) {
        await staleFile.delete();
      }
    }
    final kept = existing
        .where((entry) => !replaced.any((stale) => stale.id == entry.id))
        .toList();
    await _writeRegistry(<WasmPluginRecord>[record, ...kept]);
    return record;
  }

  Future<void> removePlugin(String id) async {
    final records = await loadPlugins();
    final kept = <WasmPluginRecord>[];

    for (final record in records) {
      if (record.id != id) {
        kept.add(record);
        continue;
      }

      final dir = await pluginsDirectory();
      final file = File('${dir.path}/${record.storedFileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _writeRegistry(kept);
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

  List<WasmPluginRecord> _dedupeByPluginVersion(
      List<WasmPluginRecord> records) {
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
    final version = _normalizeOptional(record.pluginVersion) ??
        _extractVersionFromFileName(record.originalFileName);
    if (version == null) return null;
    return '$pluginId::$version';
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
    required String? incomingPluginVersion,
  }) {
    final pluginId = _normalizeOptional(incomingPluginId);
    final pluginVersion = _normalizeOptional(incomingPluginVersion);
    if (pluginId == null || pluginVersion == null) {
      return const <WasmPluginRecord>[];
    }
    return existing.where((record) {
      final recordPluginId = _normalizeOptional(record.pluginId);
      if (recordPluginId != pluginId) return false;
      final recordVersion = _normalizeOptional(record.pluginVersion) ??
          _extractVersionFromFileName(record.originalFileName);
      return recordVersion == pluginVersion;
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
      List<WasmPluginRecord> records) async {
    if (records.isEmpty) return;
    final dir = await pluginsDirectory();
    for (final record in records) {
      final file = File('${dir.path}/${record.storedFileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }
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
