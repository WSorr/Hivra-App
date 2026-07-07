import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_revalidation_service.dart';

void main() {
  group('BingxFuturesOrderRevalidationService', () {
    const service = BingxFuturesOrderRevalidationService();

    test('keeps managed order that still matches live TVH zone', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'SELL',
          priceDecimal: '104.5',
          triggerPriceDecimal: '104.5',
        ),
        liveDecision: _decision(
          side: 'sell',
          zoneLowDecimal: '104.0',
          zoneHighDecimal: '105.0',
          canPrepareIntent: true,
        ),
      );

      expect(result.shouldCancel, isFalse);
      expect(result.reasonCode, 'live_setup_still_valid');
    });

    test('cancels order when momentum gate says retest was missed', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'SELL',
          priceDecimal: '104.5',
          triggerPriceDecimal: '104.5',
        ),
        liveDecision: _decision(
          side: 'sell',
          zoneLowDecimal: '104.0',
          zoneHighDecimal: '105.0',
          canPrepareIntent: false,
          trendGateBlocked: true,
          trendGateCode: 'momentum_gate_short_missed_retest',
        ),
      );

      expect(result.shouldCancel, isTrue);
      expect(result.reasonCode, 'momentum_gate_short_missed_retest');
    });

    test('cancels order when live side flips', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'SELL',
          priceDecimal: '104.5',
          triggerPriceDecimal: '104.5',
        ),
        liveDecision: _decision(
          side: 'buy',
          zoneLowDecimal: '98.0',
          zoneHighDecimal: '99.0',
          canPrepareIntent: true,
        ),
      );

      expect(result.shouldCancel, isTrue);
      expect(result.reasonCode, 'live_side_mismatch');
    });

    test('cancels order when price leaves current live zone', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'SELL',
          priceDecimal: '112.0',
          triggerPriceDecimal: '112.0',
        ),
        liveDecision: _decision(
          side: 'sell',
          zoneLowDecimal: '104.0',
          zoneHighDecimal: '105.0',
          canPrepareIntent: true,
        ),
      );

      expect(result.shouldCancel, isTrue);
      expect(result.reasonCode, 'live_zone_mismatch');
    });

    test('cancels NO_SIGNAL order outside side-locked structural zone', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'BUY',
          priceDecimal: '560.0',
          triggerPriceDecimal: '560.0',
        ),
        liveDecision: _decision(
          side: null,
          zoneEvaluationSide: 'buy',
          zoneLowDecimal: '595.0',
          zoneHighDecimal: '597.0',
          canPrepareIntent: false,
          decision: BingxTvhDecisionKind.noSignal,
        ),
      );

      expect(result.shouldCancel, isTrue);
      expect(result.reasonCode, 'live_zone_mismatch');
    });

    test('cancels NO_SIGNAL order when structural anchor is unavailable', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'BUY',
          priceDecimal: '560.0',
          triggerPriceDecimal: '560.0',
        ),
        liveDecision: _decision(
          side: null,
          zoneEvaluationSide: 'buy',
          zoneLowDecimal: '559.0',
          zoneHighDecimal: '561.0',
          canPrepareIntent: false,
          decision: BingxTvhDecisionKind.noSignal,
          zoneAnchorExecutable: false,
        ),
      );

      expect(result.shouldCancel, isTrue);
      expect(result.reasonCode, 'liquidity_anchor_unavailable');
    });

    test('keeps NO_SIGNAL order inside side-locked structural zone', () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'BUY',
          priceDecimal: '560.0',
          triggerPriceDecimal: '560.0',
        ),
        liveDecision: _decision(
          side: null,
          zoneEvaluationSide: 'buy',
          zoneLowDecimal: '559.0',
          zoneHighDecimal: '561.0',
          canPrepareIntent: false,
          decision: BingxTvhDecisionKind.noSignal,
        ),
      );

      expect(result.shouldCancel, isFalse);
      expect(result.reasonCode, 'structural_setup_still_valid');
    });

    test('keeps plain NO_SIGNAL when no structural evaluation was requested',
        () {
      final result = service.revalidate(
        order: _openOrder(
          side: 'BUY',
          priceDecimal: '560.0',
          triggerPriceDecimal: '560.0',
        ),
        liveDecision: _decision(
          side: null,
          zoneLowDecimal: null,
          zoneHighDecimal: null,
          canPrepareIntent: false,
          decision: BingxTvhDecisionKind.noSignal,
          zoneAnchorExecutable: false,
        ),
      );

      expect(result.shouldCancel, isFalse);
      expect(result.reasonCode, 'live_decision_not_actionable');
    });
  });
}

BingxFuturesOpenOrder _openOrder({
  required String side,
  required String priceDecimal,
  required String triggerPriceDecimal,
}) {
  return BingxFuturesOpenOrder(
    orderId: 'ord-1',
    symbol: 'BNB-USDT',
    side: side,
    positionSide: side == 'BUY' ? 'LONG' : 'SHORT',
    orderType: 'TRIGGER_LIMIT',
    status: 'NEW',
    priceDecimal: priceDecimal,
    triggerPriceDecimal: triggerPriceDecimal,
    quantityDecimal: '0.01',
    executedQuantityDecimal: '0',
    createdAtMs: 1780577371423,
  );
}

BingxFuturesLiveDecisionResult _decision({
  required String? side,
  required String? zoneLowDecimal,
  required String? zoneHighDecimal,
  required bool canPrepareIntent,
  BingxTvhDecisionKind? decision,
  String? zoneEvaluationSide,
  bool zoneAnchorExecutable = true,
  bool trendGateBlocked = false,
  String trendGateCode = 'ok',
}) {
  return BingxFuturesLiveDecisionResult(
    canPrepareIntent: canPrepareIntent,
    decision: decision ??
        (side == 'buy'
            ? BingxTvhDecisionKind.long
            : BingxTvhDecisionKind.short),
    side: side,
    zoneSide: (side ?? zoneEvaluationSide) == 'buy'
        ? 'buyside'
        : (side ?? zoneEvaluationSide) == 'sell'
            ? 'sellside'
            : null,
    zoneLowDecimal: zoneLowDecimal,
    zoneHighDecimal: zoneHighDecimal,
    zoneConflict: false,
    marketSnapshotHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    featureHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    tvhDecisionHashHex:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    liveDecisionHashHex:
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    canonicalJson: '{"decision":"stub"}',
    reasons: <BingxTvhDecisionReason>[
      BingxTvhDecisionReason(
        code: trendGateCode,
        passed: !trendGateBlocked,
        detail: trendGateCode,
      ),
    ],
    trend15m: side == 'buy' ? 'bullish' : 'bearish',
    trend4h: side == 'buy' ? 'bull' : 'bear',
    trend1d: side == 'buy' ? 'bull' : 'bear',
    trendGateBlocked: trendGateBlocked,
    trendGateCode: trendGateCode,
    zoneEvaluationSide: zoneEvaluationSide ?? side,
    zoneAnchorExecutable: zoneAnchorExecutable,
  );
}
