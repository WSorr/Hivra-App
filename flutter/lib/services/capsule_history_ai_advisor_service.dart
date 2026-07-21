import 'dart:convert';

import 'ai_doctor_credential_store.dart';
import 'capsule_history_projection_service.dart';
import 'inference_provider_adapter.dart';

class CapsuleHistoryAiResult {
  final String text;
  final String model;
  final InferenceProviderKind provider;

  const CapsuleHistoryAiResult({
    required this.text,
    required this.model,
    required this.provider,
  });
}

class CapsuleHistoryAiAdvisorService {
  static const int maxHistoryEvents = 100;

  final AiDoctorCredentialStore _credentialStore;
  final InferenceProviderAdapter Function(InferenceProviderKind provider)
  _adapterFactory;

  CapsuleHistoryAiAdvisorService({
    required AiDoctorCredentialStore credentialStore,
    InferenceProviderAdapter Function(InferenceProviderKind provider)?
    adapterFactory,
  }) : _credentialStore = credentialStore,
       _adapterFactory = adapterFactory ?? inferenceProviderAdapterFor;

  Future<CapsuleHistoryAiResult> explain(
    CapsuleHistoryProjection projection,
  ) async {
    if (projection.entries.isEmpty) {
      throw StateError('No confirmed ledger history exists for this item');
    }
    final provider =
        await _credentialStore.loadPreferredProvider() ??
        InferenceProviderKind.gemini;
    final apiKey = await _credentialStore.loadApiKey(provider);
    if (provider.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        '${provider.label} API key is not saved. Configure it in Capsule Analyst.',
      );
    }
    final baseUrl = await _credentialStore.loadBaseUrl(provider);
    if (provider == InferenceProviderKind.localOpenAiCompatible &&
        (baseUrl == null || baseUrl.isEmpty)) {
      throw StateError(
        '${provider.label} base URL is not saved. Configure it in Capsule Analyst.',
      );
    }

    final events =
        projection.entries.length <= maxHistoryEvents
            ? projection.entries
            : projection.entries.sublist(
              projection.entries.length - maxHistoryEvents,
            );
    final payload = <String, dynamic>{
      'schema_version': 1,
      'mode': 'scoped_capsule_history_explanation',
      'history': <String, dynamic>{
        ...projection.toAdvisoryJson(),
        'events': events.map((entry) => entry.toAdvisoryJson()).toList(),
        'truncated': events.length != projection.entries.length,
        'total_event_count': projection.entries.length,
      },
      'constraints': <String, dynamic>{
        'advisory_only': true,
        'no_ledger_mutation': true,
        'facts_only_from_supplied_projection': true,
        'distinguish_fact_from_inference': true,
        'no_secret_request': true,
      },
      'redaction': <String, dynamic>{
        'raw_payload_included': false,
        'signatures_included': false,
        'private_keys_included': false,
        'credentials_included': false,
      },
    };
    final response = await _adapterFactory(provider).ask(
      apiKey: apiKey ?? '',
      model: provider.defaultModel,
      baseUrl: baseUrl,
      prompt: InferencePrompt(
        instructions: _instructions,
        inputJson: const JsonEncoder.withIndent('  ').convert(payload),
      ),
    );
    return CapsuleHistoryAiResult(
      text: response.text,
      model: response.model,
      provider: response.provider,
    );
  }

  static const String _instructions = '''
You are Hivra Capsule History Analyst.
Explain the supplied entity history in concise, plain language.
The local ledger projection is the only source of confirmed facts.
Describe the lifecycle in chronological order, current meaning, and any visible inconsistency.
Explicitly distinguish confirmed facts from inference. If evidence is insufficient, say so.
Do not request or infer seeds, private keys, credentials, raw payloads, or repository access.
Your answer is advisory only and cannot change Capsule state.
''';
}
