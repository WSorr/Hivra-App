enum BingxTvhDecisionKind { long, short, noSignal, blocked }

class BingxTvhDecisionReason {
  final String code;
  final bool passed;
  final String detail;

  const BingxTvhDecisionReason({
    required this.code,
    required this.passed,
    required this.detail,
  });
}

class BingxTvhPolicy {
  final double minAbsTradeImbalanceRatio;
  final double maxAbsFundingRate;
  final bool requireConsensusSignable;

  const BingxTvhPolicy({
    this.minAbsTradeImbalanceRatio = 0.01,
    this.maxAbsFundingRate = 0.01,
    this.requireConsensusSignable = false,
  });
}

class BingxTvhDecisionResult {
  final String ruleSet;
  final String featureHashHex;
  final BingxTvhDecisionKind decision;
  final List<BingxTvhDecisionReason> reasons;
  final String canonicalJson;
  final String decisionHashHex;

  const BingxTvhDecisionResult({
    required this.ruleSet,
    required this.featureHashHex,
    required this.decision,
    required this.reasons,
    required this.canonicalJson,
    required this.decisionHashHex,
  });
}
