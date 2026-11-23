import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/capsule_chat_models.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/screens/capsule_chat_screen.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/capsule_passive_receive_coordinator.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/consensus_attestation_sync_service.dart';
import 'package:hivra_app/services/invitation_intent_handler.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/app_runtime_service.dart';
import 'package:hivra_app/widgets/capsule_chat_conversation_workspace.dart';
import 'package:hivra_app/utils/peer_identity_format.dart';

void main() {
  const peerHex =
      '2222222222222222222222222222222222222222222222222222222222222222';
  const capsuleHex =
      '1111111111111111111111111111111111111111111111111111111111111111';

  group('Core-recovered Chat readiness', () {
    late _RecoveryChatModule module;

    tearDown(() => module.passiveReceive.pauseForeground());

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(1200, 900),
      String? initialPeerHex,
    }) async {
      module = _RecoveryChatModule(capsuleHex, peerHex);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CapsuleChatScreen(
            runtime: module,
            initialPeerHex: initialPeerHex,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('selecting a peer secures it without sending a message', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Needs verification'), findsOneWidget);
      expect(module.attestationExchange.requests, isEmpty);
      await tester.tap(find.text('New conversation'));
      await tester.pump();
      expect(module.attestationExchange.requests, [peerHex]);
      expect(module.messageSends, 0);

      module.manualChecks.ready = true;
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
      expect(find.text('Ready to chat'), findsWidgets);
      expect(find.text('Needs verification'), findsNothing);
      expect(module.messageSends, 0);
    });

    testWidgets('failed verification can retry without sending Chat', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('New conversation'));
      await tester.pump();
      module.attestationExchange.pending.completeError(
        StateError('Transport is unavailable'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Select it again to retry.'), findsOneWidget);

      module.attestationExchange.pending =
          Completer<ConsensusAttestationExchangeResult>();
      await tester.tap(find.text('Change'));
      await tester.pump();
      module.manualChecks.ready = true;
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
      expect(module.attestationExchange.requests, [peerHex, peerHex]);
      expect(find.text('Ready to chat'), findsWidgets);
      expect(find.textContaining('Select it again to retry.'), findsNothing);
      expect(module.messageSends, 0);
    });

    testWidgets('attestation-only receive refreshes readiness with no Chat', (
      tester,
    ) async {
      await open(tester);
      module.manualChecks.ready = true;
      module.storedAttestations = 1;
      await module.passiveReceive.trigger(
        capsuleHex: capsuleHex,
        reason: CapsulePassiveReceiveReason.manual,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to chat'), findsOneWidget);
      expect(find.text('Needs verification'), findsNothing);
      expect(module.messageSends, 0);
    });

    testWidgets('late verification failure cannot affect another Capsule', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('New conversation'));
      await tester.pump();
      expect(module.attestationExchange.requests, [peerHex]);
      final reads = module.manualChecks.reads;
      module.owner = '3' * 64;
      module.attestationExchange.pending.completeError(
        StateError('Old Capsule transport failed'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(module.manualChecks.reads, reads);
      expect(
        find.textContaining('Could not secure this conversation.'),
        findsNothing,
      );
      expect(module.messageSends, 0);
    });

    testWidgets('relationship entry opens its conversation directly', (
      tester,
    ) async {
      await open(tester, size: const Size(390, 844), initialPeerHex: peerHex);
      expect(find.text('Conversations'), findsNothing);
      expect(find.byKey(const Key('capsule-chat-composer')), findsOneWidget);
      expect(module.attestationExchange.requests, [peerHex]);
      expect(module.messageSends, 0);
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
    });

    testWidgets('compact Chat returns from a conversation to its list', (
      tester,
    ) async {
      await open(tester, size: const Size(390, 844));
      expect(find.text('Conversations'), findsOneWidget);
      await tester.tap(find.text('Needs verification'));
      await tester.pump();
      expect(find.text('Conversations'), findsNothing);
      expect(find.byKey(const Key('capsule-chat-composer')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.text('Conversations'), findsOneWidget);
      expect(find.byKey(const Key('capsule-chat-composer')), findsNothing);
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
      expect(module.messageSends, 0);
    });

    testWidgets('compact conversation shows verification before any send', (
      tester,
    ) async {
      await open(tester, size: const Size(390, 844));
      await tester.tap(find.text('Needs verification'));
      await tester.pump();
      expect(find.text('Needs verification'), findsOneWidget);
      expect(find.text('Ready to chat'), findsNothing);
      expect(module.messageSends, 0);

      module.manualChecks.ready = true;
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
      expect(find.text('Ready to chat'), findsOneWidget);
      expect(find.text('Needs verification'), findsNothing);
      expect(module.messageSends, 0);
    });

    testWidgets('compact conversation reflects attestation-only receive', (
      tester,
    ) async {
      await open(tester, size: const Size(390, 844));
      await tester.tap(find.text('Needs verification'));
      await tester.pump();
      expect(find.text('Needs verification'), findsOneWidget);

      module.manualChecks.ready = true;
      module.storedAttestations = 1;
      await module.passiveReceive.trigger(
        capsuleHex: capsuleHex,
        reason: CapsulePassiveReceiveReason.manual,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to chat'), findsOneWidget);
      expect(find.text('Needs verification'), findsNothing);
      expect(module.messageSends, 0);
      module.attestationExchange.pending.complete(_readyExchange);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('sidebar lists trusted contacts and opens the selected chat', (
    tester,
  ) async {
    const otherPeerHex =
        '3333333333333333333333333333333333333333333333333333333333333333';
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 500,
            child: CapsuleChatContactSidebar(
              contacts: const <ConsensusPreview>[
                ConsensusPreview(
                  peerHex: peerHex,
                  peerLabel: '',
                  invitationCount: 1,
                  relationshipCount: 1,
                  hashHex: '',
                  canonicalJson: '',
                  blockingFacts: <ConsensusBlockingFact>[],
                ),
                ConsensusPreview(
                  peerHex: otherPeerHex,
                  peerLabel: '',
                  invitationCount: 1,
                  relationshipCount: 1,
                  hashHex: '',
                  canonicalJson: '',
                  blockingFacts: <ConsensusBlockingFact>[],
                ),
              ],
              messages: const <CapsuleChatInboxMessage>[
                CapsuleChatInboxMessage(
                  id: 'recent',
                  fromHex: otherPeerHex,
                  toHex: capsuleHex,
                  messageText: 'See you soon',
                  createdAtUtc: '2026-09-27T00:00:00Z',
                  envelopeHashHex: '',
                  timestampMs: 10,
                  direction: CapsuleChatMessageDirection.incoming,
                  deliveryState: CapsuleChatMessageDeliveryState.received,
                ),
              ],
              contactLabels: <String, String>{
                PeerIdentityFormat.capsuleKeyFromRootHex(peerHex)!: 'Ada',
                PeerIdentityFormat.capsuleKeyFromRootHex(otherPeerHex)!: 'Ben',
              },
              unreadByPeer: const <String, int>{otherPeerHex: 2},
              selectedPeerHex: peerHex,
              enabled: true,
              refreshing: false,
              onSelect: (peer) => selected = peer,
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(find.text('See you soon'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Ben'));
    expect(selected, otherPeerHex);
  });

  testWidgets('shows a conversation instead of transport controls', (
    tester,
  ) async {
    final peerController = TextEditingController(text: peerHex);
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
      ),
    );

    expect(find.text('Change'), findsOneWidget);
    expect(find.byKey(const Key('capsule-chat-composer')), findsOneWidget);
    expect(find.text('Choose Consensus Peer'), findsNothing);
    expect(find.text('Fetch Inbox'), findsNothing);
    expect(find.text('Run Capsule Chat'), findsNothing);
    expect(find.text('Envelope prepared'), findsNothing);
  });

  testWidgets('projects a selected contact after one controller update', (
    tester,
  ) async {
    final peerController = TextEditingController();
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
      ),
    );

    expect(find.text('No conversation selected'), findsOneWidget);
    expect(find.text('Change'), findsNothing);

    peerController.text = peerHex;
    await tester.pump();

    expect(find.text('No conversation selected'), findsNothing);
    expect(find.text('Change'), findsOneWidget);
    expect(find.byKey(const Key('capsule-chat-composer')), findsOneWidget);
  });

  testWidgets('empty state keeps one conversation action in the header', (
    tester,
  ) async {
    final peerController = TextEditingController();
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
      ),
    );

    expect(find.text('New conversation'), findsOneWidget);

    peerController.text = peerHex;
    await tester.pump();

    expect(find.text('New conversation'), findsNothing);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('renders chronological directional bubbles with honest states', (
    tester,
  ) async {
    final peerController = TextEditingController(text: peerHex);
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
        messages: const <CapsuleChatInboxMessage>[
          CapsuleChatInboxMessage(
            id: 'second',
            fromHex: capsuleHex,
            toHex: peerHex,
            messageText: 'outgoing second',
            createdAtUtc: '2026-08-14T12:01:00Z',
            envelopeHashHex: 'bb',
            timestampMs: 2,
            direction: CapsuleChatMessageDirection.outgoing,
            deliveryState: CapsuleChatMessageDeliveryState.transportAccepted,
          ),
          CapsuleChatInboxMessage(
            id: 'first',
            fromHex: peerHex,
            messageText: 'incoming first',
            createdAtUtc: '2026-08-14T12:00:00Z',
            envelopeHashHex: 'aa',
            timestampMs: 1,
          ),
        ],
      ),
    );

    expect(find.text('incoming first'), findsOneWidget);
    expect(find.text('outgoing second'), findsOneWidget);
    expect(find.textContaining('Accepted by transport'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('incoming first')).dy,
      lessThan(tester.getTopLeft(find.text('outgoing second')).dy),
    );

    final incomingBubble = tester.getTopLeft(
      find.byKey(const Key('capsule-chat-message-first')),
    );
    final outgoingBubble = tester.getTopLeft(
      find.byKey(const Key('capsule-chat-message-second')),
    );
    expect(incomingBubble.dx, lessThan(outgoingBubble.dx));
  });

  testWidgets('keeps cached messages visible when receive retry fails', (
    tester,
  ) async {
    final peerController = TextEditingController(text: peerHex);
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);
    var retries = 0;

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
        notice:
            'Could not check for new messages. Saved conversation remains available.',
        noticeIsError: true,
        onRetryReceive: () async => retries += 1,
        messages: const <CapsuleChatInboxMessage>[
          CapsuleChatInboxMessage(
            id: 'cached',
            fromHex: peerHex,
            messageText: 'cached after timeout',
            createdAtUtc: '2026-08-14T12:00:00Z',
            envelopeHashHex: 'aa',
            timestampMs: 1,
          ),
        ],
      ),
    );

    expect(find.text('cached after timeout'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('cached after timeout'), findsOneWidget);
  });

  testWidgets(
    'projects a passive cached message while the workspace remains open',
    (tester) async {
      final peerController = TextEditingController(text: peerHex);
      final messageController = TextEditingController();
      addTearDown(peerController.dispose);
      addTearDown(messageController.dispose);
      final initialMessages = List<CapsuleChatInboxMessage>.generate(
        8,
        (index) => CapsuleChatInboxMessage(
          id: 'existing-$index',
          fromHex: peerHex,
          messageText: 'existing message $index',
          createdAtUtc: '2026-08-14T12:00:00Z',
          envelopeHashHex: 'aa$index',
          timestampMs: index,
        ),
      );
      var cachedMessages = initialMessages;
      var receiveRetries = 0;
      var projectionCount = 0;

      await tester.pumpWidget(
        _testApp(
          peerController: peerController,
          messageController: messageController,
          messages: initialMessages,
          onRetryReceive: () async => receiveRetries += 1,
          loadCachedMessages: () async => cachedMessages,
          onMessagesProjected: (_) => projectionCount += 1,
          cacheProjectionInterval: const Duration(milliseconds: 50),
          height: 400,
        ),
      );
      await tester.pump();
      expect(find.text('passive while open'), findsNothing);

      cachedMessages = <CapsuleChatInboxMessage>[
        ...initialMessages,
        CapsuleChatInboxMessage(
          id: 'passive',
          fromHex: peerHex,
          messageText: 'passive while open',
          createdAtUtc: '2026-08-14T12:02:00Z',
          envelopeHashHex: 'cc',
          timestampMs: 9,
        ),
      ];
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(receiveRetries, 0);
      expect(projectionCount, 1);
      expect(find.text('passive while open'), findsOneWidget);
    },
  );

  testWidgets(
    'open conversation follows cache eviction without resurrecting old bubbles',
    (tester) async {
      final peerController = TextEditingController(text: peerHex);
      final messageController = TextEditingController();
      addTearDown(peerController.dispose);
      addTearDown(messageController.dispose);
      const old = CapsuleChatInboxMessage(
        id: 'old',
        fromHex: peerHex,
        messageText: 'evicted body',
        createdAtUtc: '2026-11-02T00:00:00Z',
        envelopeHashHex: 'old',
        timestampMs: 1,
      );
      var retained = <CapsuleChatInboxMessage>[old];
      await tester.pumpWidget(
        _testApp(
          peerController: peerController,
          messageController: messageController,
          messages: [old],
          loadCachedMessages: () async => retained,
          cacheProjectionInterval: const Duration(milliseconds: 50),
        ),
      );
      await tester.pump();
      expect(find.text('evicted body'), findsOneWidget);
      retained = [];
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('evicted body'), findsNothing);
      // A subsequent refresh still projects the same canonical empty window.
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('evicted body'), findsNothing);
    },
  );

  test('send notices preserve product truth and the draft contract', () {
    expect(
      chatWorkspaceNoticeForSendResult(
        const CapsuleChatSendResult(
          status: CapsuleChatSendStatus.sent,
          message: 'Message sent',
        ),
      ),
      'Accepted by transport',
    );
    expect(
      chatWorkspaceNoticeForSendResult(
        const CapsuleChatSendResult(
          status: CapsuleChatSendStatus.syncing,
          message: 'Pair consensus attestation is not ready',
        ),
      ),
      contains('Your draft is preserved'),
    );
  });
}

Widget _testApp({
  required TextEditingController peerController,
  required TextEditingController messageController,
  List<CapsuleChatInboxMessage> messages = const <CapsuleChatInboxMessage>[],
  String? notice,
  bool noticeIsError = false,
  Future<void> Function()? onRetryReceive,
  Future<List<CapsuleChatInboxMessage>> Function()? loadCachedMessages,
  ValueChanged<List<CapsuleChatInboxMessage>>? onMessagesProjected,
  Duration cacheProjectionInterval = const Duration(seconds: 1),
  double height = 680,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 700,
          height: height,
          child: CapsuleChatConversationWorkspace(
            sending: false,
            checkingForMessages: false,
            notice: notice,
            noticeIsError: noticeIsError,
            messages: messages,
            hiddenMessageCount: 0,
            deferredMessageCount: 0,
            peerController: peerController,
            selectedPeerLabel: 'Trusted peer',
            contactLabels: const <String, String>{},
            messageController: messageController,
            onInputChanged: () {},
            onChooseContact: () async {},
            onRetryReceive: onRetryReceive ?? () async {},
            onSend: () async {},
            loadCachedMessages: loadCachedMessages,
            onMessagesProjected: onMessagesProjected,
            cacheProjectionInterval: cacheProjectionInterval,
          ),
        ),
      ),
    ),
  );
}

const _emptyChat = CapsuleChatDeliveryReceiveResult(
  code: 0,
  errorMessage: null,
  droppedByConsensus: 0,
  messages: [],
);

const _readyExchange = ConsensusAttestationExchangeResult(
  status: ConsensusAttestationExchangeStatus.ready,
  message: null,
  receiveCode: 0,
  receivedCount: 0,
  storedCount: 0,
  localEvidenceSent: false,
);

class _RecoveryChatModule extends Fake implements AppRuntimeService {
  String owner;
  int storedAttestations = 0;
  int messageSends = 0;

  final _RecoveryChatExchange attestationExchange = _RecoveryChatExchange();
  final _RecoveryChatChecks manualChecks;
  final chatDelivery = _RecoveryChatCache();
  final contactLabels = _RecoveryChatLabels();

  @override
  CapsuleChatDeliveryService buildCapsuleChatDeliveryService() => chatDelivery;

  @override
  CapsuleContactLabelStore buildCapsuleContactLabelStore() => contactLabels;

  @override
  ManualConsensusCheckService buildManualConsensusCheckService() =>
      manualChecks;

  @override
  ConsensusAttestationExchangeService
  buildConsensusAttestationExchangeService() => attestationExchange;
  @override
  late final CapsulePassiveReceiveCoordinator passiveReceive =
      CapsulePassiveReceiveCoordinator.withRunners(
        quickIngress:
            (_, {required manualRetry}) async =>
                const InvitationIntentResult(code: 0, message: ''),
        fullIngress:
            (_, {required manualRetry}) async =>
                const InvitationIntentResult(code: 0, message: ''),
        drainAttestations:
            () async => ConsensusAttestationReceiveResult(
              code: 0,
              errorMessage: null,
              receivedCount: storedAttestations,
              storedCount: storedAttestations,
              rejectedCount: 0,
            ),
        drainChat: () async => _emptyChat,
      );

  _RecoveryChatModule(this.owner, String peer)
    : manualChecks = _RecoveryChatChecks(peer);

  @override
  String activeCapsuleRootHex() => owner;

  @override
  Future<CapsuleChatSendResult> sendChatMessage({
    required String peerHex,
    required String messageText,
  }) async {
    messageSends++;
    throw StateError('Readiness must not send Chat content');
  }
}

class _RecoveryChatExchange extends Fake
    implements ConsensusAttestationExchangeService {
  final requests = <String>[];
  var pending = Completer<ConsensusAttestationExchangeResult>();

  @override
  Future<ConsensusAttestationExchangeResult> ensureForPeer(String peer) {
    requests.add(peer);
    return pending.future;
  }
}

class _RecoveryChatChecks extends Fake implements ManualConsensusCheckService {
  final String peer;
  bool ready = false;
  int reads = 0;

  _RecoveryChatChecks(this.peer);

  @override
  Future<List<ConsensusPreview>> loadAttestedChecks() async {
    reads++;
    return [
      ConsensusPreview(
        peerHex: peer,
        peerLabel: '',
        invitationCount: 0,
        relationshipCount: 1,
        hashHex: '',
        canonicalJson: '',
        blockingFacts:
            ready
                ? []
                : [
                  const ConsensusBlockingFact(code: 'pair_attestation_missing'),
                ],
      ),
    ];
  }
}

class _RecoveryChatCache extends Fake implements CapsuleChatDeliveryService {
  @override
  Future<List<CapsuleChatInboxMessage>> loadCachedMessagesDurably() async => [];

  @override
  Future<Map<String, int>> unreadCachedMessageCountsByPeer() async => {};
}

class _RecoveryChatLabels extends Fake implements CapsuleContactLabelStore {
  @override
  Future<Map<String, String>> load() async => {};
}
