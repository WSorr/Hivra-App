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
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
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
import 'package:hivra_app/screens/capsule_chat_plugin_screen.dart';
import 'package:hivra_app/screens/main_screen.dart';
import 'package:flutter/material.dart';

void main() {
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
      'passive chat projection merges durable and drained messages once',
      () {
        const existing = CapsuleChatInboxMessage(
          id: 'existing',
          fromHex: peerHex,
          toHex: capsuleHex,
          messageText: 'existing',
          createdAtUtc: '2026-08-13T08:00:00.000Z',
          envelopeHashHex: '',
          timestampMs: 1,
        );
        const passive = CapsuleChatInboxMessage(
          id: 'passive',
          fromHex: peerHex,
          toHex: capsuleHex,
          messageText: 'passive',
          createdAtUtc: '2026-08-13T08:00:01.000Z',
          envelopeHashHex: '',
          timestampMs: 2,
        );

        final projected = mergeChatMessages(<Iterable<CapsuleChatInboxMessage>>[
          const <CapsuleChatInboxMessage>[existing],
          const <CapsuleChatInboxMessage>[existing, passive],
          const <CapsuleChatInboxMessage>[passive],
        ]);

        expect(projected, <CapsuleChatInboxMessage>[existing, passive]);
      },
    );

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

    test('conversation metadata projects both directions by peer', () {
      const otherPeerHex =
          '3333333333333333333333333333333333333333333333333333333333333333';
      CapsuleChatInboxMessage message({
        required String id,
        required String fromHex,
        String? toHex,
        required int timestampMs,
        CapsuleChatMessageDirection direction =
            CapsuleChatMessageDirection.incoming,
      }) => CapsuleChatInboxMessage(
        id: id,
        fromHex: fromHex,
        toHex: toHex,
        messageText: id,
        createdAtUtc: '2026-08-13T08:00:00.000Z',
        envelopeHashHex: '',
        timestampMs: timestampMs,
        direction: direction,
      );

      expect(
        latestChatMessageTimestampByPeer(<CapsuleChatInboxMessage>[
          message(
            id: 'incoming',
            fromHex: peerHex,
            toHex: capsuleHex,
            timestampMs: 10,
          ),
          message(
            id: 'outgoing',
            fromHex: capsuleHex,
            toHex: peerHex,
            timestampMs: 20,
            direction: CapsuleChatMessageDirection.outgoing,
          ),
          message(id: 'other', fromHex: otherPeerHex, timestampMs: 30),
          message(id: 'malformed', fromHex: 'not-a-peer', timestampMs: 40),
        ]),
        <String, int>{peerHex: 20, otherPeerHex: 30},
      );
    });

    test('conversation order prioritizes unread, recency, and readiness', () {
      const unreadPeer = peerHex;
      const recentPeer =
          '3333333333333333333333333333333333333333333333333333333333333333';
      const readyPeer =
          '4444444444444444444444444444444444444444444444444444444444444444';
      const lexicalPeer =
          '5555555555555555555555555555555555555555555555555555555555555555';

      expect(
        orderChatConversationPeerHexes(
          peerHexes: const <String>[
            lexicalPeer,
            readyPeer,
            recentPeer,
            unreadPeer,
          ],
          signableByPeer: const <String, bool>{
            unreadPeer: false,
            recentPeer: false,
            readyPeer: true,
            lexicalPeer: false,
          },
          unreadByPeer: const <String, int>{unreadPeer: 1},
          latestTimestampByPeer: const <String, int>{
            unreadPeer: 1,
            recentPeer: 30,
            readyPeer: 20,
            lexicalPeer: 20,
          },
        ),
        const <String>[unreadPeer, recentPeer, readyPeer, lexicalPeer],
      );
    });

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

  test('durably persisted chat message acknowledges its handoff event', () async {
    const peerHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const localRootHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    final tempHome = await Directory.systemTemp.createTemp('hivra-chat-');
    addTearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });
    final acknowledged = <String>[];
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
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      ]),
      deliveryInboxStore: CapsuleDeliveryInboxStore(
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
        loadTimelineSeed:
            (_) async => Uint8List.fromList(List<int>.filled(32, 12)),
      ),
      receiveWorkerRunner:
          (_) async => <String, Object?>{
            'result': 1,
            'json': jsonEncode(<Map<String, Object?>>[
              <String, Object?>{
                'event_id': 'chat-event-one',
                'from_hex': peerHex,
                'payload_json': jsonEncode(<String, Object?>{
                  'message_text': 'durable handoff',
                  'created_at_utc': '2026-08-17T12:00:00.000Z',
                  'envelope_hash_hex':
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                }),
                'timestamp_ms': 1,
              },
            ]),
            'lastError': null,
          },
      acknowledgeWorkerRunner: (args) async {
        acknowledged.addAll(
          (args['eventIds'] as List<Object?>).map((value) => value.toString()),
        );
        return <String, Object?>{'result': 0, 'lastError': null};
      },
    );

    final result = await service.drainAndFilter();

    expect(result.messages.single.messageText, 'durable handoff');
    expect(acknowledged, <String>['chat-event-one']);
  });

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
    'retired trading payload is acknowledged without creating state',
    () async {
      const peerHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const localRootHex =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final acknowledged = <String>[];
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
            blockingFacts: <ConsensusBlockingFact>[],
          ),
        ]),
        receiveWorkerRunner:
            (_) async => <String, Object?>{
              'result': 1,
              'json': jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'event_id': 'retired-trading-event',
                  'from_hex': peerHex,
                  'payload_json': jsonEncode(<String, Object?>{
                    'contract_kind': 'bingx_trade_signal_v1',
                    'signal_id': 'retired-signal',
                    'symbol': 'BTC-USDT',
                  }),
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

      final result = await service.drainAndFilter();

      expect(result.code, 1);
      expect(result.messages, isEmpty);
      expect(service.loadCachedMessages(), isEmpty);
      expect(acknowledged, <String>['retired-trading-event']);
    },
  );

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
    store.merge(
      firstCapsule,
      messages: <CapsuleChatInboxMessage>[message('first', 1)],
    );
    store.merge(
      secondCapsule,
      messages: <CapsuleChatInboxMessage>[
        message('old', 1),
        message('middle', 2),
        message('new', 3),
      ],
    );
    store.merge(
      thirdCapsule,
      messages: <CapsuleChatInboxMessage>[message('third', 4)],
    );

    expect(store.loadMessages(firstCapsule), isEmpty);
    expect(
      store.loadMessages(secondCapsule).map((message) => message.id),
      <String>['middle', 'new'],
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
    );
    store.merge(
      retainedCapsule,
      messages: const <CapsuleChatInboxMessage>[message],
    );

    store.clearCapsule(deletedCapsule);

    expect(store.loadMessages(deletedCapsule), isEmpty);
    expect(store.loadMessages(retainedCapsule), hasLength(1));
  });

  test('unread state survives restart without replay inflation', () async {
    const capsuleHex =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const firstPeerHex =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const secondPeerHex =
        '3333333333333333333333333333333333333333333333333333333333333333';
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
      fromHex: firstPeerHex,
      messageText: 'first',
      createdAtUtc: '2026-08-13T08:00:00.000Z',
      envelopeHashHex: '',
      timestampMs: 1,
    );
    const second = CapsuleChatInboxMessage(
      id: 'message-2',
      fromHex: secondPeerHex,
      messageText: 'second',
      createdAtUtc: '2026-08-13T08:00:01.000Z',
      envelopeHashHex: '',
      timestampMs: 2,
    );
    const third = CapsuleChatInboxMessage(
      id: 'message-3',
      fromHex: firstPeerHex,
      messageText: 'third',
      createdAtUtc: '2026-08-13T08:00:02.000Z',
      envelopeHashHex: '',
      timestampMs: 3,
    );
    const outgoing = CapsuleChatInboxMessage(
      id: 'message-4',
      fromHex: capsuleHex,
      toHex: firstPeerHex,
      messageText: 'outgoing',
      createdAtUtc: '2026-08-13T08:00:03.000Z',
      envelopeHashHex: '',
      timestampMs: 4,
      direction: CapsuleChatMessageDirection.outgoing,
    );

    firstStore.merge(
      capsuleHex,
      messages: const <CapsuleChatInboxMessage>[first, second, third, outgoing],
    );
    expect(await firstStore.unreadMessageCount(capsuleHex), 3);
    expect(
      await firstStore.unreadMessageCountsByPeer(capsuleHex),
      <String, int>{firstPeerHex: 2, secondPeerHex: 1},
    );
    await firstStore.markMessagesRead(capsuleHex, const <String>['message-1']);
    expect(await firstStore.unreadMessageCount(capsuleHex), 2);
    expect(
      await firstStore.unreadMessageCountsByPeer(capsuleHex),
      <String, int>{firstPeerHex: 1, secondPeerHex: 1},
    );

    final restartedStore = CapsuleDeliveryInboxStore(fileStore: fileStore);
    restartedStore.merge(
      capsuleHex,
      messages: const <CapsuleChatInboxMessage>[
        first,
        second,
        third,
        outgoing,
        first,
      ],
    );

    expect(await restartedStore.unreadMessageCount(capsuleHex), 2);
    expect(
      await restartedStore.unreadMessageCountsByPeer(capsuleHex),
      <String, int>{firstPeerHex: 1, secondPeerHex: 1},
    );
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
    store.merge(capsuleHex, messages: const <CapsuleChatInboxMessage>[message]);
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
    expect(await store.unreadMessageCountsByPeer(capsuleHex), <String, int>{
      otherCapsuleHex: 1,
    });
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
    );
    await store.markMessagesRead(capsuleHex, const <String>['old']);
    store.merge(
      capsuleHex,
      messages: <CapsuleChatInboxMessage>[message('new', 2)],
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
    'chat send uses canonical invitation projection for transport endpoint',
    () async {
      const peerRootHex =
          '7991eeb935d7ade8a63322d95a4eced25f93cd8f362688f45136b1b15bba72b0';
      const peerTransportHex =
          'a33a34ac5881e2ae7eb2967d40b9396c6969a16ec4c9e76288c656b16d949627';
      const localRootHex =
          '265ea129e43aab9648315b98a59848fa8e3bd8dec9208f239bfeb51c2eede698';
      Uint8List? sentToPubkey;

      final ledgerJson = jsonEncode(<String, Object?>{
        'events': <Map<String, Object?>>[],
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
        loadInvitations:
            () => <Invitation>[
              Invitation(
                id: base64Encode(Uint8List.fromList(List<int>.filled(32, 1))),
                fromPubkey: base64Encode(_hexToBytes(peerTransportHex)),
                fromRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                status: InvitationStatus.pending,
                sentAt: DateTime.utc(2026, 6, 28),
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
  String? projectInvitationCurrentViewV1(String ledgerJson) => null;

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
