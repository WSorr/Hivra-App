import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/app_runtime_runtime.dart';
import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/ffi/ledger_view_runtime.dart';
import 'package:hivra_app/services/bingx_futures_execution_command_service.dart';
import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';

void main() {
  group('chatSendShouldRetry', () {
    test('retries for transient timeout/transport codes', () {
      expect(chatSendShouldRetry(code: -1003), isTrue);
      expect(chatSendShouldRetry(code: -11), isTrue);
      expect(chatSendShouldRetry(code: -12), isTrue);
      expect(chatSendShouldRetry(code: -13), isTrue);
      expect(chatSendShouldRetry(code: -6), isTrue);
    });

    test('retries when error message signals transient relay issues', () {
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'relay connection dropped',
        ),
        isTrue,
      );
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'timed out while publishing',
        ),
        isTrue,
      );
    });

    test('does not retry deterministic validation failures', () {
      expect(
        chatSendShouldRetry(
          code: -1,
          errorMessage: 'peer_hex must be a 64-char lowercase hex',
        ),
        isFalse,
      );
    });
  });

  group('tradeSignalInboxRecordId', () {
    test('separates same signal_id from different peers', () {
      const signalId = 'sig-123';
      final a = tradeSignalInboxRecordId(
        fromHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        signalId: signalId,
        timestampMs: 1,
        payloadJson: '{"x":1}',
      );
      final b = tradeSignalInboxRecordId(
        fromHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        signalId: signalId,
        timestampMs: 1,
        payloadJson: '{"x":1}',
      );

      expect(a, isNot(equals(b)));
    });

    test('keeps stable id for same peer and same signal_id', () {
      const fromHex =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const signalId = 'sig-123';
      final first = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: signalId,
        timestampMs: 11,
        payloadJson: '{"x":1}',
      );
      final second = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: signalId,
        timestampMs: 12,
        payloadJson: '{"x":2}',
      );

      expect(first, equals(second));
    });

    test('falls back to deterministic hash when signal_id is empty', () {
      const fromHex =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final first = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 10,
        payloadJson: '{"a":1}',
      );
      final second = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 10,
        payloadJson: '{"a":1}',
      );
      final third = tradeSignalInboxRecordId(
        fromHex: fromHex,
        signalId: '',
        timestampMs: 11,
        payloadJson: '{"a":1}',
      );

      expect(first, equals(second));
      expect(first, isNot(equals(third)));
    });
  });

  group('CapsuleChatDeliveryService execution command flow', () {
    const peerHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const localRootHex =
        '2222222222222222222222222222222222222222222222222222222222222222';

    test(
        'evaluates incoming futures execution command and emits receipt decision',
        () async {
      final replayStore = InMemoryBingxExecutionCommandReplayStore();
      final commandService =
          BingxFuturesExecutionCommandService(replayStore: replayStore);
      final commandEnvelope = commandService.buildCommandEnvelope(
        commandId: 'cmd-1',
        intentHashHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        symbol: 'BTCUSDT',
        side: 'buy',
        quantityDecimal: '0.1',
        entryPriceDecimal: '65000',
        stopLossDecimal: '64000',
        takeProfitDecimal: '68000',
        leverageDecimal: '3',
        riskPercentDecimal: '1.5',
        createdAtUtc: DateTime.utc(2026, 4, 25, 12, 0, 0).toIso8601String(),
        expiresAtUtc: DateTime.utc(2026, 4, 25, 12, 5, 0).toIso8601String(),
        targetCapsuleRootHex: localRootHex,
      );

      final service = CapsuleChatDeliveryService(
        runtime: _FakeRuntime(
          capsuleRootKey: _hexToBytes(localRootHex),
        ),
        manualChecks: _FakeManualConsensusCheckService(
          <ManualConsensusCheck>[
            const ManualConsensusCheck(
              peerHex: peerHex,
              peerLabel: 'peer',
              invitationCount: 1,
              relationshipCount: 1,
              hashHex:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              canonicalJson: '{}',
              isSignable: true,
              blockingFacts: <ConsensusBlockingFact>[],
            ),
          ],
        ),
        executionCommandService: commandService,
        executionPolicyForPeer: (_) => const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTCUSDT'},
          maxLeverage: 5,
          maxRiskPercent: 2,
        ),
        nowUtc: () => DateTime.utc(2026, 4, 25, 12, 1, 0),
        receiveWorkerRunner: (_) async => <String, Object?>{
          'result': 0,
          'json': jsonEncode(
            <Map<String, Object?>>[
              <String, Object?>{
                'from_hex': peerHex,
                'payload_json': commandEnvelope,
                'timestamp_ms': 1,
              },
            ],
          ),
          'lastError': null,
        },
      );

      final result = await service.receiveAndFilter();

      expect(result.code, equals(0));
      expect(result.messages, isEmpty);
      expect(result.tradeSignals, isEmpty);
      expect(result.executionReceipts, isEmpty);
      expect(result.executionDecisions, hasLength(1));
      expect(result.executionDecisions.single.commandId, equals('cmd-1'));
      expect(result.executionDecisions.single.decision, equals('accepted'));
      expect(result.executionDecisions.single.decisionCode,
          equals('accepted_for_execution'));
      expect(
          result.executionDecisions.single.receiptDeliveryCode, equals(-2003));
    });

    test('parses incoming execution receipt envelope', () async {
      final payloadJson = jsonEncode(<String, Object?>{
        'schema_version': 1,
        'receipt_kind': 'futures_execution_receipt_v1',
        'command_id': 'cmd-9',
        'intent_hash_hex':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'decision': 'rejected',
        'decision_code': 'policy_symbol_blocked',
        'decision_message': 'Symbol is not allowed by local policy',
        'target_capsule_root_hex': localRootHex,
        'peer_hex': peerHex,
        'receipt_created_at_utc':
            DateTime.utc(2026, 4, 25, 12, 2, 0).toIso8601String(),
      });

      final service = CapsuleChatDeliveryService(
        runtime: _FakeRuntime(
          capsuleRootKey: _hexToBytes(localRootHex),
        ),
        manualChecks: _FakeManualConsensusCheckService(
          <ManualConsensusCheck>[
            const ManualConsensusCheck(
              peerHex: peerHex,
              peerLabel: 'peer',
              invitationCount: 1,
              relationshipCount: 1,
              hashHex:
                  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              canonicalJson: '{}',
              isSignable: true,
              blockingFacts: <ConsensusBlockingFact>[],
            ),
          ],
        ),
        receiveWorkerRunner: (_) async => <String, Object?>{
          'result': 0,
          'json': jsonEncode(
            <Map<String, Object?>>[
              <String, Object?>{
                'from_hex': peerHex,
                'payload_json': payloadJson,
                'timestamp_ms': 99,
              },
            ],
          ),
          'lastError': null,
        },
      );

      final result = await service.receiveAndFilter();

      expect(result.code, equals(0));
      expect(result.executionDecisions, isEmpty);
      expect(result.executionReceipts, hasLength(1));
      expect(result.executionReceipts.single.commandId, equals('cmd-9'));
      expect(result.executionReceipts.single.decision, equals('rejected'));
      expect(result.executionReceipts.single.decisionCode,
          equals('policy_symbol_blocked'));
    });
  });
}

class _FakeManualConsensusCheckService extends ManualConsensusCheckService {
  final List<ManualConsensusCheck> _checks;

  _FakeManualConsensusCheckService(this._checks)
      : super(
          consensus: const ConsensusRuntimeService(
            exportLedger: _nullLedgerExport,
            readLocalTransportKey: _nullTransportKey,
          ),
        );

  @override
  List<ManualConsensusCheck> loadChecks() =>
      List<ManualConsensusCheck>.unmodifiable(_checks);
}

class _FakeRuntime implements AppRuntimeRuntime {
  final Uint8List? capsuleRootKey;
  final Map<String, Object?> workerBootstrap = const <String, Object?>{};

  _FakeRuntime({required this.capsuleRootKey});

  @override
  LedgerViewRuntime get ledgerViewRuntime => const _FakeLedgerViewRuntime();

  @override
  InvitationActionsRuntime get invitationActionsRuntime =>
      const _FakeInvitationActionsRuntime();

  @override
  CapsuleAddressRuntime get capsuleAddressRuntime =>
      const _FakeCapsuleAddressRuntime();

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() async => true;

  @override
  Future<void> persistLedgerSnapshot() async {}

  @override
  Uint8List? capsuleRootPublicKey() => capsuleRootKey;

  @override
  Uint8List? capsuleNostrPublicKey() => capsuleRootKey;

  @override
  Uint8List? loadSeed() => null;

  @override
  String? exportLedger() => null;

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() async =>
      workerBootstrap;

  @override
  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) {
    return false;
  }

  @override
  Future<CapsuleTraceReport> diagnoseCapsuleTraces() async =>
      CapsuleTraceReport(
        activePubKeyHex: null,
        runtimePubKeyHex: null,
        runtimeSeedExists: false,
        indexHasEntry: false,
        secureSeedExists: false,
        fallbackSeedExists: false,
        capsuleDirPath: '',
        capsuleDirExists: false,
        ledgerFileExists: false,
        stateFileExists: false,
        backupFileExists: false,
        legacyDocsPath: '',
        legacyLedgerExists: false,
        legacyStateExists: false,
        legacyBackupExists: false,
      );

  @override
  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() async =>
      CapsuleBootstrapReport(
        activePubKeyHex: null,
        runtimePubKeyHex: null,
        rootPubKeyHex: null,
        nostrPubKeyHex: null,
        identityMode: 'root_owner',
        bootstrapSource: 'none',
        seedAvailable: false,
        seedMatchesActiveCapsule: false,
        rootMatchesActiveCapsule: false,
        nostrMatchesActiveCapsule: false,
        runtimeMatchesRoot: false,
        runtimeMatchesNostr: false,
        stateFileExists: false,
        ledgerFileExists: false,
        backupFileExists: false,
        workerBootstrapAvailable: false,
        ledgerImportable: false,
        issue: null,
      );

  @override
  bool verifyConsensusSignature({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  }) {
    return false;
  }
}

class _FakeLedgerViewRuntime implements LedgerViewRuntime {
  const _FakeLedgerViewRuntime();

  @override
  String? exportLedger() => null;

  @override
  String? exportCapsuleStateJson() => null;

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() => null;

  @override
  Uint8List? capsuleRuntimeTransportPublicKey() => null;
}

class _FakeInvitationActionsRuntime implements InvitationActionsRuntime {
  const _FakeInvitationActionsRuntime();

  @override
  Future<bool> applyLedgerSnapshotIfNotStale(String ledgerJson) async => false;

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() async => true;

  @override
  bool expireInvitation(Uint8List invitationId) => false;

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs({
    String? capsuleHex,
  }) async =>
      null;

  @override
  Future<bool> persistLedgerSnapshot() async => false;

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  ) async {}

  @override
  Future<String?> resolveActiveCapsuleHex() async => null;
}

class _FakeCapsuleAddressRuntime implements CapsuleAddressRuntime {
  const _FakeCapsuleAddressRuntime();

  @override
  Uint8List? capsuleNostrPublicKey() => null;

  @override
  Uint8List? capsuleRootPublicKey() => null;
}

String? _nullLedgerExport() => null;
Uint8List? _nullTransportKey() => null;

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i += 1) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
