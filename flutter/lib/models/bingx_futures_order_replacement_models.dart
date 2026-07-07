import 'bingx_futures_exchange_models.dart';
import 'bingx_futures_execution_queue_models.dart';
import 'bingx_futures_risk_models.dart';
import 'plugin_host_api_models.dart';

typedef BingxReplacementIntentPreparer = Future<PluginHostApiResponse> Function(
  Map<String, dynamic> hostArgs,
);
typedef BingxReplacementRiskEvaluator = Future<BingxFuturesRiskDecision?>
    Function(
  BingxFuturesIntentPayload payload,
  Map<String, dynamic> rawIntentResult,
);
typedef BingxReplacementExecutor = Future<BingxQueuedExecutionResult> Function(
  BingxFuturesIntentPayload payload,
  bool testOrder,
);

enum BingxFuturesReplacementPlanStatus {
  ready,
  skipped,
}

class BingxFuturesReplacementPlan {
  final BingxFuturesReplacementPlanStatus status;
  final String reasonCode;
  final String reasonMessage;
  final Map<String, dynamic>? hostArgs;

  const BingxFuturesReplacementPlan({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.hostArgs,
  });

  bool get isReady =>
      status == BingxFuturesReplacementPlanStatus.ready && hostArgs != null;
}

enum BingxFuturesReplacementRuntimeStatus {
  skipped,
  hostBlocked,
  riskUnavailable,
  riskBlocked,
  executionFailed,
  executed,
}

class BingxFuturesReplacementRuntimeResult {
  final BingxFuturesReplacementRuntimeStatus status;
  final BingxFuturesReplacementPlan plan;
  final PluginHostApiResponse? hostResponse;
  final BingxFuturesIntentPayload? payload;
  final BingxFuturesRiskDecision? riskDecision;
  final BingxQueuedExecutionResult? queuedExecution;

  const BingxFuturesReplacementRuntimeResult({
    required this.status,
    required this.plan,
    required this.hostResponse,
    required this.payload,
    required this.riskDecision,
    required this.queuedExecution,
  });

  bool get isExecuted =>
      status == BingxFuturesReplacementRuntimeStatus.executed &&
      queuedExecution?.execution.isSuccess == true;
}
