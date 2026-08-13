import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/app_runtime_runtime.dart';
import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/ffi/ledger_view_runtime.dart';
import 'package:hivra_app/models/capsule_chat_models.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/bingx_futures_execution_command_service.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/capsule_chat_deferred_inbox_store.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_delivery_inbox_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/transport_health_policy_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/screens/wasm_plugins_screen.dart';
import 'package:hivra_app/screens/main_screen.dart';
import 'package:flutter/material.dart';

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

  group('Capsule chat conversation timeline', () {
    const capsuleHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const peerHex =
        '2222222222222222222222222222222222222222222222222222222222222222';

    test('classifies timeout as ambiguous instead of delivered', () {
      expect(
        outgoingChatStateForDeliveryCode(0),
        CapsuleChatMessageDeliveryState.transportAccepted,
      );
      expect(
        outgoingChatStateForDeliveryCode(-1003),
        CapsuleChatMessageDeliveryState.ambiguous,
      );
      expect(
        outgoingChatStateForDeliveryCode(-6),
        CapsuleChatMessageDeliveryState.failed,
      );
    });

    test(
      'peer projection includes both directions without cross-peer leak',
      () {
        const otherPeerHex =
            '3333333333333333333333333333333333333333333333333333333333333333';
        const incoming = CapsuleChatInboxMessage(
          id: 'incoming',
          fromHex: peerHex,
          toHex: capsuleHex,
          messageText: 'in',
          createdAtUtc: '2026-08-13T08:00:00.000Z',
          envelopeHashHex: '',
          timestampMs: 1,
        );
        const outgoing = CapsuleChatInboxMessage(
          id: 'outgoing',
          fromHex: capsuleHex,
          toHex: peerHex,
          messageText: 'out',
          createdAtUtc: '2026-08-13T08:00:01.000Z',
          envelopeHashHex: '',
          timestampMs: 2,
          direction: CapsuleChatMessageDirection.outgoing,
          deliveryState: CapsuleChatMessageDeliveryState.transportAccepted,
        );
        const unrelated = CapsuleChatInboxMessage(
          id: 'unrelated',
          fromHex: otherPeerHex,
          toHex: capsuleHex,
          messageText: 'hidden',
          createdAtUtc: '2026-08-13T08:00:02.000Z',
          envelopeHashHex: '',
          timestampMs: 3,
        );

        expect(
          chatMessagesForPeer(const <CapsuleChatInboxMessage>[
            incoming,
            outgoing,
            unrelated,
          ], peerHex).map((message) => message.id),
          <String>['incoming', 'outgoing'],
        );
      },
    );

    test('persists incoming and outgoing messages across restart', () async {
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final firstStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 7)),
      );
      const incoming = CapsuleChatInboxMessage(
        id: 'incoming-envelope',
        fromHex: peerHex,
        toHex: capsuleHex,
        messageText: 'incoming',
        createdAtUtc: '2026-08-13T08:00:00.000Z',
        envelopeHashHex: 'incoming-envelope',
        timestampMs: 1,
      );
      const pending = CapsuleChatInboxMessage(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        fromHex: capsuleHex,
        toHex: peerHex,
        messageText: 'outgoing',
        createdAtUtc: '2026-08-13T08:00:01.000Z',
        envelopeHashHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        timestampMs: 2,
        direction: CapsuleChatMessageDirection.outgoing,
        deliveryState: CapsuleChatMessageDeliveryState.pending,
      );

      await firstStore.mergeDurably(
        capsuleHex,
        messages: const <CapsuleChatInboxMessage>[incoming],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
      await firstStore.upsertMessageDurably(capsuleHex, pending);
      await firstStore.upsertMessageDurably(
        capsuleHex,
        pending.copyWith(
          deliveryState: CapsuleChatMessageDeliveryState.transportAccepted,
        ),
      );

      final capsuleDir = await fileStore.capsuleDirForHex(capsuleHex);
      final sealed = await fileStore.readChatTimeline(capsuleDir);
      expect(sealed, isNot(contains('incoming')));
      expect(sealed, isNot(contains('outgoing')));
      final wrongScopeDir = await fileStore.capsuleDirForHex(
        peerHex,
        create: true,
      );
      await fileStore.writeChatTimeline(wrongScopeDir, sealed!);
      final wrongScopeStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 7)),
      );
      await wrongScopeStore.hydrateCapsule(peerHex);
      expect(wrongScopeStore.loadMessages(peerHex), isEmpty);

      final restartedStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 7)),
      );
      await restartedStore.hydrateCapsule(capsuleHex);
      final messages = restartedStore.loadMessages(capsuleHex);

      expect(messages, hasLength(2));
      expect(messages.last.direction, CapsuleChatMessageDirection.outgoing);
      expect(
        messages.last.deliveryState,
        CapsuleChatMessageDeliveryState.transportAccepted,
      );
      expect(await restartedStore.unreadMessageCount(capsuleHex), 1);
    });

    test('durable replay keeps one record per canonical envelope', () async {
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final store = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 8)),
      );
      const message = CapsuleChatInboxMessage(
        id: 'same-envelope',
        fromHex: peerHex,
        toHex: capsuleHex,
        messageText: 'once',
        createdAtUtc: '2026-08-13T08:00:00.000Z',
        envelopeHashHex: 'same-envelope',
        timestampMs: 1,
      );

      await store.mergeDurably(
        capsuleHex,
        messages: const <CapsuleChatInboxMessage>[message, message],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
      await store.mergeDurably(
        capsuleHex,
        messages: const <CapsuleChatInboxMessage>[
          CapsuleChatInboxMessage(
            id: 'same-envelope',
            fromHex: peerHex,
            toHex: capsuleHex,
            messageText: 'conflicting rewrite',
            createdAtUtc: '2026-08-13T08:00:01.000Z',
            envelopeHashHex: 'same-envelope',
            timestampMs: 2,
          ),
        ],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
      final restartedStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 8)),
      );
      await restartedStore.hydrateCapsule(capsuleHex);

      expect(restartedStore.loadMessages(capsuleHex), hasLength(1));
      expect(
        restartedStore.loadMessages(capsuleHex).single.messageText,
        'once',
      );

      final wrongKeyStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 9)),
      );
      await wrongKeyStore.hydrateCapsule(capsuleHex);
      expect(wrongKeyStore.loadMessages(capsuleHex), isEmpty);
    });

    test('durable retention keeps only the newest bounded records', () async {
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      Future<Uint8List?> seedLoader(String _) async =>
          Uint8List.fromList(List<int>.filled(32, 14));
      final store = CapsuleDeliveryInboxStore(
        maxRecordsPerCapsule: 2,
        fileStore: fileStore,
        loadTimelineSeed: seedLoader,
      );
      CapsuleChatInboxMessage message(String id, int timestampMs) =>
          CapsuleChatInboxMessage(
            id: id,
            fromHex: peerHex,
            toHex: capsuleHex,
            messageText: id,
            createdAtUtc: '2026-08-13T08:00:0$timestampMs.000Z',
            envelopeHashHex: '',
            timestampMs: timestampMs,
          );

      await store.mergeDurably(
        capsuleHex,
        messages: <CapsuleChatInboxMessage>[
          message('old', 1),
          message('middle', 2),
          message('new', 3),
        ],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
      final restartedStore = CapsuleDeliveryInboxStore(
        maxRecordsPerCapsule: 2,
        fileStore: fileStore,
        loadTimelineSeed: seedLoader,
      );
      await restartedStore.hydrateCapsule(capsuleHex);

      expect(
        restartedStore.loadMessages(capsuleHex).map((value) => value.id),
        <String>['middle', 'new'],
      );
    });

    test('wrong-capsule or corrupt timeline fails closed', () async {
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final capsuleDir = await fileStore.capsuleDirForHex(
        capsuleHex,
        create: true,
      );
      await fileStore.writeChatTimeline(
        capsuleDir,
        jsonEncode(<String, Object?>{
          'version': 1,
          'capsule_root_hex': peerHex,
          'messages': const <Object?>[],
        }),
      );
      final wrongOwnerStore = CapsuleDeliveryInboxStore(fileStore: fileStore);
      await wrongOwnerStore.hydrateCapsule(capsuleHex);
      expect(wrongOwnerStore.loadMessages(capsuleHex), isEmpty);

      await fileStore.writeChatTimeline(capsuleDir, '{not-json');
      final corruptStore = CapsuleDeliveryInboxStore(
        fileStore: fileStore,
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 11)),
      );
      await corruptStore.hydrateCapsule(capsuleHex);
      expect(corruptStore.loadMessages(capsuleHex), isEmpty);
      await expectLater(
        corruptStore.upsertMessageDurably(
          capsuleHex,
          const CapsuleChatInboxMessage(
            id: 'replacement',
            fromHex: peerHex,
            toHex: capsuleHex,
            messageText: 'must not overwrite',
            createdAtUtc: '2026-08-13T08:00:00.000Z',
            envelopeHashHex: '',
            timestampMs: 1,
          ),
        ),
        throwsStateError,
      );
      expect(await fileStore.readChatTimeline(capsuleDir), '{not-json');
    });
  });

  test(
    'trade signals received by chat remain available to trading drone',
    () async {
      const peerHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const localRootHex =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final store = CapsuleDeliveryInboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 12)),
      );
      final runtime = _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      );
      final checks = _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]);
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
      final acknowledged = <String>[];
      final chatService = CapsuleChatDeliveryService(
        runtime: runtime,
        manualChecks: checks,
        deliveryInboxStore: store,
        receiveWorkerRunner:
            (_) async => <String, Object?>{
              'result': 1,
              'json': jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'event_id': 'trade-event-one',
                  'from_hex': peerHex,
                  'payload_json': payloadJson,
                  'timestamp_ms': 1,
                },
              ]),
              'lastError': null,
            },
        acknowledgeWorkerRunner: (args) async {
          acknowledged.addAll(
            (args['eventIds'] as List<Object?>).map(
              (value) => value.toString(),
            ),
          );
          return <String, Object?>{'result': 0, 'lastError': null};
        },
      );
      final droneService = CapsuleChatDeliveryService(
        runtime: runtime,
        manualChecks: checks,
        deliveryInboxStore: store,
      );

      final received = await chatService.drainAndFilter();

      expect(received.tradeSignals, hasLength(1));
      expect(droneService.loadCachedTradeSignals(), hasLength(1));
      expect(
        droneService.loadCachedTradeSignals().single.signalId,
        equals('sig-shared'),
      );
      expect(acknowledged, equals(<String>['trade-event-one']));
    },
  );

  test('chat handoff acknowledgement failure is fail-closed', () async {
    const peerHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const localRootHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      receiveWorkerRunner:
          (_) async => <String, Object?>{
            'result': 1,
            'json': jsonEncode(<Map<String, Object?>>[
              <String, Object?>{
                'event_id': 'unsupported-event-one',
                'from_hex': peerHex,
                'payload_json': '{"unsupported":true}',
                'timestamp_ms': 1,
              },
            ]),
            'lastError': null,
          },
      acknowledgeWorkerRunner:
          (_) async => <String, Object?>{
            'result': -9,
            'lastError': 'durable acknowledgement failed',
          },
    );

    final result = await service.drainAndFilter();

    expect(result.code, -9);
    expect(result.errorMessage, 'durable acknowledgement failed');
  });

  test(
    'chat timeline persistence failure blocks handoff acknowledgement',
    () async {
      const peerHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const localRootHex =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      var acknowledgementCalls = 0;
      final service = CapsuleChatDeliveryService(
        runtime: _FakeRuntime(
          capsuleRootKey: _hexToBytes(localRootHex),
          workerBootstrap: const <String, Object?>{
            'activeCapsuleHex': localRootHex,
          },
        ),
        manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
        ]),
        deliveryInboxStore: CapsuleDeliveryInboxStore(
          fileStore: CapsuleFileStore(
            dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
          ),
          loadTimelineSeed: (_) async => null,
        ),
        receiveWorkerRunner:
            (_) async => <String, Object?>{
              'result': 1,
              'json': jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'event_id': 'event-without-key',
                  'from_hex': peerHex,
                  'payload_json': jsonEncode(<String, Object?>{
                    'message_text': 'retry me',
                    'created_at_utc': '2026-08-13T09:00:00.000Z',
                    'envelope_hash_hex': '',
                  }),
                  'timestamp_ms': 1,
                },
              ]),
              'lastError': null,
            },
        acknowledgeWorkerRunner: (_) async {
          acknowledgementCalls += 1;
          return <String, Object?>{'result': 0, 'lastError': null};
        },
      );

      final result = await service.drainAndFilter();

      expect(result.code, -2005);
      expect(result.errorMessage, contains('Capsule seed is unavailable'));
      expect(acknowledgementCalls, 0);
    },
  );

  test(
    'workspace keeps passive chat visible when the next refresh times out',
    () async {
      const peerHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const localRootHex =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final store = CapsuleDeliveryInboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 13)),
      );
      final runtime = _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      );
      final checks = _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]);
      final passiveService = CapsuleChatDeliveryService(
        runtime: runtime,
        manualChecks: checks,
        deliveryInboxStore: store,
        receiveWorkerRunner:
            (_) async => <String, Object?>{
              'result': 1,
              'json': jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'from_hex': peerHex,
                  'payload_json': jsonEncode(<String, Object?>{
                    'message_text': 'preserved',
                    'created_at_utc': '2026-08-08T12:00:00.000Z',
                    'envelope_hash_hex':
                        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  }),
                  'timestamp_ms': 1,
                },
              ]),
              'lastError': null,
            },
      );
      final workspaceService = CapsuleChatDeliveryService(
        runtime: runtime,
        manualChecks: checks,
        deliveryInboxStore: store,
      );

      var projected = const <CapsuleChatInboxMessage>[];

      final received = await passiveService.drainAndFilter();
      final result = await projectCachedMessagesBeforeChatRefresh(
        currentMessages: const <CapsuleChatInboxMessage>[],
        loadCachedMessages: workspaceService.loadCachedMessagesDurably,
        refresh:
            () async => const CapsuleChatDeliveryReceiveResult(
              code: -1003,
              errorMessage: 'Transport receive timed out',
              droppedByConsensus: 0,
              messages: <CapsuleChatInboxMessage>[],
              tradeSignals: <CapsuleTradeSignalInboxMessage>[],
            ),
        projectMessages: (messages) => projected = messages,
      );

      expect(received.messages, hasLength(1));
      expect(result.code, -1003);
      expect(projected, hasLength(1));
      expect(projected.single.messageText, 'preserved');
    },
  );

  test('delivery inbox isolates capsule and seals stable-id conflicts', () {
    const firstCapsule =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const secondCapsule =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final store = CapsuleDeliveryInboxStore();
    const first = CapsuleChatInboxMessage(
      id: 'message-1',
      fromHex: firstCapsule,
      messageText: 'first',
      createdAtUtc: '2026-08-08T12:00:00.000Z',
      envelopeHashHex: '',
      timestampMs: 1,
    );
    const replacement = CapsuleChatInboxMessage(
      id: 'message-1',
      fromHex: firstCapsule,
      messageText: 'replacement',
      createdAtUtc: '2026-08-08T12:00:01.000Z',
      envelopeHashHex: '',
      timestampMs: 2,
    );

    store.merge(
      firstCapsule,
      messages: const <CapsuleChatInboxMessage>[first, replacement],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );

    expect(store.loadMessages(firstCapsule), hasLength(1));
    expect(store.loadMessages(firstCapsule).single.messageText, 'first');
    expect(store.loadMessages(secondCapsule), isEmpty);
  });

  test('delivery inbox bounds records and capsule scopes', () {
    final store = CapsuleDeliveryInboxStore(
      maxCapsules: 2,
      maxRecordsPerCapsule: 2,
    );
    const firstCapsule =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const secondCapsule =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const thirdCapsule =
        '3333333333333333333333333333333333333333333333333333333333333333';

    CapsuleChatInboxMessage message(String id, int timestampMs) =>
        CapsuleChatInboxMessage(
          id: id,
          fromHex: secondCapsule,
          messageText: id,
          createdAtUtc: '2026-08-09T08:00:00.000Z',
          envelopeHashHex: '',
          timestampMs: timestampMs,
        );
    CapsuleTradeSignalInboxMessage signal(String id, int timestampMs) =>
        CapsuleTradeSignalInboxMessage(
          id: id,
          signalId: id,
          fromHex: secondCapsule,
          symbol: 'BTC-USDT',
          side: 'buy',
          orderType: 'limit',
          quantityDecimal: '0.01',
          entryMode: 'zone_pending',
          intentHashHex: '',
          createdAtUtc: '2026-08-09T08:00:00.000Z',
          strategyTag: null,
          canonicalIntentJson: '{}',
          timestampMs: timestampMs,
        );

    store.merge(
      firstCapsule,
      messages: <CapsuleChatInboxMessage>[message('first', 1)],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    store.merge(
      secondCapsule,
      messages: <CapsuleChatInboxMessage>[
        message('old', 1),
        message('middle', 2),
        message('new', 3),
      ],
      tradeSignals: <CapsuleTradeSignalInboxMessage>[
        signal('old-signal', 1),
        signal('middle-signal', 2),
        signal('new-signal', 3),
      ],
    );
    store.merge(
      thirdCapsule,
      messages: <CapsuleChatInboxMessage>[message('third', 4)],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );

    expect(store.loadMessages(firstCapsule), isEmpty);
    expect(
      store.loadMessages(secondCapsule).map((message) => message.id),
      <String>['middle', 'new'],
    );
    expect(
      store.loadTradeSignals(secondCapsule).map((signal) => signal.id),
      <String>['middle-signal', 'new-signal'],
    );
    expect(store.loadMessages(thirdCapsule), hasLength(1));
  });

  test('delivery inbox cleanup removes only the deleted capsule', () {
    const deletedCapsule =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const retainedCapsule =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final store = CapsuleDeliveryInboxStore();
    const message = CapsuleChatInboxMessage(
      id: 'message',
      fromHex: retainedCapsule,
      messageText: 'cached',
      createdAtUtc: '2026-08-09T08:00:00.000Z',
      envelopeHashHex: '',
      timestampMs: 1,
    );
    store.merge(
      deletedCapsule,
      messages: const <CapsuleChatInboxMessage>[message],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    store.merge(
      retainedCapsule,
      messages: const <CapsuleChatInboxMessage>[message],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );

    store.clearCapsule(deletedCapsule);

    expect(store.loadMessages(deletedCapsule), isEmpty);
    expect(store.loadMessages(retainedCapsule), hasLength(1));
  });

  test('unread state survives restart without replay inflation', () async {
    const capsuleHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final tempHome = await Directory.systemTemp.createTemp('hivra-unread-');
    addTearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });
    final fileStore = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    final firstStore = CapsuleDeliveryInboxStore(fileStore: fileStore);
    const first = CapsuleChatInboxMessage(
      id: 'message-1',
      fromHex: capsuleHex,
      messageText: 'first',
      createdAtUtc: '2026-08-13T08:00:00.000Z',
      envelopeHashHex: '',
      timestampMs: 1,
    );
    const second = CapsuleChatInboxMessage(
      id: 'message-2',
      fromHex: capsuleHex,
      messageText: 'second',
      createdAtUtc: '2026-08-13T08:00:01.000Z',
      envelopeHashHex: '',
      timestampMs: 2,
    );

    firstStore.merge(
      capsuleHex,
      messages: const <CapsuleChatInboxMessage>[first, second],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    expect(await firstStore.unreadMessageCount(capsuleHex), 2);
    await firstStore.markMessagesRead(capsuleHex, const <String>['message-1']);
    expect(await firstStore.unreadMessageCount(capsuleHex), 1);

    final restartedStore = CapsuleDeliveryInboxStore(fileStore: fileStore);
    restartedStore.merge(
      capsuleHex,
      messages: const <CapsuleChatInboxMessage>[first, second, first],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );

    expect(await restartedStore.unreadMessageCount(capsuleHex), 1);
    await restartedStore.markMessagesRead(
      capsuleHex,
      restartedStore.loadMessages(capsuleHex).map((message) => message.id),
    );
    expect(await restartedStore.unreadMessageCount(capsuleHex), 0);
  });

  test('corrupt or cross-capsule read state never hides unread', () async {
    const capsuleHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const otherCapsuleHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final tempHome = await Directory.systemTemp.createTemp('hivra-unread-');
    addTearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });
    final fileStore = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    final store = CapsuleDeliveryInboxStore(fileStore: fileStore);
    const message = CapsuleChatInboxMessage(
      id: 'message-1',
      fromHex: otherCapsuleHex,
      messageText: 'unread',
      createdAtUtc: '2026-08-13T08:00:00.000Z',
      envelopeHashHex: '',
      timestampMs: 1,
    );
    store.merge(
      capsuleHex,
      messages: const <CapsuleChatInboxMessage>[message],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    final capsuleDir = await fileStore.capsuleDirForHex(
      capsuleHex,
      create: true,
    );
    await fileStore.writeChatReadState(capsuleDir, '{not-json');
    expect(await store.unreadMessageCount(capsuleHex), 1);

    await fileStore.writeChatReadState(
      capsuleDir,
      jsonEncode(<String, Object?>{
        'version': 1,
        'capsule_root_hex': otherCapsuleHex,
        'read_message_ids': <String>['message-1'],
      }),
    );
    expect(await store.unreadMessageCount(capsuleHex), 1);
    expect(await store.unreadMessageCount(otherCapsuleHex), 0);
  });

  test('evicted messages cannot resurrect unread state', () async {
    const capsuleHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final tempHome = await Directory.systemTemp.createTemp('hivra-unread-');
    addTearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });
    final store = CapsuleDeliveryInboxStore(
      maxRecordsPerCapsule: 1,
      fileStore: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      ),
    );
    CapsuleChatInboxMessage message(String id, int timestampMs) =>
        CapsuleChatInboxMessage(
          id: id,
          fromHex: capsuleHex,
          messageText: id,
          createdAtUtc: '2026-08-13T08:00:00.000Z',
          envelopeHashHex: '',
          timestampMs: timestampMs,
        );
    store.merge(
      capsuleHex,
      messages: <CapsuleChatInboxMessage>[message('old', 1)],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );
    await store.markMessagesRead(capsuleHex, const <String>['old']);
    store.merge(
      capsuleHex,
      messages: <CapsuleChatInboxMessage>[message('new', 2)],
      tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
    );

    expect(store.loadMessages(capsuleHex).single.id, 'new');
    expect(await store.unreadMessageCount(capsuleHex), 1);
    await store.markMessagesRead(capsuleHex, const <String>['new']);
    expect(await store.unreadMessageCount(capsuleHex), 0);
  });

  test(
    'concurrent read projections preserve the newest complete set',
    () async {
      const capsuleHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      final tempHome = await Directory.systemTemp.createTemp('hivra-unread-');
      addTearDown(() async {
        if (await tempHome.exists()) await tempHome.delete(recursive: true);
      });
      final store = CapsuleDeliveryInboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
      CapsuleChatInboxMessage message(String id, int timestampMs) =>
          CapsuleChatInboxMessage(
            id: id,
            fromHex: capsuleHex,
            messageText: id,
            createdAtUtc: '2026-08-13T08:00:00.000Z',
            envelopeHashHex: '',
            timestampMs: timestampMs,
          );
      store.merge(
        capsuleHex,
        messages: <CapsuleChatInboxMessage>[
          message('first', 1),
          message('second', 2),
        ],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );

      await Future.wait(<Future<void>>[
        store.markMessagesRead(capsuleHex, const <String>['first']),
        store.markMessagesRead(capsuleHex, const <String>['first', 'second']),
      ]);

      expect(await store.unreadMessageCount(capsuleHex), 0);
    },
  );

  testWidgets('chat navigation badge is visible only for unread messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: chatUnreadNavigationIcon(3))),
    );
    expect(find.byKey(const ValueKey<String>('chat-unread-badge')), findsOne);
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Icon(Icons.extension))),
    );
    expect(
      find.byKey(const ValueKey<String>('chat-unread-badge')),
      findsNothing,
    );
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
        manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
        ]),
        loadRelationships:
            () => <Relationship>[
              Relationship(
                // Regression shape: a mixed root/transport ledger can expose the
                // root as peerPubkey. Sending must still prefer the contact card
                // transport endpoint for a root-addressed peer.
                peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                ownStarterId: base64Encode(Uint8List(32)),
                peerStarterId: base64Encode(
                  Uint8List.fromList(List<int>.filled(32, 1)),
                ),
                establishedAt: DateTime.utc(2026, 6, 28),
              ),
            ],
        listTrustedCards:
            () async => const <CapsuleAddressCard>[
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
          return <String, Object?>{'result': 0, 'lastError': null};
        },
      );

      final result = await service.sendCanonicalEnvelope(
        peerHex: peerRootHex,
        canonicalEnvelopeJson: '{"message_text":"hello"}',
      );

      expect(result.isSuccess, isTrue);
      expect(result.deliveryPeerHex, equals(peerTransportHex));
      expect(_bytesToHex(sentToPubkey!), equals(peerTransportHex));
    },
  );

  test(
    'chat send rejects root-only relationship without transport card',
    () async {
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
        manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
        ]),
        loadRelationships:
            () => <Relationship>[
              Relationship(
                peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                ownStarterId: base64Encode(Uint8List(32)),
                peerStarterId: base64Encode(
                  Uint8List.fromList(List<int>.filled(32, 1)),
                ),
                establishedAt: DateTime.utc(2026, 6, 28),
              ),
            ],
        sendWorkerRunner: (_) async {
          sendCalls += 1;
          return <String, Object?>{'result': 0, 'lastError': null};
        },
      );

      final result = await service.sendCanonicalEnvelope(
        peerHex: peerRootHex,
        canonicalEnvelopeJson: '{"message_text":"hello"}',
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, -2003);
      expect(result.errorMessage, contains('No transport endpoint'));
      expect(sendCalls, 0);
    },
  );

  test('tracked chat send persists acceptance and timeout ambiguity', () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const peerTransportHex =
        'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
    addTearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });
    final fileStore = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    Future<Uint8List?> seedLoader(String _) async =>
        Uint8List.fromList(List<int>.filled(32, 15));
    final timelineStore = CapsuleDeliveryInboxStore(
      fileStore: fileStore,
      loadTimelineSeed: seedLoader,
    );
    var nextCode = 0;
    var sendCalls = 0;
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      listTrustedCards:
          () async => const <CapsuleAddressCard>[
            CapsuleAddressCard(
              rootKey:
                  'h10xg7awf467k73f3nytv45nkw6f0e8nv0xcng3az3x6cmzka6w2cqqgpav3',
              rootHex: peerRootHex,
              nostrNpub:
                  'npub15varftzcs832ul4jje75pwfed35kngtwcny7wc5gcettzmv5jcnsysfak5',
              nostrHex: peerTransportHex,
            ),
          ],
      deliveryInboxStore: timelineStore,
      sendWorkerRunner: (_) async {
        sendCalls += 1;
        return <String, Object?>{
          'result': nextCode,
          'lastError': nextCode == 0 ? null : 'local timeout',
        };
      },
    );
    const acceptedHash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const ambiguousHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    final accepted = await service.sendCanonicalEnvelopeWithTimeline(
      capsuleRootHex: localRootHex,
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"accepted"}',
      envelopeHashHex: acceptedHash,
      messageText: 'accepted',
      createdAtUtc: '2026-08-13T10:00:00.000Z',
    );
    nextCode = -1003;
    final ambiguous = await service.sendCanonicalEnvelopeWithTimeline(
      capsuleRootHex: localRootHex,
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"ambiguous"}',
      envelopeHashHex: ambiguousHash,
      messageText: 'ambiguous',
      createdAtUtc: '2026-08-13T10:00:01.000Z',
    );

    expect(accepted.isSuccess, isTrue);
    expect(ambiguous.code, -1003);
    expect(sendCalls, 2);
    final restartedStore = CapsuleDeliveryInboxStore(
      fileStore: fileStore,
      loadTimelineSeed: seedLoader,
    );
    await restartedStore.hydrateCapsule(localRootHex);
    final byId = <String, CapsuleChatInboxMessage>{
      for (final message in restartedStore.loadMessages(localRootHex))
        message.id: message,
    };
    expect(
      byId[acceptedHash]?.deliveryState,
      CapsuleChatMessageDeliveryState.transportAccepted,
    );
    expect(
      byId[ambiguousHash]?.deliveryState,
      CapsuleChatMessageDeliveryState.ambiguous,
    );
  });

  test(
    'chat send recovers transport endpoint from incoming invitation ledger fact',
    () async {
      const peerRootHex =
          '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
      const peerTransportHex =
          'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
      const localRootHex =
          '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
      Uint8List? sentToPubkey;

      final invitationPayload = <int>[
        ...Uint8List.fromList(List<int>.filled(32, 1)),
        ...Uint8List.fromList(List<int>.filled(32, 2)),
        ..._hexToBytes(localRootHex),
        ..._hexToBytes(peerRootHex),
        0,
        ..._hexToBytes(peerTransportHex),
      ];
      final ledgerJson = jsonEncode(<String, Object?>{
        'events': <Map<String, Object?>>[
          <String, Object?>{
            'kind': 'InvitationReceived',
            'payload': invitationPayload,
          },
        ],
      });

      final service = CapsuleChatDeliveryService(
        runtime: _FakeRuntime(
          capsuleRootKey: _hexToBytes(localRootHex),
          ledgerJson: ledgerJson,
          workerBootstrap: const <String, Object?>{
            'activeCapsuleHex': localRootHex,
          },
        ),
        manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
        ]),
        loadRelationships:
            () => <Relationship>[
              Relationship(
                peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                ownStarterId: base64Encode(Uint8List(32)),
                peerStarterId: base64Encode(
                  Uint8List.fromList(List<int>.filled(32, 1)),
                ),
                establishedAt: DateTime.utc(2026, 6, 28),
              ),
            ],
        sendWorkerRunner: (args) async {
          sentToPubkey = args['toPubkey'] as Uint8List;
          return <String, Object?>{'result': 0, 'lastError': null};
        },
      );

      final result = await service.sendCanonicalEnvelope(
        peerHex: peerRootHex,
        canonicalEnvelopeJson: '{"message_text":"hello"}',
      );

      expect(result.isSuccess, isTrue);
      expect(result.deliveryPeerHex, equals(peerTransportHex));
      expect(_bytesToHex(sentToPubkey!), equals(peerTransportHex));
    },
  );

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
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      listTrustedCards:
          () async => const <CapsuleAddressCard>[
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
        return <String, Object?>{'result': -1003, 'lastError': 'relay timeout'};
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

  test('chat send rejects worker bootstrap from another capsule', () async {
    const peerRootHex =
        '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
    const peerTransportHex =
        'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
    const localRootHex =
        '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
    const otherRootHex =
        '365ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede699';
    var sendCalls = 0;
    final service = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': otherRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      listTrustedCards:
          () async => const <CapsuleAddressCard>[
            CapsuleAddressCard(
              rootKey: 'h1peer',
              rootHex: peerRootHex,
              nostrNpub: 'npub1peer',
              nostrHex: peerTransportHex,
            ),
          ],
      sendWorkerRunner: (_) async {
        sendCalls += 1;
        return <String, Object?>{'result': 0, 'lastError': null};
      },
    );

    final result = await service.sendCanonicalEnvelope(
      peerHex: peerRootHex,
      canonicalEnvelopeJson: '{"message_text":"hello"}',
      expectedCapsuleRootHex: localRootHex,
    );

    expect(result.isSuccess, isFalse);
    expect(result.code, -2004);
    expect(sendCalls, 0);
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
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      readAttestedSignable:
          (_) async => const ConsensusSignableResult(
            preview: null,
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(code: 'pair_attestation_missing'),
            ],
          ),
      sendWorkerRunner: (_) async {
        sendCalls += 1;
        return <String, Object?>{'result': 0, 'lastError': null};
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
    final fileStore = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    final deferredStore = CapsuleChatDeferredInboxStore(fileStore: fileStore);
    final deliveryStore = CapsuleDeliveryInboxStore(
      fileStore: fileStore,
      loadTimelineSeed:
          (_) async => Uint8List.fromList(List<int>.filled(32, 10)),
    );
    final envelope = jsonEncode(<String, Object?>{
      'message_text': 'hello',
      'created_at_utc': '2026-07-14T09:00:00.000Z',
      'envelope_hash_hex': '',
    });
    final acknowledgedEventIds = <String>[];
    final blockedService = CapsuleChatDeliveryService(
      runtime: _FakeRuntime(
        capsuleRootKey: _hexToBytes(localRootHex),
        workerBootstrap: const <String, Object?>{
          'activeCapsuleHex': localRootHex,
        },
      ),
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      readAttestedSignable:
          (_) async => const ConsensusSignableResult(
            preview: null,
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(code: 'pair_attestation_missing'),
            ],
          ),
      deferredInboxStore: deferredStore,
      deliveryInboxStore: deliveryStore,
      transportHealth: TransportHealthPolicyService(
        timeoutBackoff: const <Duration>[Duration(minutes: 1)],
      ),
      receiveWorkerRunner:
          (_) async => <String, Object?>{
            'result': 0,
            'json': jsonEncode(<Map<String, Object?>>[
              <String, Object?>{
                'event_id': 'nostr-event-one',
                'from_hex': peerRootHex,
                'payload_json': envelope,
                'timestamp_ms': 1,
              },
            ]),
            'lastError': null,
          },
      acknowledgeWorkerRunner: (args) async {
        acknowledgedEventIds.addAll(
          (args['eventIds'] as List<Object?>).map((value) => value.toString()),
        );
        return <String, Object?>{'result': 0, 'lastError': null};
      },
    );

    final blocked = await blockedService.drainAndFilter();

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
      manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
      ]),
      readAttestedSignable:
          (_) async => const ConsensusSignableResult(
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
      deliveryInboxStore: deliveryStore,
      transportHealth: TransportHealthPolicyService(
        timeoutBackoff: const <Duration>[Duration(minutes: 1)],
      ),
      receiveWorkerRunner:
          (_) async => <String, Object?>{
            'result': 0,
            'json': null,
            'lastError': null,
          },
      acknowledgeWorkerRunner: (args) async {
        acknowledgedEventIds.addAll(
          (args['eventIds'] as List<Object?>).map((value) => value.toString()),
        );
        return <String, Object?>{'result': 0, 'lastError': null};
      },
    );

    final ready = await readyService.drainAndFilter();

    expect(ready.messages, hasLength(1));
    expect(ready.messages.single.id, equals('nostr-event-one'));
    expect(ready.messages.single.messageText, equals('hello'));
    expect(ready.droppedByConsensus, 0);
    expect(ready.deferredByConsensus, 0);
    expect(await deferredStore.load(localRootHex), isEmpty);
    expect(acknowledgedEventIds, contains('nostr-event-one'));
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
        final commandService = BingxFuturesExecutionCommandService(
          replayStore: replayStore,
        );
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
          runtime: _FakeRuntime(capsuleRootKey: _hexToBytes(localRootHex)),
          manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
          ]),
          executionCommandService: commandService,
          executionPolicyForPeer:
              (_) => const BingxExecutionPolicy(
                allowedSymbols: <String>{'BTCUSDT'},
                maxLeverage: 5,
                maxRiskPercent: 2,
              ),
          nowUtc: () => DateTime.utc(2026, 4, 25, 12, 1, 0),
          receiveWorkerRunner:
              (_) async => <String, Object?>{
                'result': 0,
                'json': jsonEncode(<Map<String, Object?>>[
                  <String, Object?>{
                    'from_hex': peerHex,
                    'payload_json': commandEnvelope,
                    'timestamp_ms': 1,
                  },
                ]),
                'lastError': null,
              },
        );

        final result = await service.drainAndFilter();

        expect(result.code, equals(0));
        expect(result.messages, isEmpty);
        expect(result.tradeSignals, isEmpty);
        expect(result.executionReceipts, isEmpty);
        expect(result.executionDecisions, hasLength(1));
        expect(result.executionDecisions.single.commandId, equals('cmd-1'));
        expect(result.executionDecisions.single.decision, equals('accepted'));
        expect(
          result.executionDecisions.single.decisionCode,
          equals('accepted_for_execution'),
        );
        expect(
          result.executionDecisions.single.receiptDeliveryCode,
          equals(-2003),
        );
      },
    );

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
        runtime: _FakeRuntime(capsuleRootKey: _hexToBytes(localRootHex)),
        manualChecks: _FakeManualConsensusCheckService(<ManualConsensusCheck>[
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
        ]),
        receiveWorkerRunner:
            (_) async => <String, Object?>{
              'result': 0,
              'json': jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'from_hex': peerHex,
                  'payload_json': payloadJson,
                  'timestamp_ms': 99,
                },
              ]),
              'lastError': null,
            },
      );

      final result = await service.drainAndFilter();

      expect(result.code, equals(0));
      expect(result.executionDecisions, isEmpty);
      expect(result.executionReceipts, hasLength(1));
      expect(result.executionReceipts.single.commandId, equals('cmd-9'));
      expect(result.executionReceipts.single.decision, equals('rejected'));
      expect(
        result.executionReceipts.single.decisionCode,
        equals('policy_symbol_blocked'),
      );
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
  final String? ledgerJson;

  _FakeRuntime({
    required this.capsuleRootKey,
    this.workerBootstrap = const <String, Object?>{},
    this.ledgerJson,
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
  String? exportLedger() => ledgerJson;

  @override
  String? invokeWasmJson({
    required Uint8List moduleBytes,
    required String entryExport,
    required Uint8List inputJsonBytes,
  }) => null;

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
  String? breakRelationshipWithDeliveryReference(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) => null;

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
  String? projectInvitationCurrentViewV1(String ledgerJson) => null;

  @override
  String? projectRelationshipCurrentViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  }) => null;

  @override
  String? projectPairViewV1(
    String ledgerJson, {
    Uint8List? localTransportPublicKey,
  }) => null;

  @override
  String? projectHistoryViewV1(String ledgerJson, String requestJson) => null;

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
  }) async => null;

  @override
  Future<bool> persistLedgerSnapshot() async => false;

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson, {
    String? capsuleStateJson,
  }) async {}

  @override
  Future<String?> resolveActiveCapsuleHex() async => null;
}

class _FakeCapsuleAddressRuntime implements CapsuleAddressRuntime {
  const _FakeCapsuleAddressRuntime();

  @override
  Uint8List? capsuleNostrPublicKey() => null;

  @override
  Uint8List? capsuleRootPublicKey() => null;

  @override
  Uint8List? signRootDigest32(Uint8List message32) => null;

  @override
  bool verifyRootDigest32({
    required Uint8List message32,
    required Uint8List pubkey32,
    required Uint8List signature64,
  }) => false;
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
