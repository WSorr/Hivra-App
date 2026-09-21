import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_execution_models.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_execution_queue_models.dart';
import 'package:hivra_app/models/bingx_futures_intent_models.dart';
import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_live_strategy_models.dart';
import 'package:hivra_app/models/bingx_futures_observability_models.dart';
import 'package:hivra_app/models/bingx_futures_order_sizing_models.dart';
import 'package:hivra_app/models/bingx_futures_risk_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/bingx_futures_trading_cycle_use_case_service.dart';

void main() {
  group('shared structural stop', () {
    for (final side in ['buy', 'sell']) {
      test('$side uses instrument precision before risk and sizing', () {
        final result = deriveBingxFuturesLiquidityTargets(
          side: side,
          entryPrice: 100,
          zoneLow: 98.876,
          zoneHigh: 101.124,
          atr14m5Decimal: '1',
          stopLossPercent: 1,
          minimumRiskReward: 2,
          oppositeLiquidityTargetDecimal: side == 'buy' ? '110.129' : '89.871',
          pricePrecision: 2,
        );
        expect(result.blockerCode, isNull);
        expect(result.stopLossDecimal, side == 'buy' ? '98.87' : '101.13');
        expect(result.takeProfitDecimal, side == 'buy' ? '110.12' : '89.88');
        expect(result.notionalScale, closeTo(1 / 1.13, 1e-10));
        expect(result.actualRiskReward, closeTo(10.12 / 1.13, 1e-10));
      });
    }
    test('integer price formatting preserves significant zeroes', () {
      expect(bingxFuturesPriceDecimal(100, precision: 0), '100');
      expect(
        bingxFuturesPriceDecimal(100.123, precision: 2, roundUp: true),
        '100.13',
      );
      expect(
        bingxFuturesPriceDecimal(100.123, precision: 2, roundUp: false),
        '100.12',
      );
    });
    test('risk reward uses the serialized target rather than extra digits', () {
      final result = deriveBingxFuturesLiquidityTargets(
        side: 'buy',
        entryPrice: 100,
        zoneLow: 99,
        zoneHigh: 101,
        atr14m5Decimal: '1',
        stopLossPercent: 1,
        minimumRiskReward: 2.000000001,
        oppositeLiquidityTargetDecimal: '102.000000004',
      );
      expect(result.takeProfitDecimal, '102');
      expect(result.actualRiskReward, 2);
      expect(result.blockerCode, 'opposite_liquidity_risk_reward_insufficient');
    });
    for (final side in ['buy', 'sell']) {
      test('$side uses structure and reduces notional to the loss budget', () {
        final result = deriveBingxFuturesLiquidityTargets(
          side: side,
          entryPrice: 100,
          zoneLow: 95,
          zoneHigh: 105,
          atr14m5Decimal: '1',
          stopLossPercent: 1,
          minimumRiskReward: 2,
          oppositeLiquidityTargetDecimal: side == 'buy' ? '120' : '80',
        );
        expect(result.blockerCode, isNull);
        expect(result.stopLossDecimal, side == 'buy' ? '95' : '105');
        expect(result.actualRiskReward, 4);
        expect(result.notionalScale, closeTo(0.2, 1e-9));
      });
      test('$side ATR floor never moves stop inside the entry structure', () {
        final result = deriveBingxFuturesLiquidityTargets(
          side: side,
          entryPrice: 100,
          zoneLow: 99,
          zoneHigh: 101,
          atr14m5Decimal: '5',
          stopLossPercent: 10,
          minimumRiskReward: 2,
          oppositeLiquidityTargetDecimal: side == 'buy' ? '120' : '80',
        );
        expect(result.stopLossDecimal, side == 'buy' ? '96' : '104');
        expect(result.notionalScale, 1);
        expect(result.actualRiskReward, 5);
      });
    }
    for (final atr in [null, 'NaN', 'Infinity', '0', '-1']) {
      test(
        'missing or invalid ATR $atr cannot fall back to percentage stop',
        () {
          final result = deriveBingxFuturesLiquidityTargets(
            side: 'buy',
            entryPrice: 100,
            zoneLow: 99,
            zoneHigh: 101,
            atr14m5Decimal: atr,
            stopLossPercent: 1,
            minimumRiskReward: 2,
            oppositeLiquidityTargetDecimal: '120',
          );
          expect(result.blockerCode, 'structural_stop_unavailable');
          expect(result.stopLossDecimal, isNull);
          expect(result.notionalScale, 0);
        },
      );
    }
  });
  group('BingxFuturesTradingCycleUseCaseService', () {
    test('missing instrument precision never prepares or executes', () async {
      final service = _service(
        pricePrecision: null,
        intentRunner: (_) async => throw StateError('unexpected intent'),
        executionRunner: _executionRunner(
          onCall: () => fail('unexpected effect'),
        ),
      );
      final result = await service.run(_command(executeEffect: false));
      expect(result.reasonCode, 'contract_price_precision_unavailable');
    });
    test('prepared entry uses the same instrument price as sizing', () async {
      final service = _service(
        pricePrecision: 2,
        decision: _decision(low: '99.012', high: '101.016', atr: '1'),
        intentRunner: (command) async {
          expect(command.zonePriceRule, 'manual');
          expect(command.manualEntryPriceDecimal, '100.01');
          expect(command.triggerPriceDecimal, '101.02');
          expect(command.stopLossDecimal, '99.01');
          return _intentResult(command);
        },
        executionRunner: _executionRunner(
          onCall: () => fail('unexpected effect'),
        ),
      );
      final result = await service.run(_command(executeEffect: false));
      expect(result.status, BingxFuturesTradingCycleStatus.prepared);
    });
    test('wider ATR stop reaches sizing as a smaller notional cap', () async {
      num? cap;
      final service = _service(
        decision: _decision(atr: '25', oppositeLiquidityTargetDecimal: '160'),
        sizingRunner: ({
          required rules,
          required symbol,
          required maximumNotionalQuote,
          required referencePriceDecimal,
        }) async {
          cap = maximumNotionalQuote;
          return const BingxFuturesOrderSizingResult(
            status: BingxFuturesOrderSizingStatus.sized,
            reasonCode: 'sized',
            reasonMessage: 'ok',
            quantityDecimal: '0.5',
            orderNotionalQuoteDecimal: '50',
            minimumQuantityDecimal: '0.001',
            minimumNotionalQuoteDecimal: '2',
          );
        },
        executionRunner: _executionRunner(
          onCall: () => fail('unexpected effect'),
        ),
      );
      final result = await service.run(_command(executeEffect: false));
      expect(result.status, BingxFuturesTradingCycleStatus.prepared);
      expect(cap, 50);
      expect(result.stopLossDecimal, '80');
    });
    test(
      'prepares the canonical solo limit intent without an effect',
      () async {
        BingxFuturesIntentCommand? capturedIntent;
        var executionCalls = 0;
        final service = _service(
          intentRunner: (command) async {
            capturedIntent = command;
            return _intentResult(command);
          },
          executionRunner: _executionRunner(onCall: () => executionCalls += 1),
        );

        final result = await service.run(_command(executeEffect: false));

        expect(result.status, BingxFuturesTradingCycleStatus.prepared);
        expect(executionCalls, 0);
        expect(capturedIntent!.clientOrderId, 'hivra-$_eventPrefix');
        expect(capturedIntent!.entryMode, 'zone_pending');
        expect(capturedIntent!.quantityDecimal, '0.5');
        expect(capturedIntent!.stopLossDecimal, '90');
        expect(capturedIntent!.takeProfitDecimal, '120');
        expect(capturedIntent!.liveDecision!.liquidityEventId, _eventId);
      },
    );

    test('sizes a pending buy against its exact zone-mid price', () async {
      String? capturedReferencePrice;
      BingxFuturesIntentCommand? capturedIntent;
      final service = _service(
        sizingRunner: ({
          required rules,
          required symbol,
          required maximumNotionalQuote,
          required referencePriceDecimal,
        }) async {
          capturedReferencePrice = referencePriceDecimal;
          return const BingxFuturesOrderSizingResult(
            status: BingxFuturesOrderSizingStatus.sized,
            reasonCode: 'sized',
            reasonMessage: 'ok',
            quantityDecimal: '0.13',
            orderNotionalQuoteDecimal: '96.99125',
            minimumQuantityDecimal: '0.01',
            minimumNotionalQuoteDecimal: '2',
          );
        },
        intentRunner: (command) async {
          capturedIntent = command;
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () {}),
      );

      final result = await service.run(_command(executeEffect: false));

      expect(result.status, BingxFuturesTradingCycleStatus.prepared);
      expect(capturedReferencePrice, '100');
      expect(capturedIntent!.quantityDecimal, '0.13');
      expect(capturedIntent!.triggerPriceDecimal, '110');
    });

    test('sizes a pending sell against its exact zone-mid price', () async {
      String? capturedReferencePrice;
      BingxFuturesIntentCommand? capturedIntent;
      final service = _service(
        decision: _decision(decision: BingxTvhDecisionKind.short, side: 'sell'),
        sizingRunner: ({
          required rules,
          required symbol,
          required maximumNotionalQuote,
          required referencePriceDecimal,
        }) async {
          capturedReferencePrice = referencePriceDecimal;
          return const BingxFuturesOrderSizingResult(
            status: BingxFuturesOrderSizingStatus.sized,
            reasonCode: 'sized',
            reasonMessage: 'ok',
            quantityDecimal: '0.13',
            orderNotionalQuoteDecimal: '11.7',
            minimumQuantityDecimal: '0.01',
            minimumNotionalQuoteDecimal: '2',
          );
        },
        intentRunner: (command) async {
          capturedIntent = command;
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () {}),
      );

      final result = await service.run(_command(executeEffect: false));

      expect(result.status, BingxFuturesTradingCycleStatus.prepared);
      expect(capturedReferencePrice, '100');
      expect(capturedIntent!.quantityDecimal, '0.13');
      expect(capturedIntent!.triggerPriceDecimal, '90');
      expect(capturedIntent!.takeProfitDecimal, '70');
    });

    test('blocks when fresh opposite liquidity is unavailable', () async {
      var intentCalls = 0;
      final service = _service(
        decision: _decision(oppositeLiquidityTargetDecimal: null),
        intentRunner: (command) async {
          intentCalls += 1;
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () {}),
      );

      final result = await service.run(_command(executeEffect: false));

      expect(result.status, BingxFuturesTradingCycleStatus.marketBlocked);
      expect(result.reasonCode, 'opposite_liquidity_target_unavailable');
      expect(intentCalls, 0);
    });

    test('blocks opposite liquidity on the wrong side of entry', () async {
      final service = _service(
        decision: _decision(oppositeLiquidityTargetDecimal: '95'),
        executionRunner: _executionRunner(onCall: () {}),
      );

      final result = await service.run(_command(executeEffect: false));

      expect(result.status, BingxFuturesTradingCycleStatus.marketBlocked);
      expect(result.reasonCode, 'opposite_liquidity_target_wrong_side');
    });

    test('uses R only as a minimum quality gate', () async {
      final service = _service(
        decision: _decision(oppositeLiquidityTargetDecimal: '115'),
        executionRunner: _executionRunner(onCall: () {}),
      );

      final result = await service.run(_command(executeEffect: false));

      expect(result.status, BingxFuturesTradingCycleStatus.marketBlocked);
      expect(result.reasonCode, 'opposite_liquidity_risk_reward_insufficient');
      expect(result.takeProfitDecimal, '115');
    });

    test('rejects missing event evidence before intent or effect', () async {
      var intentCalls = 0;
      var executionCalls = 0;
      final service = _service(
        decision: _decision(eventId: null),
        intentRunner: (command) async {
          intentCalls += 1;
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () => executionCalls += 1),
      );

      final result = await service.run(_command(executeEffect: true));

      expect(result.status, BingxFuturesTradingCycleStatus.marketBlocked);
      expect(result.reasonCode, 'liquidity_event_evidence_missing');
      expect(intentCalls, 0);
      expect(executionCalls, 0);
    });

    test(
      'projects the exact market blocker without preparing an effect',
      () async {
        var intentCalls = 0;
        var executionCalls = 0;
        final service = _service(
          decision: _decision(
            canPrepareIntent: false,
            decision: BingxTvhDecisionKind.noSignal,
            side: null,
            reasons: const <BingxTvhDecisionReason>[
              BingxTvhDecisionReason(
                code: 'long_trade_imbalance',
                passed: false,
                detail: 'below_threshold',
              ),
              BingxTvhDecisionReason(
                code: 'short_trade_imbalance',
                passed: false,
                detail: 'above_threshold',
              ),
            ],
          ),
          intentRunner: (command) async {
            intentCalls += 1;
            return _intentResult(command);
          },
          executionRunner: _executionRunner(onCall: () => executionCalls += 1),
        );

        final result = await service.run(_command(executeEffect: true));

        expect(result.status, BingxFuturesTradingCycleStatus.marketBlocked);
        expect(result.reasonCode, 'market_volume_activation_unavailable');
        expect(
          result.reasonMessage,
          'Buyers and sellers are still balanced. The drone will wait for a clearer move.',
        );
        expect(intentCalls, 0);
        expect(executionCalls, 0);
      },
    );

    test('rejects sizing failure before intent or effect', () async {
      var intentCalls = 0;
      var executionCalls = 0;
      final service = _service(
        sizing: const BingxFuturesOrderSizingResult(
          status: BingxFuturesOrderSizingStatus.blocked,
          reasonCode: 'exchange_minimum_exceeds_risk_budget',
          reasonMessage: 'blocked',
          quantityDecimal: null,
          orderNotionalQuoteDecimal: null,
          minimumQuantityDecimal: '1',
          minimumNotionalQuoteDecimal: '200',
        ),
        intentRunner: (command) async {
          intentCalls += 1;
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () => executionCalls += 1),
      );

      final result = await service.run(_command(executeEffect: true));

      expect(result.status, BingxFuturesTradingCycleStatus.sizingBlocked);
      expect(result.reasonCode, 'exchange_minimum_exceeds_risk_budget');
      expect(intentCalls, 0);
      expect(executionCalls, 0);
    });

    test('requires credentials before the canonical effect owner', () async {
      var executionCalls = 0;
      final service = _service(
        executionRunner: _executionRunner(onCall: () => executionCalls += 1),
      );

      final result = await service.run(
        _command(executeEffect: true, credentials: null),
      );

      expect(result.status, BingxFuturesTradingCycleStatus.executionBlocked);
      expect(result.reasonCode, 'trading_credentials_required');
      expect(executionCalls, 0);
    });

    test('keeps a rejected WASM intent away from the effect owner', () async {
      var executionCalls = 0;
      final service = _service(
        intentRunner:
            (command) async => _intentResult(
              command,
              status: PluginHostApiStatus.rejected,
              errorCode: 'plugin_rejected',
            ),
        executionRunner: _executionRunner(onCall: () => executionCalls += 1),
      );

      final result = await service.run(_command(executeEffect: true));

      expect(result.status, BingxFuturesTradingCycleStatus.intentBlocked);
      expect(result.reasonCode, 'plugin_rejected');
      expect(executionCalls, 0);
    });

    test('maps host timeout without reaching the effect owner', () async {
      var executionCalls = 0;
      final service = _service(
        intentTimeout: const Duration(milliseconds: 1),
        intentRunner: (command) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _intentResult(command);
        },
        executionRunner: _executionRunner(onCall: () => executionCalls += 1),
      );

      final result = await service.run(_command(executeEffect: true));

      expect(result.status, BingxFuturesTradingCycleStatus.intentBlocked);
      expect(result.reasonCode, 'host_intent_timeout');
      expect(executionCalls, 0);
    });

    test(
      'delegates one effect and refresh to the existing execution owner',
      () async {
        var liveCalls = 0;
        var executionCalls = 0;
        BingxFuturesLiveDecisionResult? refreshed;
        final service = _service(
          liveRunner: (command) async {
            liveCalls += 1;
            return _liveResult(_decision());
          },
          executionRunner: ({
            required screen,
            required rawIntentResult,
            required credentials,
            required riskPolicy,
            required testOrder,
            preparedDecision,
            refreshDecision,
          }) async {
            executionCalls += 1;
            refreshed = await refreshDecision!();
            expect(preparedDecision!.liquidityEventId, _eventId);
            expect(rawIntentResult['client_order_id'], 'hivra-$_eventPrefix');
            return _executedResult;
          },
        );

        final result = await service.run(_command(executeEffect: true));

        expect(result.status, BingxFuturesTradingCycleStatus.executed);
        expect(executionCalls, 1);
        expect(liveCalls, 2);
        expect(refreshed!.liquidityEventId, _eventId);
      },
    );

    test(
      'projects test validation without claiming an exchange effect',
      () async {
        final service = _service(
          executionRunner: ({
            required screen,
            required rawIntentResult,
            required credentials,
            required riskPolicy,
            required testOrder,
            preparedDecision,
            refreshDecision,
          }) async {
            expect(testOrder, isTrue);
            return _validatedResult();
          },
        );

        final result = await service.run(
          _command(executeEffect: true, testOrder: true),
        );

        expect(result.status, BingxFuturesTradingCycleStatus.validated);
        expect(result.reasonCode, 'request_validated');
        expect(
          result.reasonMessage,
          'Exact request validated; no exchange order was created.',
        );
        expect(result.isPrepared, isTrue);
      },
    );

    test(
      'rejects contradictory executed outcome without provider success',
      () async {
        final service = _service(
          executionRunner:
              ({
                required screen,
                required rawIntentResult,
                required credentials,
                required riskPolicy,
                required testOrder,
                preparedDecision,
                refreshDecision,
              }) async => _providerRejectedResult,
        );

        final result = await service.run(_command(executeEffect: true));

        expect(result.status, BingxFuturesTradingCycleStatus.executionBlocked);
        expect(result.reasonCode, 'exchange_effect_failed');
        expect(result.isPrepared, isFalse);
      },
    );
  });
}

BingxFuturesTradingCycleUseCaseService _service({
  int? pricePrecision = 8,
  BingxFuturesLiveDecisionResult? decision,
  BingxFuturesOrderSizingResult sizing = const BingxFuturesOrderSizingResult(
    status: BingxFuturesOrderSizingStatus.sized,
    reasonCode: 'sized',
    reasonMessage: 'ok',
    quantityDecimal: '0.5',
    orderNotionalQuoteDecimal: '50',
    minimumQuantityDecimal: '0.001',
    minimumNotionalQuoteDecimal: '2',
  ),
  BingxFuturesLiveStrategyCycleRunner? liveRunner,
  BingxFuturesOrderSizingCycleRunner? sizingRunner,
  BingxFuturesIntentCycleRunner? intentRunner,
  required BingxFuturesExecutionCycleRunner executionRunner,
  Duration intentTimeout = const Duration(seconds: 20),
}) {
  return BingxFuturesTradingCycleUseCaseService(
    contractRulesLoader:
        (symbol) async => BingxFuturesContractRules(
          symbol: symbol,
          minimumQuantityDecimal: '0.001',
          minimumNotionalQuoteDecimal: '2',
          quantityPrecision: 3,
          pricePrecision: pricePrecision,
        ),
    liveStrategyRunner:
        liveRunner ?? (command) async => _liveResult(decision ?? _decision()),
    sizingRunner:
        sizingRunner ??
        ({
          required symbol,
          required maximumNotionalQuote,
          required referencePriceDecimal,
          required rules,
        }) async => sizing,
    intentRunner: intentRunner ?? (command) async => _intentResult(command),
    executionRunner: executionRunner,
    nowUtc: () => DateTime.utc(2026, 8, 16),
    intentTimeout: intentTimeout,
  );
}

BingxFuturesTradingCycleCommand _command({
  required bool executeEffect,
  BingxFuturesApiCredentials? credentials = _credentials,
  bool testOrder = false,
}) {
  return BingxFuturesTradingCycleCommand(
    screen: 'test_headless_cycle',
    symbol: 'btc-usdt',
    preferredSide: 'buy',
    maximumNotionalQuote: 100,
    stopLossPercent: 10,
    takeProfitRiskReward: 2,
    credentials: credentials,
    riskPolicy: _policy,
    testOrder: testOrder,
    executeEffect: executeEffect,
    recentMicroBars: 8,
    zoneNearBps: 15,
    zoneFarBps: 35,
  );
}

BingxFuturesLiveStrategyResult _liveResult(
  BingxFuturesLiveDecisionResult decision,
) {
  return BingxFuturesLiveStrategyResult(
    decision: decision,
    symbol: 'BTC-USDT',
    errorCode: null,
    errorMessage: null,
    diagnostic: 'ok',
  );
}

BingxFuturesLiveDecisionResult _decision({
  String? eventId = _eventId,
  bool canPrepareIntent = true,
  BingxTvhDecisionKind decision = BingxTvhDecisionKind.long,
  String? side = 'buy',
  List<BingxTvhDecisionReason> reasons = const <BingxTvhDecisionReason>[],
  String? oppositeLiquidityTargetDecimal = '120',
  String? atr = '12.5',
  String low = '90',
  String high = '110',
}) {
  return BingxFuturesLiveDecisionResult(
    atr14m5Decimal: atr,
    canPrepareIntent: canPrepareIntent,
    decision: decision,
    side: side,
    zoneSide: 'buyside',
    zoneLowDecimal: low,
    zoneHighDecimal: high,
    zoneConflict: false,
    marketSnapshotHashHex: _hash1,
    featureHashHex: _hash2,
    tvhDecisionHashHex: _hash3,
    liveDecisionHashHex: _hash4,
    canonicalJson: '{}',
    reasons: reasons,
    trend15m: 'bullish',
    trend4h: 'bull',
    trend1d: 'bull',
    trendGateBlocked: false,
    trendGateCode: 'ok',
    liquidityEventId: eventId,
    liquidityEventAtUtc: '2026-08-16T00:00:00.000Z',
    latestClosedMicroBarAtUtc: '2026-08-16T00:05:00.000Z',
    oppositeLiquidityTargetDecimal:
        side == 'sell' && oppositeLiquidityTargetDecimal == '120'
            ? '70'
            : oppositeLiquidityTargetDecimal,
    oppositeLiquidityTargetSource: '1d_fresh_high',
    oppositeLiquidityTargetAtUtc: '2026-08-15T00:00:00.000Z',
  );
}

BingxFuturesIntentUseCaseResult _intentResult(
  BingxFuturesIntentCommand command, {
  PluginHostApiStatus status = PluginHostApiStatus.executed,
  String? errorCode,
}) {
  return BingxFuturesIntentUseCaseResult(
    response: PluginHostApiResponse(
      status: status,
      pluginId: 'hivra.contract.bingx-futures-trading.v1',
      method: 'place_bingx_futures_order_intent',
      executionSource: 'test',
      executionPackageId: null,
      executionPackageVersion: null,
      executionPackageKind: null,
      executionPackageDigestHex: null,
      executionContractKind: 'bingx_futures_order_intent',
      executionRuntimeMode: null,
      executionRuntimeAbi: null,
      executionRuntimeEntryExport: null,
      executionRuntimeModulePath: null,
      executionRuntimeModuleSelection: null,
      executionRuntimeModuleDigestHex: null,
      executionRuntimeInvokeDigestHex: null,
      executionCapabilities: const <String>[],
      errorCode: errorCode,
      errorMessage: errorCode == null ? null : 'rejected',
      blockingFacts: const [],
      result:
          status == PluginHostApiStatus.executed
              ? <String, dynamic>{
                'client_order_id': command.clientOrderId,
                'intent_hash_hex': _hash5,
                'canonical_intent_json': '{}',
                'symbol': command.symbol,
                'side': command.side,
                'order_type': command.orderType,
                'quantity_decimal': command.quantityDecimal,
              }
              : null,
      canonicalJson: '{}',
      responseHashHex: _hash6,
    ),
    decisionEnvelope: BingxFuturesLogEnvelope(
      canonicalJson: '{}',
      envelopeHashHex: _hash7,
    ),
  );
}

BingxFuturesExecutionCycleRunner _executionRunner({
  required void Function() onCall,
}) {
  return ({
    required screen,
    required rawIntentResult,
    required credentials,
    required riskPolicy,
    required testOrder,
    preparedDecision,
    refreshDecision,
  }) async {
    onCall();
    return _executedResult;
  };
}

const _credentials = BingxFuturesApiCredentials(
  apiKey: 'key',
  apiSecret: 'secret',
);
const _policy = BingxFuturesRiskPolicy(
  maxRiskPerTradePercent: 2,
  maxDailyLossPercent: 5,
  maxConcurrentPositions: 3,
  cooldownAfterLossStreak: 2,
  cooldownMinutes: 60,
);
const _eventId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _eventPrefix = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hash1 =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _hash2 =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _hash3 =
    '3333333333333333333333333333333333333333333333333333333333333333';
const _hash4 =
    '4444444444444444444444444444444444444444444444444444444444444444';
const _hash5 =
    '5555555555555555555555555555555555555555555555555555555555555555';
const _hash6 =
    '6666666666666666666666666666666666666666666666666666666666666666';
const _hash7 =
    '7777777777777777777777777777777777777777777777777777777777777777';
const _executedResult = BingxFuturesExchangeExecutionUseCaseResult(
  status: BingxFuturesExchangeExecutionUseCaseStatus.executed,
  payload: null,
  riskDecision: null,
  queuedExecution: BingxQueuedExecutionResult(
    execution: BingxFuturesOrderExecutionResult(
      isSuccess: true,
      httpStatusCode: 200,
      exchangeCode: '0',
      exchangeMessage: 'ok',
      orderId: 'order-1',
      endpointPath: '/order/test',
      signedPayloadHashHex: _hash1,
      responseBody: '{}',
      intentHashHex: _hash5,
    ),
    attempts: 1,
    fromIdempotentCache: false,
    exhaustedRetries: false,
    idempotencyKey: 'effect-1',
  ),
  executionEnvelope: BingxFuturesLogEnvelope(
    canonicalJson: '{}',
    envelopeHashHex:
        '8888888888888888888888888888888888888888888888888888888888888888',
  ),
  errorCode: null,
  errorMessage: null,
  diagnostics: <String>[],
);

BingxFuturesExchangeExecutionUseCaseResult _validatedResult() {
  return BingxFuturesExchangeExecutionUseCaseResult(
    status: BingxFuturesExchangeExecutionUseCaseStatus.validated,
    payload: _executedResult.payload,
    riskDecision: _executedResult.riskDecision,
    queuedExecution: _executedResult.queuedExecution,
    executionEnvelope: _executedResult.executionEnvelope,
    errorCode: null,
    errorMessage: null,
    diagnostics: const <String>[],
  );
}

const _providerRejectedResult = BingxFuturesExchangeExecutionUseCaseResult(
  status: BingxFuturesExchangeExecutionUseCaseStatus.executed,
  payload: null,
  riskDecision: null,
  queuedExecution: BingxQueuedExecutionResult(
    execution: BingxFuturesOrderExecutionResult(
      isSuccess: false,
      httpStatusCode: 400,
      exchangeCode: '100001',
      exchangeMessage: 'rejected',
      orderId: null,
      endpointPath: '/order/test',
      signedPayloadHashHex: _hash1,
      responseBody: '{}',
      intentHashHex: _hash5,
    ),
    attempts: 1,
    fromIdempotentCache: false,
    exhaustedRetries: false,
    idempotencyKey: 'effect-rejected',
  ),
  executionEnvelope: BingxFuturesLogEnvelope(
    canonicalJson: '{}',
    envelopeHashHex:
        '9999999999999999999999999999999999999999999999999999999999999999',
  ),
  errorCode: null,
  errorMessage: null,
  diagnostics: <String>[],
);
