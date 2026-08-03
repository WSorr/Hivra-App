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
  static const String defaultModel = 'gpt-5.5';
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

  Future<void> saveProviderApiKey(String providerId, String apiKey) {
    return _runtime.saveProviderApiKey(providerId, apiKey);
  }

  Future<void> savePreferredProviderId(String providerId) {
    return _runtime.savePreferredProviderId(providerId);
  }

  Future<String?> loadPreferredProviderId() {
    return _runtime.loadPreferredProviderId();
  }

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
    required Iterable<AiDoctorContextSection> sections,
  }) {
    return _promptService
        .buildPrompt(
          snapshot: snapshot,
          userQuery: userQuery,
          sections: sections,
        )
        .preview;
  }

  Future<AiDoctorChatResult> ask({
    required AiCapsuleInspectionSnapshot snapshot,
    required String userQuery,
    required Iterable<AiDoctorContextSection> sections,
    String model = defaultModel,
    String providerId = defaultProviderId,
  }) async {
    final prompt = _promptService.buildPrompt(
      snapshot: snapshot,
      userQuery: userQuery,
      sections: sections,
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
