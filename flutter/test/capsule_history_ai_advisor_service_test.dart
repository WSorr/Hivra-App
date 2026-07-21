import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/capsule_history_ai_advisor_service.dart';
import 'package:hivra_app/services/capsule_history_projection_service.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

void main() {
  test(
    'advisor sends redacted scoped history through preferred provider',
    () async {
      final adapter = _RecordingAdapter();
      final service = CapsuleHistoryAiAdvisorService(
        credentialStore: _FakeCredentialStore(),
        adapterFactory: (_) => adapter,
      );
      const projection = CapsuleHistoryProjection(
        schemaVersion: 1,
        subject: CapsuleHistorySubject.starter(
          starterId: 'private-full-starter-id',
          displayLabel: 'Juice · Slot 1',
        ),
        entries: <CapsuleHistoryEntry>[
          CapsuleHistoryEntry(
            ledgerIndex: 4,
            eventKind: 'StarterCreated',
            timestamp: 100,
            timeLabel: 'Ledger step 100',
            summary: 'Starter abc...xyz created (Juice).',
          ),
        ],
        projectionHashHex: 'hash',
      );

      final result = await service.explain(projection);

      expect(result.text, 'Explained');
      expect(
        adapter.prompt!.inputJson,
        contains('scoped_capsule_history_explanation'),
      );
      expect(adapter.prompt!.inputJson, contains('StarterCreated'));
      expect(
        adapter.prompt!.inputJson,
        isNot(contains('private-full-starter-id')),
      );
      expect(adapter.prompt!.inputJson, contains('raw_payload_included'));
    },
  );
}

class _FakeCredentialStore extends AiDoctorCredentialStore {
  @override
  Future<InferenceProviderKind?> loadPreferredProvider() async =>
      InferenceProviderKind.gemini;

  @override
  Future<String?> loadApiKey(InferenceProviderKind provider) async => 'key';

  @override
  Future<String?> loadBaseUrl(InferenceProviderKind provider) async => null;
}

class _RecordingAdapter implements InferenceProviderAdapter {
  InferencePrompt? prompt;

  @override
  InferenceProviderKind get provider => InferenceProviderKind.gemini;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    this.prompt = prompt;
    return const InferenceProviderResponse(
      text: 'Explained',
      model: 'gemini-test',
      provider: InferenceProviderKind.gemini,
    );
  }
}
