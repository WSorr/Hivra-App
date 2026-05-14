import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_feature_extractor_service.dart';
import 'package:hivra_app/services/bingx_futures_tvh_rule_engine_service.dart';

void main() {
  group('BingxFuturesTvhRuleEngineService', () {
    const service = BingxFuturesTvhRuleEngineService();
    const policy = BingxTvhPolicy(
      minAbsTradeDelta: 0.5,
      minAbsSessionNetDelta: 1.0,
      maxAbsFundingRate: 0.01,
      requireWhaleActivation: true,
      requireConsensusSignable: true,
    );

    test('returns LONG on bullish aligned input', () {
      final result = service.evaluate(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '1.50',
          sessionNetDeltaDecimal: '3.20',
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        isConsensusSignable: true,
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.long);
      expect(result.reasons.first.code, 'funding_guard');
      expect(result.decisionHashHex.length, 64);
    });

    test('returns SHORT on bearish aligned input', () {
      final result = service.evaluate(
        features: _feature(
          trend: BingxTrendDirection.bearish,
          tradeDeltaDecimal: '-1.10',
          sessionNetDeltaDecimal: '-2.90',
          hasBuyWhaleActivation: false,
          hasSellWhaleActivation: true,
        ),
        fundingRateDecimal: '-0.0007',
        isConsensusSignable: true,
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.short);
      expect(result.decisionHashHex.length, 64);
    });

    test('returns NO_SIGNAL on funding guard block', () {
      final result = service.evaluate(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '2.00',
          sessionNetDeltaDecimal: '5.00',
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0200',
        isConsensusSignable: true,
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.noSignal);
      expect(result.reasons.first.code, 'funding_guard');
      expect(result.reasons.first.passed, isFalse);
    });

    test('returns BLOCKED on consensus guard block', () {
      final result = service.evaluate(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '2.00',
          sessionNetDeltaDecimal: '5.00',
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0002',
        isConsensusSignable: false,
        blockingFactCodes: const <String>['pending_remote_break'],
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.blocked);
      expect(result.reasons.first.code, 'consensus_guard');
      expect(result.reasons.first.passed, isFalse);
    });

    test('is hash-stable for identical inputs', () {
      final features = _feature(
        trend: BingxTrendDirection.bullish,
        tradeDeltaDecimal: '1.50',
        sessionNetDeltaDecimal: '3.20',
        hasBuyWhaleActivation: true,
        hasSellWhaleActivation: false,
      );
      final first = service.evaluate(
        features: features,
        fundingRateDecimal: '0.0008',
        isConsensusSignable: true,
        policy: policy,
      );
      final second = service.evaluate(
        features: features,
        fundingRateDecimal: '0.0008',
        isConsensusSignable: true,
        policy: policy,
      );

      expect(first.decision, second.decision);
      expect(first.canonicalJson, second.canonicalJson);
      expect(first.decisionHashHex, second.decisionHashHex);
    });
  });
}

BingxFuturesFeatureExtractionResult _feature({
  required BingxTrendDirection trend,
  required String tradeDeltaDecimal,
  required String sessionNetDeltaDecimal,
  required bool hasBuyWhaleActivation,
  required bool hasSellWhaleActivation,
}) {
  return BingxFuturesFeatureExtractionResult(
    ruleSet: 'tvh_v1',
    marketSnapshotHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    canonicalJson: '{}',
    featureHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    trendDirection: trend,
    ema50m15Decimal: '101.0',
    ema200m15Decimal: '100.0',
    atr14m5Decimal: '0.5',
    tradeDeltaDecimal: tradeDeltaDecimal,
    openInterestDeltaDecimal: '10.0',
    sessionNetDeltaDecimal: sessionNetDeltaDecimal,
    liquidityLevels: const <BingxDetectedLiquidityLevel>[],
    whaleActivations: const <BingxWhaleActivationEvent>[],
    hasBuyWhaleActivation: hasBuyWhaleActivation,
    hasSellWhaleActivation: hasSellWhaleActivation,
  );
}
