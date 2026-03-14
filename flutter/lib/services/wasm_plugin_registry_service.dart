import 'dart:convert';
import 'dart:io';

import 'user_visible_data_directory_service.dart';

class WasmPluginRecord {
  final String id;
  final String displayName;
  final String originalFileName;
  final String storedFileName;
  final int sizeBytes;
  final String installedAtIso;

  const WasmPluginRecord({
    required this.id,
    required this.displayName,
    required this.originalFileName,
    required this.storedFileName,
    required this.sizeBytes,
    required this.installedAtIso,
  });

  factory WasmPluginRecord.fromJson(Map<String, dynamic> json) {
    return WasmPluginRecord(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown plugin',
      originalFileName: json['originalFileName'] as String? ?? 'unknown.wasm',
      storedFileName: json['storedFileName'] as String? ?? 'unknown.wasm',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      installedAtIso: json['installedAtIso'] as String? ?? '',
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
    };
  }
}

class WasmPluginRegistryService {
  static const String _registryFileName = 'registry.json';
  final UserVisibleDataDirectoryService _dataDirs;

  const WasmPluginRegistryService({
    UserVisibleDataDirectoryService dataDirs =
        const UserVisibleDataDirectoryService(),
  }) : _dataDirs = dataDirs;

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
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <WasmPluginRecord>[];
      return decoded
          .whereType<Map>()
          .map((entry) =>
              WasmPluginRecord.fromJson(Map<String, dynamic>.from(entry)))
          .toList()
        ..sort((a, b) => b.installedAtIso.compareTo(a.installedAtIso));
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
      throw const FormatException('Only .wasm or .zip plugin packages are supported');
    }

    final pluginsDir = await pluginsDirectory(create: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storedFileName = '$id$extension';
    final storedFile = File('${pluginsDir.path}/$storedFileName');
    await sourceFile.copy(storedFile.path);
    final sizeBytes = await storedFile.length();

    final record = WasmPluginRecord(
      id: id,
      displayName: _displayNameFromFile(sourceName),
      originalFileName: sourceName,
      storedFileName: storedFileName,
      sizeBytes: sizeBytes,
      installedAtIso: DateTime.now().toUtc().toIso8601String(),
    );

    final existing = await loadPlugins();
    await _writeRegistry(<WasmPluginRecord>[record, ...existing]);
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
}
