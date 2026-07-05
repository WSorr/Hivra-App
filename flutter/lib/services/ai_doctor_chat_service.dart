import 'ai_capsule_inspection_service.dart';
import 'ai_doctor_credential_store.dart';
import 'ai_doctor_prompt_service.dart';
import 'ai_doctor_provider_adapter.dart';

class AiDoctorChatResult {
  final AiDoctorOutboundPreview preview;
  final AiDoctorProviderResponse providerResponse;

  const AiDoctorChatResult({
    required this.preview,
    required this.providerResponse,
  });
}

class AiDoctorChatService {
  static const String defaultModel = 'gpt-5.5';

  final AiDoctorCredentialStore _credentialStore;
  final AiDoctorPromptService _promptService;
  final AiDoctorProviderAdapter _providerAdapter;

  const AiDoctorChatService({
    required AiDoctorCredentialStore credentialStore,
    AiDoctorPromptService promptService = const AiDoctorPromptService(),
    AiDoctorProviderAdapter? providerAdapter,
  })  : _credentialStore = credentialStore,
        _promptService = promptService,
        _providerAdapter =
            providerAdapter ?? const _DefaultAiDoctorProviderAdapter();

  Future<void> saveOpenAiApiKey(String apiKey) {
    return _credentialStore.saveOpenAiApiKey(apiKey);
  }

  Future<void> clearOpenAiApiKey() {
    return _credentialStore.clearOpenAiApiKey();
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
  }) async {
    final apiKey = await _credentialStore.loadOpenAiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('OpenAI API key is not saved');
    }
    final prompt = _promptService.buildPrompt(
      snapshot: snapshot,
      userQuery: userQuery,
      sections: sections,
    );
    final response = await _providerAdapter.ask(
      apiKey: apiKey,
      model: model,
      prompt: prompt,
    );
    return AiDoctorChatResult(
      preview: prompt.preview,
      providerResponse: response,
    );
  }
}

class _DefaultAiDoctorProviderAdapter implements AiDoctorProviderAdapter {
  const _DefaultAiDoctorProviderAdapter();

  @override
  Future<AiDoctorProviderResponse> ask({
    required String apiKey,
    required String model,
    required AiDoctorPrompt prompt,
  }) {
    return OpenAiResponsesDoctorProviderAdapter().ask(
      apiKey: apiKey,
      model: model,
      prompt: prompt,
    );
  }
}
