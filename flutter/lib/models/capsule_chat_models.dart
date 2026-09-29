import 'dart:convert';

enum CapsuleChatMessageDirection { incoming, outgoing }

enum CapsuleChatMessageDeliveryState {
  received,
  pending,
  transportAccepted,
  ambiguous,
  failed,
}

class CapsuleChatDeliverySendResult {
  final bool isSuccess;
  final bool blockedByConsensus;
  final int code;
  final String? errorMessage;
  final String? deliveryPeerHex;
  final String? deliveryReceiptsJson;

  const CapsuleChatDeliverySendResult({
    required this.isSuccess,
    required this.blockedByConsensus,
    required this.code,
    required this.errorMessage,
    required this.deliveryPeerHex,
    this.deliveryReceiptsJson,
  });

  int get deliveryReceiptCount {
    final raw = deliveryReceiptsJson;
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 0;
      final receipts = decoded['receipts'];
      return receipts is List ? receipts.length : 0;
    } catch (_) {
      return 0;
    }
  }
}

class CapsuleChatInboxMessage {
  final String id;
  final String fromHex;
  final String? toHex;
  final String messageText;
  final String createdAtUtc;
  final String envelopeHashHex;
  final int timestampMs;
  final CapsuleChatMessageDirection direction;
  final CapsuleChatMessageDeliveryState deliveryState;

  const CapsuleChatInboxMessage({
    required this.id,
    required this.fromHex,
    this.toHex,
    required this.messageText,
    required this.createdAtUtc,
    required this.envelopeHashHex,
    required this.timestampMs,
    this.direction = CapsuleChatMessageDirection.incoming,
    this.deliveryState = CapsuleChatMessageDeliveryState.received,
  });

  CapsuleChatInboxMessage copyWith({
    CapsuleChatMessageDeliveryState? deliveryState,
  }) {
    return CapsuleChatInboxMessage(
      id: id,
      fromHex: fromHex,
      toHex: toHex,
      messageText: messageText,
      createdAtUtc: createdAtUtc,
      envelopeHashHex: envelopeHashHex,
      timestampMs: timestampMs,
      direction: direction,
      deliveryState: deliveryState ?? this.deliveryState,
    );
  }
}

class CapsuleChatDeliveryReceiveResult {
  final int code;
  final String? errorMessage;
  final int droppedByConsensus;
  final int deferredByConsensus;
  final List<CapsuleChatInboxMessage> messages;

  const CapsuleChatDeliveryReceiveResult({
    required this.code,
    required this.errorMessage,
    required this.droppedByConsensus,
    this.deferredByConsensus = 0,
    required this.messages,
  });
}
