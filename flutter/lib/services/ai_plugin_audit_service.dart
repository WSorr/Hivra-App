import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/wasm_plugin_models.dart';
import 'ai_developer_workspace_service.dart';
import 'wasm_plugin_capability_policy_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_runtime_service.dart';

class AiPluginAuditFinding {
  final String severity;
  final String pluginLabel;
  final String title;
  final String detail;
  final String recommendedAction;

  const AiPluginAuditFinding({
    required this.severity,
    required this.pluginLabel,
    required this.title,
    required this.detail,
    required this.recommendedAction,
  });
}

class AiPluginAuditEntry {
  final String pluginLabel;
  final String? pluginId;
  final String? pluginVersion;
  final String packageKind;
  final String packageDigestHex;
  final int sizeBytes;
  final List<String> capabilities;
  final List<AiPluginAuditFinding> findings;

  const AiPluginAuditEntry({
    required this.pluginLabel,
    required this.pluginId,
    required this.pluginVersion,
    required this.packageKind,
    required this.packageDigestHex,
    required this.sizeBytes,
    required this.capabilities,
    required this.findings,
  });
}

class AiPluginAuditReport {
  final int schemaVersion;
  final List<AiPluginAuditEntry> entries;
  final String reportHashHex;

  const AiPluginAuditReport({
    required this.schemaVersion,
    required this.entries,
    required this.reportHashHex,
  });

  List<AiPluginAuditFinding> get findings =>
      entries.expand((entry) => entry.findings).toList(growable: false);

  String get statusLabel {
    if (findings.any((finding) => finding.severity == 'critical')) {
      return 'Critical';
    }
    if (findings.any((finding) => finding.severity == 'warning')) {
      return 'Needs attention';
    }
    return 'Healthy';
  }
}

class AiPluginSourceAuditSnippet {
  final String relativePath;
  final int sizeBytes;
  final String sha256Hex;
  final List<String> evidenceKinds;

  const AiPluginSourceAuditSnippet({
    required this.relativePath,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.evidenceKinds,
  });
}

class AiPluginSourceAuditReport {
  final int schemaVersion;
  final List<AiPluginSourceAuditSnippet> snippets;
  final List<AiPluginAuditFinding> findings;
  final bool canGrantCapabilities;
  final String reportHashHex;

  const AiPluginSourceAuditReport({
    required this.schemaVersion,
    required this.snippets,
    required this.findings,
    required this.canGrantCapabilities,
    required this.reportHashHex,
  });

  String get statusLabel {
    if (findings.any((finding) => finding.severity == 'critical')) {
      return 'Critical';
    }
    if (findings.any((finding) => finding.severity == 'warning')) {
      return 'Needs attention';
    }
    return 'Healthy';
  }
}

class AiPluginAuditService {
  final WasmPluginRegistryService _registry;
  final WasmPluginCapabilityPolicyService _capabilityPolicy;

  const AiPluginAuditService({
    WasmPluginRegistryService registry = const WasmPluginRegistryService(),
    WasmPluginCapabilityPolicyService capabilityPolicy =
        const WasmPluginCapabilityPolicyService(),
  })  : _registry = registry,
        _capabilityPolicy = capabilityPolicy;

  Future<AiPluginAuditReport> auditInstalledPlugins() async {
    final records = await _registry.loadPlugins();
    final pluginsDir = await _registry.pluginsDirectory();
    final entries = <AiPluginAuditEntry>[];

    for (final record in records) {
      entries.add(await _auditRecord(record, pluginsDir));
    }
    entries
        .sort((left, right) => left.pluginLabel.compareTo(right.pluginLabel));
    final canonical = <String, dynamic>{
      'schema_version': 1,
      'entries': entries
          .map(
            (entry) => <String, dynamic>{
              'plugin_label': entry.pluginLabel,
              'plugin_id': entry.pluginId,
              'plugin_version': entry.pluginVersion,
              'package_kind': entry.packageKind,
              'package_digest_hex': entry.packageDigestHex,
              'size_bytes': entry.sizeBytes,
              'capabilities': entry.capabilities,
              'findings': entry.findings
                  .map(
                    (finding) => <String, dynamic>{
                      'severity': finding.severity,
                      'title': finding.title,
                      'detail': finding.detail,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
    return AiPluginAuditReport(
      schemaVersion: 1,
      entries: entries,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  AiPluginSourceAuditReport auditSelectedSourceContext({
    required AiDeveloperWorkspaceSelectedContext context,
    String? expectedPluginId,
  }) {
    final snippets = <AiPluginSourceAuditSnippet>[];
    final findings = <AiPluginAuditFinding>[];
    var manifestFound = false;
    var runtimeEvidenceFound = false;
    var catalogEvidenceFound = false;

    if (context.snippets.isEmpty) {
      findings.add(const AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: 'selected-source',
        title: 'No selected plugin source evidence',
        detail: 'Plugin source audit requires explicit selected snippets.',
        recommendedAction:
            'Build Developer Workspace selected context for plugin source files first.',
      ));
    }

    for (final snippet in context.snippets) {
      final kinds = <String>[];
      final relativePath = snippet.relativePath.replaceAll('\\', '/');
      final text = snippet.text;
      final isManifest = relativePath.endsWith('manifest.json');
      if (isManifest) {
        kinds.add('manifest');
        manifestFound = true;
        _auditManifestSnippet(
          relativePath: relativePath,
          text: text,
          expectedPluginId: expectedPluginId,
          findings: findings,
        );
      }
      if (!isManifest &&
          text.contains(WasmPluginRuntimeService.requiredEntryExport)) {
        kinds.add('runtime_entry_export');
        runtimeEvidenceFound = true;
      }
      if (relativePath.endsWith('plugin_catalog.json') ||
          text.contains('hivra.plugin.catalog')) {
        kinds.add('catalog');
        catalogEvidenceFound = true;
        _auditCatalogSnippet(
          relativePath: relativePath,
          text: text,
          findings: findings,
        );
      }
      snippets.add(AiPluginSourceAuditSnippet(
        relativePath: relativePath,
        sizeBytes: snippet.sizeBytes,
        sha256Hex: snippet.sha256Hex,
        evidenceKinds: kinds..sort(),
      ));
    }

    if (!manifestFound) {
      findings.add(const AiPluginAuditFinding(
        severity: 'warning',
        pluginLabel: 'selected-source',
        title: 'Plugin manifest evidence is missing',
        detail: 'Selected source context did not include manifest.json.',
        recommendedAction:
            'Select the plugin manifest before asking for plugin source audit.',
      ));
    }
    if (!runtimeEvidenceFound) {
      findings.add(AiPluginAuditFinding(
        severity: 'warning',
        pluginLabel: 'selected-source',
        title: 'Runtime entry evidence is missing',
        detail:
            'Selected source did not reference ${WasmPluginRuntimeService.requiredEntryExport}.',
        recommendedAction:
            'Select runtime source or generated glue that exposes the host ABI entrypoint.',
      ));
    }
    if (!catalogEvidenceFound) {
      findings.add(const AiPluginAuditFinding(
        severity: 'info',
        pluginLabel: 'selected-source',
        title: 'Catalog evidence was not selected',
        detail:
            'Source audit can run without catalog evidence, but release review should include catalog digest/signature evidence.',
        recommendedAction:
            'Select plugin_catalog.json when auditing release provenance.',
      ));
    }

    final canonical = <String, dynamic>{
      'schema_version': 1,
      'snippets': snippets
          .map((snippet) => <String, dynamic>{
                'relative_path': snippet.relativePath,
                'size_bytes': snippet.sizeBytes,
                'sha256_hex': snippet.sha256Hex,
                'evidence_kinds': snippet.evidenceKinds,
              })
          .toList(growable: false),
      'findings': findings
          .map((finding) => <String, dynamic>{
                'severity': finding.severity,
                'title': finding.title,
                'detail': finding.detail,
              })
          .toList(growable: false),
      'can_grant_capabilities': false,
    };
    return AiPluginSourceAuditReport(
      schemaVersion: 1,
      snippets: snippets,
      findings: findings,
      canGrantCapabilities: false,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  Future<AiPluginAuditEntry> _auditRecord(
    WasmPluginRecord record,
    Directory pluginsDir,
  ) async {
    final findings = <AiPluginAuditFinding>[];
    final label = _pluginLabel(record);
    final packageFile = File('${pluginsDir.path}/${record.storedFileName}');
    final exists = await packageFile.exists();
    final digest = exists
        ? sha256.convert(await packageFile.readAsBytes()).toString()
        : '';
    final sizeBytes = exists ? await packageFile.length() : 0;

    if (!exists) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: label,
        title: 'Plugin package file is missing',
        detail: 'Registry entry points to ${record.storedFileName}, but the '
            'stored package is not present.',
        recommendedAction:
            'Remove and reinstall the plugin package from a trusted catalog.',
      ));
    }
    if ((record.pluginId ?? '').trim().isEmpty) {
      findings.add(AiPluginAuditFinding(
        severity: 'warning',
        pluginLabel: label,
        title: 'Plugin id is missing',
        detail: 'Registry metadata has no manifest plugin id.',
        recommendedAction: 'Reinstall a package with a valid manifest.',
      ));
    }
    if ((record.pluginVersion ?? '').trim().isEmpty) {
      findings.add(AiPluginAuditFinding(
        severity: 'warning',
        pluginLabel: label,
        title: 'Plugin version is missing',
        detail: 'Registry metadata has no manifest plugin version.',
        recommendedAction: 'Reinstall a versioned package.',
      ));
    }
    if (record.runtimeAbi != WasmPluginRuntimeService.requiredRuntimeAbi) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: label,
        title: 'Runtime ABI mismatch',
        detail: 'Expected ${WasmPluginRuntimeService.requiredRuntimeAbi}, '
            'found ${record.runtimeAbi ?? 'none'}.',
        recommendedAction:
            'Use a plugin package built for the current Hivra host ABI.',
      ));
    }
    if (record.runtimeEntryExport !=
        WasmPluginRuntimeService.requiredEntryExport) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: label,
        title: 'Runtime entry export mismatch',
        detail: 'Expected ${WasmPluginRuntimeService.requiredEntryExport}, '
            'found ${record.runtimeEntryExport ?? 'none'}.',
        recommendedAction:
            'Rebuild or reinstall the plugin with the supported entry export.',
      ));
    }
    if (record.capabilities.isEmpty) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: label,
        title: 'No capabilities declared',
        detail: 'Plugin cannot be authorized without explicit capabilities.',
        recommendedAction:
            'Install only packages with manifest-declared capabilities.',
      ));
    } else {
      try {
        _capabilityPolicy.normalizeAndValidate(record.capabilities);
      } catch (error) {
        findings.add(AiPluginAuditFinding(
          severity: 'critical',
          pluginLabel: label,
          title: 'Unsupported capability declared',
          detail: error.toString(),
          recommendedAction:
              'Remove this package or install a version with allowlisted capabilities.',
        ));
      }
    }
    if (record.packageKind != 'zip' && record.packageKind != 'wasm') {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: label,
        title: 'Unsupported package kind',
        detail: 'Found package kind ${record.packageKind}.',
        recommendedAction: 'Install a .zip or .wasm plugin package.',
      ));
    }

    return AiPluginAuditEntry(
      pluginLabel: label,
      pluginId: record.pluginId,
      pluginVersion: record.pluginVersion,
      packageKind: record.packageKind,
      packageDigestHex: digest,
      sizeBytes: sizeBytes,
      capabilities: record.capabilities,
      findings: findings,
    );
  }

  String _pluginLabel(WasmPluginRecord record) {
    final pluginId = record.pluginId?.trim();
    if (pluginId != null && pluginId.isNotEmpty) {
      return pluginId;
    }
    return record.displayName.trim().isNotEmpty
        ? record.displayName.trim()
        : record.id;
  }

  void _auditManifestSnippet({
    required String relativePath,
    required String text,
    required String? expectedPluginId,
    required List<AiPluginAuditFinding> findings,
  }) {
    final decoded = _parseJsonMap(text);
    if (decoded == null) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Plugin manifest is not valid JSON',
        detail: relativePath,
        recommendedAction: 'Fix manifest JSON before packaging the plugin.',
      ));
      return;
    }
    if (decoded['schema'] != 'hivra.plugin.manifest') {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Unsupported plugin manifest schema',
        detail: decoded['schema']?.toString() ?? 'missing',
        recommendedAction: 'Use schema hivra.plugin.manifest.',
      ));
    }
    final pluginId = decoded['plugin_id']?.toString().trim() ?? '';
    if (pluginId.isEmpty) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Plugin id is missing',
        detail: 'manifest plugin_id is empty.',
        recommendedAction: 'Add a stable plugin_id to manifest.json.',
      ));
    } else if (expectedPluginId != null &&
        expectedPluginId.trim().isNotEmpty &&
        pluginId != expectedPluginId.trim()) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Plugin source id does not match expected plugin',
        detail: 'Expected ${expectedPluginId.trim()}, found $pluginId.',
        recommendedAction:
            'Select source evidence for the installed plugin being audited.',
      ));
    }

    final runtime = decoded['runtime'];
    if (runtime is Map) {
      final abi = runtime['abi']?.toString().trim();
      final entryExport = runtime['entry_export']?.toString().trim();
      if (abi != WasmPluginRuntimeService.requiredRuntimeAbi) {
        findings.add(AiPluginAuditFinding(
          severity: 'critical',
          pluginLabel: relativePath,
          title: 'Manifest runtime ABI mismatch',
          detail:
              'Expected ${WasmPluginRuntimeService.requiredRuntimeAbi}, found ${abi ?? 'missing'}.',
          recommendedAction: 'Build plugin for the current Hivra host ABI.',
        ));
      }
      if (entryExport != WasmPluginRuntimeService.requiredEntryExport) {
        findings.add(AiPluginAuditFinding(
          severity: 'critical',
          pluginLabel: relativePath,
          title: 'Manifest runtime entry export mismatch',
          detail:
              'Expected ${WasmPluginRuntimeService.requiredEntryExport}, found ${entryExport ?? 'missing'}.',
          recommendedAction:
              'Expose the required semantic WASM entrypoint in manifest.',
        ));
      }
    } else {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Manifest runtime block is missing',
        detail: relativePath,
        recommendedAction: 'Add runtime ABI metadata to manifest.json.',
      ));
    }

    final rawCapabilities = decoded['capabilities'];
    final capabilities = <String>[];
    if (rawCapabilities is List) {
      for (final value in rawCapabilities) {
        final normalized = value?.toString().trim() ?? '';
        if (normalized.isNotEmpty) capabilities.add(normalized);
      }
    }
    if (capabilities.isEmpty) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'No capabilities declared',
        detail: 'manifest capabilities are empty.',
        recommendedAction: 'Declare explicit least-privilege capabilities.',
      ));
    } else {
      try {
        _capabilityPolicy.normalizeAndValidate(capabilities);
      } catch (error) {
        findings.add(AiPluginAuditFinding(
          severity: 'critical',
          pluginLabel: relativePath,
          title: 'Unsupported capability declared',
          detail: error.toString(),
          recommendedAction:
              'Remove unsupported capability from source manifest.',
        ));
      }
    }
  }

  void _auditCatalogSnippet({
    required String relativePath,
    required String text,
    required List<AiPluginAuditFinding> findings,
  }) {
    final decoded = _parseJsonMap(text);
    if (decoded == null) {
      findings.add(AiPluginAuditFinding(
        severity: 'critical',
        pluginLabel: relativePath,
        title: 'Plugin catalog evidence is not valid JSON',
        detail: relativePath,
        recommendedAction: 'Select a valid plugin_catalog.json.',
      ));
      return;
    }
    final signatures = decoded['signatures'];
    final entries = decoded['entries'];
    final hasSignatureEvidence = signatures is List && signatures.isNotEmpty;
    final hasDigestEvidence = entries is List &&
        entries.any((entry) =>
            entry is Map &&
            (entry['sha256_hex']?.toString().trim().isNotEmpty ?? false));
    if (!hasSignatureEvidence && !hasDigestEvidence) {
      findings.add(AiPluginAuditFinding(
        severity: 'warning',
        pluginLabel: relativePath,
        title: 'Catalog digest/signature evidence is missing',
        detail: relativePath,
        recommendedAction:
            'Use signed catalog v2 entries with package sha256_hex.',
      ));
    }
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
