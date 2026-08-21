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
    late BingxFuturesOrderTrackingStore executionControlStore;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-risk-execution-');
      riskHistory = BingxFuturesRiskHistoryService(
        readActiveCapsuleRootHex: () => List.filled(64, 'a').join(),
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
      executionControlStore = _trackingStore(tempHome);
      await _setDroneEnabled(executionControlStore, true);
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
        orderTrackingStore: executionControlStore,
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

    test(
      'blocks execution when durable trading control is unavailable',
      () async {
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
          rawIntentResult: _marketIntent,
          credentials: _credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: true,
        );

        expect(
          result.status,
          BingxFuturesExchangeExecutionUseCaseStatus.executionPaused,
        );
        expect(result.errorCode, 'trading_control_unavailable');
        expect(placeOrderCalled, isFalse);
      },
    );

    test(
      'restored Capsule pause blocks execution before provider access',
      () async {
        var placeOrderCalled = false;
        final store = _trackingStore(tempHome);
        await _setDroneEnabled(store, false);
        final restartedStore = _trackingStore(tempHome);
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
          orderTrackingStore: restartedStore,
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
          BingxFuturesExchangeExecutionUseCaseStatus.executionPaused,
        );
        expect(result.errorCode, 'trading_paused');
        expect(placeOrderCalled, isFalse);
      },
    );

    test('pause during risk refresh blocks the final provider effect', () async {
      var placeOrderCalled = false;
      var pauseWritten = false;
      final store = _trackingStore(tempHome);
      await _setDroneEnabled(store, true);
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          if (!pauseWritten && request.uri.path.endsWith('/quote/contracts')) {
            pauseWritten = true;
            await _setDroneEnabled(store, false);
          }
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
        orderTrackingStore: store,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: <String, dynamic>{
          ..._marketIntent,
          'quantity_decimal': '0.03',
          'stop_loss_decimal': '95',
        },
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
      );

      expect(pauseWritten, isTrue);
      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.executionPaused,
      );
      expect(result.errorCode, 'trading_paused');
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
        orderTrackingStore: executionControlStore,
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
        orderTrackingStore: executionControlStore,
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
        orderTrackingStore: executionControlStore,
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

    test(
      'test validation is idempotent without a durable effect claim',
      () async {
        var placeOrderCalls = 0;
        final exchange = BingxFuturesExchangeService();
        final store = _trackingStore(tempHome);
        await _setDroneEnabled(store, true);
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
                orderId: 'semantic-event-order',
                endpointPath: '/test-order',
                signedPayloadHashHex: List<String>.filled(64, 'e').join(),
                responseBody: '{}',
                intentHashHex: intent.intentHashHex,
              );
            },
          ),
          riskHistory: riskHistory,
          orderTrackingStore: store,
        );

        final first = await service.execute(
          screen: 'test',
          rawIntentResult: _zoneIntent,
          credentials: _credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: true,
          preparedDecision: _decision(),
          refreshDecision: () async => _decision(liveHashHex: '5'),
        );
        final second = await service.execute(
          screen: 'test',
          rawIntentResult: _zoneIntent,
          credentials: _credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: true,
          preparedDecision: _decision(),
          refreshDecision: () async => _decision(liveHashHex: '6'),
        );

        expect(
          first.status,
          BingxFuturesExchangeExecutionUseCaseStatus.validated,
          reason: first.errorCode,
        );
        expect(
          second.status,
          BingxFuturesExchangeExecutionUseCaseStatus.validated,
        );
        expect(second.queuedExecution!.fromIdempotentCache, isTrue);
        expect(placeOrderCalls, 1);
        expect((await store.load())!.liquidityEventEffectClaims, isEmpty);
      },
    );

    test('test validation falls back when account equity is zero', () async {
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
          if (request.uri.path.endsWith('/user/balance')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"balance":{"asset":"USDT","equity":"0"}}}',
            );
          }
          if (request.uri.path.endsWith('/user/positions') ||
              request.uri.path.endsWith('/user/income')) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":[]}',
            );
          }
          return const BingxHttpResponse(statusCode: 404, body: '{}');
        },
      );
      final store = _trackingStore(tempHome);
      await _setDroneEnabled(store, true);
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
              orderId: null,
              endpointPath: '/test-order',
              signedPayloadHashHex: List<String>.filled(64, 'e').join(),
              responseBody: '{}',
              intentHashHex: intent.intentHashHex,
            );
          },
        ),
        riskHistory: riskHistory,
        orderTrackingStore: store,
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
        BingxFuturesExchangeExecutionUseCaseStatus.validated,
        reason: result.errorCode,
      );
      expect(result.diagnostics, contains(contains('fallbacks=balance,-,-')));
      expect(
        result.diagnostics,
        contains(contains('account_equity_non_positive')),
      );
      expect(placeOrderCalls, 1);
      expect((await store.load())!.liquidityEventEffectClaims, isEmpty);
    });

    test('reports rejected provider effect as execution failure', () async {
      final exchange = BingxFuturesExchangeService();
      final store = _trackingStore(tempHome);
      await _setDroneEnabled(store, true);
      final service = BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchange,
        queue: BingxFuturesExecutionQueueService(
          exchangeService: exchange,
          placeOrderRunner: ({
            required credentials,
            required intent,
            required testOrder,
          }) async {
            return BingxFuturesOrderExecutionResult(
              isSuccess: false,
              httpStatusCode: 400,
              exchangeCode: '100001',
              exchangeMessage: 'provider rejected order',
              orderId: null,
              endpointPath: '/test-order',
              signedPayloadHashHex: List<String>.filled(64, 'e').join(),
              responseBody: '{}',
              intentHashHex: intent.intentHashHex,
            );
          },
        ),
        riskHistory: riskHistory,
        orderTrackingStore: store,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _zoneIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
        preparedDecision: _decision(),
        refreshDecision: () async => _decision(),
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.executionFailed,
      );
      expect(result.queuedExecution!.execution.isSuccess, isFalse);
      expect(result.errorCode, 'exchange_effect_failed');
      expect(result.errorMessage, 'provider rejected order');
      final state = await store.load();
      expect(state!.liquidityEventEffectClaims, isEmpty);
    });

    test('bounded mandate rejects scope and authority mutations', () async {
      var placeOrderCalled = false;
      final store = _trackingStore(tempHome);
      final now = DateTime.utc(2026, 8, 16, 12);
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
        orderTrackingStore: store,
        nowUtc: () => now,
      );

      Future<BingxFuturesExchangeExecutionUseCaseResult> run(
        BingxFuturesTradingMandate mandate, {
        BingxFuturesApiCredentials credentials = _credentials,
      }) async {
        await store.save(
          BingxFuturesOrderTrackingState(
            trackedSymbol: null,
            trackedOrderId: null,
            managedOrderIds: const <String>[],
            managedOrderSymbols: const <String, String>{},
            droneEnabled: true,
            tradingMandate: mandate,
            stopLossPercent: null,
            takeProfitRiskReward: null,
          ),
        );
        return service.execute(
          screen: 'test',
          rawIntentResult: _zoneIntent,
          credentials: credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: true,
          preparedDecision: _decision(),
          refreshDecision: () async => _decision(),
        );
      }

      final mutations = <BingxFuturesTradingMandate>[
        _mandate(now: now, capsuleRootHex: List<String>.filled(64, 'b').join()),
        _mandate(
          now: now,
          accountBindingHashHex: List<String>.filled(64, 'c').join(),
        ),
        _mandate(now: now, symbol: 'ETH-USDT'),
        _mandate(now: now, testOrder: false),
        _mandate(now: now.subtract(const Duration(hours: 2))),
        _mandate(now: now, maxNotional: '5'),
        _mandate(now: now, maxRiskPerTradePercent: 1),
        _mandate(now: now).revoke(now),
      ];
      for (final mandate in mutations) {
        final result = await run(mandate);
        expect(
          result.status,
          BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked,
          reason: mandate.mandateId,
        );
      }
      expect(placeOrderCalled, isFalse);
    });

    test('bounded mandate rejects effects without an event claim', () async {
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
        orderTrackingStore: executionControlStore,
      );
      final direct = <String, dynamic>{..._zoneIntent, 'entry_mode': 'direct'};
      final result = await service.execute(
        screen: 'test',
        rawIntentResult: direct,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked,
      );
      expect(result.errorCode, 'trading_mandate_event_required');
      expect(placeOrderCalled, isFalse);
    });

    test('blocks same event when its executable zone changes', () async {
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
        orderTrackingStore: executionControlStore,
      );

      final result = await service.execute(
        screen: 'test',
        rawIntentResult: _zoneIntent,
        credentials: _credentials,
        riskPolicy: _policy,
        fallbackEquityQuote: 100,
        testOrder: true,
        preparedDecision: _decision(),
        refreshDecision: () async => _decision(zoneLowDecimal: '98'),
      );

      expect(
        result.status,
        BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
      );
      expect(result.errorCode, 'liquidity_event_stale');
      expect(placeOrderCalled, isFalse);
    });

    test('live restart preserves receipt and blocks a second effect', () async {
      var placeOrderCalls = 0;
      var activeCapsule = List<String>.filled(64, 'd').join();
      final originalCapsule = activeCapsule;
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
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
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":[]}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 503,
            body: '{"code":503,"msg":"test fallback"}',
          );
        },
      );
      final trackingStore = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => activeCapsule,
        fileStore: fileStore,
      );
      await _setDroneEnabled(trackingStore, true, testOrder: false);
      BingxFuturesExchangeExecutionUseCaseService buildUseCase(
        BingxFuturesOrderTrackingStore store,
      ) {
        return BingxFuturesExchangeExecutionUseCaseService(
          exchange: exchange,
          queue: BingxFuturesExecutionQueueService(
            exchangeService: exchange,
            placeOrderRunner: ({
              required credentials,
              required intent,
              required testOrder,
            }) async {
              placeOrderCalls += 1;
              activeCapsule = List<String>.filled(64, 'e').join();
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
          orderTrackingStore: store,
        );
      }

      Future<BingxFuturesExchangeExecutionUseCaseResult> execute(
        BingxFuturesExchangeExecutionUseCaseService useCase,
      ) {
        return useCase.execute(
          screen: 'test',
          rawIntentResult: _zoneIntent,
          credentials: _credentials,
          riskPolicy: _policy,
          fallbackEquityQuote: 100,
          testOrder: false,
          preparedDecision: _decision(),
          refreshDecision: () async => _decision(),
        );
      }

      final first = await execute(buildUseCase(trackingStore));
      final originalCapsuleState = await trackingStore.loadForCapsule(
        originalCapsule,
      );
      final switchedCapsuleState = await trackingStore.loadForCapsule(
        List<String>.filled(64, 'e').join(),
      );
      activeCapsule = originalCapsule;
      final restartedStore = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => activeCapsule,
        fileStore: fileStore,
      );
      final restartedUseCase = buildUseCase(restartedStore);
      final restoredAfterRestart = await restartedStore.load();
      final second = await execute(restartedUseCase);

      expect(first.status, BingxFuturesExchangeExecutionUseCaseStatus.executed);
      expect(first.queuedExecution!.execution.orderId, 'order-1');
      expect(first.queuedExecution!.execution.endpointPath, '/test-order');
      expect(first.executionEnvelope!.envelopeHashHex, hasLength(64));
      expect(
        first.executionEnvelope!.canonicalJson,
        contains('"order_id":"order-1"'),
      );
      expect(
        first.executionEnvelope!.canonicalJson,
        contains('"intent_hash_hex":"${_zoneIntent['intent_hash_hex']}"'),
      );
      expect(
        second.status,
        BingxFuturesExchangeExecutionUseCaseStatus.duplicateLiquidityEvent,
      );
      expect(second.queuedExecution, isNull);
      expect(placeOrderCalls, 1);
      expect(switchedCapsuleState, isNull);
      expect(restoredAfterRestart!.toJson(), originalCapsuleState!.toJson());
      final claim =
          restoredAfterRestart.liquidityEventEffectClaims.values.single;
      expect(claim.status, BingxLiquidityEventEffectClaimStatus.confirmed);
      expect(claim.orderId, 'order-1');
      expect(claim.symbol, 'BTC-USDT');
      expect(claim.side, 'buy');
      expect(claim.clientOrderId, _zoneIntent['client_order_id']);
      expect(claim.intentHashHex, _zoneIntent['intent_hash_hex']);
      expect(claim.canonicalIntentJson, _zoneIntent['canonical_intent_json']);
      expect(
        claim.accountBindingHashHex,
        BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
          _credentials,
        ),
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
        orderTrackingStore: executionControlStore,
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
      await _setDroneEnabled(executionControlStore, true, testOrder: false);
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
        orderTrackingStore: executionControlStore,
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
      await _setDroneEnabled(executionControlStore, true, testOrder: false);
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
        orderTrackingStore: executionControlStore,
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

    test(
      'restart resolves a missing open order from exact terminal evidence',
      () async {
        final store = _trackingStore(tempHome);
        final binding =
            BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
              _credentials,
            );
        await store.save(
          _trackingState(
            orderId: 'managed-filled',
            accountBindingHashHex: binding,
          ),
        );
        var exactQueries = 0;
        final exchange = BingxFuturesExchangeService(
          requestSender: (_) async {
            exactQueries += 1;
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"orderID":"managed-filled","clientOrderId":"managed-client","symbol":"BTC-USDT","side":"BUY","status":"FILLED"}}',
            );
          },
        );
        final useCase = _reconciliationUseCase(
          exchange: exchange,
          store: store,
          riskHistory: riskHistory,
        );

        final result = await useCase.reconcileManagedOrders(
          credentials: _credentials,
          openOrders: _openOrders(<BingxFuturesOpenOrder>[
            const BingxFuturesOpenOrder(
              orderId: 'manual-order',
              symbol: 'BTC-USDT',
              side: 'BUY',
              positionSide: 'LONG',
              orderType: 'LIMIT',
              status: 'NEW',
              priceDecimal: '99',
              triggerPriceDecimal: null,
              quantityDecimal: '1',
              executedQuantityDecimal: '0',
              createdAtMs: 1,
            ),
          ]),
        );

        expect(exactQueries, 1);
        expect(result.activeCount, 0);
        expect(result.terminalCount, 1);
        expect(result.state!.managedOrderIds, isEmpty);
        expect(
          result
              .state!
              .managedOrderProvenance['managed-filled']!
              .lifecycleStatus,
          BingxManagedOrderLifecycleStatus.filled,
        );
        expect(
          result.state!.managedOrderProvenance,
          isNot(contains('manual-order')),
        );
      },
    );

    test(
      'timeout preserves unresolved ownership evidence without recreation',
      () async {
        final store = _trackingStore(tempHome);
        final binding =
            BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
              _credentials,
            );
        await store.save(
          _trackingState(
            orderId: 'managed-timeout',
            accountBindingHashHex: binding,
          ),
        );
        var requests = 0;
        final exchange = BingxFuturesExchangeService(
          requestSender: (_) async {
            requests += 1;
            throw const SocketException('offline');
          },
        );

        final result = await _reconciliationUseCase(
          exchange: exchange,
          store: store,
          riskHistory: riskHistory,
        ).reconcileManagedOrders(
          credentials: _credentials,
          openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
        );

        expect(requests, 1);
        expect(result.unresolvedCount, 1);
        expect(result.state!.managedOrderIds, isEmpty);
        expect(
          result
              .state!
              .managedOrderProvenance['managed-timeout']!
              .lifecycleStatus,
          BingxManagedOrderLifecycleStatus.unresolved,
        );
        expect(
          result.diagnostics,
          contains('provider_query_error:SocketException'),
        );
      },
    );

    test('account mismatch fails closed before provider access', () async {
      final store = _trackingStore(tempHome);
      await store.save(
        _trackingState(
          orderId: 'managed-account-a',
          accountBindingHashHex: List<String>.filled(64, 'b').join(),
        ),
      );
      var requests = 0;
      final exchange = BingxFuturesExchangeService(
        requestSender: (_) async {
          requests += 1;
          throw StateError('must not query mismatched account');
        },
      );

      final result = await _reconciliationUseCase(
        exchange: exchange,
        store: store,
        riskHistory: riskHistory,
      ).reconcileManagedOrders(
        credentials: _credentials,
        openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
      );

      expect(requests, 0);
      expect(result.unresolvedCount, 1);
      expect(result.diagnostics, contains('account_binding_mismatch'));
    });

    test(
      'reserved event claim recovers accepted order by exact client id',
      () async {
        final store = _trackingStore(tempHome);
        final binding =
            BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
              _credentials,
            );
        final eventId = List<String>.filled(64, 'd').join();
        await store.reserveLiquidityEventEffect(
          liquidityEventId: eventId,
          clientOrderId: 'hivra-recover-client',
          symbol: 'BTC-USDT',
          side: 'buy',
          intentHashHex: List<String>.filled(64, 'c').join(),
          canonicalIntentJson: '{"symbol":"BTC-USDT","side":"buy"}',
          testOrder: false,
          recordedAtUtc: '2026-08-13T10:00:00.000Z',
          accountBindingHashHex: binding,
        );
        final exchange = BingxFuturesExchangeService(
          requestSender: (request) async {
            expect(
              request.uri.query,
              contains('clientOrderId=hivra-recover-client'),
            );
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"orderID":"recovered-order","clientOrderId":"hivra-recover-client","symbol":"BTC-USDT","side":"BUY","status":"NEW"}}',
            );
          },
        );

        final result = await _reconciliationUseCase(
          exchange: exchange,
          store: store,
          riskHistory: riskHistory,
        ).reconcileManagedOrders(
          credentials: _credentials,
          openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
        );

        final claim =
            result.state!.liquidityEventEffectClaims['live|$eventId']!;
        expect(claim.status, BingxLiquidityEventEffectClaimStatus.confirmed);
        expect(claim.orderId, 'recovered-order');
        expect(claim.lifecycleStatus, BingxManagedOrderLifecycleStatus.active);
        expect(result.state!.managedOrderIds, <String>['recovered-order']);
        expect(
          result.state!.managedOrderProvenance,
          contains('recovered-order'),
        );
      },
    );

    test(
      'maps provider terminal statuses without recreating an effect',
      () async {
        final store = _trackingStore(tempHome);
        final binding =
            BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
              _credentials,
            );
        var providerStatus = 'CANCELED';
        final exchange = BingxFuturesExchangeService(
          requestSender:
              (_) async => BingxHttpResponse(
                statusCode: 200,
                body:
                    '{"code":0,"msg":"ok","data":{"orderID":"managed-terminal","clientOrderId":"managed-client","symbol":"BTC-USDT","side":"BUY","status":"$providerStatus"}}',
              ),
        );
        final useCase = _reconciliationUseCase(
          exchange: exchange,
          store: store,
          riskHistory: riskHistory,
        );
        const expected = <String, BingxManagedOrderLifecycleStatus>{
          'CANCELED': BingxManagedOrderLifecycleStatus.cancelled,
          'REJECTED': BingxManagedOrderLifecycleStatus.rejected,
          'EXPIRED': BingxManagedOrderLifecycleStatus.expired,
        };

        for (final entry in expected.entries) {
          providerStatus = entry.key;
          await store.save(
            _trackingState(
              orderId: 'managed-terminal',
              accountBindingHashHex: binding,
            ),
          );
          final result = await useCase.reconcileManagedOrders(
            credentials: _credentials,
            openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
          );
          expect(
            result
                .state!
                .managedOrderProvenance['managed-terminal']!
                .lifecycleStatus,
            entry.value,
            reason: entry.key,
          );
          expect(result.state!.managedOrderIds, isEmpty);
        }
      },
    );

    test(
      'provider not-found remains unresolved rather than terminal',
      () async {
        final store = _trackingStore(tempHome);
        final binding =
            BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
              _credentials,
            );
        await store.save(
          _trackingState(
            orderId: 'managed-missing',
            accountBindingHashHex: binding,
          ),
        );
        final exchange = BingxFuturesExchangeService(
          requestSender:
              (_) async => const BingxHttpResponse(
                statusCode: 200,
                body: '{"code":109421,"msg":"The order does not exist"}',
              ),
        );

        final result = await _reconciliationUseCase(
          exchange: exchange,
          store: store,
          riskHistory: riskHistory,
        ).reconcileManagedOrders(
          credentials: _credentials,
          openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
        );

        expect(result.unresolvedCount, 1);
        expect(result.diagnostics, contains('provider_query_109421'));
        expect(
          result
              .state!
              .managedOrderProvenance['managed-missing']!
              .lifecycleStatus,
          BingxManagedOrderLifecycleStatus.unresolved,
        );
      },
    );

    test('unknown provider status remains unresolved', () async {
      final store = _trackingStore(tempHome);
      final binding =
          BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
            _credentials,
          );
      await store.save(
        _trackingState(
          orderId: 'managed-unknown',
          accountBindingHashHex: binding,
        ),
      );
      final exchange = BingxFuturesExchangeService(
        requestSender:
            (_) async => const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"orderID":"managed-unknown","clientOrderId":"managed-client","symbol":"BTC-USDT","side":"BUY","status":"PENDING_REVIEW"}}',
            ),
      );

      final result = await _reconciliationUseCase(
        exchange: exchange,
        store: store,
        riskHistory: riskHistory,
      ).reconcileManagedOrders(
        credentials: _credentials,
        openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
      );

      expect(result.unresolvedCount, 1);
      expect(
        result.diagnostics,
        contains('provider_status_unknown:PENDING_REVIEW'),
      );
      expect(
        result
            .state!
            .managedOrderProvenance['managed-unknown']!
            .lifecycleStatus,
        BingxManagedOrderLifecycleStatus.unresolved,
      );
      expect(result.state!.managedOrderIds, isEmpty);
    });

    test('late reconciliation stays bound to the starting capsule', () async {
      var activeCapsule = List<String>.filled(64, 'a').join();
      final fileStore = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );
      final store = BingxFuturesOrderTrackingStore(
        readActiveCapsuleRootHex: () => activeCapsule,
        fileStore: fileStore,
      );
      final binding =
          BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
            _credentials,
          );
      await store.save(
        _trackingState(
          orderId: 'managed-capsule-a',
          accountBindingHashHex: binding,
        ),
      );
      final exchange = BingxFuturesExchangeService(
        requestSender: (_) async {
          activeCapsule = List<String>.filled(64, 'b').join();
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"orderID":"managed-capsule-a","clientOrderId":"managed-client","symbol":"BTC-USDT","side":"BUY","status":"FILLED"}}',
          );
        },
      );

      final result = await _reconciliationUseCase(
        exchange: exchange,
        store: store,
        riskHistory: riskHistory,
      ).reconcileManagedOrders(
        credentials: _credentials,
        openOrders: _openOrders(const <BingxFuturesOpenOrder>[]),
      );

      expect(result.capsuleRootHex, List<String>.filled(64, 'a').join());
      final capsuleA = await store.loadForCapsule(
        List<String>.filled(64, 'a').join(),
      );
      final capsuleB = await store.loadForCapsule(
        List<String>.filled(64, 'b').join(),
      );
      expect(
        capsuleA!.managedOrderProvenance['managed-capsule-a']!.lifecycleStatus,
        BingxManagedOrderLifecycleStatus.filled,
      );
      expect(capsuleB, isNull);
    });
  });
}

BingxFuturesOrderTrackingStore _trackingStore(Directory tempHome) {
  return BingxFuturesOrderTrackingStore(
    readActiveCapsuleRootHex: () => List<String>.filled(64, 'a').join(),
    fileStore: CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    ),
  );
}

Future<void> _setDroneEnabled(
  BingxFuturesOrderTrackingStore store,
  bool enabled, {
  bool testOrder = true,
}) {
  final now = DateTime.now().toUtc();
  final capsuleRootHex = store.activeCapsuleRootHex!;
  return store.save(
    BingxFuturesOrderTrackingState(
      trackedSymbol: null,
      trackedOrderId: null,
      managedOrderIds: const <String>[],
      managedOrderSymbols: const <String, String>{},
      droneEnabled: enabled,
      tradingMandate:
          enabled
              ? BingxFuturesTradingMandate.issue(
                capsuleRootHex: capsuleRootHex,
                accountBindingHashHex:
                    BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
                      _credentials,
                    ),
                symbol: 'BTC-USDT',
                testOrder: testOrder,
                issuedAtUtc: now,
                expiresAtUtc: now.add(const Duration(hours: 24)),
                maxOrderNotionalQuoteDecimal: '1000000000',
                maxRiskPerTradePercent: _policy.maxRiskPerTradePercent,
                maxDailyLossPercent: _policy.maxDailyLossPercent,
                maxConcurrentPositions: _policy.maxConcurrentPositions,
                cooldownAfterLossStreak: _policy.cooldownAfterLossStreak,
                cooldownMinutes: _policy.cooldownMinutes,
                maxEffects: 32,
              )
              : null,
      stopLossPercent: null,
      takeProfitRiskReward: null,
    ),
  );
}

BingxFuturesExchangeExecutionUseCaseService _reconciliationUseCase({
  required BingxFuturesExchangeService exchange,
  required BingxFuturesOrderTrackingStore store,
  required BingxFuturesRiskHistoryService riskHistory,
}) {
  return BingxFuturesExchangeExecutionUseCaseService(
    exchange: exchange,
    queue: BingxFuturesExecutionQueueService(exchangeService: exchange),
    riskHistory: riskHistory,
    orderTrackingStore: store,
  );
}

BingxFuturesOrderTrackingState _trackingState({
  required String orderId,
  required String accountBindingHashHex,
}) {
  return BingxFuturesOrderTrackingState(
    trackedSymbol: 'BTC-USDT',
    trackedOrderId: orderId,
    managedOrderIds: <String>[orderId],
    managedOrderSymbols: <String, String>{orderId: 'BTC-USDT'},
    managedOrderProvenance: <String, BingxManagedOrderProvenance>{
      orderId: BingxManagedOrderProvenance(
        orderId: orderId,
        symbol: 'BTC-USDT',
        side: 'buy',
        testOrder: false,
        intentHashHex: List<String>.filled(64, 'c').join(),
        canonicalIntentJson: '{"symbol":"BTC-USDT","side":"buy"}',
        clientOrderId: 'managed-client',
        accountBindingHashHex: accountBindingHashHex,
        lifecycleStatus: BingxManagedOrderLifecycleStatus.active,
        lifecycleEvidenceAtUtc: '2026-08-13T09:00:00.000Z',
        marketSnapshotHashHex: null,
        featureHashHex: null,
        tvhDecisionHashHex: null,
        liveDecisionHashHex: null,
        recordedAtUtc: '2026-08-13T09:00:00.000Z',
      ),
    },
    stopLossPercent: 5,
    takeProfitRiskReward: 2,
  );
}

BingxFuturesOpenOrdersResult _openOrders(List<BingxFuturesOpenOrder> orders) {
  return BingxFuturesOpenOrdersResult(
    isSuccess: true,
    httpStatusCode: 200,
    exchangeCode: '0',
    exchangeMessage: 'ok',
    endpointPath: '/openApi/swap/v2/trade/openOrders',
    signedPayloadHashHex: List<String>.filled(64, 'e').join(),
    responseBody: '{}',
    symbol: 'ALL',
    orders: orders,
  );
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

BingxFuturesTradingMandate _mandate({
  required DateTime now,
  String? capsuleRootHex,
  String? accountBindingHashHex,
  String symbol = 'BTC-USDT',
  bool testOrder = true,
  String maxNotional = '1000',
  double maxRiskPerTradePercent = 2,
}) {
  return BingxFuturesTradingMandate.issue(
    capsuleRootHex: capsuleRootHex ?? List<String>.filled(64, 'a').join(),
    accountBindingHashHex:
        accountBindingHashHex ??
        BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
          _credentials,
        ),
    symbol: symbol,
    testOrder: testOrder,
    issuedAtUtc: now,
    expiresAtUtc: now.add(const Duration(hours: 1)),
    maxOrderNotionalQuoteDecimal: maxNotional,
    maxRiskPerTradePercent: maxRiskPerTradePercent,
    maxDailyLossPercent: 5,
    maxConcurrentPositions: 3,
    cooldownAfterLossStreak: 2,
    cooldownMinutes: 60,
    maxEffects: 32,
  );
}

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
  String zoneLowDecimal = '99',
  String zoneHighDecimal = '101',
}) {
  return BingxFuturesLiveDecisionResult(
    canPrepareIntent: true,
    decision: BingxTvhDecisionKind.long,
    side: 'buy',
    zoneSide: 'buyside',
    zoneLowDecimal: zoneLowDecimal,
    zoneHighDecimal: zoneHighDecimal,
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
