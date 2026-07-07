import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/plugin_host_api_models.dart';

typedef WasmJsonInvoker = String? Function({
  required Uint8List moduleBytes,
  required String entryExport,
  required Uint8List inputJsonBytes,
});

class WasmPluginRuntimeService {
  static const String runtimeMode = 'wasmi_v1';
  static const String requiredRuntimeAbi = 'hivra_host_abi_v2';
  static const String requiredEntryExport = 'hivra_evaluate_v1';
  static const int _maxPackageBytes = 8 * 1024 * 1024;
  static const int _maxModuleBytes = 4 * 1024 * 1024;
  static const int _maxArchiveEntries = 128;
  static const int _maxExpandedArchiveBytes = 16 * 1024 * 1024;

  final WasmJsonInvoker _invokeJson;

  const WasmPluginRuntimeService({
    required WasmJsonInvoker invokeJson,
  }) : _invokeJson = invokeJson;

  Future<PluginRuntimeInvokeEvidence?> invoke({
    required PluginHostApiRequest request,
    required PluginRuntimeBinding binding,
  }) async {
    if (binding.source != 'external_package') {
      return null;
    }
    if (binding.runtimeAbi?.trim() != requiredRuntimeAbi) {
      throw const FormatException('Plugin runtime ABI mismatch');
    }
    final entryExport = binding.runtimeEntryExport?.trim() ?? '';
    if (entryExport != requiredEntryExport) {
      throw const FormatException('Plugin runtime entry export mismatch');
    }
    final packagePath = binding.packageFilePath?.trim() ?? '';
    final packageKind = binding.packageKind?.trim().toLowerCase() ?? '';
    if (packagePath.isEmpty || packageKind.isEmpty) {
      throw const FormatException('Plugin package binding is incomplete');
    }
    final packageFile = File(packagePath);
    if (!await packageFile.exists()) {
      throw const FormatException('Plugin package file is missing');
    }
    if (await packageFile.length() > _maxPackageBytes) {
      throw const FormatException('Plugin package exceeds the size limit');
    }
    await _verifyPackageDigest(
      packageFile: packageFile,
      expectedDigestHex: binding.packageDigestHex,
    );

    final module = await _extractModule(
      packageFile: packageFile,
      packageKind: packageKind,
      runtimeModulePath: binding.runtimeModulePath,
    );
    _validateWasmHeader(module.bytes);

    final invokeInput = <String, dynamic>{
      ...request.args,
      'schema_version': request.schemaVersion,
      'plugin_id': request.pluginId,
    };
    final inputCanonical = _canonicalJson(invokeInput);
    final outputRaw = _invokeJson(
      moduleBytes: Uint8List.fromList(module.bytes),
      entryExport: entryExport,
      inputJsonBytes: Uint8List.fromList(utf8.encode(inputCanonical)),
    );
    if (outputRaw == null || outputRaw.trim().isEmpty) {
      throw const FormatException('WASM runtime returned no semantic output');
    }
    final output = _decodeEnvelope(outputRaw);
    final outputCanonical = _canonicalJson(output);
    final moduleDigestHex = sha256.convert(module.bytes).toString();
    final invokeDigestHex = sha256
        .convert(
          utf8.encode(
            '$runtimeMode|${request.pluginId}|${request.method}|'
            '${module.selection}|${module.path}|$moduleDigestHex|'
            '$inputCanonical|$outputCanonical',
          ),
        )
        .toString();

    final status = output['status'] as String;
    final result = output['result'];
    return PluginRuntimeInvokeEvidence(
      mode: runtimeMode,
      modulePath: module.path,
      moduleSelection: module.selection,
      moduleDigestHex: moduleDigestHex,
      invokeDigestHex: invokeDigestHex,
      semanticStatus: switch (status) {
        'executed' => PluginHostApiStatus.executed,
        'rejected' => PluginHostApiStatus.rejected,
        _ => throw const FormatException('Unsupported WASM semantic status'),
      },
      semanticResult: result is Map ? Map<String, dynamic>.from(result) : null,
      semanticErrorCode: output['error_code']?.toString(),
      semanticErrorMessage: output['error_message']?.toString(),
    );
  }

  Future<_ResolvedModule> _extractModule({
    required File packageFile,
    required String packageKind,
    required String? runtimeModulePath,
  }) async {
    if (packageKind == 'wasm') {
      final bytes = await packageFile.readAsBytes();
      if (bytes.length > _maxModuleBytes) {
        throw const FormatException(
            'Plugin WASM module exceeds the size limit');
      }
      return _ResolvedModule(
        path: 'package/module.wasm',
        selection: 'package_wasm',
        bytes: bytes,
      );
    }
    if (packageKind != 'zip') {
      throw const FormatException('Unsupported plugin package kind');
    }

    final archive = ZipDecoder().decodeBytes(
      await packageFile.readAsBytes(),
      verify: true,
    );
    if (archive.files.length > _maxArchiveEntries) {
      throw const FormatException('Plugin package has too many entries');
    }
    final expandedBytes = archive.files.fold<int>(
      0,
      (total, file) => total + file.size,
    );
    if (expandedBytes > _maxExpandedArchiveBytes) {
      throw const FormatException('Expanded plugin package is too large');
    }
    final requiredPath = _normalizeArchivePath(
      runtimeModulePath,
      rejectParentTraversal: true,
    );
    if (requiredPath == null) {
      throw const FormatException('Plugin runtime module_path is missing');
    }
    for (final entry in archive.files) {
      if (!entry.isFile || _normalizeArchivePath(entry.name) != requiredPath) {
        continue;
      }
      final content = entry.content;
      if (content is! List<int> || content.isEmpty) {
        throw const FormatException('Plugin WASM module is empty');
      }
      if (content.length > _maxModuleBytes) {
        throw const FormatException(
            'Plugin WASM module exceeds the size limit');
      }
      return _ResolvedModule(
        path: requiredPath,
        selection: 'manifest_module_path',
        bytes: content,
      );
    }
    throw const FormatException(
      'Plugin runtime module_path not found in package',
    );
  }

  Future<void> _verifyPackageDigest({
    required File packageFile,
    required String? expectedDigestHex,
  }) async {
    final expected = expectedDigestHex?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw const FormatException('Plugin package digest is required');
    }
    final actual = sha256.convert(await packageFile.readAsBytes()).toString();
    if (actual != expected) {
      throw const FormatException('Plugin package digest mismatch');
    }
  }

  Map<String, dynamic> _decodeEnvelope(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('WASM semantic output must be an object');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    if (envelope['schema_version'] != 1) {
      throw const FormatException('WASM semantic schema version mismatch');
    }
    final status = envelope['status'];
    if (status == 'executed') {
      if (envelope['result'] is! Map ||
          envelope['error_code'] != null ||
          envelope['error_message'] != null) {
        throw const FormatException('Invalid executed WASM envelope');
      }
    } else if (status == 'rejected') {
      if (envelope['result'] != null ||
          (envelope['error_code']?.toString().trim().isEmpty ?? true) ||
          (envelope['error_message']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('Invalid rejected WASM envelope');
      }
    } else {
      throw const FormatException('Unsupported WASM semantic status');
    }
    return envelope;
  }

  void _validateWasmHeader(List<int> bytes) {
    if (bytes.length < 8 ||
        bytes[0] != 0x00 ||
        bytes[1] != 0x61 ||
        bytes[2] != 0x73 ||
        bytes[3] != 0x6d ||
        bytes[4] != 0x01 ||
        bytes[5] != 0x00 ||
        bytes[6] != 0x00 ||
        bytes[7] != 0x00) {
      throw const FormatException('Invalid WASM module header');
    }
  }

  String? _normalizeArchivePath(
    String? rawPath, {
    bool rejectParentTraversal = false,
  }) {
    var normalized = rawPath?.trim().replaceAll('\\', '/') ?? '';
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.isEmpty) return null;
    if (normalized.split('/').contains('..')) {
      if (rejectParentTraversal) {
        throw const FormatException(
          'Plugin runtime module_path must not include parent traversal',
        );
      }
      return null;
    }
    return normalized;
  }

  String _canonicalJson(Object? value) {
    Object? normalize(Object? node) {
      if (node is Map) {
        final keys = node.keys.map((key) => key.toString()).toList()..sort();
        return <String, dynamic>{
          for (final key in keys) key: normalize(node[key]),
        };
      }
      if (node is List) {
        return node.map(normalize).toList(growable: false);
      }
      return node;
    }

    return jsonEncode(normalize(value));
  }
}

class _ResolvedModule {
  final String path;
  final String selection;
  final List<int> bytes;

  const _ResolvedModule({
    required this.path,
    required this.selection,
    required this.bytes,
  });
}
