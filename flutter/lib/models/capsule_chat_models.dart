import 'dart:convert';

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
  final String messageText;
  final String createdAtUtc;
  final String envelopeHashHex;
  final int timestampMs;

  const CapsuleChatInboxMessage({
    required this.id,
    required this.fromHex,
    required this.messageText,
    required this.createdAtUtc,
    required this.envelopeHashHex,
    required this.timestampMs,
  });
}

class CapsuleTradeSignalInboxMessage {
  final String id;
  final String signalId;
  final String fromHex;
  final String symbol;
  final String side;
  final String orderType;
  final String quantityDecimal;
  final String entryMode;
  final String intentHashHex;
  final String createdAtUtc;
  final String? strategyTag;
  final String canonicalIntentJson;
  final int timestampMs;

  const CapsuleTradeSignalInboxMessage({
    required this.id,
    required this.signalId,
    required this.fromHex,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.entryMode,
    required this.intentHashHex,
    required this.createdAtUtc,
    required this.strategyTag,
    required this.canonicalIntentJson,
    required this.timestampMs,
  });
}

class CapsuleExecutionCommandDecisionMessage {
  final String id;
  final String fromHex;
  final String commandId;
  final String decision;
  final String decisionCode;
  final String decisionMessage;
  final String receiptHashHex;
  final int receiptDeliveryCode;
  final String? receiptDeliveryError;
  final int timestampMs;

  const CapsuleExecutionCommandDecisionMessage({
    required this.id,
    required this.fromHex,
    required this.commandId,
    required this.decision,
    required this.decisionCode,
    required this.decisionMessage,
    required this.receiptHashHex,
    required this.receiptDeliveryCode,
    required this.receiptDeliveryError,
    required this.timestampMs,
  });
}

class CapsuleExecutionReceiptInboxMessage {
  final String id;
  final String fromHex;
  final String commandId;
  final String decision;
  final String decisionCode;
  final String decisionMessage;
  final String targetCapsuleRootHex;
  final String peerHex;
  final String receiptCreatedAtUtc;
  final int timestampMs;

  const CapsuleExecutionReceiptInboxMessage({
    required this.id,
    required this.fromHex,
    required this.commandId,
    required this.decision,
    required this.decisionCode,
    required this.decisionMessage,
    required this.targetCapsuleRootHex,
    required this.peerHex,
    required this.receiptCreatedAtUtc,
    required this.timestampMs,
  });
}

class CapsuleChatDeliveryReceiveResult {
  final int code;
  final String? errorMessage;
  final int droppedByConsensus;
  final int deferredByConsensus;
  final List<CapsuleChatInboxMessage> messages;
  final List<CapsuleTradeSignalInboxMessage> tradeSignals;
  final List<CapsuleExecutionCommandDecisionMessage> executionDecisions;
  final List<CapsuleExecutionReceiptInboxMessage> executionReceipts;

  const CapsuleChatDeliveryReceiveResult({
    required this.code,
    required this.errorMessage,
    required this.droppedByConsensus,
    this.deferredByConsensus = 0,
    required this.messages,
    required this.tradeSignals,
    this.executionDecisions = const <CapsuleExecutionCommandDecisionMessage>[],
    this.executionReceipts = const <CapsuleExecutionReceiptInboxMessage>[],
  });
}
