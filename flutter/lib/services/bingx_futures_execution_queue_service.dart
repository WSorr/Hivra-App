import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'bingx_futures_exchange_service.dart';

const List<Duration> _defaultBingxExecutionRetryDelays = <Duration>[
  Duration(milliseconds: 900),
  Duration(seconds: 2),
  Duration(seconds: 5),
];

typedef BingxFuturesPlaceOrderRunner = Future<BingxFuturesOrderExecutionResult>
    Function({
  required BingxFuturesApiCredentials credentials,
  required BingxFuturesIntentPayload intent,
  required bool testOrder,
});

typedef BingxExecutionQueueDelay = Future<void> Function(Duration delay);

Future<void> _defaultExecutionDelay(Duration delay) {
  return Future<void>.delayed(delay);
}

bool bingxExchangeExecutionShouldRetry({
  required int httpStatusCode,
  required String exchangeCode,
  required String exchangeMessage,
}) {
  if (httpStatusCode == 408 || httpStatusCode == 429 || httpStatusCode >= 500) {
    return true;
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
    return true;
  }

  final message = exchangeMessage.trim().toLowerCase();
  return message.contains('timeout') ||
      message.contains('timed out') ||
      message.contains('connection') ||
      message.contains('network') ||
      message.contains('unavailable') ||
      message.contains('too many requests') ||
      message.contains('rate limit') ||
      message.contains('temporarily');
}

class BingxQueuedExecutionResult {
  final BingxFuturesOrderExecutionResult execution;
  final String idempotencyKey;
  final int attempts;
  final bool fromIdempotentCache;
  final bool exhaustedRetries;

  const BingxQueuedExecutionResult({
    required this.execution,
    required this.idempotencyKey,
    required this.attempts,
    required this.fromIdempotentCache,
    required this.exhaustedRetries,
  });

  BingxQueuedExecutionResult asIdempotentCacheHit() {
    return BingxQueuedExecutionResult(
      execution: execution,
      idempotencyKey: idempotencyKey,
      attempts: attempts,
      fromIdempotentCache: true,
      exhaustedRetries: exhaustedRetries,
    );
  }
}

class BingxFuturesExecutionQueueService {
  final BingxFuturesPlaceOrderRunner _placeOrder;
  final BingxExecutionQueueDelay _delay;
  final List<Duration> retryDelays;
  final int maxSuccessCacheEntries;

  final LinkedHashMap<String, BingxQueuedExecutionResult> _successfulByKey =
      LinkedHashMap<String, BingxQueuedExecutionResult>();
  final Map<String, Future<BingxQueuedExecutionResult>> _inFlightByKey =
      <String, Future<BingxQueuedExecutionResult>>{};

  BingxFuturesExecutionQueueService({
    required BingxFuturesExchangeService exchangeService,
    BingxFuturesPlaceOrderRunner? placeOrderRunner,
    BingxExecutionQueueDelay delay = _defaultExecutionDelay,
    List<Duration> retryDelays = _defaultBingxExecutionRetryDelays,
    this.maxSuccessCacheEntries = 128,
  })  : _placeOrder = placeOrderRunner ?? exchangeService.placeOrder,
        _delay = delay,
        retryDelays = List<Duration>.unmodifiable(retryDelays);

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
        if (execution.isSuccess) {
          _rememberSuccessfulResult(
            idempotencyKey: idempotencyKey,
            result: result,
          );
        }
        return result;
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
