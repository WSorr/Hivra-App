import 'bingx_futures_market_snapshot_models.dart';
import 'bingx_futures_tvh_rule_models.dart';

class BingxFuturesLiveDecisionInput {
  final BingxFuturesMarketSnapshotInput snapshotInput;
  final bool isConsensusSignable;
  final List<String> blockingFactCodes;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;
  final BingxTvhPolicy policy;
  final String? zoneEvaluationSide;

  const BingxFuturesLiveDecisionInput({
    required this.snapshotInput,
    required this.isConsensusSignable,
    this.blockingFactCodes = const <String>[],
    this.recentMicroBars = 8,
    this.zoneNearBps = 15.0,
    this.zoneFarBps = 35.0,
    this.policy = const BingxTvhPolicy(),
    this.zoneEvaluationSide,
  });
}

class BingxFuturesLiveDecisionResult {
  final bool canPrepareIntent;
  final BingxTvhDecisionKind decision;
  final String? side;
  final String? zoneSide;
  final String? zoneLowDecimal;
  final String? zoneHighDecimal;
  final bool zoneConflict;
  final String marketSnapshotHashHex;
  final String featureHashHex;
  final String tvhDecisionHashHex;
  final String liveDecisionHashHex;
  final String canonicalJson;
  final List<BingxTvhDecisionReason> reasons;
  final String trend15m;
  final String trend4h;
  final String trend1d;
  final bool trendGateBlocked;
  final String trendGateCode;
  final String? zoneAnchorSource;
  final bool zoneAnchorExecutable;
  final String? zoneAnchorLifecycle;
  final String? zoneEvaluationSide;

  const BingxFuturesLiveDecisionResult({
    required this.canPrepareIntent,
    required this.decision,
    required this.side,
    required this.zoneSide,
    required this.zoneLowDecimal,
    required this.zoneHighDecimal,
    required this.zoneConflict,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.tvhDecisionHashHex,
    required this.liveDecisionHashHex,
    required this.canonicalJson,
    required this.reasons,
    required this.trend15m,
    required this.trend4h,
    required this.trend1d,
    required this.trendGateBlocked,
    required this.trendGateCode,
    this.zoneAnchorSource,
    this.zoneAnchorExecutable = false,
    this.zoneAnchorLifecycle,
    this.zoneEvaluationSide,
  });
}
