import 'bingx_futures_exchange_models.dart';
import 'bingx_futures_execution_queue_models.dart';
import 'bingx_futures_observability_models.dart';
import 'bingx_futures_risk_models.dart';
import 'bingx_futures_order_tracking_models.dart';

enum BingxFuturesExchangeExecutionUseCaseStatus {
  invalidIntent,
  executionPaused,
  mandateBlocked,
  staleIntent,
  duplicateLiquidityEvent,
  effectClaimUnavailable,
  riskUnavailable,
  riskBlocked,
  executionFailed,
  executed,
}

class BingxFuturesExchangeExecutionUseCaseResult {
  final BingxFuturesExchangeExecutionUseCaseStatus status;
  final BingxFuturesIntentPayload? payload;
  final BingxFuturesRiskDecision? riskDecision;
  final BingxQueuedExecutionResult? queuedExecution;
  final BingxFuturesLogEnvelope? executionEnvelope;
  final String? errorCode;
  final String? errorMessage;
  final List<String> diagnostics;

  const BingxFuturesExchangeExecutionUseCaseResult({
    required this.status,
    required this.payload,
    required this.riskDecision,
    required this.queuedExecution,
    required this.executionEnvelope,
    required this.errorCode,
    required this.errorMessage,
    required this.diagnostics,
  });
}

class BingxFuturesRiskEvaluationResult {
  final BingxFuturesRiskDecision? decision;
  final String? errorCode;
  final String? errorMessage;
  final List<String> diagnostics;

  const BingxFuturesRiskEvaluationResult({
    required this.decision,
    required this.errorCode,
    required this.errorMessage,
    required this.diagnostics,
  });
}

enum BingxFuturesManagedOrderReconciliationStatus {
  noState,
  reconciled,
  unavailable,
}

class BingxFuturesManagedOrderReconciliationResult {
  final BingxFuturesManagedOrderReconciliationStatus status;
  final String? capsuleRootHex;
  final BingxFuturesOrderTrackingState? state;
  final int activeCount;
  final int terminalCount;
  final int unresolvedCount;
  final List<String> diagnostics;

  const BingxFuturesManagedOrderReconciliationResult({
    required this.status,
    required this.capsuleRootHex,
    required this.state,
    required this.activeCount,
    required this.terminalCount,
    required this.unresolvedCount,
    required this.diagnostics,
  });
}
