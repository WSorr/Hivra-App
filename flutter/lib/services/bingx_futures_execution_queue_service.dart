import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_execution_queue_models.dart';
import 'bingx_futures_exchange_service.dart';

const List<Duration> _defaultBingxExecutionRetryDelays = <Duration>[
  Duration(milliseconds: 900),
  Duration(seconds: 2),
  Duration(seconds: 5),
];

const Duration _defaultPendingOrderTtl = Duration(minutes: 20);

typedef BingxFuturesPlaceOrderRunner = Future<BingxFuturesOrderExecutionResult>
    Function({
  required BingxFuturesApiCredentials credentials,
  required BingxFuturesIntentPayload intent,
  required bool testOrder,
});

typedef BingxExecutionQueueDelay = Future<void> Function(Duration delay);
typedef BingxExecutionQueueClock = DateTime Function();

Future<void> _defaultExecutionDelay(Duration delay) {
  return Future<void>.delayed(delay);
}

DateTime _defaultQueueClock() => DateTime.now().toUtc();

enum BingxExecutionRetryClass {
  retryableTransient,
  retryableClockSkew,
  nonRetryable,
}

bool bingxExchangeExecutionShouldRetry({
  required int httpStatusCode,
  required String exchangeCode,
  required String exchangeMessage,
}) {
  return bingxExchangeExecutionRetryClass(
        httpStatusCode: httpStatusCode,
        exchangeCode: exchangeCode,
        exchangeMessage: exchangeMessage,
      ) !=
      BingxExecutionRetryClass.nonRetryable;
}

BingxExecutionRetryClass bingxExchangeExecutionRetryClass({
  required int httpStatusCode,
  required String exchangeCode,
  required String exchangeMessage,
}) {
  if (httpStatusCode == 408 || httpStatusCode == 429 || httpStatusCode >= 500) {
    return BingxExecutionRetryClass.retryableTransient;
  }

  final code = exchangeCode.trim().toLowerCase();
  if (const <String>{
    '-1003',
    '-11',
    '-12',
    '-13',
    '-5',
    '-6',
    'http_408',
    'http_429',
    'http_500',
    'http_502',
    'http_503',
    'http_504',
  }.contains(code)) {
    return BingxExecutionRetryClass.retryableTransient;
  }
  if (const <String>{
    '-1021',
    'timestamp_invalid',
    'recvwindow_invalid',
  }.contains(code)) {
    return BingxExecutionRetryClass.retryableClockSkew;
  }

  final message = exchangeMessage.trim().toLowerCase();
  if (message.contains('timestamp') ||
      message.contains('recvwindow') ||
      message.contains('clock')) {
    return BingxExecutionRetryClass.retryableClockSkew;
  }
  if (message.contains('timeout') ||
      message.contains('timed out') ||
      message.contains('connection') ||
      message.contains('network') ||
      message.contains('unavailable') ||
      message.contains('too many requests') ||
      message.contains('rate limit') ||
      message.contains('temporarily')) {
    return BingxExecutionRetryClass.retryableTransient;
  }
  return BingxExecutionRetryClass.nonRetryable;
}

class BingxFuturesExecutionQueueService {
  final BingxFuturesPlaceOrderRunner _placeOrder;
  final BingxExecutionQueueDelay _delay;
  final BingxExecutionQueueClock _clockUtc;
  final List<Duration> retryDelays;
  final Duration pendingOrderTtl;
  final int maxSuccessCacheEntries;
  final int maxPendingOrderEntries;

  final LinkedHashMap<String, BingxQueuedExecutionResult> _successfulByKey =
      LinkedHashMap<String, BingxQueuedExecutionResult>();
  final Map<String, Future<BingxQueuedExecutionResult>> _inFlightByKey =
      <String, Future<BingxQueuedExecutionResult>>{};
  final LinkedHashMap<String, BingxPendingOrderRecord> _pendingByKey =
      LinkedHashMap<String, BingxPendingOrderRecord>();

  BingxFuturesExecutionQueueService({
    required BingxFuturesExchangeService exchangeService,
    BingxFuturesPlaceOrderRunner? placeOrderRunner,
    BingxExecutionQueueDelay delay = _defaultExecutionDelay,
    BingxExecutionQueueClock clockUtc = _defaultQueueClock,
    List<Duration> retryDelays = _defaultBingxExecutionRetryDelays,
    this.pendingOrderTtl = _defaultPendingOrderTtl,
    this.maxSuccessCacheEntries = 128,
    this.maxPendingOrderEntries = 128,
  })  : _placeOrder = placeOrderRunner ?? exchangeService.placeOrder,
        _delay = delay,
        _clockUtc = clockUtc,
        retryDelays = List<Duration>.unmodifiable(retryDelays);

  int get pendingOrderCount => _pendingByKey.length;

  String buildIdempotencyKey({
    required BingxFuturesIntentPayload intent,
    required bool testOrder,
  }) {
    final mode = testOrder ? 'test' : 'live';
    final intentHash = (intent.intentHashHex ?? '').trim().toLowerCase();
    if (intentHash.isNotEmpty) {
      return '$mode|$intentHash';
    }
    final fallback = <String>[
      intent.clientOrderId.trim(),
      intent.symbol.trim().toUpperCase(),
      intent.side.trim().toLowerCase(),
      intent.orderType.trim().toLowerCase(),
      intent.quantityDecimal.trim(),
      intent.limitPriceDecimal?.trim() ?? '',
      intent.triggerPriceDecimal?.trim() ?? '',
    ].join('|');
    return '$mode|$fallback';
  }

  Future<BingxQueuedExecutionResult> enqueueOrderExecution({
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesIntentPayload intent,
    required bool testOrder,
  }) {
    // Auto-sweep stale pending orders before handling any new execution.
    collectExpiredPendingOrderActions();

    final key = buildIdempotencyKey(
      intent: intent,
      testOrder: testOrder,
    );
    final cached = _successfulByKey[key];
    if (cached != null) {
      return Future<BingxQueuedExecutionResult>.value(
        cached.asIdempotentCacheHit(),
      );
    }

    final inFlight = _inFlightByKey[key];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _runExecutionWithRetry(
      idempotencyKey: key,
      credentials: credentials,
      intent: intent,
      testOrder: testOrder,
    );
    _inFlightByKey[key] = future;
    return future.whenComplete(() {
      _inFlightByKey.remove(key);
    });
  }

  Future<BingxQueuedExecutionResult> _runExecutionWithRetry({
    required String idempotencyKey,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesIntentPayload intent,
    required bool testOrder,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final execution = await _placeOrder(
          credentials: credentials,
          intent: intent,
          testOrder: testOrder,
        );
        final canRetry = !execution.isSuccess &&
            attempt <= retryDelays.length &&
            bingxExchangeExecutionShouldRetry(
              httpStatusCode: execution.httpStatusCode,
              exchangeCode: execution.exchangeCode,
              exchangeMessage: execution.exchangeMessage,
            );
        if (canRetry) {
          await _delay(retryDelays[attempt - 1]);
          continue;
        }

        final result = BingxQueuedExecutionResult(
          execution: execution,
          idempotencyKey: idempotencyKey,
          attempts: attempt,
          fromIdempotentCache: false,
          exhaustedRetries: !execution.isSuccess &&
              attempt > retryDelays.length &&
              bingxExchangeExecutionShouldRetry(
                httpStatusCode: execution.httpStatusCode,
                exchangeCode: execution.exchangeCode,
                exchangeMessage: execution.exchangeMessage,
              ),
        );
        final withPending = _trackPendingIfNeeded(
          result: result,
          intent: intent,
        );
        if (execution.isSuccess) {
          _rememberSuccessfulResult(
            idempotencyKey: idempotencyKey,
            result: withPending,
          );
        }
        return withPending;
      } on FormatException {
        rethrow;
      } catch (error) {
        if (!_shouldRetryThrownError(error) || attempt > retryDelays.length) {
          rethrow;
        }
        await _delay(retryDelays[attempt - 1]);
      }
    }
  }

  bool _shouldRetryThrownError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TlsException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('unavailable');
  }

  List<BingxPendingOrderAction> collectExpiredPendingOrderActions({
    DateTime? nowUtc,
  }) {
    if (_pendingByKey.isEmpty) return const <BingxPendingOrderAction>[];
    final now = (nowUtc ?? _clockUtc()).toUtc();
    final actions = <BingxPendingOrderAction>[];
    final expiredKeys = <String>[];
    for (final entry in _pendingByKey.entries) {
      final pending = entry.value;
      if (now.isBefore(pending.expiresAtUtc)) {
        continue;
      }
      expiredKeys.add(entry.key);
      actions.add(
        BingxPendingOrderAction(
          actionType: BingxPendingOrderActionType.cancelReplace,
          idempotencyKey: pending.idempotencyKey,
          orderId: pending.orderId,
          reasonCode: 'pending_order_ttl_expired',
          reasonMessage:
              'Pending order TTL expired, queue requests deterministic cancel/replace.',
        ),
      );
    }
    for (final key in expiredKeys) {
      _pendingByKey.remove(key);
      _successfulByKey.remove(key);
    }
    return actions;
  }

  void markPendingOrderCompleted(String idempotencyKey) {
    _pendingByKey.remove(idempotencyKey);
    _successfulByKey.remove(idempotencyKey);
  }

  BingxQueuedExecutionResult _trackPendingIfNeeded({
    required BingxQueuedExecutionResult result,
    required BingxFuturesIntentPayload intent,
  }) {
    final execution = result.execution;
    final orderId = execution.orderId?.trim();
    if (!execution.isSuccess || orderId == null || orderId.isEmpty) {
      return result;
    }
    final trackPending = intent.orderType.toLowerCase() == 'limit' ||
        intent.entryMode == 'zone_pending';
    if (!trackPending) {
      return result;
    }

    final createdAtUtc = _clockUtc().toUtc();
    final record = BingxPendingOrderRecord(
      idempotencyKey: result.idempotencyKey,
      orderId: orderId,
      symbol: intent.symbol,
      entryMode: intent.entryMode,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: createdAtUtc.add(pendingOrderTtl),
    );
    _pendingByKey.remove(result.idempotencyKey);
    _pendingByKey[result.idempotencyKey] = record;
    while (_pendingByKey.length > maxPendingOrderEntries) {
      _pendingByKey.remove(_pendingByKey.keys.first);
    }
    return BingxQueuedExecutionResult(
      execution: execution,
      idempotencyKey: result.idempotencyKey,
      attempts: result.attempts,
      fromIdempotentCache: result.fromIdempotentCache,
      exhaustedRetries: result.exhaustedRetries,
      pendingTracked: true,
    );
  }

  void _rememberSuccessfulResult({
    required String idempotencyKey,
    required BingxQueuedExecutionResult result,
  }) {
    _successfulByKey.remove(idempotencyKey);
    _successfulByKey[idempotencyKey] = result;
    while (_successfulByKey.length > maxSuccessCacheEntries) {
      _successfulByKey.remove(_successfulByKey.keys.first);
    }
  }
}
