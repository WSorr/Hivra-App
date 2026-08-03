import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';
import 'package:hivra_app/services/capsule_history_ai_advisor_service.dart';
import 'package:hivra_app/services/capsule_history_projection_service.dart';

void main() {
  test(
    'advisor sends redacted scoped history through Capsule AI Runtime',
    () async {
      final runtime = _RecordingRuntime();
      final service = CapsuleHistoryAiAdvisorService(runtime: runtime);

      final result = await service.explain(_projection);

      expect(result.text, 'Explained');
      expect(result.providerLabel, 'Gemini');
      expect(
        runtime.request!.capabilityId,
        CapsuleHistoryAiAdvisorService.capabilityId,
      );
      expect(
        runtime.request!.proposalSchemaId,
        CapsuleHistoryAiAdvisorService.proposalSchemaId,
      );
      expect(
        runtime.request!.inputJson,
        contains('scoped_capsule_history_explanation'),
      );
      expect(runtime.request!.inputJson, contains('StarterCreated'));
      expect(
        runtime.request!.inputJson,
        isNot(contains('private-full-starter-id')),
      );
      expect(runtime.request!.inputJson, contains('raw_payload_included'));
    },
  );

  test(
    'advisor delegates explicit session unlock to Capsule AI Runtime',
    () async {
      final runtime = _RecordingRuntime();
      final service = CapsuleHistoryAiAdvisorService(runtime: runtime);

      await service.unlockSession();

      expect(runtime.unlockCount, 1);
    },
  );
}

const _projection = CapsuleHistoryProjection(
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

class _RecordingRuntime implements CapsuleInferenceRuntime {
  CapsuleInferenceRequestV1? request;
  int unlockCount = 0;

  @override
  String requireActiveCapsuleRootHex() =>
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  @override
  Future<void> unlockPreferredProviderSession() async {
    unlockCount += 1;
  }

  @override
  Future<CapsuleInferenceResultV1> infer(
    CapsuleInferenceRequestV1 request,
  ) async {
    this.request = request;
    return CapsuleInferenceResultV1(
      requestId: request.requestId,
      capsuleRootHex: request.capsuleRootHex,
      capabilityId: request.capabilityId,
      disclosureHashHex: request.disclosureHashHex,
      proposalSchemaId: request.proposalSchemaId,
      proposalSchemaVersion: request.proposalSchemaVersion,
      proposalText: 'Explained',
      providerId: 'gemini',
      providerLabel: 'Gemini',
      model: 'gemini-test',
      responseHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      elapsedMilliseconds: 1,
    );
  }
}
