import 'dart:async';

import 'package:flutter/material.dart';

import '../models/capsule_chat_models.dart';
import '../models/plugin_host_api_models.dart';
import '../services/capsule_passive_receive_coordinator.dart';
import '../services/plugin_runtime_module_service.dart';
import '../utils/peer_identity_format.dart';
import '../widgets/capsule_chat_conversation_workspace.dart';

@visibleForTesting
Future<CapsuleChatDeliveryReceiveResult>
projectCachedMessagesBeforeChatRefresh({
  required List<CapsuleChatInboxMessage> currentMessages,
  required Future<List<CapsuleChatInboxMessage>> Function() loadCachedMessages,
  required Future<CapsuleChatDeliveryReceiveResult> Function() refresh,
  required void Function(List<CapsuleChatInboxMessage> messages)
  projectMessages,
}) async {
  Future<void> projectCachedMessages() async {
    final byId = <String, CapsuleChatInboxMessage>{
      for (final message in currentMessages) message.id: message,
      for (final message in await loadCachedMessages()) message.id: message,
    };
    final merged =
        byId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    projectMessages(List<CapsuleChatInboxMessage>.unmodifiable(merged));
  }

  await projectCachedMessages();
  try {
    return await refresh();
  } finally {
    await projectCachedMessages();
  }
}

@visibleForTesting
List<CapsuleChatInboxMessage> chatMessagesForPeer(
  List<CapsuleChatInboxMessage> messages,
  String peerHex,
) {
  final normalizedPeer = peerHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedPeer)) return messages;
  return messages
      .where(
        (message) =>
            (message.direction == CapsuleChatMessageDirection.outgoing
                ? message.toHex
                : message.fromHex) ==
            normalizedPeer,
      )
      .toList(growable: false);
}

@visibleForTesting
String chatWorkspaceNoticeForSendResult(PluginChatSendResult result) {
  return switch (result.status) {
    PluginChatSendStatus.sent => 'Accepted by transport',
    PluginChatSendStatus.syncing =>
      'Securing this conversation. Your draft is preserved; press Send again when it is ready.',
    PluginChatSendStatus.blocked =>
      'This conversation is not ready yet. Your draft is preserved.',
    PluginChatSendStatus.rejected => result.message,
    PluginChatSendStatus.failed => result.message,
    PluginChatSendStatus.capsuleChanged => result.message,
  };
}

@visibleForTesting
Map<String, int> latestChatMessageTimestampByPeer(
  Iterable<CapsuleChatInboxMessage> messages,
) {
  final latestByPeer = <String, int>{};
  for (final message in messages) {
    final peerHex =
        (message.direction == CapsuleChatMessageDirection.outgoing
                ? message.toHex
                : message.fromHex)
            ?.trim()
            .toLowerCase();
    if (peerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
      continue;
    }
    final previous = latestByPeer[peerHex];
    if (previous == null || message.timestampMs > previous) {
      latestByPeer[peerHex] = message.timestampMs;
    }
  }
  return Map<String, int>.unmodifiable(latestByPeer);
}

@visibleForTesting
List<String> orderChatConversationPeerHexes({
  required Iterable<String> peerHexes,
  required Map<String, bool> signableByPeer,
  required Map<String, int> unreadByPeer,
  required Map<String, int> latestTimestampByPeer,
}) {
  final ordered = peerHexes.toList(growable: false);
  ordered.sort((left, right) {
    final unreadOrder = (unreadByPeer[right] ?? 0).compareTo(
      unreadByPeer[left] ?? 0,
    );
    if (unreadOrder != 0) return unreadOrder;
    final recentOrder = (latestTimestampByPeer[right] ?? 0).compareTo(
      latestTimestampByPeer[left] ?? 0,
    );
    if (recentOrder != 0) return recentOrder;
    final signableOrder = ((signableByPeer[right] ?? false) ? 1 : 0).compareTo(
      (signableByPeer[left] ?? false) ? 1 : 0,
    );
    if (signableOrder != 0) return signableOrder;
    return left.compareTo(right);
  });
  return List<String>.unmodifiable(ordered);
}

class CapsuleChatPluginScreen extends StatefulWidget {
  final PluginRuntimeModule module;
  final VoidCallback? onUnreadChanged;

  const CapsuleChatPluginScreen({
    super.key,
    required this.module,
    this.onUnreadChanged,
  });

  @override
  State<CapsuleChatPluginScreen> createState() =>
      _CapsuleChatPluginScreenState();
}

class _CapsuleChatPluginScreenState extends State<CapsuleChatPluginScreen> {
  final TextEditingController _peerController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  PluginHostApiResponse? _lastResponse;
  String? _notice;
  bool _noticeIsError = false;
  bool _sending = false;
  bool _refreshing = false;
  String? _selectedPeerLabel;
  Map<String, String> _contactLabels = const <String, String>{};
  List<CapsuleChatInboxMessage> _messages = const <CapsuleChatInboxMessage>[];
  int _droppedByConsensus = 0;
  int _deferredByConsensus = 0;

  PluginRuntimeModule get _module => widget.module;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _peerController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final labels = await _module.contactLabels.load();
    if (!mounted) return;
    setState(() {
      _contactLabels = labels;
    });
    await _refreshInbox(silentWhenEmpty: true);
  }

  Future<String?> _selectContact() async {
    final checks = await _module.manualChecks.loadAttestedChecks();
    final labels = await _module.contactLabels.load();
    if (!mounted) return null;
    if (checks.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No trusted contacts yet. Create at least one relationship first.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return null;
    }

    final candidates = checks.toList();
    if (candidates.length == 1) return candidates.first.peerHex;

    var unreadByPeer = const <String, int>{};
    var timeline = _messages;
    try {
      unreadByPeer =
          await _module.chatDelivery.unreadCachedMessageCountsByPeer();
      timeline = await _module.chatDelivery.loadCachedMessagesDurably();
    } catch (_) {}
    if (!mounted) return null;
    final peerOrder = orderChatConversationPeerHexes(
      peerHexes: candidates.map((check) => check.peerHex),
      signableByPeer: <String, bool>{
        for (final check in candidates) check.peerHex: check.isSignable,
      },
      unreadByPeer: unreadByPeer,
      latestTimestampByPeer: latestChatMessageTimestampByPeer(timeline),
    );
    final rankByPeer = <String, int>{
      for (var index = 0; index < peerOrder.length; index += 1)
        peerOrder[index]: index,
    };
    candidates.sort(
      (left, right) => (rankByPeer[left.peerHex] ?? peerOrder.length).compareTo(
        rankByPeer[right.peerHex] ?? peerOrder.length,
      ),
    );

    return showModalBottomSheet<String>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    'New conversation',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Choose a trusted Capsule.'),
                ),
                for (final check in candidates)
                  ListTile(
                    leading: Icon(
                      check.isSignable ? Icons.verified_rounded : Icons.warning,
                      color: check.isSignable ? Colors.green : Colors.orange,
                    ),
                    title: Text(
                      PeerIdentityFormat.capsuleLabelFromRootHex(
                        check.peerHex,
                        localLabel:
                            labels[PeerIdentityFormat.capsuleKeyFromRootHex(
                              check.peerHex,
                            )],
                      ),
                    ),
                    subtitle: Text(
                      '${check.isSignable ? 'Ready to chat' : 'Select to secure this conversation'}\n'
                      '${PeerIdentityFormat.capsuleIdentityHintFromRootHex(check.peerHex)}',
                    ),
                    trailing:
                        (unreadByPeer[check.peerHex] ?? 0) > 0
                            ? Badge.count(
                              count: unreadByPeer[check.peerHex] ?? 0,
                            )
                            : check.isSignable
                            ? const Text(
                              'Ready',
                              style: TextStyle(color: Colors.green),
                            )
                            : const Text(
                              'Needs verification',
                              style: TextStyle(color: Colors.orange),
                            ),
                    onTap: () => Navigator.of(sheetContext).pop(check.peerHex),
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _chooseContact() async {
    final selectedPeerHex = await _selectContact();
    if (!mounted || selectedPeerHex == null || selectedPeerHex.isEmpty) return;
    final peerKey = PeerIdentityFormat.capsuleKeyFromRootHex(selectedPeerHex);
    final labels = await _module.contactLabels.load();
    if (!mounted) return;
    setState(() {
      _peerController.text = selectedPeerHex;
      _contactLabels = labels;
      _selectedPeerLabel = labels[peerKey];
      _lastResponse = null;
      _notice = null;
      _noticeIsError = false;
    });
  }

  Future<void> _send() async {
    if (_sending || !mounted) return;
    setState(() {
      _sending = true;
      _notice = 'Sending...';
      _noticeIsError = false;
    });

    try {
      final result = await _module.sendChatMessage(
        peerHex: _peerController.text,
        messageText: _messageController.text,
      );
      if (!mounted) return;
      setState(() {
        _lastResponse = result.hostResponse;
        _notice = chatWorkspaceNoticeForSendResult(result);
        _noticeIsError =
            result.status != PluginChatSendStatus.sent &&
            result.status != PluginChatSendStatus.syncing;
        if (result.isSuccess) _messageController.clear();
      });
      if (result.isSuccess) await _refreshInbox(silentWhenEmpty: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _refreshInbox({bool silentWhenEmpty = false}) async {
    if (_refreshing) {
      if (!silentWhenEmpty && mounted) {
        setState(() {
          _notice = 'Inbox refresh already in progress';
          _noticeIsError = true;
        });
      }
      return;
    }
    _refreshing = true;
    if (!silentWhenEmpty && mounted) {
      setState(() {
        _notice = 'Checking for messages...';
        _noticeIsError = false;
      });
    }

    try {
      final stopwatch = Stopwatch()..start();
      final capsuleHex = _module.activeCapsuleRootHex();
      if (capsuleHex == null) {
        if (mounted) {
          setState(() {
            _notice = 'Active capsule identity is unavailable';
            _noticeIsError = true;
          });
        }
        return;
      }
      final result = await projectCachedMessagesBeforeChatRefresh(
        currentMessages: _messages,
        loadCachedMessages: _module.chatDelivery.loadCachedMessagesDurably,
        refresh:
            () => _module.passiveReceive
                .trigger(
                  capsuleHex: capsuleHex,
                  reason:
                      silentWhenEmpty
                          ? CapsulePassiveReceiveReason.screenActivation
                          : CapsulePassiveReceiveReason.manual,
                  quick: silentWhenEmpty,
                  manualRetry: !silentWhenEmpty,
                )
                .then((value) => value.chat),
        projectMessages: _projectMessages,
      );
      stopwatch.stop();
      await _module.uiLog.log(
        'chat.fetch.result',
        'code=${result.code} elapsedMs=${stopwatch.elapsedMilliseconds} chat=${result.messages.length} trade=${result.tradeSignals.length} cmd=${result.executionDecisions.length} receipt=${result.executionReceipts.length} dropped=${result.droppedByConsensus} deferred=${result.deferredByConsensus}'
            '${result.errorMessage == null ? "" : " error=${result.errorMessage}"}',
      );
      if (!mounted) return;
      if (result.code < 0) {
        setState(() {
          _notice =
              'Could not check for new messages. Saved conversation remains available.';
          _noticeIsError = true;
        });
        return;
      }

      final cachedMessages =
          await _module.chatDelivery.loadCachedMessagesDurably();
      if (!mounted) return;
      final byId = <String, CapsuleChatInboxMessage>{
        for (final message in _messages) message.id: message,
        for (final message in cachedMessages) message.id: message,
        for (final message in result.messages) message.id: message,
      };
      final merged =
          byId.values.toList()
            ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      setState(() {
        _droppedByConsensus = result.droppedByConsensus;
        _deferredByConsensus = result.deferredByConsensus;
        _messages = List<CapsuleChatInboxMessage>.unmodifiable(merged);
        if (!silentWhenEmpty || result.messages.isNotEmpty) {
          _notice =
              result.messages.isEmpty
                  ? 'Conversation is up to date.'
                  : 'New messages: ${result.messages.length}';
          _noticeIsError = false;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = 'Chat history is unavailable: $error';
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      } else {
        _refreshing = false;
      }
    }
  }

  void _projectMessages(List<CapsuleChatInboxMessage> messages) {
    if (!mounted) return;
    setState(() {
      _messages = messages;
    });
    unawaited(_markMessagesRead(_messagesForSelectedPeer(messages)));
  }

  Future<void> _markMessagesRead(List<CapsuleChatInboxMessage> messages) async {
    if (messages.isEmpty) return;
    try {
      await _module.chatDelivery.markCachedMessagesRead(messages);
    } catch (_) {
      return;
    }
    widget.onUnreadChanged?.call();
  }

  List<CapsuleChatInboxMessage> _messagesForSelectedPeer(
    List<CapsuleChatInboxMessage> messages,
  ) => chatMessagesForPeer(messages, _peerController.text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsule Chat'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Consensus-bound plugin workspace',
              style: TextStyle(color: Color(0xFF9CA7B5), fontSize: 12),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CapsuleChatConversationWorkspace(
                sending: _sending,
                checkingForMessages: _refreshing,
                lastResponse: _lastResponse,
                notice: _notice,
                noticeIsError: _noticeIsError,
                messages: _messages,
                hiddenMessageCount: _droppedByConsensus,
                deferredMessageCount: _deferredByConsensus,
                peerController: _peerController,
                selectedPeerLabel: _selectedPeerLabel,
                contactLabels: _contactLabels,
                messageController: _messageController,
                onInputChanged: () => setState(() {}),
                onChooseContact: _chooseContact,
                onRetryReceive: _refreshInbox,
                onSend: _send,
                loadCachedMessages:
                    _module.chatDelivery.loadCachedMessagesDurably,
                onMessagesProjected:
                    (messages) => unawaited(
                      _markMessagesRead(_messagesForSelectedPeer(messages)),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
