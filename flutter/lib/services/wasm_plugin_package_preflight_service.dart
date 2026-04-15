import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'wasm_plugin_capability_policy_service.dart';

class WasmPluginPackagePreflight {
  final String packageKind;
  final String? pluginId;
  final String? pluginVersion;
  final String? contractKind;
  final String? runtimeAbi;
  final String? runtimeEntryExport;
  final String? runtimeModulePath;
  final List<String> capabilities;

  const WasmPluginPackagePreflight({
    required this.packageKind,
    this.pluginId,
    this.pluginVersion,
    this.contractKind,
    this.runtimeAbi,
    this.runtimeEntryExport,
    this.runtimeModulePath,
    this.capabilities = const <String>[],
  });
}

class WasmPluginPackagePreflightService {
  static const String requiredRuntimeAbi = 'hivra_host_abi_v1';
  static const String requiredRuntimeEntryExport = 'hivra_entry_v1';

  final WasmPluginCapabilityPolicyService _capabilityPolicy;

  const WasmPluginPackagePreflightService({
    WasmPluginCapabilityPolicyService capabilityPolicy =
        const WasmPluginCapabilityPolicyService(),
  }) : _capabilityPolicy = capabilityPolicy;

  Future<WasmPluginPackagePreflight> inspect(File sourceFile) async {
    final fileName = _fileNameOnly(sourceFile.path);
    final extension = _fileExtension(fileName).toLowerCase();
    if (extension == '.wasm') {
      await _validateWasmBinary(sourceFile);
      return const WasmPluginPackagePreflight(
        packageKind: 'wasm',
        capabilities: <String>[],
      );
    }
    if (extension == '.zip') {
      return _validateZipPackage(sourceFile);
    }
    throw const FormatException(
      'Only .wasm or .zip plugin packages are supported',
    );
  }

  Future<void> _validateWasmBinary(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    if (bytes.length < 8) {
      throw const FormatException('WASM package is too small');
    }
    const magic = <int>[0x00, 0x61, 0x73, 0x6d];
    const version = <int>[0x01, 0x00, 0x00, 0x00];
    for (var i = 0; i < 4; i += 1) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('Invalid WASM header magic');
      }
      if (bytes[i + 4] != version[i]) {
        throw const FormatException('Unsupported WASM binary version');
      }
    }
  }

  Future<WasmPluginPackagePreflight> _validateZipPackage(
    File sourceFile,
  ) async {
    final bytes = await sourceFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    if (archive.isEmpty) {
      throw const FormatException('Plugin package archive is empty');
    }

    final manifestFile = archive.files.firstWhere(
      (file) => file.isFile && file.name.split('/').last == 'manifest.json',
      orElse: () => throw const FormatException(
        'Zip plugin package must include manifest.json',
      ),
    );
    final manifestText = utf8.decode(_archiveFileBytes(manifestFile));
    final decoded = jsonDecode(manifestText);
    if (decoded is! Map) {
      throw const FormatException('Plugin manifest must be a JSON object');
    }
    final manifest = Map<String, dynamic>.from(decoded);

    if (manifest['schema'] != 'hivra.plugin.manifest') {
      throw const FormatException('Unsupported plugin manifest schema');
    }
    if (manifest['version'] != 1) {
      throw const FormatException('Unsupported plugin manifest version');
    }

    final pluginId = manifest['plugin_id']?.toString().trim();
    if (pluginId == null || pluginId.isEmpty) {
      throw const FormatException('Plugin manifest is missing plugin_id');
    }
    final pluginVersion = _parsePluginVersion(manifest);

    String? contractKind;
    final contract = manifest['contract'];
    if (contract is Map) {
      contractKind = contract['kind']?.toString();
    }
    final runtime = manifest['runtime'];
    if (runtime is! Map) {
      throw const FormatException(
        'Plugin manifest is missing runtime section',
      );
    }
    final runtimeMap = Map<String, dynamic>.from(runtime);
    final runtimeAbi = runtimeMap['abi']?.toString().trim() ?? '';
    final runtimeEntryExport =
        runtimeMap['entry_export']?.toString().trim() ?? '';
    final runtimeModulePath = _parseRuntimeModulePath(
      runtimeMap['module_path'],
    );
    if (runtimeAbi != requiredRuntimeAbi) {
      throw const FormatException(
        'Unsupported plugin runtime ABI',
      );
    }
    if (runtimeEntryExport != requiredRuntimeEntryExport) {
      throw const FormatException(
        'Unsupported plugin runtime entry export',
      );
    }
    final wasmModulePaths = <String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalizedPath = _normalizeArchivePath(file.name);
      if (normalizedPath == null) continue;
      if (!normalizedPath.toLowerCase().endsWith('.wasm')) continue;
      wasmModulePaths.add(normalizedPath);
    }
    if (wasmModulePaths.isEmpty) {
      throw const FormatException(
        'Zip plugin package must include at least one .wasm module',
      );
    }
    if (runtimeModulePath != null) {
      final normalizedRuntimeModulePath = _normalizeArchivePath(
        runtimeModulePath,
        rejectParentTraversal: true,
      )!;
      final hasDeclaredModule =
          wasmModulePaths.contains(normalizedRuntimeModulePath);
      if (!hasDeclaredModule) {
        throw const FormatException(
          'Plugin runtime module_path not found in package',
        );
      }
    }
    final capabilities = _parseCapabilities(manifest['capabilities']);

    return WasmPluginPackagePreflight(
      packageKind: 'zip',
      pluginId: pluginId,
      pluginVersion: pluginVersion,
      contractKind: contractKind,
      runtimeAbi: runtimeAbi,
      runtimeEntryExport: runtimeEntryExport,
      runtimeModulePath: runtimeModulePath,
      capabilities: capabilities,
    );
  }

  String? _parseRuntimeModulePath(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) {
      throw const FormatException(
        'Plugin runtime module_path must be a non-empty string',
      );
    }
    final normalized = _normalizeArchivePath(
      value,
      rejectParentTraversal: true,
    )!;
    if (!normalized.toLowerCase().endsWith('.wasm')) {
      throw const FormatException(
        'Plugin runtime module_path must point to a .wasm file',
      );
    }
    return normalized;
  }

  String? _normalizeArchivePath(
    String path, {
    bool rejectParentTraversal = false,
  }) {
    var normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return null;
    }
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    final segments = normalized.split('/');
    final hasParentTraversal =
        segments.any((segment) => segment.trim() == '..');
    if (hasParentTraversal) {
      if (rejectParentTraversal) {
        throw const FormatException(
          'Plugin runtime module_path must not include parent traversal',
        );
      }
      return null;
    }
    return normalized;
  }

  String? _parsePluginVersion(Map<String, dynamic> manifest) {
    final raw = manifest['release_version'] ?? manifest['plugin_version'];
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  List<String> _parseCapabilities(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw const FormatException(
          'Plugin manifest capabilities must be a list');
    }
    final unique = <String>{};
    for (final entry in raw) {
      final value = entry?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw const FormatException(
          'Plugin manifest capabilities entries must be non-empty strings',
        );
      }
      unique.add(value);
    }
    final normalized = unique.toList()..sort();
    return _capabilityPolicy.normalizeAndValidate(normalized);
  }

  List<int> _archiveFileBytes(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return content;
    if (content is String) return utf8.encode(content);
    throw const FormatException(
        'Unable to read file content from plugin archive');
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
}
