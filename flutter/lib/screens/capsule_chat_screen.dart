import 'dart:async';

import 'package:flutter/material.dart';

import '../models/capsule_chat_models.dart';
import '../models/consensus_models.dart';
import '../services/capsule_passive_receive_coordinator.dart';
import '../services/app_runtime_service.dart';
import '../utils/peer_identity_format.dart';
import '../widgets/capsule_chat_conversation_workspace.dart';

@visibleForTesting
Future<CapsuleChatDeliveryReceiveResult>
projectCachedMessagesBeforeChatRefresh({
  required Future<List<CapsuleChatInboxMessage>> Function() loadCachedMessages,
  required Future<CapsuleChatDeliveryReceiveResult> Function() refresh,
  required void Function(List<CapsuleChatInboxMessage> messages)
  projectMessages,
}) async {
  Future<void> projectCachedMessages() async {
    projectMessages(await loadCachedMessages());
  }

  await projectCachedMessages();
  try {
    return await refresh();
  } finally {
    await projectCachedMessages();
  }
}

@visibleForTesting
String chatWorkspaceNoticeForSendResult(CapsuleChatSendResult result) {
  return switch (result.status) {
    CapsuleChatSendStatus.sent => 'Accepted by transport',
    CapsuleChatSendStatus.syncing =>
      'Securing this conversation. Your draft is preserved; press Send again when it is ready.',
    CapsuleChatSendStatus.blocked =>
      'This conversation is not ready yet. Your draft is preserved.',
    CapsuleChatSendStatus.rejected => result.message,
    CapsuleChatSendStatus.failed => result.message,
    CapsuleChatSendStatus.capsuleChanged => result.message,
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

class CapsuleChatScreen extends StatefulWidget {
  final AppRuntimeService runtime;
  final String? initialPeerHex;
  final VoidCallback? onOpenInvitations;
  final VoidCallback? onUnreadChanged;

  const CapsuleChatScreen({
    super.key,
    required this.runtime,
    this.initialPeerHex,
    this.onOpenInvitations,
    this.onUnreadChanged,
  });

  @override
  State<CapsuleChatScreen> createState() => _CapsuleChatScreenState();
}

class _CapsuleChatScreenState extends State<CapsuleChatScreen> {
  final TextEditingController _peerController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _notice;
  bool _noticeIsError = false;
  bool _sending = false;
  bool _refreshing = false;
  String? _selectedPeerLabel;
  Map<String, String> _contactLabels = const <String, String>{};
  List<ConsensusPreview> _contacts = const <ConsensusPreview>[];
  Map<String, int> _unreadByPeer = const <String, int>{};
  final Map<String, String> _draftByPeer = <String, String>{};
  List<CapsuleChatInboxMessage> _messages = const <CapsuleChatInboxMessage>[];
  int _droppedByConsensus = 0;
  int _deferredByConsensus = 0;

  late final String? _owner;
  late final _chatDelivery = widget.runtime.buildCapsuleChatDeliveryService();
  late final _manualChecks = widget.runtime.buildManualConsensusCheckService();
  late final _attestationExchange =
      widget.runtime.buildConsensusAttestationExchangeService();
  late final _contactLabelsStore =
      widget.runtime.buildCapsuleContactLabelStore();

  bool get _ownsCapsule =>
      mounted &&
      _owner != null &&
      widget.runtime.activeCapsuleRootHex() == _owner;

  @override
  void initState() {
    super.initState();
    _owner = widget.runtime.activeCapsuleRootHex();
    widget.runtime.passiveReceive.addResultListener(
      _handlePassiveReceiveResult,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    widget.runtime.passiveReceive.removeResultListener(
      _handlePassiveReceiveResult,
    );
    _peerController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handlePassiveReceiveResult(
    CapsulePassiveReceiveResult result,
  ) async {
    final activeCapsule =
        widget.runtime.activeCapsuleRootHex()?.trim().toLowerCase();
    if (!_ownsCapsule ||
        activeCapsule == null ||
        activeCapsule != result.capsuleHex) {
      return;
    }
    if (result.chat.messages.isEmpty) {
      if (result.attestations.storedCount > 0) await _refreshContacts();
      return;
    }

    try {
      final cachedMessages = await _chatDelivery.loadCachedMessagesDurably();
      final currentCapsule =
          widget.runtime.activeCapsuleRootHex()?.trim().toLowerCase();
      if (!mounted || currentCapsule != result.capsuleHex) return;
      final retained = cachedMessages;
      setState(() {
        _messages = retained;
        _droppedByConsensus = result.chat.droppedByConsensus;
        _deferredByConsensus = result.chat.deferredByConsensus;
      });
      unawaited(_markMessagesRead(_messagesForSelectedPeer(retained)));
      await _refreshContacts();
    } catch (_) {
      return;
    }
  }

  Future<void> _initialize() async {
    if (!_ownsCapsule) return;
    await _refreshContacts();
    if (!_ownsCapsule) return;
    final peerHex = widget.initialPeerHex;
    if (peerHex != null) _selectPeer(peerHex);
    await _refreshInbox(silentWhenEmpty: true);
  }

  Future<void> _refreshContacts() async {
    try {
      final contacts = await _manualChecks.loadAttestedChecks();
      final labels = await _contactLabelsStore.load();
      final unread = await _chatDelivery.unreadCachedMessageCountsByPeer();
      if (!_ownsCapsule) return;
      setState(() {
        _contacts = contacts;
        _contactLabels = labels;
        _selectedPeerLabel =
            labels[PeerIdentityFormat.capsuleKeyFromRootHex(
              _peerController.text,
            )];
        _unreadByPeer = unread;
      });
    } catch (_) {
      if (!_ownsCapsule) return;
      setState(() {
        _notice =
            'Contacts are unavailable. Saved conversation remains available.';
        _noticeIsError = true;
      });
    }
  }

  Future<String?> _selectContact() async {
    final checks = await _manualChecks.loadAttestedChecks();
    final labels = await _contactLabelsStore.load();
    if (!mounted || !_ownsCapsule) return null;
    final candidates =
        checks.where((peer) => peer.relationshipCount > 0).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accept an invitation to start a conversation.'),
        ),
      );
      return null;
    }
    if (candidates.length == 1) return candidates.first.peerHex;

    var unreadByPeer = const <String, int>{};
    var timeline = _messages;
    try {
      unreadByPeer = await _chatDelivery.unreadCachedMessageCountsByPeer();
      timeline = await _chatDelivery.loadCachedMessagesDurably();
    } catch (_) {}
    if (!mounted || !_ownsCapsule) return null;
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
    if (!_ownsCapsule || selectedPeerHex == null || selectedPeerHex.isEmpty) {
      return;
    }
    final labels = await _contactLabelsStore.load();
    if (!_ownsCapsule) return;
    _selectPeer(selectedPeerHex, labels: labels);
  }

  void _selectPeer(String peerHex, {Map<String, String>? labels}) {
    if (_sending || !_ownsCapsule) return;
    final previousPeer = _peerController.text.trim().toLowerCase();
    if (previousPeer.isNotEmpty) {
      _draftByPeer[previousPeer] = _messageController.text;
    }
    final nextPeer = peerHex.trim().toLowerCase();
    final currentLabels = labels ?? _contactLabels;
    setState(() {
      _peerController.text = nextPeer;
      _messageController.text = _draftByPeer[nextPeer] ?? '';
      _contactLabels = currentLabels;
      _selectedPeerLabel =
          currentLabels[PeerIdentityFormat.capsuleKeyFromRootHex(nextPeer)];
      _notice = null;
      _noticeIsError = false;
    });
    unawaited(_markMessagesRead(_messagesForSelectedPeer(_messages)));
    if (nextPeer.isNotEmpty) unawaited(_secureSelectedPeer(nextPeer));
  }

  Future<void> _secureSelectedPeer(String peerHex) async {
    final owner = widget.runtime.activeCapsuleRootHex();
    if (owner == null) return;
    var failed = false;
    try {
      await _attestationExchange.ensureForPeer(peerHex);
    } catch (_) {
      failed = true;
    }
    if (!mounted ||
        owner != widget.runtime.activeCapsuleRootHex() ||
        peerHex != _peerController.text) {
      return;
    }
    if (failed) {
      setState(() {
        _notice =
            'Could not secure this conversation. Select it again to retry.';
        _noticeIsError = true;
      });
    }
    await _refreshContacts();
  }

  Future<void> _send() async {
    if (_sending || !_ownsCapsule) return;
    setState(() {
      _sending = true;
      _notice = 'Sending...';
      _noticeIsError = false;
    });

    try {
      final result = await widget.runtime.sendChatMessage(
        peerHex: _peerController.text,
        messageText: _messageController.text,
      );
      if (!_ownsCapsule) return;
      setState(() {
        _notice = chatWorkspaceNoticeForSendResult(result);
        _noticeIsError =
            result.status != CapsuleChatSendStatus.sent &&
            result.status != CapsuleChatSendStatus.syncing;
        if (result.isSuccess) _messageController.clear();
      });
      if (result.isSuccess) await _refreshInbox(silentWhenEmpty: true);
    } finally {
      if (_ownsCapsule) {
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
      final capsuleHex = widget.runtime.activeCapsuleRootHex();
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
        loadCachedMessages: _chatDelivery.loadCachedMessagesDurably,
        refresh:
            () => widget.runtime.passiveReceive
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
      if (!_ownsCapsule) return;
      if (result.code < 0) {
        setState(() {
          _notice =
              'Could not check for new messages. Saved conversation remains available.';
          _noticeIsError = true;
        });
        return;
      }

      final cachedMessages = await _chatDelivery.loadCachedMessagesDurably();
      if (!_ownsCapsule) return;
      final retained = cachedMessages;
      setState(() {
        _droppedByConsensus = result.droppedByConsensus;
        _deferredByConsensus = result.deferredByConsensus;
        _messages = List<CapsuleChatInboxMessage>.unmodifiable(retained);
        if (!silentWhenEmpty || result.messages.isNotEmpty) {
          _notice =
              result.messages.isEmpty
                  ? 'Conversation is up to date.'
                  : 'New messages: ${result.messages.length}';
          _noticeIsError = false;
        }
      });
      await _refreshContacts();
    } catch (_) {
      if (_ownsCapsule) {
        setState(() {
          _notice = 'Chat history is unavailable. Try again.';
          _noticeIsError = true;
        });
      }
    } finally {
      if (_ownsCapsule) {
        setState(() {
          _refreshing = false;
        });
      } else {
        _refreshing = false;
      }
    }
  }

  void _projectMessages(List<CapsuleChatInboxMessage> messages) {
    if (!_ownsCapsule) return;
    setState(() {
      _messages = messages;
    });
    unawaited(_markMessagesRead(_messagesForSelectedPeer(messages)));
  }

  Future<void> _markMessagesRead(List<CapsuleChatInboxMessage> messages) async {
    if (messages.isEmpty || !_ownsCapsule) return;
    try {
      await _chatDelivery.markCachedMessagesRead(messages);
    } catch (_) {
      return;
    }
    if (!_ownsCapsule) return;
    widget.onUnreadChanged?.call();
    try {
      final unread = await _chatDelivery.unreadCachedMessageCountsByPeer();
      if (_ownsCapsule) setState(() => _unreadByPeer = unread);
    } catch (_) {}
  }

  List<CapsuleChatInboxMessage> _messagesForSelectedPeer(
    List<CapsuleChatInboxMessage> messages,
  ) => chatMessagesForPeer(messages, _peerController.text);

  Future<void> _configureCache() async {
    final capsule = widget.runtime.activeCapsuleRootHex();
    try {
      final bytes = await _chatDelivery.loadCacheBudgetBytes();
      final retainedCount =
          (await _chatDelivery.loadCachedMessagesDurably()).length;
      if (!mounted ||
          !_ownsCapsule ||
          capsule != widget.runtime.activeCapsuleRootHex()) {
        return;
      }
      var budgetText = (bytes / 1000000).toString().replaceFirst(
        RegExp(r'\.0$'),
        '',
      );
      final form = GlobalKey<FormState>();
      final selected = await showDialog<int>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Local message cache'),
              content: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared across conversations in this Capsule. Oldest completed '
                      'messages leave this device when the budget is reached. '
                      'Unresolved sends are kept separately until their outcome is known. '
                      'Evicted messages may not be recoverable.',
                    ),
                    const SizedBox(height: 16),
                    Text('Retained messages: $retainedCount'),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: budgetText,
                      onChanged: (value) => budgetText = value,
                      decoration: const InputDecoration(
                        labelText: 'Cache budget (MB)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final mb = double.tryParse(value?.trim() ?? '');
                        return mb == null || !mb.isFinite || mb < 0.001
                            ? 'Enter at least 0.001 MB (1 KB)'
                            : null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    Navigator.pop(
                      context,
                      (double.parse(budgetText.trim()) * 1000000).round(),
                    );
                  },
                  child: const Text('Apply budget'),
                ),
              ],
            ),
      );
      if (selected == null ||
          !mounted ||
          capsule != widget.runtime.activeCapsuleRootHex()) {
        return;
      }
      await _chatDelivery.setCacheBudgetBytes(selected);
      final retained = await _chatDelivery.loadCachedMessagesDurably();
      if (!mounted ||
          !_ownsCapsule ||
          capsule != widget.runtime.activeCapsuleRootHex()) {
        return;
      }
      _projectMessages(retained);
      setState(() {
        _notice = 'Local message cache budget saved.';
        _noticeIsError = false;
      });
    } catch (_) {
      if (!_ownsCapsule) return;
      setState(() {
        _notice = 'Could not apply the local message cache budget.';
        _noticeIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = CapsuleChatConversationWorkspace(
      sending: _sending,
      checkingForMessages: _refreshing,
      notice: _notice,
      noticeIsError: _noticeIsError,
      messages: _messages,
      hiddenMessageCount: _droppedByConsensus,
      deferredMessageCount: _deferredByConsensus,
      peerController: _peerController,
      selectedPeerLabel: _selectedPeerLabel,
      canCompose: _contacts.any(
        (contact) =>
            contact.peerHex == _peerController.text &&
            contact.relationshipCount > 0,
      ),
      selectedPeerIsSignable: _contacts.any(
        (contact) =>
            contact.peerHex == _peerController.text && contact.isSignable,
      ),
      contactLabels: _contactLabels,
      messageController: _messageController,
      onInputChanged: () => setState(() {}),
      onChooseContact: _chooseContact,
      onRetryReceive: _refreshInbox,
      onSend: _send,
      loadCachedMessages: _chatDelivery.loadCachedMessagesDurably,
      onMessagesProjected: _projectMessages,
    );
    if (!_ownsCapsule) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Reopen Chat for the active Capsule.')),
      );
    }
    final conversations = CapsuleChatContactSidebar(
      contacts: _contacts,
      messages: _messages,
      contactLabels: _contactLabels,
      unreadByPeer: _unreadByPeer,
      selectedPeerHex: _peerController.text,
      enabled: !_sending,
      refreshing: _refreshing,
      onSelect: _selectPeer,
      onRefresh: _refreshInbox,
      onOpenInvitations:
          widget.onOpenInvitations == null
              ? null
              : () {
                Navigator.of(context).pop();
                widget.onOpenInvitations!();
              },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final hasPeer = _peerController.text.isNotEmpty;
        final returnToList =
            compact && hasPeer && widget.initialPeerHex == null;
        return PopScope<void>(
          canPop: !returnToList,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && returnToList) _selectPeer('');
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Chat'),
              leading:
                  returnToList
                      ? BackButton(onPressed: () => _selectPeer(''))
                      : null,
              actions: [
                IconButton(
                  onPressed: _sending ? null : _configureCache,
                  tooltip: 'Local message cache',
                  icon: const Icon(Icons.storage_outlined),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 20),
                child:
                    compact
                        ? (hasPeer ? workspace : conversations)
                        : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: Row(
                              children: [
                                SizedBox(width: 260, child: conversations),
                                const SizedBox(width: 14),
                                Expanded(child: workspace),
                              ],
                            ),
                          ),
                        ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CapsuleChatContactSidebar extends StatelessWidget {
  final List<ConsensusPreview> contacts;
  final List<CapsuleChatInboxMessage> messages;
  final Map<String, String> contactLabels;
  final Map<String, int> unreadByPeer;
  final String selectedPeerHex;
  final bool enabled;
  final bool refreshing;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenInvitations;

  const CapsuleChatContactSidebar({
    super.key,
    required this.contacts,
    required this.messages,
    required this.contactLabels,
    required this.unreadByPeer,
    required this.selectedPeerHex,
    required this.enabled,
    required this.refreshing,
    required this.onSelect,
    required this.onRefresh,
    this.onOpenInvitations,
  });

  @override
  Widget build(BuildContext context) {
    final latestByPeer = <String, CapsuleChatInboxMessage>{};
    for (final message in messages) {
      final peer =
          (message.direction == CapsuleChatMessageDirection.outgoing
                  ? message.toHex
                  : message.fromHex)
              ?.trim()
              .toLowerCase();
      if (peer == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(peer)) continue;
      final previous = latestByPeer[peer];
      if (previous == null || message.timestampMs > previous.timestampMs) {
        latestByPeer[peer] = message;
      }
    }
    final byPeer = <String, ConsensusPreview>{
      for (final contact in contacts) contact.peerHex: contact,
    };
    final ordered = orderChatConversationPeerHexes(
      peerHexes: {
        for (final contact in contacts)
          if (contact.relationshipCount > 0) contact.peerHex,
        ...latestByPeer.keys,
      },
      signableByPeer: <String, bool>{
        for (final contact in contacts) contact.peerHex: contact.isSignable,
      },
      unreadByPeer: unreadByPeer,
      latestTimestampByPeer: latestChatMessageTimestampByPeer(messages),
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Conversations',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Check for messages',
                  onPressed: refreshing ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2B3846)),
          Expanded(
            child:
                ordered.isEmpty
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Accept an invitation to start a conversation.',
                              textAlign: TextAlign.center,
                            ),
                            if (onOpenInvitations != null)
                              TextButton(
                                onPressed: onOpenInvitations,
                                child: const Text('Open Invitations'),
                              ),
                          ],
                        ),
                      ),
                    )
                    : ListView.builder(
                      itemCount: ordered.length,
                      itemBuilder: (context, index) {
                        final peerHex = ordered[index];
                        final ready = byPeer[peerHex]?.isSignable ?? false;
                        final unread = unreadByPeer[peerHex] ?? 0;
                        final latest = latestByPeer[peerHex];
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            selected: peerHex == selectedPeerHex,
                            leading: CircleAvatar(
                              backgroundColor:
                                  ready
                                      ? const Color(0xFF2D4651)
                                      : const Color(0xFF493A2A),
                              child: Icon(
                                ready
                                    ? Icons.person_rounded
                                    : Icons.lock_outline_rounded,
                              ),
                            ),
                            title: Text(
                              PeerIdentityFormat.capsuleLabelFromRootHex(
                                peerHex,
                                localLabel:
                                    contactLabels[PeerIdentityFormat.capsuleKeyFromRootHex(
                                      peerHex,
                                    )],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              latest?.messageText ??
                                  (ready
                                      ? 'Ready to chat'
                                      : 'Needs verification'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                unread > 0 ? Badge.count(count: unread) : null,
                            onTap: enabled ? () => onSelect(peerHex) : null,
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
