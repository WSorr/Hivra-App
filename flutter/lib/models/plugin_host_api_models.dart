import 'dart:convert';

import 'consensus_models.dart';

const int pluginHostApiSchemaVersion = 1;

enum PluginHostApiStatus { executed, blocked, rejected }

class PluginHostApiRequest {
  final int schemaVersion;
  final String pluginId;
  final String method;
  final Map<String, dynamic> args;

  const PluginHostApiRequest({
    required this.schemaVersion,
    required this.pluginId,
    required this.method,
    required this.args,
  });
}

class PluginHostApiResponse {
  final PluginHostApiStatus status;
  final String pluginId;
  final String method;
  final String executionSource;
  final String? executionPackageId;
  final String? executionPackageVersion;
  final String? executionPackageKind;
  final String? executionPackageDigestHex;
  final String? executionContractKind;
  final String? executionRuntimeMode;
  final String? executionRuntimeAbi;
  final String? executionRuntimeEntryExport;
  final String? executionRuntimeModulePath;
  final String? executionRuntimeModuleSelection;
  final String? executionRuntimeModuleDigestHex;
  final String? executionRuntimeInvokeDigestHex;
  final List<String> executionCapabilities;
  final String? errorCode;
  final String? errorMessage;
  final List<ConsensusBlockingFact> blockingFacts;
  final Map<String, dynamic>? result;
  final String canonicalJson;
  final String responseHashHex;

  const PluginHostApiResponse({
    required this.status,
    required this.pluginId,
    required this.method,
    required this.executionSource,
    required this.executionPackageId,
    required this.executionPackageVersion,
    required this.executionPackageKind,
    required this.executionPackageDigestHex,
    required this.executionContractKind,
    required this.executionRuntimeMode,
    required this.executionRuntimeAbi,
    required this.executionRuntimeEntryExport,
    required this.executionRuntimeModulePath,
    required this.executionRuntimeModuleSelection,
    required this.executionRuntimeModuleDigestHex,
    required this.executionRuntimeInvokeDigestHex,
    required this.executionCapabilities,
    required this.errorCode,
    required this.errorMessage,
    required this.blockingFacts,
    required this.result,
    required this.canonicalJson,
    required this.responseHashHex,
  });
}

class PluginRuntimeBinding {
  final String source;
  final String? packageId;
  final String? packageVersion;
  final String? packageKind;
  final String? packageDigestHex;
  final String? packageFilePath;
  final String? runtimeAbi;
  final String? runtimeEntryExport;
  final String? runtimeModulePath;
  final String? contractKind;
  final List<String> capabilities;

  const PluginRuntimeBinding({
    required this.source,
    required this.packageId,
    required this.packageVersion,
    required this.packageKind,
    required this.packageDigestHex,
    required this.packageFilePath,
    required this.runtimeAbi,
    required this.runtimeEntryExport,
    required this.runtimeModulePath,
    required this.contractKind,
    required this.capabilities,
  });

  const PluginRuntimeBinding.hostFallback()
    : source = 'host_fallback',
      packageId = null,
      packageVersion = null,
      packageKind = null,
      packageDigestHex = null,
      packageFilePath = null,
      runtimeAbi = null,
      runtimeEntryExport = null,
      runtimeModulePath = null,
      contractKind = null,
      capabilities = const <String>[];

  const PluginRuntimeBinding.externalPackage({
    required this.packageId,
    required this.packageVersion,
    required this.packageKind,
    this.packageDigestHex,
    this.packageFilePath,
    this.runtimeAbi,
    this.runtimeEntryExport,
    this.runtimeModulePath,
    required this.contractKind,
    this.capabilities = const <String>[],
  }) : source = 'external_package',
       assert(packageId != null),
       assert(packageKind != null);
}

typedef PluginRuntimeBindingResolver =
    Future<PluginRuntimeBinding> Function(String pluginId);

class PluginRuntimeInvokeEvidence {
  final String mode;
  final String? modulePath;
  final String? moduleSelection;
  final String moduleDigestHex;
  final String invokeDigestHex;
  final PluginHostApiStatus semanticStatus;
  final Map<String, dynamic>? semanticResult;
  final String? semanticErrorCode;
  final String? semanticErrorMessage;

  const PluginRuntimeInvokeEvidence({
    required this.mode,
    required this.modulePath,
    required this.moduleSelection,
    required this.moduleDigestHex,
    required this.invokeDigestHex,
    required this.semanticStatus,
    required this.semanticResult,
    required this.semanticErrorCode,
    required this.semanticErrorMessage,
  });
}

typedef PluginRuntimeInvokeResolver =
    Future<PluginRuntimeInvokeEvidence?> Function(
      PluginHostApiRequest request,
      PluginRuntimeBinding binding,
    );

/// One deadline/revocation predicate for app, headless runner and custody checks.
/// A null deadline is explicit owner authorization until revocation; zero is ended.
bool workspaceExecutionIsActive(Map control, {int? nowMs}) {
  final deadline = control['expires_at_ms'];
  return control['revoked'] != true &&
      control.containsKey('expires_at_ms') &&
      (deadline == null ||
          (deadline is int &&
              deadline > (nowMs ?? DateTime.now().millisecondsSinceEpoch)));
}

/// Version-one grants remain readable for custody/recovery, never upgraded
/// into a version-two capability permission by interpreting their old scope.
String workspaceExecutionFlag(Map control) =>
    control['version'] == 2 ? 'enabled' : 'allow_new_entries';
bool workspaceExecutionEnabled(Map control) =>
    control[workspaceExecutionFlag(control)] == true;

void validateWorkspaceExecutionControl(
  dynamic control,
  String owner,
  String pluginId,
) {
  if (control is! Map ||
      ![1, 2].contains(control['version']) ||
      control['owner'] != owner ||
      control['plugin_id'] != pluginId ||
      control['revision'] is! int ||
      control['revision'] <= 0 ||
      control[workspaceExecutionFlag(control)] is! bool ||
      !control.containsKey('expires_at_ms') ||
      (control['expires_at_ms'] != null &&
          (control['expires_at_ms'] is! int ||
              control['expires_at_ms'] < 0 ||
              control['expires_at_ms'] > 8640000000000000)) ||
      (control.containsKey('revoked') && control['revoked'] is! bool) ||
      ((control['revoked'] == true || control['expires_at_ms'] == 0) &&
          workspaceExecutionEnabled(control)) ||
      control['settings'] is! Map ||
      control['scope'] is! Map ||
      control['package_id'] is! String ||
      (control['package_id'] as String).isEmpty ||
      (control['package_id'] as String).length > 128 ||
      control['package_digest'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(control['package_digest']) ||
      !{'local', 'vps'}.contains(control['executor'] ?? 'local') ||
      (control['executor'] == 'vps' &&
          (control['executor_id'] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(control['executor_id']))) ||
      ['handoff_id', 'handoff_digest'].any(
        (key) =>
            control[key] != null &&
            (control[key] is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(control[key])),
      )) {
    throw StateError(
      'Execution grant is unreadable; no cycle or effect admitted',
    );
  }
  final references = control['credentials'];
  if (references != null &&
      (references is! Map ||
          references.length > 8 ||
          references.entries.any(
            (e) =>
                e.key is! String ||
                !RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(e.key) ||
                e.value is! Map ||
                (e.value as Map).length > 8 ||
                (e.value as Map).entries.any(
                  (f) =>
                      f.key is! String ||
                      !RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(f.key) ||
                      f.value is! String ||
                      (f.value as String).isEmpty ||
                      (f.value as String).length > 1024,
                ),
          ))) {
    throw StateError('Invalid owner credential references');
  }
  final settings = control['settings'] as Map;
  if (settings.length > 8 ||
      utf8.encode(jsonEncode(settings)).length > 2048 ||
      settings.values.any((v) => v is! String && v is! num)) {
    throw StateError('Execution settings are invalid');
  }
  validateWorkspaceExecutionSchedule(
    Map<String, dynamic>.from(control['scope'] as Map),
  );
}

void validateWorkspaceExecutionSchedule(Map<String, dynamic> scope) {
  if (scope['version'] == 2) {
    final scheduled =
        scope['action'] != null || scope['interval_seconds'] != null;
    if ((scheduled &&
            (scope['action'] is! String ||
                !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(scope['action']) ||
                scope['interval_seconds'] is! int ||
                scope['interval_seconds'] < 1 ||
                scope['interval_seconds'] > 3600)) ||
        scope['access'] is! Map ||
        scope['description'] is! String ||
        (scope['description'] as String).length > 2048 ||
        utf8.encode(jsonEncode(scope)).length > 6144) {
      throw StateError('Invalid permission scope');
    }
    return;
  }

  if (scope.length != 6 ||
      scope['account_id'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(scope['account_id']) ||
      scope['symbol'] is! String ||
      (scope['symbol'] as String).length > 64 ||
      !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(scope['symbol']) ||
      scope['action'] is! String ||
      !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(scope['action']) ||
      scope['interval_seconds'] is! int ||
      scope['interval_seconds'] < 30 ||
      scope['interval_seconds'] > 3600 ||
      scope['max_margin'] is! num ||
      !scope['max_margin'].isFinite ||
      scope['max_margin'] <= 0 ||
      scope['max_stop_percent'] is! num ||
      !scope['max_stop_percent'].isFinite ||
      scope['max_stop_percent'] <= 0 ||
      scope['max_stop_percent'] > 100) {
    throw StateError('Invalid bounded execution scope');
  }
}

/// Recovery retains remote custody and evidence, never a live permission lease.
Map<String, dynamic> sealWorkspaceExecutionForRecovery(
  Map<String, dynamic> control,
  String owner,
  String pluginId,
) {
  validateWorkspaceExecutionControl(control, owner, pluginId);
  return {
    ...control,
    'expires_at_ms': 0,
    workspaceExecutionFlag(control): false,
  };
}
