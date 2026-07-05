import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
