import 'consensus_processor.dart';
import 'plugin_host_api_service.dart';

class PluginHostContractResult {
  final PluginHostApiStatus status;
  final Map<String, dynamic>? result;
  final List<ConsensusBlockingFact> blockingFacts;
  final String? errorCode;
  final String? errorMessage;

  const PluginHostContractResult.executed(Map<String, dynamic> this.result)
      : status = PluginHostApiStatus.executed,
        blockingFacts = const <ConsensusBlockingFact>[],
        errorCode = null,
        errorMessage = null;

  const PluginHostContractResult.blocked(
    this.blockingFacts,
  )   : status = PluginHostApiStatus.blocked,
        result = null,
        errorCode = null,
        errorMessage = null;

  const PluginHostContractResult.rejected({
    required String code,
    required String message,
  })  : status = PluginHostApiStatus.rejected,
        result = null,
        blockingFacts = const <ConsensusBlockingFact>[],
        errorCode = code,
        errorMessage = message;
}

abstract interface class PluginHostContractHandler {
  String get pluginId;
  String get contractKind;
  Set<String> get methods;
  bool get requiresExternalRuntime;

  Set<String> requiredCapabilities(String method);

  PluginHostContractResult? preflight(PluginHostApiRequest request);

  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  });
}
