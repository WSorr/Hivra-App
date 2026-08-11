import '../models/bingx_futures_risk_models.dart';
import 'bingx_futures_exchange_risk_input_service.dart';
import '../models/bingx_futures_exchange_execution_models.dart';
import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_execution_queue_models.dart';
import '../models/bingx_futures_observability_models.dart';
import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_order_tracking_models.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_execution_queue_service.dart';
import 'bingx_futures_observability_envelope_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_risk_history_service.dart';

class BingxFuturesExchangeExecutionUseCaseService {
  final BingxFuturesExchangeService _exchange;
  final BingxFuturesExecutionQueueService _queue;
  final BingxFuturesExchangeRiskInputService _riskInput;
  final BingxFuturesRiskGovernorService _riskGovernor;
  final BingxFuturesRiskHistoryService _riskHistory;
  final BingxFuturesObservabilityEnvelopeService _observability;
  final BingxFuturesOrderTrackingStore? _orderTrackingStore;

  const BingxFuturesExchangeExecutionUseCaseService({
    required BingxFuturesExchangeService exchange,
    required BingxFuturesExecutionQueueService queue,
    BingxFuturesExchangeRiskInputService riskInput =
        const BingxFuturesExchangeRiskInputService(),
    BingxFuturesRiskGovernorService riskGovernor =
        const BingxFuturesRiskGovernorService(),
    required BingxFuturesRiskHistoryService riskHistory,
    BingxFuturesOrderTrackingStore? orderTrackingStore,
    BingxFuturesObservabilityEnvelopeService observability =
        const BingxFuturesObservabilityEnvelopeService(),
  }) : _exchange = exchange,
       _queue = queue,
       _riskInput = riskInput,
       _riskGovernor = riskGovernor,
       _riskHistory = riskHistory,
       _orderTrackingStore = orderTrackingStore,
       _observability = observability;

  Future<BingxFuturesExchangeExecutionUseCaseResult> execute({
    required String screen,
    required Map<String, dynamic> rawIntentResult,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesRiskPolicy riskPolicy,
    required double fallbackEquityQuote,
    required bool testOrder,
    BingxFuturesLiveDecisionResult? preparedDecision,
    Future<BingxFuturesLiveDecisionResult?> Function()? refreshDecision,
  }) async {
    late final BingxFuturesIntentPayload payload;
    try {
      payload = BingxFuturesIntentPayload.fromPluginResult(rawIntentResult);
    } on FormatException catch (error) {
      return _result(
        status: BingxFuturesExchangeExecutionUseCaseStatus.invalidIntent,
        errorCode: 'invalid_intent',
        errorMessage: error.message,
      );
    }

    final liquidityEventId = preparedDecision?.liquidityEventId?.trim() ?? '';
    if (payload.entryMode == 'zone_pending') {
      final preparedBar =
          preparedDecision?.latestClosedMicroBarAtUtc?.trim() ?? '';
      if (liquidityEventId.isEmpty ||
          preparedBar.isEmpty ||
          refreshDecision == null) {
        return _result(
          status: BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
          payload: payload,
          errorCode: 'liquidity_event_evidence_missing',
          errorMessage: 'Run a fresh liquidity intent before execution.',
        );
      }
      final fresh = await refreshDecision();
      if (fresh == null ||
          !fresh.canPrepareIntent ||
          fresh.liquidityEventId != liquidityEventId ||
          fresh.latestClosedMicroBarAtUtc != preparedBar ||
          fresh.liveDecisionHashHex != preparedDecision!.liveDecisionHashHex ||
          fresh.side != payload.side ||
          fresh.zoneSide != rawIntentResult['zone_side']?.toString().trim()) {
        return _result(
          status: BingxFuturesExchangeExecutionUseCaseStatus.staleIntent,
          payload: payload,
          errorCode: 'liquidity_event_stale',
          errorMessage:
              'Market structure changed. Prepare a new liquidity intent.',
        );
      }
    }

    final risk = await evaluateRisk(
      payload: payload,
      rawIntentResult: rawIntentResult,
      credentials: credentials,
      riskPolicy: riskPolicy,
      fallbackEquityQuote: fallbackEquityQuote,
      allowExchangeRiskInputFallbacks: testOrder,
    );
    if (risk.decision == null) {
      return _result(
        status: BingxFuturesExchangeExecutionUseCaseStatus.riskUnavailable,
        payload: payload,
        errorCode: risk.errorCode,
        errorMessage: risk.errorMessage,
        diagnostics: risk.diagnostics,
      );
    }
    if (risk.decision!.status == BingxFuturesRiskDecisionStatus.blocked) {
      final envelope = _observability.buildExecutionEnvelope(
        screen: screen,
        symbol: payload.symbol,
        side: payload.side,
        orderType: payload.orderType,
        idempotencyKey:
            'risk_blocked:${payload.intentHashHex}:${risk.decision!.decisionHashHex}',
        attempts: 0,
        fromIdempotentCache: false,
        isSuccess: false,
        httpStatusCode: 0,
        exchangeCode: risk.decision!.reasonCode,
        endpointPath: 'risk_governor',
        orderId: null,
        intentHashHex: payload.intentHashHex,
        riskDecisionCode: risk.decision!.reasonCode,
        riskDecisionHashHex: risk.decision!.decisionHashHex,
        marketSnapshotHashHex:
            rawIntentResult['market_snapshot_hash_hex']?.toString().trim(),
        featureHashHex: rawIntentResult['feature_hash_hex']?.toString().trim(),
        tvhDecisionHashHex:
            rawIntentResult['tvh_decision_hash_hex']?.toString().trim(),
        liveDecisionHashHex:
            rawIntentResult['live_decision_hash_hex']?.toString().trim(),
      );
      return _result(
        status: BingxFuturesExchangeExecutionUseCaseStatus.riskBlocked,
        payload: payload,
        riskDecision: risk.decision,
        executionEnvelope: envelope,
        diagnostics: risk.diagnostics,
      );
    }

    if (liquidityEventId.isNotEmpty) {
      final orderTrackingStore = _orderTrackingStore;
      if (orderTrackingStore == null) {
        return _result(
          status:
              BingxFuturesExchangeExecutionUseCaseStatus.effectClaimUnavailable,
          payload: payload,
          riskDecision: risk.decision,
          errorCode: 'liquidity_event_claim_store_unavailable',
          errorMessage:
              'Execution blocked because the event claim store is unavailable.',
          diagnostics: risk.diagnostics,
        );
      }
      BingxLiquidityEventEffectReservation reservation;
      try {
        reservation = await orderTrackingStore.reserveLiquidityEventEffect(
          liquidityEventId: liquidityEventId,
          clientOrderId: payload.clientOrderId,
          symbol: payload.symbol,
          side: payload.side,
          testOrder: testOrder,
          recordedAtUtc: DateTime.now().toUtc().toIso8601String(),
        );
      } catch (error) {
        return _result(
          status:
              BingxFuturesExchangeExecutionUseCaseStatus.effectClaimUnavailable,
          payload: payload,
          riskDecision: risk.decision,
          errorCode: 'liquidity_event_claim_persist_failed',
          errorMessage:
              'Execution blocked because the event claim was not saved.',
          diagnostics: <String>[...risk.diagnostics, 'claim_error=$error'],
        );
      }
      if (reservation == BingxLiquidityEventEffectReservation.unavailable) {
        return _result(
          status:
              BingxFuturesExchangeExecutionUseCaseStatus.effectClaimUnavailable,
          payload: payload,
          riskDecision: risk.decision,
          errorCode: 'liquidity_event_claim_unavailable',
          errorMessage:
              'Execution blocked because the event claim was not saved.',
          diagnostics: risk.diagnostics,
        );
      }
      if (reservation == BingxLiquidityEventEffectReservation.alreadyClaimed) {
        return _result(
          status:
              BingxFuturesExchangeExecutionUseCaseStatus
                  .duplicateLiquidityEvent,
          payload: payload,
          riskDecision: risk.decision,
          errorCode: 'liquidity_event_already_claimed',
          errorMessage:
              'This liquidity event already owns an execution effect.',
          diagnostics: risk.diagnostics,
        );
      }
    }

    final queued = await _queue.enqueueOrderExecution(
      credentials: credentials,
      intent: payload,
      testOrder: testOrder,
    );
    final executionDiagnostics = <String>[...risk.diagnostics];
    if (liquidityEventId.isNotEmpty && queued.execution.isSuccess) {
      try {
        await _orderTrackingStore!.confirmLiquidityEventEffect(
          liquidityEventId: liquidityEventId,
          testOrder: testOrder,
          orderId: queued.execution.orderId ?? '',
        );
      } catch (error) {
        executionDiagnostics.add('claim_confirmation_error=$error');
      }
    }
    final envelope = _observability.buildExecutionEnvelope(
      screen: screen,
      symbol: payload.symbol,
      side: payload.side,
      orderType: payload.orderType,
      idempotencyKey: queued.idempotencyKey,
      attempts: queued.attempts,
      fromIdempotentCache: queued.fromIdempotentCache,
      isSuccess: queued.execution.isSuccess,
      httpStatusCode: queued.execution.httpStatusCode,
      exchangeCode: queued.execution.exchangeCode,
      endpointPath: queued.execution.endpointPath,
      orderId: queued.execution.orderId,
      intentHashHex: payload.intentHashHex,
      riskDecisionCode: risk.decision!.reasonCode,
      riskDecisionHashHex: risk.decision!.decisionHashHex,
      marketSnapshotHashHex:
          rawIntentResult['market_snapshot_hash_hex']?.toString().trim(),
      featureHashHex: rawIntentResult['feature_hash_hex']?.toString().trim(),
      tvhDecisionHashHex:
          rawIntentResult['tvh_decision_hash_hex']?.toString().trim(),
      liveDecisionHashHex:
          rawIntentResult['live_decision_hash_hex']?.toString().trim(),
    );
    return _result(
      status: BingxFuturesExchangeExecutionUseCaseStatus.executed,
      payload: payload,
      riskDecision: risk.decision,
      queuedExecution: queued,
      executionEnvelope: envelope,
      diagnostics: executionDiagnostics,
    );
  }

  Future<BingxFuturesRiskEvaluationResult> evaluateRisk({
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> rawIntentResult,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesRiskPolicy riskPolicy,
    required double fallbackEquityQuote,
    bool allowExchangeRiskInputFallbacks = false,
  }) async {
    final diagnostics = <String>[];
    var entryPriceDecimal =
        _nonEmpty(payload.limitPriceDecimal) ??
        _nonEmpty(payload.triggerPriceDecimal);
    if (entryPriceDecimal == null) {
      final quote = await _exchange.getPublicPrice(symbol: payload.symbol);
      if (quote.isSuccess) {
        entryPriceDecimal = _nonEmpty(quote.priceDecimal);
      }
    }
    if (entryPriceDecimal == null) {
      return BingxFuturesRiskEvaluationResult(
        decision: null,
        errorCode: 'entry_price_unavailable',
        errorMessage: 'Risk check failed: entry price unavailable',
        diagnostics: <String>[
          'entry_price_unavailable symbol=${payload.symbol}',
        ],
      );
    }

    final contractRules = await _exchange.getPerpetualContractRules(
      symbol: payload.symbol,
    );
    final marketQuote = await _exchange.getPublicPrice(symbol: payload.symbol);
    final rules = contractRules.isSuccess ? contractRules.rules : null;
    final referencePriceDecimal =
        marketQuote.isSuccess
            ? _nonEmpty(marketQuote.priceDecimal) ?? entryPriceDecimal
            : entryPriceDecimal;
    diagnostics.add(
      'contract_rules symbol=${payload.symbol} '
      'success=${contractRules.isSuccess} '
      'min_qty=${rules?.minimumQuantityDecimal ?? "-"} '
      'min_notional=${rules?.minimumNotionalQuoteDecimal ?? "-"} '
      'reference=$referencePriceDecimal',
    );

    var stopLossDecimal = _nonEmpty(
      rawIntentResult['stop_loss_decimal']?.toString(),
    );
    stopLossDecimal ??= _nonEmpty(
      rawIntentResult[payload.side == 'buy'
              ? 'zone_low_decimal'
              : 'zone_high_decimal']
          ?.toString(),
    );
    stopLossDecimal ??= entryPriceDecimal;

    final nowUtc = DateTime.now().toUtc();
    final exchangeRiskInput = await _riskInput.read(
      exchangeService: _exchange,
      riskHistoryService: _riskHistory,
      credentials: credentials,
      nowUtc: nowUtc,
      fallbackEquityQuote: fallbackEquityQuote,
    );
    diagnostics.add(
      'risk_inputs symbol=${payload.symbol} '
      'equity=${exchangeRiskInput.accountEquityQuoteDecimal} '
      'pnl=${exchangeRiskInput.realizedDailyPnlQuoteDecimal} '
      'positions=${exchangeRiskInput.concurrentPositions} '
      'loss_streak=${exchangeRiskInput.lossStreakCount} '
      'last_loss_at=${exchangeRiskInput.lastLossAtUtc ?? "-"} '
      'fallbacks=${exchangeRiskInput.usedBalanceFallback ? "balance" : "-"},'
      '${exchangeRiskInput.usedPnlFallback ? "pnl" : "-"},'
      '${exchangeRiskInput.usedPositionsFallback ? "positions" : "-"} '
      'exchange_reason=${exchangeRiskInput.firstUnavailableReason ?? "-"}',
    );
    if (!allowExchangeRiskInputFallbacks &&
        (exchangeRiskInput.usedBalanceFallback ||
            exchangeRiskInput.usedPnlFallback ||
            exchangeRiskInput.usedPositionsFallback)) {
      final reason = exchangeRiskInput.firstUnavailableReason;
      return BingxFuturesRiskEvaluationResult(
        decision: null,
        errorCode: 'exchange_risk_inputs_unavailable',
        errorMessage:
            reason == null
                ? 'Risk check failed: exchange balance, pnl, or positions unavailable'
                : 'Risk check failed: BingX futures access unavailable ($reason)',
        diagnostics: diagnostics,
      );
    }
    final decision = _riskGovernor.evaluate(
      input: BingxFuturesRiskGovernorInput(
        symbol: payload.symbol,
        quantityDecimal: payload.quantityDecimal,
        entryPriceDecimal: entryPriceDecimal,
        stopLossDecimal: stopLossDecimal,
        accountEquityQuoteDecimal: exchangeRiskInput.accountEquityQuoteDecimal,
        realizedDailyPnlQuoteDecimal:
            exchangeRiskInput.realizedDailyPnlQuoteDecimal,
        concurrentPositions: exchangeRiskInput.concurrentPositions,
        lossStreakCount: exchangeRiskInput.lossStreakCount,
        lastLossAtUtc: exchangeRiskInput.lastLossAtUtc,
        nowUtc: nowUtc.toIso8601String(),
        exchangeMinimumQuantityDecimal: rules?.minimumQuantityDecimal,
        exchangeMinimumNotionalQuoteDecimal: rules?.minimumNotionalQuoteDecimal,
        exchangeReferencePriceDecimal: referencePriceDecimal,
      ),
      policy: riskPolicy,
    );
    return BingxFuturesRiskEvaluationResult(
      decision: decision,
      errorCode: null,
      errorMessage: null,
      diagnostics: diagnostics,
    );
  }

  BingxFuturesExchangeExecutionUseCaseResult _result({
    required BingxFuturesExchangeExecutionUseCaseStatus status,
    BingxFuturesIntentPayload? payload,
    BingxFuturesRiskDecision? riskDecision,
    BingxQueuedExecutionResult? queuedExecution,
    BingxFuturesLogEnvelope? executionEnvelope,
    String? errorCode,
    String? errorMessage,
    List<String> diagnostics = const <String>[],
  }) {
    return BingxFuturesExchangeExecutionUseCaseResult(
      status: status,
      payload: payload,
      riskDecision: riskDecision,
      queuedExecution: queuedExecution,
      executionEnvelope: executionEnvelope,
      errorCode: errorCode,
      errorMessage: errorMessage,
      diagnostics: List<String>.unmodifiable(diagnostics),
    );
  }

  String? _nonEmpty(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
