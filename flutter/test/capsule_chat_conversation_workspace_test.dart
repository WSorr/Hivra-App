import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/capsule_chat_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/screens/wasm_plugins_screen.dart';
import 'package:hivra_app/services/plugin_runtime_module_service.dart';
import 'package:hivra_app/widgets/capsule_chat_conversation_workspace.dart';

void main() {
  const peerHex =
      '2222222222222222222222222222222222222222222222222222222222222222';
  const capsuleHex =
      '1111111111111111111111111111111111111111111111111111111111111111';

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

  testWidgets('keeps runtime details collapsed by default', (tester) async {
    final peerController = TextEditingController(text: peerHex);
    final messageController = TextEditingController();
    addTearDown(peerController.dispose);
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      _testApp(
        peerController: peerController,
        messageController: messageController,
        lastResponse: _response,
      ),
    );

    expect(find.text('Technical details'), findsOneWidget);
    expect(
      find.textContaining('Method: post_capsule_chat_message'),
      findsNothing,
    );

    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Method: post_capsule_chat_message'),
      findsOneWidget,
    );
  });

  testWidgets(
    'projects a passive cached message while the workspace remains open',
    (tester) async {
      final peerController = TextEditingController(text: peerHex);
      final messageController = TextEditingController();
      addTearDown(peerController.dispose);
      addTearDown(messageController.dispose);
      var cachedMessages = const <CapsuleChatInboxMessage>[];
      var receiveRetries = 0;
      var projectionCount = 0;

      await tester.pumpWidget(
        _testApp(
          peerController: peerController,
          messageController: messageController,
          onRetryReceive: () async => receiveRetries += 1,
          loadCachedMessages: () async => cachedMessages,
          onMessagesProjected: (_) => projectionCount += 1,
          cacheProjectionInterval: const Duration(milliseconds: 50),
        ),
      );
      await tester.pump();
      expect(find.text('passive while open'), findsNothing);

      cachedMessages = const <CapsuleChatInboxMessage>[
        CapsuleChatInboxMessage(
          id: 'passive',
          fromHex: peerHex,
          messageText: 'passive while open',
          createdAtUtc: '2026-08-14T12:02:00Z',
          envelopeHashHex: 'cc',
          timestampMs: 3,
        ),
      ];
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('passive while open'), findsOneWidget);
      expect(receiveRetries, 0);
      expect(projectionCount, 1);
    },
  );

  test('send notices preserve product truth and the draft contract', () {
    expect(
      chatWorkspaceNoticeForSendResult(
        const PluginChatSendResult(
          status: PluginChatSendStatus.sent,
          message: 'Message sent',
        ),
      ),
      'Accepted by transport',
    );
    expect(
      chatWorkspaceNoticeForSendResult(
        const PluginChatSendResult(
          status: PluginChatSendStatus.syncing,
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
  PluginHostApiResponse? lastResponse,
  String? notice,
  bool noticeIsError = false,
  Future<void> Function()? onRetryReceive,
  Future<List<CapsuleChatInboxMessage>> Function()? loadCachedMessages,
  ValueChanged<List<CapsuleChatInboxMessage>>? onMessagesProjected,
  Duration cacheProjectionInterval = const Duration(seconds: 1),
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 700,
          height: 680,
          child: CapsuleChatConversationWorkspace(
            sending: false,
            checkingForMessages: false,
            lastResponse: lastResponse,
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

const _response = PluginHostApiResponse(
  status: PluginHostApiStatus.executed,
  pluginId: 'capsule-chat',
  method: 'post_capsule_chat_message',
  executionSource: 'external_package',
  executionPackageId: 'capsule-chat',
  executionPackageVersion: '1',
  executionPackageKind: 'wasm',
  executionPackageDigestHex: 'aa',
  executionContractKind: 'chat',
  executionRuntimeMode: 'wasm',
  executionRuntimeAbi: 'hivra_host_abi_v2',
  executionRuntimeEntryExport: 'hivra_evaluate_v1',
  executionRuntimeModulePath: 'chat.wasm',
  executionRuntimeModuleSelection: 'manifest_module_path',
  executionRuntimeModuleDigestHex: 'bb',
  executionRuntimeInvokeDigestHex: 'cc',
  executionCapabilities: <String>[],
  errorCode: null,
  errorMessage: null,
  blockingFacts: <Never>[],
  result: <String, dynamic>{'envelope_hash_hex': 'dd'},
  canonicalJson: '{}',
  responseHashHex: 'ee',
);
