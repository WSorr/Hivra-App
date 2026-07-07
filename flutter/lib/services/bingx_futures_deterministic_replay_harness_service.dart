import '../models/bingx_futures_market_snapshot_models.dart';
import '../models/bingx_futures_tvh_rule_models.dart';
import 'bingx_futures_feature_extractor_service.dart';
import 'bingx_futures_market_snapshot_service.dart';
import 'bingx_futures_tvh_rule_engine_service.dart';

class BingxFuturesReplayFixture {
  final String id;
  final BingxFuturesMarketSnapshotInput snapshotInput;
  final String fundingRateDecimal;
  final bool isConsensusSignable;
  final List<String> blockingFactCodes;
  final BingxTvhDecisionKind expectedDecision;
  final String expectedReasonCode;

  const BingxFuturesReplayFixture({
    required this.id,
    required this.snapshotInput,
    required this.fundingRateDecimal,
    required this.isConsensusSignable,
    this.blockingFactCodes = const <String>[],
    required this.expectedDecision,
    required this.expectedReasonCode,
  });
}

class BingxFuturesReplayRunResult {
  final String fixtureId;
  final String marketSnapshotHashHex;
  final String featureHashHex;
  final String decisionHashHex;
  final BingxTvhDecisionKind decision;
  final String topReasonCode;

  const BingxFuturesReplayRunResult({
    required this.fixtureId,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.decisionHashHex,
    required this.decision,
    required this.topReasonCode,
  });
}

class BingxFuturesDeterministicReplayHarnessService {
  final BingxFuturesMarketSnapshotService _snapshotService;
  final BingxFuturesFeatureExtractorService _featureExtractor;
  final BingxFuturesTvhRuleEngineService _ruleEngine;
  final BingxTvhPolicy _policy;

  const BingxFuturesDeterministicReplayHarnessService({
    BingxFuturesMarketSnapshotService snapshotService =
        const BingxFuturesMarketSnapshotService(),
    BingxFuturesFeatureExtractorService featureExtractor =
        const BingxFuturesFeatureExtractorService(),
    BingxFuturesTvhRuleEngineService ruleEngine =
        const BingxFuturesTvhRuleEngineService(),
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  })  : _snapshotService = snapshotService,
        _featureExtractor = featureExtractor,
        _ruleEngine = ruleEngine,
        _policy = policy;

  BingxFuturesReplayRunResult runFixture(BingxFuturesReplayFixture fixture) {
    final snapshotDigest = _snapshotService.build(fixture.snapshotInput);
    final featureResult = _featureExtractor.extract(snapshotDigest);
    final decision = _ruleEngine.evaluate(
      features: featureResult,
      fundingRateDecimal: fixture.fundingRateDecimal,
      isConsensusSignable: fixture.isConsensusSignable,
      blockingFactCodes: fixture.blockingFactCodes,
      policy: _policy,
    );
    final topReasonCode =
        decision.reasons.isNotEmpty ? decision.reasons.first.code : '';
    return BingxFuturesReplayRunResult(
      fixtureId: fixture.id,
      marketSnapshotHashHex: snapshotDigest.marketSnapshotHashHex,
      featureHashHex: featureResult.featureHashHex,
      decisionHashHex: decision.decisionHashHex,
      decision: decision.decision,
      topReasonCode: topReasonCode,
    );
  }

  List<BingxFuturesReplayRunResult> runMany({
    required List<BingxFuturesReplayFixture> fixtures,
    int repeat = 1,
  }) {
    if (repeat < 1) {
      throw const FormatException('repeat must be >= 1');
    }
    final results = <BingxFuturesReplayRunResult>[];
    for (var round = 0; round < repeat; round++) {
      for (final fixture in fixtures) {
        results.add(runFixture(fixture));
      }
    }
    return results;
  }
}
