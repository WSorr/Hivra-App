import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_execution_queue_service.dart';

void main() {
  group('BingxFuturesExecutionQueueService', () {
    const credentials = BingxFuturesApiCredentials(
      apiKey: 'key',
      apiSecret: 'secret',
    );
    const intent = BingxFuturesIntentPayload(
      clientOrderId: 'cid-1',
      symbol: 'BTC-USDT',
      side: 'buy',
      orderType: 'limit',
      quantityDecimal: '0.01',
      limitPriceDecimal: '60000',
      timeInForce: 'GTC',
      triggerPriceDecimal: null,
      intentHashHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    test('deduplicates in-flight execution by idempotency key', () async {
      var calls = 0;
      final completer = Completer<BingxFuturesOrderExecutionResult>();
      final service = BingxFuturesExecutionQueueService(
        exchangeService: BingxFuturesExchangeService(),
        placeOrderRunner: ({
          required credentials,
          required intent,
          required testOrder,
        }) {
          calls += 1;
          return completer.future;
        },
        delay: (_) async {},
        retryDelays: const <Duration>[],
      );

      final first = service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: true,
      );
      final second = service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: true,
      );

      expect(calls, 1);
      completer.complete(_successResult(orderId: 'ord-1'));

      final firstResult = await first;
      final secondResult = await second;
      expect(firstResult.execution.isSuccess, isTrue);
      expect(secondResult.execution.isSuccess, isTrue);
      expect(firstResult.fromIdempotentCache, isFalse);
      expect(secondResult.fromIdempotentCache, isFalse);
    });

    test('returns cached successful result for repeated execution', () async {
      var calls = 0;
      final service = BingxFuturesExecutionQueueService(
        exchangeService: BingxFuturesExchangeService(),
        placeOrderRunner: ({
          required credentials,
          required intent,
          required testOrder,
        }) async {
          calls += 1;
          return _successResult(orderId: 'ord-cache');
        },
        delay: (_) async {},
        retryDelays: const <Duration>[],
      );

      final first = await service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: false,
      );
      final second = await service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: false,
      );

      expect(calls, 1);
      expect(first.fromIdempotentCache, isFalse);
      expect(second.fromIdempotentCache, isTrue);
      expect(second.execution.orderId, 'ord-cache');
    });

    test('retries transient failure and succeeds on next attempt', () async {
      var calls = 0;
      final service = BingxFuturesExecutionQueueService(
        exchangeService: BingxFuturesExchangeService(),
        placeOrderRunner: ({
          required credentials,
          required intent,
          required testOrder,
        }) async {
          calls += 1;
          if (calls == 1) {
            return _failedResult(
              httpStatusCode: 504,
              exchangeCode: 'http_504',
              exchangeMessage: 'Gateway timeout',
            );
          }
          return _successResult(orderId: 'ord-retry');
        },
        delay: (_) async {},
        retryDelays: const <Duration>[
          Duration.zero,
          Duration.zero,
        ],
      );

      final result = await service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: true,
      );

      expect(calls, 2);
      expect(result.execution.isSuccess, isTrue);
      expect(result.attempts, 2);
      expect(result.exhaustedRetries, isFalse);
    });

    test('does not retry deterministic exchange rejection', () async {
      var calls = 0;
      final service = BingxFuturesExecutionQueueService(
        exchangeService: BingxFuturesExchangeService(),
        placeOrderRunner: ({
          required credentials,
          required intent,
          required testOrder,
        }) async {
          calls += 1;
          return _failedResult(
            httpStatusCode: 400,
            exchangeCode: '100001',
            exchangeMessage: 'Parameter validation failed',
          );
        },
        delay: (_) async {},
        retryDelays: const <Duration>[
          Duration.zero,
          Duration.zero,
        ],
      );

      final result = await service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: true,
      );

      expect(calls, 1);
      expect(result.execution.isSuccess, isFalse);
      expect(result.attempts, 1);
      expect(result.exhaustedRetries, isFalse);
    });

    test('retries transient thrown error then succeeds', () async {
      var calls = 0;
      final service = BingxFuturesExecutionQueueService(
        exchangeService: BingxFuturesExchangeService(),
        placeOrderRunner: ({
          required credentials,
          required intent,
          required testOrder,
        }) async {
          calls += 1;
          if (calls == 1) {
            throw const SocketException('Network unreachable');
          }
          return _successResult(orderId: 'ord-after-error');
        },
        delay: (_) async {},
        retryDelays: const <Duration>[
          Duration.zero,
        ],
      );

      final result = await service.enqueueOrderExecution(
        credentials: credentials,
        intent: intent,
        testOrder: false,
      );

      expect(calls, 2);
      expect(result.execution.isSuccess, isTrue);
      expect(result.attempts, 2);
    });
  });

  group('bingxExchangeExecutionShouldRetry', () {
    test('retries timeout/network style failures', () {
      expect(
        bingxExchangeExecutionShouldRetry(
          httpStatusCode: 504,
          exchangeCode: 'http_504',
          exchangeMessage: 'Gateway timeout',
        ),
        isTrue,
      );
      expect(
        bingxExchangeExecutionShouldRetry(
          httpStatusCode: 200,
          exchangeCode: '-1003',
          exchangeMessage: 'Timed out',
        ),
        isTrue,
      );
    });

    test('does not retry deterministic validation rejection', () {
      expect(
        bingxExchangeExecutionShouldRetry(
          httpStatusCode: 400,
          exchangeCode: '100001',
          exchangeMessage: 'invalid params',
        ),
        isFalse,
      );
    });
  });
}

BingxFuturesOrderExecutionResult _successResult({
  required String orderId,
}) {
  return BingxFuturesOrderExecutionResult(
    isSuccess: true,
    httpStatusCode: 200,
    exchangeCode: '0',
    exchangeMessage: 'ok',
    orderId: orderId,
    endpointPath: '/openApi/swap/v2/trade/order/test',
    signedPayloadHashHex:
        '1111111111111111111111111111111111111111111111111111111111111111',
    responseBody: '{"code":0}',
    intentHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
}

BingxFuturesOrderExecutionResult _failedResult({
  required int httpStatusCode,
  required String exchangeCode,
  required String exchangeMessage,
}) {
  return BingxFuturesOrderExecutionResult(
    isSuccess: false,
    httpStatusCode: httpStatusCode,
    exchangeCode: exchangeCode,
    exchangeMessage: exchangeMessage,
    orderId: null,
    endpointPath: '/openApi/swap/v2/trade/order/test',
    signedPayloadHashHex:
        '2222222222222222222222222222222222222222222222222222222222222222',
    responseBody: '{"code":"$exchangeCode"}',
    intentHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
}
