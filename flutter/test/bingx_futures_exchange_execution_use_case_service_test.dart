import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_exchange_execution_models.dart';
import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_risk_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_execution_use_case_service.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_execution_queue_service.dart';
import 'package:hivra_app/services/bingx_futures_order_tracking_store.dart';
import 'package:hivra_app/services/bingx_futures_risk_history_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('BingxFuturesExchangeExecutionUseCaseService', () {
    late Directory tempHome;
    late BingxFuturesRiskHistoryService riskHistory;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-risk-execution-');
      riskHistory = BingxFuturesRiskHistoryService(
        readActiveCapsuleRootHex: () => List.filled(64, 'a').join(),
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
    });

    tearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });

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
        riskHistory: riskHistory,
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
        requestSender:
            (_) async => const BingxHttpResponse(
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
        riskHistory: riskHistory,
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

    test('blocks a zone intent after the next closed market bar', () async {
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
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _zoneIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
        preparedDecision: _decision(barAtUtc: '2026-08-11T10:00:00.000Z'),
        refreshDecision:
            () async => _decision(barAtUtc: '2026-08-11T10:05:00.000Z'),
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
      );
      expect(result.errorCode, 'liquidity_event_stale');
      expect(placeOrderCalled, isFalse);
    });

    test('blocks a zone intent when the liquidity event changes', () async {
      final exchange = BingxFuturesExchangeService();
      final service = BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchange,
        queue: BingxFuturesExecutionQueueService(exchangeService: exchange),
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _zoneIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
        preparedDecision: _decision(),
        refreshDecision: () async => _decision(eventHex: 'b'),
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
      );
      expect(result.errorCode, 'liquidity_event_stale');
    });

    test('blocks same event after live market decision changes', () async {
      final exchange = BingxFuturesExchangeService();
      final service = BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchange,
        queue: BingxFuturesExecutionQueueService(exchangeService: exchange),
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _zoneIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
        preparedDecision: _decision(),
        refreshDecision: () async => _decision(liveHashHex: '5'),
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
      );
      expect(result.errorCode, 'liquidity_event_stale');
    });

    test('durable event claim blocks a second exchange effect', () async {
      var placeOrderCalls = 0;
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          if (request.uri.path.endsWith('/quote/contracts')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":2,"quantityPrecision":3,"pricePrecision":2}]}',
            );
          }
          if (request.uri.path.endsWith('/quote/price')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":{"price":"100"}}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 503,
            body: '{"code":503,"msg":"test fallback"}',
          );
        },
      );
      final trackingStore = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => List<String>.filled(64, 'd').join(),
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
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
            placeOrderCalls += 1;
            return BingxFuturesOrderExecutionResult(
              isSuccess: true,
              httpStatusCode: 200,
              exchangeCode: '0',
              exchangeMessage: 'ok',
              orderId: 'order-$placeOrderCalls',
              endpointPath: '/test-order',
              signedPayloadHashHex: List<String>.filled(64, 'e').join(),
              responseBody: '{}',
              intentHashHex: intent.intentHashHex,
            );
          },
        ),
        riskHistory: riskHistory,
        orderTrackingStore: trackingStore,
      );

      Future<BingxFuturesExchangeExecutionUseCaseResult> execute() {
        return service.execute(
          screen: 'test',
          rawIntentResult: _zoneIntent,
          credentials: _credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: true,
          preparedDecision: _decision(),
          refreshDecision: () async => _decision(),
        );
      }

      final first = await execute();
      final second = await execute();

      expect(first.status, BingxFuturesExchangeExecutionUseCaseStatus.executed);
      expect(
        second.status,
        BingxFuturesExchangeExecutionUseCaseStatus.duplicateLiquidityEvent,
      );
      expect(placeOrderCalls, 1);
      final restored = await trackingStore.load();
      expect(
        restored!.liquidityEventEffectClaims.values.single.status,
        BingxLiquidityEventEffectClaimStatus.confirmed,
      );
      expect(
        restored.liquidityEventEffectClaims.values.single.orderId,
        'order-1',
      );
    });

    test('returns deterministic execution envelope when risk blocks', () async {
      var placeOrderCalled = false;
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          if (request.uri.path.endsWith('/quote/contracts')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":2,"quantityPrecision":3,"pricePrecision":2}]}',
            );
          }
          if (request.uri.path.endsWith('/quote/price')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":{"price":"100"}}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 404,
            body: '{"code":404,"msg":"unexpected"}',
          );
        },
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
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: <String, dynamic>{
          ..._marketIntent,
          'quantity_decimal': '10',
        },
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.riskBlocked,
      );
      expect(result.executionEnvelope, isNotNull);
      expect(
        result.executionEnvelope!.envelopeHashHex,
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        result.executionEnvelope!.canonicalJson,
        contains('"endpoint_path":"risk_governor"'),
      );
      expect(placeOrderCalled, isFalse);
    });

    test('blocks live execution when exchange risk inputs use fallback', () async {
      var placeOrderCalled = false;
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          if (request.uri.path.endsWith('/quote/contracts')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":2,"quantityPrecision":3,"pricePrecision":2}]}',
            );
          }
          if (request.uri.path.endsWith('/quote/price')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":{"price":"100"}}',
            );
          }
          if (request.uri.path.endsWith('/user/balance')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":100001,"msg":"signature invalid","data":{}}',
            );
          }
          if (request.uri.path.endsWith('/user/positions')) {
            return const BingxHttpResponse(
              statusCode: 503,
              body: '{"code":503,"msg":"positions unavailable"}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 404,
            body: '{"code":404,"msg":"unexpected"}',
          );
        },
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
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _marketIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: false,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.riskUnavailable,
      );
      expect(result.errorCode, 'exchange_risk_inputs_unavailable');
      expect(
        result.errorMessage,
        'Risk check failed: BingX futures access unavailable (100001 signature invalid)',
      );
      expect(result.diagnostics, contains(contains('fallbacks=balance,pnl')));
      expect(
        result.diagnostics,
        contains(contains('exchange_reason=100001 signature invalid')),
      );
      expect(placeOrderCalled, isFalse);
    });

    test('blocks live execution from persisted exchange loss streak', () async {
      var placeOrderCalled = false;
      final now = DateTime.now().toUtc();
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          if (request.uri.path.endsWith('/quote/contracts')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":2,"quantityPrecision":3,"pricePrecision":2}]}',
            );
          }
          if (request.uri.path.endsWith('/quote/price')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":{"price":"100"}}',
            );
          }
          if (request.uri.path.endsWith('/user/balance')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":{"balance":{"equity":"100"}}}',
            );
          }
          if (request.uri.path.endsWith('/user/positions')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":[]}',
            );
          }
          if (request.uri.path.endsWith('/user/income')) {
            return BingxHttpResponse(
              statusCode: 200,
              body: jsonEncode(<String, dynamic>{
                'code': 0,
                'msg': 'ok',
                'data': <Map<String, dynamic>>[
                  _incomeRow(
                    'loss-1',
                    -1,
                    now.subtract(const Duration(minutes: 2)),
                  ),
                  _incomeRow(
                    'loss-2',
                    -1,
                    now.subtract(const Duration(minutes: 1)),
                  ),
                ],
              }),
            );
          }
          return const BingxHttpResponse(
            statusCode: 404,
            body: '{"code":404,"msg":"unexpected"}',
          );
        },
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
        riskHistory: riskHistory,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _marketIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: false,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.riskBlocked,
      );
      expect(result.riskDecision!.reasonCode, 'risk_loss_streak_cooldown');
      expect(result.diagnostics, contains(contains('loss_streak=2')));
      expect(placeOrderCalled, isFalse);
      expect(await riskHistory.load(), isNotNull);
    });
  });
}

Map<String, dynamic> _incomeRow(String id, num income, DateTime time) =>
    <String, dynamic>{
      'symbol': 'BTC-USDT',
      'incomeType': 'REALIZED_PNL',
      'income': income.toString(),
      'asset': 'USDT',
      'time': time.millisecondsSinceEpoch,
      'tranId': id,
      'tradeId': 'trade-$id',
    };

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

const Map<String, dynamic> _zoneIntent = <String, dynamic>{
  'client_order_id': 'hivra-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'symbol': 'BTC-USDT',
  'side': 'buy',
  'order_type': 'limit',
  'quantity_decimal': '0.1',
  'limit_price_decimal': '100',
  'time_in_force': 'GTC',
  'entry_mode': 'zone_pending',
  'zone_side': 'buyside',
  'trigger_price_decimal': '101',
  'stop_loss_decimal': '95',
  'take_profit_decimal': '110',
  'intent_hash_hex':
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
};

BingxFuturesLiveDecisionResult _decision({
  String eventHex = 'a',
  String liveHashHex = '4',
  String barAtUtc = '2026-08-11T10:00:00.000Z',
}) {
  return BingxFuturesLiveDecisionResult(
    canPrepareIntent: true,
    decision: BingxTvhDecisionKind.long,
    side: 'buy',
    zoneSide: 'buyside',
    zoneLowDecimal: '99',
    zoneHighDecimal: '101',
    zoneConflict: false,
    marketSnapshotHashHex: List<String>.filled(64, '1').join(),
    featureHashHex: List<String>.filled(64, '2').join(),
    tvhDecisionHashHex: List<String>.filled(64, '3').join(),
    liveDecisionHashHex: List<String>.filled(64, liveHashHex).join(),
    canonicalJson: '{}',
    reasons: const <BingxTvhDecisionReason>[],
    trend15m: 'bullish',
    trend4h: 'bull',
    trend1d: 'bull',
    trendGateBlocked: false,
    trendGateCode: 'ok',
    liquidityEventId: List<String>.filled(64, eventHex).join(),
    liquidityEventAtUtc: '2026-08-11T09:55:00.000Z',
    latestClosedMicroBarAtUtc: barAtUtc,
  );
}
