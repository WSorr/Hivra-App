import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_live_decision_service.dart';
import 'bingx_futures_live_snapshot_builder_service.dart';

typedef BingxLiveSnapshotLoader = Future<BingxFuturesLiveSnapshotBuildResult>
    Function({
  required BingxFuturesExchangeService exchange,
  required String symbol,
  BingxFuturesApiCredentials? credentials,
});

typedef BingxLiveDecisionEvaluator = BingxFuturesLiveDecisionResult Function(
  BingxFuturesLiveDecisionInput input,
);

class BingxFuturesLiveStrategyCommand {
  final String symbol;
  final BingxFuturesApiCredentials? credentials;
  final bool isConsensusSignable;
  final List<String> blockingFactCodes;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;
  final String? zoneEvaluationSide;

  const BingxFuturesLiveStrategyCommand({
    required this.symbol,
    required this.credentials,
    required this.isConsensusSignable,
    required this.blockingFactCodes,
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

class BingxFuturesLiveStrategyUseCaseService {
  final BingxFuturesExchangeService _exchange;
  final BingxLiveSnapshotLoader _loadSnapshot;
  final BingxLiveDecisionEvaluator _evaluateDecision;

  BingxFuturesLiveStrategyUseCaseService({
    required BingxFuturesExchangeService exchange,
    BingxFuturesLiveSnapshotBuilderService snapshotBuilder =
        const BingxFuturesLiveSnapshotBuilderService(),
    BingxFuturesLiveDecisionService decisionService =
        const BingxFuturesLiveDecisionService(),
    BingxLiveSnapshotLoader? loadSnapshot,
    BingxLiveDecisionEvaluator? evaluateDecision,
  })  : _exchange = exchange,
        _loadSnapshot = loadSnapshot ?? snapshotBuilder.fetchAndBuild,
        _evaluateDecision = evaluateDecision ?? decisionService.decide;

  Future<BingxFuturesLiveStrategyResult> execute(
    BingxFuturesLiveStrategyCommand command,
  ) async {
    final snapshot = await _loadSnapshot(
      exchange: _exchange,
      symbol: command.symbol,
      credentials: command.credentials,
    );
    if (!snapshot.isSuccess || snapshot.snapshotInput == null) {
      return BingxFuturesLiveStrategyResult(
        decision: null,
        symbol: snapshot.symbol,
        errorCode: snapshot.errorCode,
        errorMessage: snapshot.errorMessage,
        diagnostic: 'symbol=${snapshot.symbol} code=${snapshot.errorCode} '
            'message=${snapshot.errorMessage}',
      );
    }

    try {
      final decision = _evaluateDecision(
        BingxFuturesLiveDecisionInput(
          snapshotInput: snapshot.snapshotInput!,
          isConsensusSignable: command.isConsensusSignable,
          blockingFactCodes: command.blockingFactCodes,
          recentMicroBars: command.recentMicroBars,
          zoneNearBps: command.zoneNearBps,
          zoneFarBps: command.zoneFarBps,
          zoneEvaluationSide: command.zoneEvaluationSide,
        ),
      );
      return BingxFuturesLiveStrategyResult(
        decision: decision,
        symbol: snapshot.symbol,
        errorCode: null,
        errorMessage: null,
        diagnostic: _decisionDiagnostic(
          symbol: snapshot.symbol,
          decision: decision,
          consensusSignable: command.isConsensusSignable,
        ),
      );
    } on FormatException catch (error) {
      return BingxFuturesLiveStrategyResult(
        decision: null,
        symbol: snapshot.symbol,
        errorCode: 'invalid_snapshot',
        errorMessage: error.message,
        diagnostic: 'symbol=${snapshot.symbol} code=invalid_snapshot '
            'message=${error.message}',
      );
    }
  }

  String _decisionDiagnostic({
    required String symbol,
    required BingxFuturesLiveDecisionResult decision,
    required bool consensusSignable,
  }) {
    return 'symbol=$symbol '
        'can_prepare=${decision.canPrepareIntent} '
        'decision=${decision.decision.name} '
        'side=${decision.side ?? "-"} '
        'zone_side=${decision.zoneSide ?? "-"} '
        'zone_evaluation_side=${decision.zoneEvaluationSide ?? "-"} '
        'zone_low=${decision.zoneLowDecimal ?? "-"} '
        'zone_high=${decision.zoneHighDecimal ?? "-"} '
        'anchor_source=${decision.zoneAnchorSource ?? "-"} '
        'anchor_lifecycle=${decision.zoneAnchorLifecycle ?? "-"} '
        'anchor_executable=${decision.zoneAnchorExecutable} '
        'trend15m=${decision.trend15m} '
        'trend4h=${decision.trend4h} '
        'trend1d=${decision.trend1d} '
        'trend_gate=${decision.trendGateCode} '
        'trend_blocked=${decision.trendGateBlocked} '
        'consensus_signable=$consensusSignable '
        'market_hash=${decision.marketSnapshotHashHex.substring(0, 12)} '
        'feature_hash=${decision.featureHashHex.substring(0, 12)} '
        'tvh_hash=${decision.tvhDecisionHashHex.substring(0, 12)} '
        'live_hash=${decision.liveDecisionHashHex.substring(0, 12)} '
        'failed=${decision.reasons.where((reason) => !reason.passed).map((reason) => "${reason.code}:${reason.detail}").join("|")}';
  }
}
