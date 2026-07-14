import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/app_runtime_runtime.dart';
import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/ffi/ledger_view_runtime.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/bingx_futures_execution_command_service.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/capsule_chat_deferred_inbox_store.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/transport_health_policy_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
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

  test('trade signals received by chat remain available to trading drone',
      () async {
    const peerHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const localRootHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final store = CapsuleTradeSignalInboxStore();
    final runtime = _FakeRuntime(
      capsuleRootKey: _hexToBytes(localRootHex),
      workerBootstrap: const <String, Object?>{
        'activeCapsuleHex': localRootHex,
      },
    );
    final checks = _FakeManualConsensusCheckService(
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
    );
    final payloadJson = jsonEncode(<String, Object?>{
      'contract_kind': 'bingx_trade_signal_v1',
      'signal_id': 'sig-shared',
      'symbol': 'BTC-USDT',
      'side': 'buy',
      'order_type': 'limit',
      'quantity_decimal': '0.01',
      'entry_mode': 'zone_pending',
      'intent_hash_hex':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'created_at_utc': '2026-06-13T09:00:00.000Z',
      'canonical_intent_json': '{"symbol":"BTC-USDT"}',
    });
    final chatService = CapsuleChatDeliveryService(
      runtime: runtime,
      manualChecks: checks,
      tradeSignalInboxStore: store,
      receiveWorkerRunner: (_) async => <String, Object?>{
        'result': 1,
        'json': jsonEncode(
          <Map<String, Object?>>[
            <String, Object?>{
              'from_hex': peerHex,
              'payload_json': payloadJson,
              'timestamp_ms': 1,
            },
          ],
        ),
        'lastError': null,
      },
    );
    final droneService = CapsuleChatDeliveryService(
      runtime: runtime,
      manualChecks: checks,
      tradeSignalInboxStore: store,
    );

    final received = await chatService.receiveAndFilter();

    expect(received.tradeSignals, hasLength(1));
    expect(droneService.loadCachedTradeSignals(), hasLength(1));
    expect(
      droneService.loadCachedTradeSignals().single.signalId,
      equals('sig-shared'),
    );
  });

  test('chat receive honors shared transport timeout cooldown', () async {
    const localRootHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    var receiveCalls = 0;
    final health = TransportHealthPolicyService(
      timeoutBackoff: const <Duration>[Duration(minutes: 1)],
    );
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        const <ManualConsensusCheck>[],
      ),
      transportHealth: health,
      receiveWorkerRunner: (_) async {
        receiveCalls += 1;
        return <String, Object?>{
          'result': -1003,
          'json': null,
          'lastError': 'Chat fetch timed out',
        };
      },
    );

    final first = await service.receiveAndFilter();
    final second = await service.receiveAndFilter();

    expect(receiveCalls, 1);
    expect(first.code, -1003);
    expect(second.code, -3101);
    expect(second.errorMessage, contains('cooling down'));
  });

  test(
      'prefers contact-card transport when root also appears as relationship peer',
      () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const peerTransportHex =
        'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    Uint8List? sentToPubkey;

    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        <ManualConsensusCheck>[
          const ManualConsensusCheck(
            peerHex: peerRootHex,
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
      loadRelationships: () => <Relationship>[
        Relationship(
          // Regression shape: a mixed root/transport ledger can expose the
          // root as peerPubkey. Sending must still prefer the contact card
          // transport endpoint for a root-addressed peer.
          peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
          peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
          kind: StarterKind.juice,
          ownStarterId: base64Encode(Uint8List(32)),
          peerStarterId:
              base64Encode(Uint8List.fromList(List<int>.filled(32, 1))),
          establishedAt: DateTime.utc(2026, 6, 28),
        ),
      ],
      listTrustedCards: () async => const <CapsuleAddressCard>[
        CapsuleAddressCard(
          rootKey:
              'h10xg7awf467k73f3nytv45nkw6f0e8nv0xcng3az3x6cmzka6w2cqqgpav3',
          rootHex: peerRootHex,
          nostrNpub:
              'npub15varftzcs832ul4jje75pwfed35kngtwcny7wc5gcettzmv5jcnsysfak5',
          nostrHex: peerTransportHex,
        ),
      ],
      sendWorkerRunner: (args) async {
        sentToPubkey = args['toPubkey'] as Uint8List;
        return <String, Object?>{
          'result': 0,
          'lastError': null,
        };
      },
    );

    final result = await service.sendCanonicalEnvelope(
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"hello"}',
    );

    expect(result.isSuccess, isTrue);
    expect(result.deliveryPeerHex, equals(peerTransportHex));
    expect(_bytesToHex(sentToPubkey!), equals(peerTransportHex));
  });

  test('chat send does not create a hidden second transport attempt', () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const peerTransportHex =
        'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    var sendCalls = 0;
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        <ManualConsensusCheck>[
          const ManualConsensusCheck(
            peerHex: peerRootHex,
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
      listTrustedCards: () async => const <CapsuleAddressCard>[
        CapsuleAddressCard(
          rootKey:
              'h10xg7awf467k73f3nytv45nkw6f0e8nv0xcng3az3x6cmzka6w2cqqgpav3',
          rootHex: peerRootHex,
          nostrNpub:
              'npub15varftzcs832ul4jje75pwfed35kngtwcny7wc5gcettzmv5jcnsysfak5',
          nostrHex: peerTransportHex,
        ),
      ],
      sendWorkerRunner: (_) async {
        sendCalls += 1;
        return <String, Object?>{
          'result': -1003,
          'lastError': 'relay timeout',
        };
      },
    );

    final result = await service.sendCanonicalEnvelope(
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"hello"}',
    );

    expect(result.isSuccess, isFalse);
    expect(result.code, -1003);
    expect(sendCalls, 1);
  });

  test('chat send requires pair attestation when guard is available', () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    var sendCalls = 0;
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        <ManualConsensusCheck>[
          const ManualConsensusCheck(
            peerHex: peerRootHex,
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
      readAttestedSignable: (_) async => const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'pair_attestation_missing'),
        ],
      ),
      sendWorkerRunner: (_) async {
        sendCalls += 1;
        return <String, Object?>{
          'result': 0,
          'lastError': null,
        };
      },
    );

    final result = await service.sendCanonicalEnvelope(
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"hello"}',
    );

    expect(result.isSuccess, isFalse);
    expect(result.blockedByConsensus, isTrue);
    expect(result.code, -2001);
    expect(sendCalls, 0);
  });

  test('chat receive defers messages until pair attestation arrives', () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });
    final deferredStore = CapsuleChatDeferredInboxStore(
      fileStore: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      ),
    );
    final envelope = jsonEncode(<String, Object?>{
      'message_text': 'hello',
      'created_at_utc': '2026-07-14T09:00:00.000Z',
      'envelope_hash_hex':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    });
    final blockedService = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        <ManualConsensusCheck>[
          const ManualConsensusCheck(
            peerHex: peerRootHex,
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
      readAttestedSignable: (_) async => const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'pair_attestation_missing'),
        ],
      ),
      deferredInboxStore: deferredStore,
      transportHealth: TransportHealthPolicyService(
        timeoutBackoff: const <Duration>[Duration(minutes: 1)],
      ),
      receiveWorkerRunner: (_) async => <String, Object?>{
        'result': 0,
        'json': jsonEncode(
          <Map<String, Object?>>[
            <String, Object?>{
              'from_hex': peerRootHex,
              'payload_json': envelope,
              'timestamp_ms': 1,
            },
          ],
        ),
        'lastError': null,
      },
    );

    final blocked = await blockedService.receiveAndFilter();

    expect(blocked.messages, isEmpty);
    expect(blocked.droppedByConsensus, 0);
    expect(blocked.deferredByConsensus, 1);
    expect(await deferredStore.load(localRootHex), hasLength(1));

    final readyService = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(
        <ManualConsensusCheck>[
          const ManualConsensusCheck(
            peerHex: peerRootHex,
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
      readAttestedSignable: (_) async => const ConsensusSignableResult(
        preview: ConsensusPreview(
          peerHex: peerRootHex,
          peerLabel: 'peer',
          invitationCount: 1,
          relationshipCount: 1,
          hashHex:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          canonicalJson: '{}',
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        blockingFacts: <ConsensusBlockingFact>[],
      ),
      deferredInboxStore: deferredStore,
      transportHealth: TransportHealthPolicyService(
        timeoutBackoff: const <Duration>[Duration(minutes: 1)],
      ),
      receiveWorkerRunner: (_) async => <String, Object?>{
        'result': 0,
        'json': null,
        'lastError': null,
      },
    );

    final ready = await readyService.receiveAndFilter();

    expect(ready.messages, hasLength(1));
    expect(ready.messages.single.messageText, equals('hello'));
    expect(ready.droppedByConsensus, 0);
    expect(ready.deferredByConsensus, 0);
    expect(await deferredStore.load(localRootHex), isEmpty);
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
  @override
  String? signConsensusCommitment(String commitmentHashHex) => null;

  final Uint8List? capsuleRootKey;
  final Map<String, Object?> workerBootstrap;

  _FakeRuntime({
    required this.capsuleRootKey,
    this.workerBootstrap = const <String, Object?>{},
  });

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
  String? invokeWasmJson({
    required Uint8List moduleBytes,
    required String entryExport,
    required Uint8List inputJsonBytes,
  }) =>
      null;

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
  int expireInvitationCode(Uint8List invitationId) => -1;

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

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
