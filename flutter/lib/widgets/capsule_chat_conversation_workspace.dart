import 'package:flutter/material.dart';

import '../models/capsule_chat_models.dart';
import '../models/plugin_host_api_models.dart';
import '../utils/peer_identity_format.dart';

class CapsuleChatConversationWorkspace extends StatelessWidget {
  final bool sending;
  final bool checkingForMessages;
  final PluginHostApiResponse? lastResponse;
  final String? notice;
  final bool noticeIsError;
  final List<CapsuleChatInboxMessage> messages;
  final int hiddenMessageCount;
  final int deferredMessageCount;
  final TextEditingController peerController;
  final String? selectedPeerLabel;
  final Map<String, String> contactLabels;
  final TextEditingController messageController;
  final VoidCallback onInputChanged;
  final Future<void> Function() onChooseContact;
  final Future<void> Function() onRetryReceive;
  final Future<void> Function() onSend;

  const CapsuleChatConversationWorkspace({
    super.key,
    required this.sending,
    required this.checkingForMessages,
    required this.lastResponse,
    required this.notice,
    required this.noticeIsError,
    required this.messages,
    required this.hiddenMessageCount,
    required this.deferredMessageCount,
    required this.peerController,
    required this.selectedPeerLabel,
    required this.contactLabels,
    required this.messageController,
    required this.onInputChanged,
    required this.onChooseContact,
    required this.onRetryReceive,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final peerHex = peerController.text.trim().toLowerCase();
    final hasPeer = RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex);
    final visibleMessages = _messagesForPeer(messages, peerHex);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        children: [
          _ConversationHeader(
            peerHex: peerHex,
            localLabel: selectedPeerLabel,
            checkingForMessages: checkingForMessages,
            onChooseContact: sending ? null : onChooseContact,
          ),
          const Divider(height: 1, color: Color(0xFF2B3846)),
          if (notice != null ||
              hiddenMessageCount > 0 ||
              deferredMessageCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _ConversationNotice(
                notice: notice,
                isError: noticeIsError,
                hiddenMessageCount: hiddenMessageCount,
                deferredMessageCount: deferredMessageCount,
                retrying: checkingForMessages,
                onRetry: noticeIsError && !sending ? onRetryReceive : null,
              ),
            ),
          Expanded(
            child:
                hasPeer
                    ? _ConversationTimeline(
                      messages: visibleMessages,
                      contactLabels: contactLabels,
                    )
                    : _EmptyConversation(onChooseContact: onChooseContact),
          ),
          const Divider(height: 1, color: Color(0xFF2B3846)),
          _ConversationComposer(
            enabled: hasPeer,
            sending: sending,
            controller: messageController,
            onChanged: onInputChanged,
            onSend: onSend,
          ),
          if (lastResponse != null) _TechnicalDetails(response: lastResponse!),
        ],
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  final String peerHex;
  final String? localLabel;
  final bool checkingForMessages;
  final Future<void> Function()? onChooseContact;

  const _ConversationHeader({
    required this.peerHex,
    required this.localLabel,
    required this.checkingForMessages,
    required this.onChooseContact,
  });

  @override
  Widget build(BuildContext context) {
    final hasPeer = RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF32254D),
            foregroundColor: const Color(0xFFC9B2FF),
            child: Icon(hasPeer ? Icons.person_rounded : Icons.forum_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPeer
                      ? PeerIdentityFormat.capsuleLabelFromRootHex(
                        peerHex,
                        localLabel: localLabel,
                      )
                      : 'No conversation selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPeer
                      ? PeerIdentityFormat.capsuleIdentityHintFromRootHex(
                        peerHex,
                      )
                      : 'Choose a trusted Capsule to begin',
                  style: const TextStyle(
                    color: Color(0xFF96A2B2),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (checkingForMessages)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton.icon(
            onPressed: onChooseContact,
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            label: Text(hasPeer ? 'Change' : 'New conversation'),
          ),
        ],
      ),
    );
  }
}

class _ConversationNotice extends StatelessWidget {
  final String? notice;
  final bool isError;
  final int hiddenMessageCount;
  final int deferredMessageCount;
  final bool retrying;
  final Future<void> Function()? onRetry;

  const _ConversationNotice({
    required this.notice,
    required this.isError,
    required this.hiddenMessageCount,
    required this.deferredMessageCount,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final securityNotice = switch ((hiddenMessageCount, deferredMessageCount)) {
      (> 0, > 0) =>
        '$hiddenMessageCount unverified message(s) hidden; '
            '$deferredMessageCount waiting for relationship verification.',
      (> 0, _) => '$hiddenMessageCount unverified message(s) hidden.',
      (_, > 0) =>
        '$deferredMessageCount message(s) waiting for relationship verification.',
      _ => null,
    };
    final visibleNotice = notice ?? securityNotice;
    if (visibleNotice == null) return const SizedBox.shrink();

    final color = isError ? const Color(0xFFFFA4A4) : const Color(0xFF9BE4AA);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF2A1D1F) : const Color(0xFF173020),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFF6B3A3F) : const Color(0xFF315F3E),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.info_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                visibleNotice,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: retrying ? null : onRetry,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  final Future<void> Function() onChooseContact;

  const _EmptyConversation({required this.onChooseContact});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.forum_outlined,
              size: 42,
              color: Color(0xFFC9B2FF),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your Capsule conversations',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Messages stay scoped to the active Capsule.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF96A2B2)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onChooseContact,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New conversation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTimeline extends StatelessWidget {
  final List<CapsuleChatInboxMessage> messages;
  final Map<String, String> contactLabels;

  const _ConversationTimeline({
    required this.messages,
    required this.contactLabels,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet. Say hello when you are ready.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF96A2B2)),
          ),
        ),
      );
    }

    return ListView.builder(
      key: const Key('capsule-chat-timeline'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final peerHex =
            message.direction == CapsuleChatMessageDirection.outgoing
                ? (message.toHex ?? '')
                : message.fromHex;
        return _MessageBubble(
          message: message,
          localLabel:
              contactLabels[PeerIdentityFormat.capsuleKeyFromRootHex(peerHex)],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final CapsuleChatInboxMessage message;
  final String? localLabel;

  const _MessageBubble({required this.message, required this.localLabel});

  @override
  Widget build(BuildContext context) {
    final isOutgoing =
        message.direction == CapsuleChatMessageDirection.outgoing;
    final peerHex = isOutgoing ? (message.toHex ?? '') : message.fromHex;
    final deliveryLabel = switch (message.deliveryState) {
      CapsuleChatMessageDeliveryState.received => 'Received',
      CapsuleChatMessageDeliveryState.pending => 'Sending',
      CapsuleChatMessageDeliveryState.transportAccepted =>
        'Accepted by transport',
      CapsuleChatMessageDeliveryState.ambiguous => 'Delivery uncertain',
      CapsuleChatMessageDeliveryState.failed => 'Send failed',
    };

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: Key('capsule-chat-message-${message.id}'),
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: isOutgoing ? const Color(0xFF2B2250) : const Color(0xFF0E141D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isOutgoing ? const Color(0xFF66528D) : const Color(0xFF3A4B5D),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isOutgoing) ...[
              Text(
                PeerIdentityFormat.capsuleLabelFromRootHex(
                  peerHex,
                  localLabel: localLabel,
                ),
                style: const TextStyle(
                  color: Color(0xFFC9B2FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.messageText,
              style: const TextStyle(color: Color(0xFFE0E6EE), height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              '$deliveryLabel · ${_formatTimestamp(message.createdAtUtc)}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF95A5B7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationComposer extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Future<void> Function() onSend;

  const _ConversationComposer({
    required this.enabled,
    required this.sending,
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && !sending && controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('capsule-chat-composer'),
              controller: controller,
              enabled: enabled && !sending,
              onChanged: (_) => onChanged(),
              minLines: 1,
              maxLines: 4,
              maxLength: 1024,
              decoration: InputDecoration(
                hintText:
                    enabled ? 'Write a message' : 'Choose a conversation first',
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF0F141C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            key: const Key('capsule-chat-send'),
            onPressed: canSend ? onSend : null,
            tooltip: 'Send',
            icon:
                sending
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  final PluginHostApiResponse response;

  const _TechnicalDetails({required this.response});

  @override
  Widget build(BuildContext context) {
    final hash = response.result?['envelope_hash_hex']?.toString() ?? '';
    return ExpansionTile(
      key: const Key('capsule-chat-technical-details'),
      dense: true,
      title: const Text(
        'Technical details',
        style: TextStyle(fontSize: 12, color: Color(0xFF96A2B2)),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SelectableText(
          'Status: ${response.status.name}\n'
          'Method: ${response.method}\n'
          'Source: ${response.executionSource}'
          '${hash.isEmpty ? '' : '\nEnvelope: $hash'}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF96A2B2)),
        ),
      ],
    );
  }
}

List<CapsuleChatInboxMessage> _messagesForPeer(
  List<CapsuleChatInboxMessage> messages,
  String peerHex,
) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
    return const <CapsuleChatInboxMessage>[];
  }
  return messages
      .where(
        (message) =>
            (message.direction == CapsuleChatMessageDirection.outgoing
                ? message.toHex
                : message.fromHex) ==
            peerHex,
      )
      .toList(growable: false)
    ..sort((left, right) => left.timestampMs.compareTo(right.timestampMs));
}

String _formatTimestamp(String value) {
  final timestamp = DateTime.tryParse(value)?.toLocal();
  if (timestamp == null) return value;
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
