import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_doctor_chat_service.dart';
import 'package:hivra_app/services/ai_doctor_prompt_service.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';

void main() {
  group('AiDoctorChatService', () {
    test(
      'routes selected redacted disclosure through Capsule AI Runtime',
      () async {
        final runtime = _RecordingRuntime();
        final service = AiDoctorChatService(runtime: runtime);

        final result = await service.ask(
          snapshot: _snapshot(),
          userQuery: 'Why is consensus blocked?',
          sections: const <AiDoctorContextSection>[
            AiDoctorContextSection.transport,
            AiDoctorContextSection.consensus,
          ],
          providerId: 'gemini',
          model: 'gemini-test',
        );

        expect(result.text, contains('Finding'));
        expect(result.providerId, 'gemini');
        expect(runtime.operations, <String>['unlock:gemini', 'infer']);
        final request = runtime.request!;
        expect(request.capabilityId, AiDoctorChatService.capabilityId);
        expect(request.proposalSchemaId, AiDoctorChatService.proposalSchemaId);
        expect(
          request.providerPolicy,
          CapsuleInferenceProviderPolicyV1.explicit,
        );
        expect(request.providerId, 'gemini');
        expect(request.modelPolicy, CapsuleInferenceModelPolicyV1.explicit);
        expect(request.model, 'gemini-test');
        expect(request.disclosedSectionIds, <String>[
          'consensus_summary',
          'transport_summary',
          'user_query',
        ]);
        expect(request.inputJson, contains('scoped_ai_capsule_analyst_chat'));
        expect(request.inputJson, contains('transport_summary'));
        expect(request.inputJson, contains('consensus_summary'));
        expect(request.inputJson, isNot(contains('ledger_summary')));
        expect(request.inputJson, isNot(contains('seed phrase')));
        expect(result.preview.payloadBytes, request.disclosureByteCount);
        expect(result.preview.secretsRedacted, isTrue);
      },
    );

    test(
      'delegates provider configuration only to Capsule AI Runtime',
      () async {
        final runtime = _RecordingRuntime(preferredProviderId: 'openai');
        final service = AiDoctorChatService(runtime: runtime);

        expect(await service.loadPreferredProviderId(), 'openai');
        await service.savePreferredProviderId('gemini');
        await service.saveProviderApiKey('gemini', 'secret');
        await service.saveProviderBaseUrl(
          'local_openai_compatible',
          'http://127.0.0.1:11434',
        );
        await service.clearProviderApiKey('gemini');
        await service.clearProviderBaseUrl('local_openai_compatible');

        expect(runtime.configuration, <String>[
          'preferred:gemini',
          'save-key:gemini:secret',
          'save-url:local_openai_compatible:http://127.0.0.1:11434',
          'clear-key:gemini',
          'clear-url:local_openai_compatible',
        ]);
      },
    );

    test('empty model delegates to the selected provider default', () async {
      final runtime = _RecordingRuntime();
      final service = AiDoctorChatService(runtime: runtime);

      await service.ask(
        snapshot: _snapshot(),
        userQuery: 'check',
        sections: const <AiDoctorContextSection>[AiDoctorContextSection.ledger],
        model: ' ',
      );

      expect(
        runtime.request!.modelPolicy,
        CapsuleInferenceModelPolicyV1.providerDefault,
      );
      expect(runtime.request!.model, isNull);
    });

    test('invalid disclosure fails before credential unlock', () async {
      final runtime = _RecordingRuntime();
      final service = AiDoctorChatService(runtime: runtime);

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          userQuery: ' ',
          sections: const <AiDoctorContextSection>[
            AiDoctorContextSection.ledger,
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(runtime.operations, isEmpty);
      expect(runtime.request, isNull);
    });

    test('runtime failure remains visible and creates no fallback', () async {
      final error = StateError('AI provider request failed: rate limit');
      final runtime = _RecordingRuntime(error: error);
      final service = AiDoctorChatService(runtime: runtime);

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          userQuery: 'check',
          sections: const <AiDoctorContextSection>[
            AiDoctorContextSection.ledger,
          ],
        ),
        throwsA(same(error)),
      );
      expect(runtime.operations, <String>['unlock:openai', 'infer']);
    });
  });
}

const _capsuleRoot =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _RecordingRuntime implements CapsuleInferenceRuntime {
  String? preferredProviderId;
  final Object? error;
  final List<String> operations = <String>[];
  final List<String> configuration = <String>[];
  CapsuleInferenceRequestV1? request;

  @override
  bool get isProviderSessionUnlocked => true;

  @override
  String? get sessionProviderLabel => 'OpenAI';

  _RecordingRuntime({this.preferredProviderId, this.error});

  @override
  String requireActiveCapsuleRootHex() => _capsuleRoot;

  @override
  Future<String?> loadPreferredProviderId() async => preferredProviderId;

  @override
  Future<void> savePreferredProviderId(String providerId) async {
    preferredProviderId = providerId;
    configuration.add('preferred:$providerId');
  }

  @override
  Future<void> saveProviderApiKey(String providerId, String apiKey) async {
    configuration.add('save-key:$providerId:$apiKey');
  }

  @override
  Future<void> clearProviderApiKey(String providerId) async {
    configuration.add('clear-key:$providerId');
  }

  @override
  Future<void> saveProviderBaseUrl(String providerId, String baseUrl) async {
    configuration.add('save-url:$providerId:$baseUrl');
  }

  @override
  Future<void> clearProviderBaseUrl(String providerId) async {
    configuration.add('clear-url:$providerId');
  }

  @override
  Future<void> unlockPreferredProviderSession() async {
    operations.add('unlock:preferred');
  }

  @override
  Future<void> unlockProviderSession(String providerId) async {
    preferredProviderId = providerId;
    operations.add('unlock:$providerId');
  }

  @override
  void lockProviderSession() {}

  @override
  Future<CapsuleInferenceResultV1> infer(
    CapsuleInferenceRequestV1 request,
  ) async {
    this.request = request;
    operations.add('infer');
    if (error != null) throw error!;
    return CapsuleInferenceResultV1(
      requestId: request.requestId,
      capsuleRootHex: request.capsuleRootHex,
      capabilityId: request.capabilityId,
      disclosureHashHex: request.disclosureHashHex,
      proposalSchemaId: request.proposalSchemaId,
      proposalSchemaVersion: request.proposalSchemaVersion,
      proposalText: 'Finding: inspect local consensus evidence.',
      providerId: request.providerId ?? 'openai',
      providerLabel: request.providerId == 'gemini' ? 'Gemini' : 'OpenAI',
      model: request.model ?? AiDoctorChatService.defaultModel,
      responseHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      elapsedMilliseconds: 1,
    );
  }
}

AiCapsuleInspectionSnapshot _snapshot() {
  return const AiCapsuleInspectionSnapshot(
    schemaVersion: 1,
    mode: 'capsule_diagnostics_local',
    capsule: <String, dynamic>{'root_preview': 'h1abc...xyz'},
    ledgerSummary: <String, dynamic>{'version': 7},
    invitationSummary: <String, dynamic>{'pending_total': 0},
    relationshipSummary: <String, dynamic>{'active_peer_group_count': 1},
    transportSummary: <String, dynamic>{'pending_count': 2},
    consensusSummary: <String, dynamic>{'blocked_count': 1},
    pluginSummary: <String, dynamic>{'installed_count': 1},
    bootstrapSummary: <String, dynamic>{'issue': 'none'},
    traceSummary: <String, dynamic>{'issue_count': 0},
    redaction: <String, dynamic>{
      'secrets_redacted': true,
      'raw_seed_included': false,
      'private_keys_included': false,
    },
    snapshotHashHex: 'abc123',
  );
}
