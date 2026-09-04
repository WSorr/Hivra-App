import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/utils/bingx_futures_zone_evidence_formatter.dart';

void main() {
  test('blocked entry preserves both sides as observations, not order prices', () {
    final decision = _decision(
      canPrepareIntent: false,
      anchorExecutable: false,
      levels: [
        for (final side in ['buyside', 'sellside'])
          BingxDetectedLiquidityLevel(
            side: side, levelClass: 'internal', centerPriceDecimal: '100',
            zoneTopDecimal: '101', zoneBottomDecimal: '99', pivotCount: 3,
            breached: side == 'sellside', anchorIndex: 8,
            breachedIndex: side == 'sellside' ? 20 : null,
          ),
      ],
    );
    final text = formatBingxFuturesLiquidityObservation(decision);
    expect(text, contains('Buyside 99–101 · 3 pivots · Untouched'));
    expect(text, contains('Sellside 99–101 · 3 pivots · Swept'));
    expect(text, contains('No confirmed executable setup'));
    expect(text, contains('snapshot, not order prices'));
    expect(decision.canPrepareIntent, isFalse);
    expect(decision.zoneAnchorExecutable, isFalse);
  });

  test('missing observations are not reported as confirmed or monitoring', () {
    expect(formatBingxFuturesLiquidityObservation(null), contains('Scan and select'));
    final text = formatBingxFuturesLiquidityObservation(
      _decision(canPrepareIntent: false, anchorExecutable: false),
    );
    expect(text, contains('No pivot clusters detected'));
    expect(text, contains('requires an active authorized Runner session'));
    expect(text, isNot(contains('Reclaim confirmed')));
  });

  test('confirmed reclaim does not claim authority or a placed order', () {
    final text = formatBingxFuturesLiquidityObservation(_decision());
    expect(text, contains('still requires risk and mandate checks'));
    final blocked = formatBingxFuturesLiquidityObservation(
      _decision(canPrepareIntent: false),
    );
    expect(blocked, contains('other entry checks block preparation'));
  });

  group('formatBingxFuturesZoneEvidence', () {
    test('distinguishes an aged unswept HTF anchor from current price', () {
      final text = formatBingxFuturesZoneEvidence(
        _decision(
          source: '4h_fresh_high',
          eventAtUtc: '2026-07-27T04:00:00Z',
          observedAtUtc: '2026-08-16T20:00:00Z',
          referencePriceDecimal: '62840',
          zoneLowDecimal: '65664.826',
          zoneHighDecimal: '65741.342',
          side: 'sell',
        ),
      );

      expect(text, contains('not current market price'));
      expect(text, contains('4h unswept high'));
      expect(text, contains('formed 27 Jul 2026 04:00 UTC'));
      expect(text, contains('age 20d 16h'));
      expect(text, contains('4.5% above'));
      expect(text, endsWith('Run Intent revalidates it'));
    });

    test('uses the near zone boundary for a buy setup', () {
      final text = formatBingxFuturesZoneEvidence(
        _decision(
          source: '1d_fresh_low',
          referencePriceDecimal: '100',
          zoneLowDecimal: '89',
          zoneHighDecimal: '90',
          side: 'buy',
        ),
      );

      expect(text, contains('1d unswept low'));
      expect(text, contains('10.0% below'));
    });

    test(
      'fails closed to generic evidence when timestamps and price are bad',
      () {
        final text = formatBingxFuturesZoneEvidence(
          _decision(
            source: 'internal_diagnostic',
            eventAtUtc: 'bad',
            observedAtUtc: 'bad',
            referencePriceDecimal: 'bad',
          ),
        );

        expect(
          text,
          'Pending liquidity zone — not current market price · Run Intent revalidates it',
        );
        expect(text, isNot(contains('age')));
        expect(text, isNot(contains('%')));
      },
    );
  });
}

BingxFuturesLiveDecisionResult _decision({
  bool canPrepareIntent = true,
  bool anchorExecutable = true,
  List<BingxDetectedLiquidityLevel> levels = const [],
  String? source,
  String? eventAtUtc,
  String? observedAtUtc,
  String? referencePriceDecimal,
  String? zoneLowDecimal = '89',
  String? zoneHighDecimal = '91',
  String? side = 'sell',
}) {
  return BingxFuturesLiveDecisionResult(
    canPrepareIntent: canPrepareIntent,
    observedLiquidityLevels: levels,
    decision: BingxTvhDecisionKind.short,
    side: side,
    zoneSide: 'sellside',
    zoneLowDecimal: zoneLowDecimal,
    zoneHighDecimal: zoneHighDecimal,
    zoneConflict: false,
    marketSnapshotHashHex: 'a' * 64,
    featureHashHex: 'b' * 64,
    tvhDecisionHashHex: 'c' * 64,
    liveDecisionHashHex: 'd' * 64,
    canonicalJson: '{}',
    reasons: const <BingxTvhDecisionReason>[],
    trend15m: 'bearish',
    trend4h: 'bear',
    trend1d: 'flat',
    trendGateBlocked: false,
    trendGateCode: 'ok',
    zoneAnchorSource: source,
    zoneAnchorExecutable: anchorExecutable,
    zoneAnchorLifecycle: 'fresh',
    liquidityEventAtUtc: eventAtUtc,
    latestClosedMicroBarAtUtc: observedAtUtc,
    referencePriceDecimal: referencePriceDecimal,
  );
}
