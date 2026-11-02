import 'ai_capsule_inspection_service.dart';
import 'ai_doctor_prompt_service.dart';
import 'capsule_ai_runtime_service.dart';

class AiDoctorChatResult {
  final AiDoctorOutboundPreview preview;
  final String text;
  final String providerId;
  final String providerLabel;
  final String model;

  const AiDoctorChatResult({
    required this.preview,
    required this.text,
    required this.providerId,
    required this.providerLabel,
    required this.model,
  });
}

class AiDoctorChatService {
  static const String defaultProviderId = 'openai';
  static const String capabilityId = 'hivra.capsule_analyst.chat';
  static const String proposalSchemaId = 'hivra.capsule_analyst.advisory.v1';

  final CapsuleInferenceRuntime _runtime;
  final AiDoctorPromptService _promptService;

  AiDoctorChatService({
    required CapsuleInferenceRuntime runtime,
    AiDoctorPromptService promptService = const AiDoctorPromptService(),
  }) : _runtime = runtime,
       _promptService = promptService;

  Future<List<InferenceConnection>> loadConnections() =>
      _runtime.loadConnections();
  Future<InferenceConnection> addConnection({
    required String name,
    required InferenceProtocol protocol,
    required String baseUrl,
    required String model,
    required bool requiresApiKey,
  }) => _runtime.addConnection(
    name: name,
    protocol: protocol,
    baseUrl: baseUrl,
    model: model,
    requiresApiKey: requiresApiKey,
  );
  Future<void> removeConnection(String id) => _runtime.removeConnection(id);

  Future<void> saveProviderApiKey(String providerId, String apiKey) {
    return _runtime.saveProviderApiKey(providerId, apiKey);
  }

  Future<bool> hasProviderApiKey(String providerId) {
    return _runtime.hasProviderApiKey(providerId);
  }

  Future<void> savePreferredProviderId(String providerId, {String? model}) {
    return _runtime.savePreferredProviderId(providerId, model: model);
  }

  Future<String?> loadPreferredProviderId() {
    return _runtime.loadPreferredProviderId();
  }

  Future<String> loadPreferredModel(String providerId) =>
      _runtime.loadPreferredModel(providerId);

  Future<void> clearProviderApiKey(String providerId) {
    return _runtime.clearProviderApiKey(providerId);
  }

  Future<void> saveProviderBaseUrl(String providerId, String baseUrl) {
    return _runtime.saveProviderBaseUrl(providerId, baseUrl);
  }

  Future<void> clearProviderBaseUrl(String providerId) {
    return _runtime.clearProviderBaseUrl(providerId);
  }

  AiDoctorOutboundPreview preview({
    required AiCapsuleInspectionSnapshot snapshot,
    required String userQuery,
  }) {
    return _promptService
        .buildPrompt(snapshot: snapshot, userQuery: userQuery)
        .preview;
  }

  Future<AiDoctorChatResult> ask({
    required AiCapsuleInspectionSnapshot snapshot,
    required String userQuery,
    String model = '',
    String providerId = defaultProviderId,
  }) async {
    final prompt = _promptService.buildPrompt(
      snapshot: snapshot,
      userQuery: userQuery,
    );
    final capsuleRootHex = _runtime.requireActiveCapsuleRootHex();
    await _runtime.unlockProviderSession(providerId);
    final normalizedModel = model.trim();
    final response = await _runtime.infer(
      CapsuleInferenceRequestV1.create(
        capsuleRootHex: capsuleRootHex,
        capabilityId: capabilityId,
        disclosureSchemaVersion: 1,
        disclosedSectionIds: <String>[
          'user_query',
          ...prompt.preview.sections.map((section) => section.key),
        ],
        proposalSchemaId: proposalSchemaId,
        proposalSchemaVersion: 1,
        cancellationScope: '$capabilityId:$capsuleRootHex',
        instructions: prompt.instructions,
        input: prompt.payload,
        providerPolicy: CapsuleInferenceProviderPolicyV1.explicit,
        providerId: providerId,
        modelPolicy:
            normalizedModel.isEmpty
                ? CapsuleInferenceModelPolicyV1.providerDefault
                : CapsuleInferenceModelPolicyV1.explicit,
        model: normalizedModel.isEmpty ? null : normalizedModel,
        maxInputBytes: AiDoctorPromptService.maxPayloadBytes,
        maxOutputBytes: CapsuleInferenceRequestV1.maxSupportedOutputBytes,
      ),
    );
    return AiDoctorChatResult(
      preview: prompt.preview,
      text: response.proposalText,
      providerId: response.providerId,
      providerLabel: response.providerLabel,
      model: response.model,
    );
  }
}
