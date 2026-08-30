import 'bingx_futures_live_decision_models.dart';

class BingxFuturesLiveStrategyCommand {
  final String symbol;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;
  final String? zoneEvaluationSide;

  const BingxFuturesLiveStrategyCommand({
    required this.symbol,
    required this.recentMicroBars,
    required this.zoneNearBps,
    required this.zoneFarBps,
    required this.zoneEvaluationSide,
  });
}

class BingxFuturesLiveStrategyResult {
  final BingxFuturesLiveDecisionResult? decision;
  final String symbol;
  final String? errorCode;
  final String? errorMessage;
  final String diagnostic;

  const BingxFuturesLiveStrategyResult({
    required this.decision,
    required this.symbol,
    required this.errorCode,
    required this.errorMessage,
    required this.diagnostic,
  });

  bool get isSuccess => decision != null;
}
