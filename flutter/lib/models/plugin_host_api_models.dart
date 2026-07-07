import 'consensus_models.dart';

const int pluginHostApiSchemaVersion = 1;

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
