import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/bingx_futures_exchange_execution_use_case_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_execution_queue_service.dart';
import 'package:hivra_app/services/bingx_futures_risk_governor_service.dart';

void main() {
  group('BingxFuturesExchangeExecutionUseCaseService', () {
    test('rejects invalid intent before exchange execution', () async {
      var placeOrderCalled = false;
      final exchange = BingxFuturesExchangeService();
      final service = BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchange,
        queue: BingxFuturesExecutionQueueService(
          exchangeService: exchange,
          placeOrderRunner: ({
            required credentials,
            required intent,
            required testOrder,
          }) async {
            placeOrderCalled = true;
            throw StateError('must not execute');
          },
        ),
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: const <String, dynamic>{},
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.invalidIntent,
      );
      expect(placeOrderCalled, isFalse);
    });

    test('blocks execution when entry price is unavailable', () async {
      var placeOrderCalled = false;
      final exchange = BingxFuturesExchangeService(
        requestSender: (_) async => const BingxHttpResponse(
          statusCode: 503,
          body: '{"code":503,"msg":"unavailable"}',
        ),
      );
      final service = BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchange,
        queue: BingxFuturesExecutionQueueService(
          exchangeService: exchange,
          placeOrderRunner: ({
            required credentials,
            required intent,
            required testOrder,
          }) async {
            placeOrderCalled = true;
            throw StateError('must not execute');
          },
        ),
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _marketIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.riskUnavailable,
      );
      expect(result.errorCode, 'entry_price_unavailable');
      expect(placeOrderCalled, isFalse);
    });
  });
}

const BingxFuturesApiCredentials _credentials = BingxFuturesApiCredentials(
  apiKey: 'key',
  apiSecret: 'secret',
);

const BingxFuturesRiskPolicy _policy = BingxFuturesRiskPolicy(
  maxRiskPerTradePercent: 2,
  maxDailyLossPercent: 5,
  maxConcurrentPositions: 3,
  cooldownAfterLossStreak: 2,
  cooldownMinutes: 60,
);

const Map<String, dynamic> _marketIntent = <String, dynamic>{
  'client_order_id': 'ord-1',
  'symbol': 'BTC-USDT',
  'side': 'buy',
  'order_type': 'market',
  'quantity_decimal': '0.01',
  'entry_mode': 'direct',
  'intent_hash_hex':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
};
