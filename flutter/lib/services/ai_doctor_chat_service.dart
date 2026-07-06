import 'ai_capsule_inspection_service.dart';
import 'ai_doctor_credential_store.dart';
import 'ai_doctor_prompt_service.dart';
import 'inference_provider_adapter.dart';

class AiDoctorChatResult {
  final AiDoctorOutboundPreview preview;
  final InferenceProviderResponse providerResponse;

  const AiDoctorChatResult({
    required this.preview,
    required this.providerResponse,
  });
}

class AiDoctorChatService {
  static const String defaultModel = 'gpt-5.5';

  final AiDoctorCredentialStore _credentialStore;
  final AiDoctorPromptService _promptService;
  final InferenceProviderAdapter Function(InferenceProviderKind provider)
      _providerAdapterFactory;

  AiDoctorChatService({
    required AiDoctorCredentialStore credentialStore,
    AiDoctorPromptService promptService = const AiDoctorPromptService(),
    InferenceProviderAdapter? providerAdapter,
    InferenceProviderAdapter Function(InferenceProviderKind provider)?
        providerAdapterFactory,
  })  : _credentialStore = credentialStore,
        _promptService = promptService,
        _providerAdapterFactory = providerAdapterFactory ??
            ((provider) =>
                providerAdapter ?? inferenceProviderAdapterFor(provider));

  Future<void> saveApiKey(
    InferenceProviderKind provider,
    String apiKey,
  ) {
    return _credentialStore.saveApiKey(provider, apiKey);
  }

  Future<void> clearApiKey(InferenceProviderKind provider) {
    return _credentialStore.clearApiKey(provider);
  }

  Future<void> saveOpenAiApiKey(String apiKey) {
    return saveApiKey(InferenceProviderKind.openAi, apiKey);
  }

  Future<void> clearOpenAiApiKey() {
    return clearApiKey(InferenceProviderKind.openAi);
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
    InferenceProviderKind provider = InferenceProviderKind.openAi,
  }) async {
    final apiKey = await _credentialStore.loadApiKey(provider);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('${provider.label} API key is not saved');
    }
    final prompt = _promptService.buildPrompt(
      snapshot: snapshot,
      userQuery: userQuery,
      sections: sections,
    );
    final response = await _providerAdapterFactory(provider).ask(
      apiKey: apiKey,
      model: model.trim().isEmpty ? provider.defaultModel : model,
      prompt: prompt,
    );
    return AiDoctorChatResult(
      preview: prompt.preview,
      providerResponse: response,
    );
  }
}
