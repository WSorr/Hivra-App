import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_feature_extractor_service.dart';
import 'package:hivra_app/services/bingx_futures_tvh_rule_engine_service.dart';

void main() {
  group('BingxFuturesTvhRuleEngineService', () {
    const service = BingxFuturesTvhRuleEngineService();
    const policy = BingxTvhPolicy(
      minAbsTradeImbalanceRatio: 0.5,
      maxAbsFundingRate: 0.01,
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

    test('default policy allows solo trading without consensus', () {
      final result = service.evaluate(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '1.50',
          sessionNetDeltaDecimal: '3.20',
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        isConsensusSignable: false,
        blockingFactCodes: const <String>['consensus_peer_not_selected'],
      );

      expect(result.decision, BingxTvhDecisionKind.long);
      expect(
        result.reasons.map((reason) => reason.code),
        isNot(contains('consensus_guard')),
      );
    });

    test('market evaluation has no consensus guard input', () {
      final result = service.evaluateMarket(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '1.50',
          sessionNetDeltaDecimal: '3.20',
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.long);
      expect(
        result.reasons.map((reason) => reason.code),
        isNot(contains('consensus_guard')),
      );
    });

    test('incomplete session evidence remains context, not authority', () {
      final result = service.evaluateMarket(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '1.50',
          sessionNetDeltaDecimal: '3.20',
          sessionEvidenceComplete: false,
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.long);
      expect(
        result.reasons.singleWhere(
          (reason) => reason.code == 'session_context',
        ),
        isA<BingxTvhDecisionReason>().having(
          (reason) => reason.passed,
          'passed',
          isTrue,
        ),
      );
    });

    test('volume activation does not require trend or whale alignment', () {
      final result = service.evaluateMarket(
        features: _feature(
          trend: BingxTrendDirection.neutral,
          tradeDeltaDecimal: '-1.50',
          sessionNetDeltaDecimal: '3.20',
          sessionEvidenceComplete: false,
          hasBuyWhaleActivation: false,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.short);
    });

    test('opposite trade flow cannot flip a constrained liquidity side', () {
      final result = service.evaluateMarket(
        features: _feature(
          trend: BingxTrendDirection.bullish,
          tradeDeltaDecimal: '1.50',
          sessionNetDeltaDecimal: '3.20',
          sessionEvidenceComplete: false,
          hasBuyWhaleActivation: true,
          hasSellWhaleActivation: false,
        ),
        fundingRateDecimal: '0.0008',
        requiredSide: 'sell',
        policy: policy,
      );

      expect(result.decision, BingxTvhDecisionKind.noSignal);
      expect(
        result.reasons
            .singleWhere((reason) => reason.code == 'liquidity_side_constraint')
            .detail,
        'sell',
      );
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
  bool sessionEvidenceComplete = true,
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
    tradeImbalanceRatioDecimal: tradeDeltaDecimal,
    openInterestDeltaDecimal: '10.0',
    sessionNetDeltaDecimal: sessionNetDeltaDecimal,
    sessionImbalanceRatioDecimal:
        (double.parse(sessionNetDeltaDecimal) / 100).toString(),
    sessionEvidenceComplete: sessionEvidenceComplete,
    liquidityLevels: const <BingxDetectedLiquidityLevel>[],
    whaleActivations: const <BingxWhaleActivationEvent>[],
    hasBuyWhaleActivation: hasBuyWhaleActivation,
    hasSellWhaleActivation: hasSellWhaleActivation,
  );
}
