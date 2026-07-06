import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_developer_engineer_service.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/ai_doctor_prompt_service.dart';
import 'package:hivra_app/services/ai_doctor_provider_adapter.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }
}

class _FakeProvider implements AiDoctorProviderAdapter {
  AiDoctorPrompt? lastPrompt;

  @override
  Future<AiDoctorProviderResponse> ask({
    required String apiKey,
    required String model,
    required AiDoctorPrompt prompt,
  }) async {
    lastPrompt = prompt;
    return AiDoctorProviderResponse(
      text: 'Finding: inspect invitation projection tests.',
      model: model,
    );
  }
}

class _ThrowingProvider implements AiDoctorProviderAdapter {
  @override
  Future<AiDoctorProviderResponse> ask({
    required String apiKey,
    required String model,
    required AiDoctorPrompt prompt,
  }) async {
    throw StateError('provider failed');
  }
}

void main() {
  group('AiDeveloperEngineerService', () {
    test('builds advisory payload from selected context only', () async {
      final secureStorage = _FakeSecureStorage();
      final credentialStore =
          AiDoctorCredentialStore(secureStorage: secureStorage);
      await credentialStore.saveOpenAiApiKey('sk-test');
      final provider = _FakeProvider();
      final service = AiDeveloperEngineerService(
        credentialStore: credentialStore,
        providerAdapter: provider,
      );

      final result = await service.ask(
        snapshot: _snapshot(),
        selectedContext: _selectedContext(),
        question: 'Where should I look?',
      );

      expect(result.preview.snippetCount, 1);
      expect(result.providerResponse.text, contains('Finding'));
      final input = provider.lastPrompt!.inputJson;
      expect(input, contains('hivra_engineer_advisory_ask'));
      expect(input, contains('no_file_writes'));
      expect(input, contains('selected_context_only'));
      expect(input, contains('lib/services/demo.dart'));
      expect(input, isNot(contains('capsule_seeds.json')));
    });

    test('rejects empty selected context', () {
      final service = AiDeveloperEngineerService(
        credentialStore: AiDoctorCredentialStore(
          secureStorage: _FakeSecureStorage(),
        ),
        providerAdapter: _FakeProvider(),
      );

      expect(
        () => service.preview(
          snapshot: _snapshot(),
          selectedContext: const AiDeveloperWorkspaceSelectedContext(
            schemaVersion: 1,
            snippets: <AiDeveloperWorkspaceSnippet>[],
            findings: <AiDeveloperWorkspaceFinding>[],
            contextHashHex: 'empty',
          ),
          question: 'check',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('provider failure leaves caller with error only', () async {
      final secureStorage = _FakeSecureStorage();
      final credentialStore =
          AiDoctorCredentialStore(secureStorage: secureStorage);
      await credentialStore.saveOpenAiApiKey('sk-test');
      final service = AiDeveloperEngineerService(
        credentialStore: credentialStore,
        providerAdapter: _ThrowingProvider(),
      );

      await expectLater(
        service.ask(
          snapshot: _snapshot(),
          selectedContext: _selectedContext(),
          question: 'check',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

AiDeveloperWorkspaceSelectedContext _selectedContext() {
  return const AiDeveloperWorkspaceSelectedContext(
    schemaVersion: 1,
    snippets: <AiDeveloperWorkspaceSnippet>[
      AiDeveloperWorkspaceSnippet(
        rootPath: '/repo',
        relativePath: 'lib/services/demo.dart',
        sizeBytes: 12,
        sha256Hex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        text: 'void demo() {}',
      ),
    ],
    findings: <AiDeveloperWorkspaceFinding>[
      AiDeveloperWorkspaceFinding(
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
    mode: 'capsule_doctor_local',
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
