import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/consensus_models.dart';
import 'plugin_host_contract_handler.dart';
import 'wasm_plugin_capability_policy_service.dart';

enum PluginHostApiStatus {
  executed,
  blocked,
  rejected,
}

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
  })  : source = 'external_package',
        assert(packageId != null),
        assert(packageKind != null);
}

typedef PluginRuntimeBindingResolver = Future<PluginRuntimeBinding> Function(
  String pluginId,
);

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

typedef PluginRuntimeInvokeResolver = Future<PluginRuntimeInvokeEvidence?>
    Function(
  PluginHostApiRequest request,
  PluginRuntimeBinding binding,
);

class PluginHostApiService {
  static const int schemaVersion = 1;

  final List<PluginHostContractHandler> _handlers;
  final PluginRuntimeBindingResolver? _resolveRuntimeBinding;
  final PluginRuntimeInvokeResolver? _resolveRuntimeInvoke;
  final WasmPluginCapabilityPolicyService _capabilityPolicy;

  const PluginHostApiService({
    required List<PluginHostContractHandler> handlers,
    PluginRuntimeBindingResolver? resolveRuntimeBinding,
    PluginRuntimeInvokeResolver? resolveRuntimeInvoke,
    WasmPluginCapabilityPolicyService capabilityPolicy =
        const WasmPluginCapabilityPolicyService(),
  })  : _handlers = handlers,
        _resolveRuntimeBinding = resolveRuntimeBinding,
        _resolveRuntimeInvoke = resolveRuntimeInvoke,
        _capabilityPolicy = capabilityPolicy;

  PluginHostApiResponse execute(PluginHostApiRequest request) {
    return _executeResolved(
      request,
      const PluginRuntimeBinding.hostFallback(),
      null,
    );
  }

  Future<PluginHostApiResponse> executeWithRuntimeHook(
    PluginHostApiRequest request,
  ) async {
    if (_resolveRuntimeBinding == null) {
      return execute(request);
    }
    final runtimeBinding = await _resolveRuntimeBinding(request.pluginId);
    final runtimeBindingValidation =
        _validateRuntimeBindingShape(runtimeBinding);
    if (runtimeBindingValidation != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_binding_invalid',
        message: runtimeBindingValidation,
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    final preflightResponse = _preflightBeforeRuntime(
      request,
      runtimeBinding,
    );
    if (preflightResponse != null) {
      return preflightResponse;
    }
    PluginRuntimeInvokeEvidence? runtimeInvoke;
    if (_resolveRuntimeInvoke != null) {
      try {
        runtimeInvoke = await _resolveRuntimeInvoke(request, runtimeBinding);
      } on FormatException catch (error) {
        return _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'runtime_invoke_invalid',
          message: error.message,
          runtimeBinding: runtimeBinding,
          runtimeInvoke: null,
        );
      } catch (_) {
        return _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'runtime_invoke_failed',
          message: 'Runtime invoke hook failed',
          runtimeBinding: runtimeBinding,
          runtimeInvoke: null,
        );
      }
    }
    if (runtimeBinding.source == 'external_package' && runtimeInvoke == null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_invoke_unavailable',
        message: 'Runtime invoke evidence unavailable for external package',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    return _executeResolved(request, runtimeBinding, runtimeInvoke);
  }

  PluginHostApiResponse? _preflightBeforeRuntime(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
  ) {
    if (request.schemaVersion != schemaVersion) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_schema_version',
        message: 'Plugin host API schema version mismatch',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    final handler = _handlerFor(request.pluginId);
    if (handler == null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_plugin',
        message: 'Unsupported plugin id',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    if (!handler.methods.contains(request.method)) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    if (handler.requiresExternalRuntime &&
        runtimeBinding.source != 'external_package') {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_invoke_unavailable',
        message: 'External runtime package is required',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    final contractKindMismatch = _validateRuntimeContractKind(
      pluginId: request.pluginId,
      runtimeBinding: runtimeBinding,
    );
    if (contractKindMismatch != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_contract_kind_mismatch',
        message: contractKindMismatch,
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    final capabilityMismatch = _validateRuntimeCapabilities(
      pluginId: request.pluginId,
      method: request.method,
      runtimeBinding: runtimeBinding,
    );
    if (capabilityMismatch != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_capability_mismatch',
        message: capabilityMismatch,
        runtimeBinding: runtimeBinding,
        runtimeInvoke: null,
      );
    }
    final result = handler.preflight(request);
    if (result == null) return null;
    return switch (result.status) {
      PluginHostApiStatus.blocked => _blocked(
          pluginId: request.pluginId,
          method: request.method,
          blockingFacts: result.blockingFacts,
          runtimeBinding: runtimeBinding,
          runtimeInvoke: null,
        ),
      PluginHostApiStatus.rejected => _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: result.errorCode!,
          message: result.errorMessage!,
          runtimeBinding: runtimeBinding,
          runtimeInvoke: null,
        ),
      PluginHostApiStatus.executed => _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'preflight_invalid',
          message: 'Plugin preflight must not execute a contract',
          runtimeBinding: runtimeBinding,
          runtimeInvoke: null,
        ),
    };
  }

  bool _requiresExternalRuntimeExecution(PluginHostApiRequest request) {
    final handler = _handlerFor(request.pluginId);
    return handler != null &&
        handler.methods.contains(request.method) &&
        handler.requiresExternalRuntime;
  }

  String? _validateRuntimeBindingShape(PluginRuntimeBinding binding) {
    if (binding.source != 'external_package') {
      return null;
    }
    final packageId = binding.packageId?.trim() ?? '';
    if (packageId.isEmpty) {
      return 'Runtime binding package_id is missing';
    }
    final packageKind = binding.packageKind?.trim().toLowerCase() ?? '';
    if (packageKind != 'zip' && packageKind != 'wasm') {
      return 'Runtime binding package_kind is invalid';
    }
    return null;
  }

  PluginHostApiResponse _executeResolved(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  ) {
    if (request.schemaVersion != schemaVersion) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_schema_version',
        message: 'Plugin host API schema version mismatch',
        runtimeBinding: runtimeBinding,
        runtimeInvoke: runtimeInvoke,
      );
    }
    if (_requiresExternalRuntimeExecution(request)) {
      if (runtimeBinding.source != 'external_package') {
        return _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'runtime_invoke_unavailable',
          message: 'Runtime package is required for futures plugin execution',
          runtimeBinding: runtimeBinding,
          runtimeInvoke: runtimeInvoke,
        );
      }
      if (runtimeInvoke == null) {
        return _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'runtime_invoke_unavailable',
          message: 'Runtime invoke evidence unavailable for external package',
          runtimeBinding: runtimeBinding,
          runtimeInvoke: runtimeInvoke,
        );
      }
    }
    final contractKindMismatch = _validateRuntimeContractKind(
      pluginId: request.pluginId,
      runtimeBinding: runtimeBinding,
    );
    if (contractKindMismatch != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_contract_kind_mismatch',
        message: contractKindMismatch,
        runtimeBinding: runtimeBinding,
        runtimeInvoke: runtimeInvoke,
      );
    }
    final capabilityMismatch = _validateRuntimeCapabilities(
      pluginId: request.pluginId,
      method: request.method,
      runtimeBinding: runtimeBinding,
    );
    if (capabilityMismatch != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'runtime_capability_mismatch',
        message: capabilityMismatch,
        runtimeBinding: runtimeBinding,
        runtimeInvoke: runtimeInvoke,
      );
    }
    final handler = _handlerFor(request.pluginId);
    if (handler != null) {
      if (!handler.methods.contains(request.method)) {
        return _rejected(
          pluginId: request.pluginId,
          method: request.method,
          code: 'unsupported_method',
          message: 'Unsupported plugin method',
          runtimeBinding: runtimeBinding,
          runtimeInvoke: runtimeInvoke,
        );
      }
      final result = handler.execute(request, runtimeInvoke: runtimeInvoke);
      return switch (result.status) {
        PluginHostApiStatus.executed => _executed(
            pluginId: request.pluginId,
            method: request.method,
            runtimeBinding: runtimeBinding,
            runtimeInvoke: runtimeInvoke,
            result: result.result!,
          ),
        PluginHostApiStatus.blocked => _blocked(
            pluginId: request.pluginId,
            method: request.method,
            blockingFacts: result.blockingFacts,
            runtimeBinding: runtimeBinding,
            runtimeInvoke: runtimeInvoke,
          ),
        PluginHostApiStatus.rejected => _rejected(
            pluginId: request.pluginId,
            method: request.method,
            code: result.errorCode!,
            message: result.errorMessage!,
            runtimeBinding: runtimeBinding,
            runtimeInvoke: runtimeInvoke,
          ),
      };
    }
    return _rejected(
      pluginId: request.pluginId,
      method: request.method,
      code: 'unsupported_plugin',
      message: 'Unsupported plugin id',
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
    );
  }

  String? _validateRuntimeContractKind({
    required String pluginId,
    required PluginRuntimeBinding runtimeBinding,
  }) {
    if (runtimeBinding.source != 'external_package') {
      return null;
    }
    final expected = _expectedContractKindForPlugin(pluginId);
    if (expected == null) {
      return null;
    }
    final actual = runtimeBinding.contractKind?.trim() ?? '';
    if (actual.isEmpty) {
      return 'Runtime contract kind is missing';
    }
    if (actual != expected) {
      return 'Runtime contract kind does not match requested plugin id';
    }
    return null;
  }

  String? _expectedContractKindForPlugin(String pluginId) {
    return _handlerFor(pluginId)?.contractKind;
  }

  String? _validateRuntimeCapabilities({
    required String pluginId,
    required String method,
    required PluginRuntimeBinding runtimeBinding,
  }) {
    if (runtimeBinding.source != 'external_package') {
      return null;
    }
    final declared = runtimeBinding.capabilities;
    if (declared.isEmpty) {
      return 'Runtime capabilities are missing required grants';
    }
    List<String> normalized;
    try {
      normalized = _capabilityPolicy.normalizeAndValidate(declared);
    } on FormatException {
      return 'Runtime capabilities contain unsupported entries';
    }
    final required = _requiredCapabilitiesFor(
      pluginId: pluginId,
      method: method,
    );
    final normalizedSet = normalized.toSet();
    final missing =
        required.where((cap) => !normalizedSet.contains(cap)).toList()..sort();
    if (missing.isNotEmpty) {
      return 'Runtime capabilities are missing required grants';
    }
    return null;
  }

  Set<String> _requiredCapabilitiesFor({
    required String pluginId,
    required String method,
  }) {
    return _handlerFor(pluginId)?.requiredCapabilities(method) ??
        const <String>{};
  }

  PluginHostContractHandler? _handlerFor(String pluginId) {
    for (final handler in _handlers) {
      if (handler.pluginId == pluginId) return handler;
    }
    return null;
  }

  PluginHostApiResponse _executed({
    required String pluginId,
    required String method,
    required PluginRuntimeBinding runtimeBinding,
    required PluginRuntimeInvokeEvidence? runtimeInvoke,
    required Map<String, dynamic> result,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
    );
    return _buildResponse(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _blocked({
    required String pluginId,
    required String method,
    required PluginRuntimeBinding runtimeBinding,
    required PluginRuntimeInvokeEvidence? runtimeInvoke,
    required List<ConsensusBlockingFact> blockingFacts,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: null,
      errorMessage: null,
      blockingFacts: blockingFacts,
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: null,
      errorMessage: null,
      blockingFacts: blockingFacts,
      result: null,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _rejected({
    required String pluginId,
    required String method,
    required String code,
    required String message,
    required PluginRuntimeBinding runtimeBinding,
    required PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: code,
      errorMessage: message,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      runtimeInvoke: runtimeInvoke,
      errorCode: code,
      errorMessage: message,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: null,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _buildResponse({
    required PluginHostApiStatus status,
    required String pluginId,
    required String method,
    required PluginRuntimeBinding runtimeBinding,
    required PluginRuntimeInvokeEvidence? runtimeInvoke,
    required String? errorCode,
    required String? errorMessage,
    required List<ConsensusBlockingFact> blockingFacts,
    required Map<String, dynamic>? result,
    required String canonical,
  }) {
    final responseHashHex = sha256.convert(utf8.encode(canonical)).toString();
    final executionCapabilities = _normalizedCapabilities(
      runtimeBinding.capabilities,
    );
    return PluginHostApiResponse(
      status: status,
      pluginId: pluginId,
      method: method,
      executionSource: runtimeBinding.source,
      executionPackageId: runtimeBinding.packageId,
      executionPackageVersion: runtimeBinding.packageVersion,
      executionPackageKind: runtimeBinding.packageKind,
      executionPackageDigestHex: runtimeBinding.packageDigestHex,
      executionContractKind: runtimeBinding.contractKind,
      executionRuntimeMode: runtimeInvoke?.mode,
      executionRuntimeAbi: runtimeBinding.runtimeAbi,
      executionRuntimeEntryExport: runtimeBinding.runtimeEntryExport,
      executionRuntimeModulePath:
          runtimeInvoke?.modulePath ?? runtimeBinding.runtimeModulePath,
      executionRuntimeModuleSelection: runtimeInvoke?.moduleSelection,
      executionRuntimeModuleDigestHex: runtimeInvoke?.moduleDigestHex,
      executionRuntimeInvokeDigestHex: runtimeInvoke?.invokeDigestHex,
      executionCapabilities: executionCapabilities,
      errorCode: errorCode,
      errorMessage: errorMessage,
      blockingFacts: (blockingFacts.toList()
        ..sort((a, b) => a.key.compareTo(b.key))),
      result: result,
      canonicalJson: canonical,
      responseHashHex: responseHashHex,
    );
  }

  String _canonical({
    required PluginHostApiStatus status,
    required String pluginId,
    required String method,
    required PluginRuntimeBinding runtimeBinding,
    required PluginRuntimeInvokeEvidence? runtimeInvoke,
    required String? errorCode,
    required String? errorMessage,
    required List<ConsensusBlockingFact> blockingFacts,
    required Map<String, dynamic>? result,
  }) {
    final executionCapabilities = _normalizedCapabilities(
      runtimeBinding.capabilities,
    );
    return jsonEncode({
      'schema_version': schemaVersion,
      'status': status.name,
      'plugin_id': pluginId,
      'method': method,
      'execution_source': runtimeBinding.source,
      'execution_package_id': runtimeBinding.packageId,
      'execution_package_version': runtimeBinding.packageVersion,
      'execution_package_kind': runtimeBinding.packageKind,
      'execution_package_digest_hex': runtimeBinding.packageDigestHex,
      'execution_contract_kind': runtimeBinding.contractKind,
      'execution_runtime_mode': runtimeInvoke?.mode,
      'execution_runtime_abi': runtimeBinding.runtimeAbi,
      'execution_runtime_entry_export': runtimeBinding.runtimeEntryExport,
      'execution_runtime_module_path':
          runtimeInvoke?.modulePath ?? runtimeBinding.runtimeModulePath,
      'execution_runtime_module_selection': runtimeInvoke?.moduleSelection,
      'execution_runtime_module_digest_hex': runtimeInvoke?.moduleDigestHex,
      'execution_runtime_invoke_digest_hex': runtimeInvoke?.invokeDigestHex,
      'execution_capabilities': executionCapabilities,
      'error_code': errorCode,
      'error_message': errorMessage,
      'blocking_facts': (blockingFacts
          .map((fact) => <String, dynamic>{
                'code': fact.code,
                'subject_id': fact.subjectId,
              })
          .toList()
        ..sort(
          (a, b) => '${a['code']}:${a['subject_id'] ?? ''}'
              .compareTo('${b['code']}:${b['subject_id'] ?? ''}'),
        )),
      'result': result,
    });
  }

  List<String> _normalizedCapabilities(List<String> raw) {
    final normalized = <String>{};
    for (final item in raw) {
      final value = item.trim();
      if (value.isEmpty) continue;
      normalized.add(value);
    }
    final ordered = normalized.toList()..sort();
    return ordered;
  }
}
