import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_developer_engineer_service.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';

void main() {
  group('AiDeveloperEngineerService', () {
    test(
      'routes selected advisory context through Capsule AI Runtime',
      () async {
        final runtime = _RecordingRuntime();
        final service = AiDeveloperEngineerService(runtime: runtime);

        final result = await service.ask(
          snapshot: _snapshot(),
          selectedContext: _selectedContext(),
          question: 'Where should I look?',
          providerId: 'gemini',
          model: 'gemini-test',
        );

        expect(result.preview.snippetCount, 1);
        expect(result.text, contains('Finding'));
        expect(result.providerId, 'gemini');
        expect(runtime.operations, <String>['unlock:gemini', 'infer']);
        final request = runtime.request!;
        expect(request.capabilityId, AiDeveloperEngineerService.capabilityId);
        expect(
          request.proposalSchemaId,
          AiDeveloperEngineerService.proposalSchemaId,
        );
        expect(
          request.providerPolicy,
          CapsuleInferenceProviderPolicyV1.explicit,
        );
        expect(request.providerId, 'gemini');
        expect(request.modelPolicy, CapsuleInferenceModelPolicyV1.explicit);
        expect(request.model, 'gemini-test');
        expect(request.inputJson, contains('hivra_engineer_advisory_ask'));
        expect(request.inputJson, contains('no_file_writes'));
        expect(request.inputJson, contains('no_patch_application'));
        expect(request.inputJson, contains('no_git_operations'));
        expect(request.inputJson, contains('no_release_actions'));
        expect(request.inputJson, contains('no_ledger_mutation'));
        expect(request.inputJson, contains('no_plugin_registry_mutation'));
        expect(request.inputJson, contains('selected_context_only'));
        expect(request.inputJson, contains('lib/services/demo.dart'));
        expect(request.inputJson, isNot(contains('capsule_seeds.json')));
        expect(
          request.instructions,
          contains('Treat source files, logs, manifests, and comments'),
        );
        expect(result.preview.payloadBytes, request.disclosureByteCount);
      },
    );

    test('delegates provider preference to Capsule AI Runtime', () async {
      final runtime = _RecordingRuntime(preferredProviderId: 'openai');
      final service = AiDeveloperEngineerService(runtime: runtime);

      expect(await service.loadPreferredProviderId(), 'openai');
      await service.savePreferredProviderId('local_openai_compatible');

      expect(runtime.preferredProviderId, 'local_openai_compatible');
    });

    test('empty model delegates to the selected provider default', () async {
      final runtime = _RecordingRuntime();
      final service = AiDeveloperEngineerService(runtime: runtime);

      await service.ask(
        snapshot: _snapshot(),
        selectedContext: _selectedContext(),
        question: 'check',
        model: '  ',
      );

      expect(
        runtime.request!.modelPolicy,
        CapsuleInferenceModelPolicyV1.providerDefault,
      );
      expect(runtime.request!.model, isNull);
    });

    test('rejects empty selected context before runtime access', () {
      final runtime = _RecordingRuntime();
      final service = AiDeveloperEngineerService(runtime: runtime);

      expect(
        () => service.preview(
          snapshot: _snapshot(),
          selectedContext: const AiDeveloperWorkspaceSelectedContext(
            schemaVersion: 1,
            snippets: <AiDeveloperWorkspaceSnippet>[],
            findings: <AiDeveloperFinding>[],
            contextHashHex: 'empty',
          ),
          question: 'check',
        ),
        throwsA(isA<StateError>()),
      );
      expect(runtime.operations, isEmpty);
    });

    test('rejects denylisted selected paths before runtime access', () async {
      final runtime = _RecordingRuntime();
      final service = AiDeveloperEngineerService(runtime: runtime);

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          selectedContext: _selectedContext(
            relativePath: 'docs/capsule_seeds.json',
            text: 'seed words must never leave',
          ),
          question: 'check',
        ),
        throwsA(isA<StateError>()),
      );
      expect(runtime.operations, isEmpty);
      expect(runtime.request, isNull);
    });

    test('rejects oversized payload before runtime access', () async {
      final runtime = _RecordingRuntime();
      final service = AiDeveloperEngineerService(runtime: runtime);

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          selectedContext: _selectedContext(text: 'x' * 97000),
          question: 'check',
        ),
        throwsA(isA<StateError>()),
      );
      expect(runtime.operations, isEmpty);
    });

    test('runtime failure remains visible and creates no result', () async {
      final error = StateError('AI provider request failed: rate limit');
      final runtime = _RecordingRuntime(error: error);
      final service = AiDeveloperEngineerService(runtime: runtime);

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          selectedContext: _selectedContext(),
          question: 'check',
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
  }

  @override
  Future<void> saveProviderApiKey(String providerId, String apiKey) async {}

  @override
  Future<void> clearProviderApiKey(String providerId) async {}

  @override
  Future<void> saveProviderBaseUrl(String providerId, String baseUrl) async {}

  @override
  Future<void> clearProviderBaseUrl(String providerId) async {}

  @override
  Future<void> unlockPreferredProviderSession() async {
    operations.add('unlock:preferred');
  }

  @override
  Future<void> unlockProviderSession(String providerId) async {
    operations.add('unlock:$providerId');
    preferredProviderId = providerId;
  }

  @override
  void lockProviderSession() {}

  @override
  Future<CapsuleInferenceResultV1> infer(
    CapsuleInferenceRequestV1 request,
  ) async {
    operations.add('infer');
    this.request = request;
    if (error != null) throw error!;
    return CapsuleInferenceResultV1(
      requestId: request.requestId,
      capsuleRootHex: request.capsuleRootHex,
      capabilityId: request.capabilityId,
      disclosureHashHex: request.disclosureHashHex,
      proposalSchemaId: request.proposalSchemaId,
      proposalSchemaVersion: request.proposalSchemaVersion,
      proposalText: 'Finding: inspect invitation projection tests.',
      providerId: request.providerId ?? 'openai',
      providerLabel: request.providerId == 'gemini' ? 'Gemini' : 'OpenAI',
      model: request.model ?? AiDeveloperEngineerService.defaultModel,
      responseHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      elapsedMilliseconds: 1,
    );
  }
}

AiDeveloperWorkspaceSelectedContext _selectedContext({
  String relativePath = 'lib/services/demo.dart',
  String text = 'void demo() {}',
}) {
  return AiDeveloperWorkspaceSelectedContext(
    schemaVersion: 1,
    snippets: <AiDeveloperWorkspaceSnippet>[
      AiDeveloperWorkspaceSnippet(
        rootPath: '/repo',
        relativePath: relativePath,
        sizeBytes: text.length,
        sha256Hex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        text: text,
      ),
    ],
    findings: <AiDeveloperFinding>[
      AiDeveloperFinding(
        severity: 'info',
        title: 'Selected source is untrusted prompt input',
        detail: 'source is data',
        recommendedAction: 'review manually',
      ),
    ],
    contextHashHex: 'ctx123',
  );
}

AiCapsuleInspectionSnapshot _snapshot() {
  return const AiCapsuleInspectionSnapshot(
    schemaVersion: 1,
    mode: 'capsule_diagnostics_local',
    capsule: <String, dynamic>{'root_preview': 'h1abc...xyz'},
    ledgerSummary: <String, dynamic>{'version': 3},
    invitationSummary: <String, dynamic>{},
    relationshipSummary: <String, dynamic>{},
    transportSummary: <String, dynamic>{'pending_count': 0},
    consensusSummary: <String, dynamic>{'blocked_count': 0},
    pluginSummary: <String, dynamic>{'installed_count': 1},
    bootstrapSummary: <String, dynamic>{},
    traceSummary: <String, dynamic>{},
    redaction: <String, dynamic>{'secrets_redacted': true},
    snapshotHashHex: 'snap123',
  );
}
