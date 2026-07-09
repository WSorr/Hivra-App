import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'atomic_file_write_service.dart';

class AiPluginScaffoldDraftRequest {
  final String pluginRepoRootPath;
  final String pluginId;
  final String purpose;
  final String contractKind;
  final String hostApiVersion;
  final List<String> capabilities;

  const AiPluginScaffoldDraftRequest({
    required this.pluginRepoRootPath,
    required this.pluginId,
    required this.purpose,
    required this.contractKind,
    required this.hostApiVersion,
    required this.capabilities,
  });
}

class AiPluginScaffoldDraftReport {
  final int schemaVersion;
  final String draftRootPath;
  final String pluginId;
  final List<String> createdRelativePaths;
  final bool buildSkipped;
  final bool installSkipped;
  final bool catalogUpdateSkipped;
  final bool signingSkipped;
  final bool gitSkipped;
  final String reportHashHex;

  const AiPluginScaffoldDraftReport({
    required this.schemaVersion,
    required this.draftRootPath,
    required this.pluginId,
    required this.createdRelativePaths,
    required this.buildSkipped,
    required this.installSkipped,
    required this.catalogUpdateSkipped,
    required this.signingSkipped,
    required this.gitSkipped,
    required this.reportHashHex,
  });
}

class AiPluginScaffoldDraftService {
  static final RegExp _pluginIdPattern =
      RegExp(r'^[a-z0-9][a-z0-9_.-]{2,127}$');
  static final RegExp _capabilityPattern =
      RegExp(r'^[a-z0-9][a-z0-9_.-]{2,127}$');

  final AtomicFileWriteService _atomicWrites;

  const AiPluginScaffoldDraftService({
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _atomicWrites = atomicWrites;

  Future<AiPluginScaffoldDraftReport> createDraft(
    AiPluginScaffoldDraftRequest request,
  ) async {
    final repoRoot = Directory(request.pluginRepoRootPath).absolute;
    await _validatePluginRepo(repoRoot);
    final pluginId = request.pluginId.trim();
    final purpose = request.purpose.trim();
    final contractKind = request.contractKind.trim();
    final hostApiVersion = request.hostApiVersion.trim();
    final capabilities = request.capabilities
        .map((capability) => capability.trim())
        .where((capability) => capability.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (!_pluginIdPattern.hasMatch(pluginId)) {
      throw ArgumentError('Plugin id must be stable lowercase dotted id');
    }
    if (purpose.isEmpty) {
      throw ArgumentError('Plugin purpose is required');
    }
    if (contractKind.isEmpty) {
      throw ArgumentError('Contract kind is required');
    }
    if (hostApiVersion.isEmpty) {
      throw ArgumentError('Host API version is required');
    }
    if (capabilities.isEmpty) {
      throw ArgumentError('At least one capability is required');
    }
    for (final capability in capabilities) {
      if (!_capabilityPattern.hasMatch(capability)) {
        throw ArgumentError('Invalid capability: $capability');
      }
    }

    final slug = _slug(pluginId);
    final draftRoot = Directory('${repoRoot.path}/plugins/drafts/$slug');
    if (await draftRoot.exists()) {
      throw StateError('Plugin draft already exists: ${draftRoot.path}');
    }
    await Directory('${draftRoot.path}/src').create(recursive: true);
    await Directory('${draftRoot.path}/tests').create(recursive: true);

    final files = <String, String>{
      'README.md': _readme(
        pluginId: pluginId,
        purpose: purpose,
        contractKind: contractKind,
        hostApiVersion: hostApiVersion,
        capabilities: capabilities,
      ),
      'Cargo.toml': _cargoToml(slug),
      'manifest.json': _manifestJson(
        pluginId: pluginId,
        contractKind: contractKind,
        capabilities: capabilities,
      ),
      'src/lib.rs': _libRs(
        pluginId: pluginId,
        contractKind: contractKind,
      ),
      'tests/golden_vectors.json': _goldenVectorsJson(
        pluginId: pluginId,
        contractKind: contractKind,
      ),
    };
    final created = <String>[];
    for (final entry in files.entries) {
      final file = File('${draftRoot.path}/${entry.key}');
      await _atomicWrites.writeString(file, entry.value);
      created.add('plugins/drafts/$slug/${entry.key}');
    }
    created.sort();

    final canonical = <String, dynamic>{
      'schema_version': 1,
      'draft_root_path': draftRoot.path,
      'plugin_id': pluginId,
      'created_relative_paths': created,
      'build_skipped': true,
      'install_skipped': true,
      'catalog_update_skipped': true,
      'signing_skipped': true,
      'git_skipped': true,
    };
    return AiPluginScaffoldDraftReport(
      schemaVersion: 1,
      draftRootPath: draftRoot.path,
      pluginId: pluginId,
      createdRelativePaths: created,
      buildSkipped: true,
      installSkipped: true,
      catalogUpdateSkipped: true,
      signingSkipped: true,
      gitSkipped: true,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  Future<void> _validatePluginRepo(Directory repoRoot) async {
    if (!await repoRoot.exists()) {
      throw ArgumentError('Plugin repository root does not exist');
    }
    final hasContracts =
        await File('${repoRoot.path}/contracts/plugin_host_api_v1.md').exists();
    final hasPluginsReadme =
        await File('${repoRoot.path}/plugins/README.md').exists();
    if (!hasContracts || !hasPluginsReadme) {
      throw ArgumentError(
        'Draft scaffolding requires the hivra-plugins repository boundary',
      );
    }
  }

  String _readme({
    required String pluginId,
    required String purpose,
    required String contractKind,
    required String hostApiVersion,
    required List<String> capabilities,
  }) {
    return '''
# $pluginId

Draft-only Hivra WASM plugin skeleton.

Purpose: $purpose

Contract kind: `$contractKind`

Host API: `$hostApiVersion`

Capabilities:
${capabilities.map((capability) => '- `$capability`').join('\n')}

This draft is not built, installed, cataloged, signed, committed, pushed, tagged, or released by the scaffolder.
''';
  }

  String _cargoToml(String slug) {
    return '''
[package]
name = "$slug"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
''';
  }

  String _manifestJson({
    required String pluginId,
    required String contractKind,
    required List<String> capabilities,
  }) {
    final manifest = <String, dynamic>{
      'schema': 'hivra.plugin.manifest',
      'version': 1,
      'release_version': '0.1.0-draft',
      'plugin_id': pluginId,
      'wasm_module': '${_slug(pluginId)}.wasm',
      'capabilities': capabilities,
      'contract': <String, dynamic>{
        'kind': contractKind,
      },
      'runtime': <String, dynamic>{
        'abi': 'hivra_host_abi_v2',
        'entry_export': 'hivra_evaluate_v1',
        'module_path': 'plugin/module.wasm',
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  }

  String _libRs({
    required String pluginId,
    required String contractKind,
  }) {
    return '''
// Draft-only Hivra plugin skeleton for $pluginId.
// Source text is untrusted evidence until reviewed and built by the plugin repo.

#[no_mangle]
pub extern "C" fn hivra_evaluate_v1(_input_ptr: *const u8, _input_len: usize) -> i32 {
    // Draft placeholder: replace with reviewed deterministic $contractKind evaluation in hivra-plugins.
    0
}
''';
  }

  String _goldenVectorsJson({
    required String pluginId,
    required String contractKind,
  }) {
    final vectors = <String, dynamic>{
      'schema': 'hivra.plugin.golden_vectors',
      'version': 1,
      'plugin_id': pluginId,
      'contract_kind': contractKind,
      'vectors': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'empty-input-draft',
          'input': <String, dynamic>{},
          'expected': <String, dynamic>{
            'status': 'draft_unimplemented',
          },
        },
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(vectors)}\n';
  }

  String _slug(String pluginId) {
    return pluginId.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _hashCanonical(Object? value) {
    return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}
