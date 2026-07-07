import 'bingx_futures_exchange_models.dart';

enum BingxPendingOrderActionType {
  cancelReplace,
}

class BingxPendingOrderAction {
  final BingxPendingOrderActionType actionType;
  final String idempotencyKey;
  final String orderId;
  final String reasonCode;
  final String reasonMessage;

  const BingxPendingOrderAction({
    required this.actionType,
    required this.idempotencyKey,
    required this.orderId,
    required this.reasonCode,
    required this.reasonMessage,
  });
}

class BingxPendingOrderRecord {
  final String idempotencyKey;
  final String orderId;
  final String symbol;
  final String entryMode;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;

  const BingxPendingOrderRecord({
    required this.idempotencyKey,
    required this.orderId,
    required this.symbol,
    required this.entryMode,
    required this.createdAtUtc,
    required this.expiresAtUtc,
  });
}

class BingxQueuedExecutionResult {
  final BingxFuturesOrderExecutionResult execution;
  final String idempotencyKey;
  final int attempts;
  final bool fromIdempotentCache;
  final bool exhaustedRetries;
  final bool pendingTracked;

  const BingxQueuedExecutionResult({
    required this.execution,
    required this.idempotencyKey,
    required this.attempts,
    required this.fromIdempotentCache,
    required this.exhaustedRetries,
    this.pendingTracked = false,
  });

  BingxQueuedExecutionResult asIdempotentCacheHit() {
    return BingxQueuedExecutionResult(
      execution: execution,
      idempotencyKey: idempotencyKey,
      attempts: attempts,
      fromIdempotentCache: true,
      exhaustedRetries: exhaustedRetries,
      pendingTracked: pendingTracked,
    );
  }
}
