import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';
import 'package:hivra_app/services/moltbook_public_bulletin_ai_service.dart';

void main() {
  test('proposes bounded facts from explicit public notes only', () async {
    final adapter = _RecordingAdapter(
      responseText:
          '{"facts":["Hivra added bounded Moltbook conversation review.",'
          '"Engagement planning cannot publish external content."]}',
    );
    final service = MoltbookPublicBulletinAiService(
      credentialStore: _FakeCredentialStore(),
      adapterFactory: (_) => adapter,
    );

    final proposal = await service.propose(
      sourceNotes:
          'Added bounded conversation review. Engagement planner has no publish capability.',
      category: 'hivra-development',
      personaSummary: 'Explain Hivra development factually.',
    );

    expect(proposal.facts, hasLength(2));
    expect(proposal.providerLabel, 'Gemini');
    expect(adapter.prompt!.inputJson, contains('source_notes'));
    expect(adapter.prompt!.inputJson, contains('no_ledger_access'));
    expect(adapter.prompt!.inputJson, isNot(contains('capsule_seed')));
    expect(adapter.prompt!.inputJson, isNot(contains('relationship')));
  });

  test('rejects provider output with fields beyond facts', () async {
    final service = MoltbookPublicBulletinAiService(
      credentialStore: _FakeCredentialStore(),
      adapterFactory:
          (_) => _RecordingAdapter(
            responseText: '{"facts":["One fact."],"publish_allowed":true}',
          ),
    );

    expect(
      () => service.propose(
        sourceNotes: 'One public fact.',
        category: 'hivra-development',
        personaSummary: 'Explain facts.',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'fails before inference when preferred provider key is missing',
    () async {
      var adapterRequested = false;
      final service = MoltbookPublicBulletinAiService(
        credentialStore: _FakeCredentialStore(apiKey: null),
        adapterFactory: (_) {
          adapterRequested = true;
          return _RecordingAdapter(responseText: '{"facts":["One fact."]}');
        },
      );

      await expectLater(
        service.propose(
          sourceNotes: 'One public fact.',
          category: 'hivra-development',
          personaSummary: 'Explain facts.',
        ),
        throwsA(isA<StateError>()),
      );
      expect(adapterRequested, isFalse);
    },
  );
}

class _FakeCredentialStore extends AiDoctorCredentialStore {
  final String? apiKey;

  _FakeCredentialStore({this.apiKey = 'gemini-key'});

  @override
  Future<InferenceProviderKind?> loadPreferredProvider() async =>
      InferenceProviderKind.gemini;

  @override
  Future<String?> loadApiKey(InferenceProviderKind provider) async => apiKey;

  @override
  Future<String?> loadBaseUrl(InferenceProviderKind provider) async => null;
}

class _RecordingAdapter implements InferenceProviderAdapter {
  final String responseText;
  InferencePrompt? prompt;

  _RecordingAdapter({required this.responseText});

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
    return InferenceProviderResponse(
      text: responseText,
      model: 'gemini-test',
      provider: provider,
    );
  }
}
