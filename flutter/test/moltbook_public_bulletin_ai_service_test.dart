import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';
import 'package:hivra_app/services/moltbook_public_bulletin_ai_service.dart';

void main() {
  test('proposes bounded reviewed prose from explicit public notes only', () async {
    final adapter = _RecordingAdapter(
      responseText:
          '{"title":"Bounded Moltbook review lands in Hivra",'
          '"body":"Hivra now reviews bounded Moltbook conversations and keeps engagement planning separate from publication.",'
          '"supporting_facts":["Hivra added bounded Moltbook conversation review.",'
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
    expect(proposal.title, 'Bounded Moltbook review lands in Hivra');
    expect(proposal.body, contains('separate from publication'));
    expect(proposal.providerLabel, 'Gemini');
    expect(adapter.prompt!.inputJson, contains('source_notes'));
    expect(adapter.prompt!.inputJson, contains('no_ledger_access'));
    expect(
      adapter.prompt!.inputJson,
      contains(MoltbookPublicBulletinAiService.canonicalProductAnchor),
    );
    expect(
      adapter.prompt!.inputJson,
      contains('content_only_from_source_notes_and_canonical_anchor'),
    );
    expect(adapter.prompt!.inputJson, isNot(contains('capsule_seed')));
  });

  test('rejects positioning that contradicts Capsule-first axis', () async {
    final service = MoltbookPublicBulletinAiService(
      credentialStore: _FakeCredentialStore(),
      adapterFactory:
          (_) => _RecordingAdapter(
            responseText:
                '{"title":"Hivra concept",'
                '"body":"Hivra is a relationship-first concept system for coordinated value.",'
                '"supporting_facts":["A source note."]}',
          ),
    );

    await expectLater(
      service.propose(
        sourceNotes: 'A source note.',
        category: 'hivra-development',
        personaSummary: 'Explain facts.',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Capsule-first product axis'),
        ),
      ),
    );
  });

  test(
    'rejects provider output with fields beyond the bulletin contract',
    () async {
      final service = MoltbookPublicBulletinAiService(
        credentialStore: _FakeCredentialStore(),
        adapterFactory:
            (_) => _RecordingAdapter(
              responseText:
                  '{"title":"One change","body":"One public fact.",'
                  '"supporting_facts":["One public fact."],"publish_allowed":true}',
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
    },
  );

  test(
    'fails before inference when preferred provider key is missing',
    () async {
      var adapterRequested = false;
      final service = MoltbookPublicBulletinAiService(
        credentialStore: _FakeCredentialStore(apiKey: null),
        adapterFactory: (_) {
          adapterRequested = true;
          return _RecordingAdapter(
            responseText:
                '{"title":"One change","body":"One public fact.",'
                '"supporting_facts":["One public fact."]}',
          );
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
