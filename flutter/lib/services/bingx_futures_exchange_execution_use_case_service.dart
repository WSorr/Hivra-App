import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_risk_models.dart';
import 'bingx_futures_exchange_risk_input_service.dart';
import '../models/bingx_futures_exchange_execution_models.dart';
import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_execution_queue_models.dart';
import '../models/bingx_futures_observability_models.dart';
import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_order_tracking_models.dart';
import '../models/external_effect_models.dart';
import '../models/plugin_contract_ids.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_execution_queue_service.dart';
import 'bingx_futures_observability_envelope_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_risk_history_service.dart';

part 'bingx_futures_exchange_execution_mandate.dart';

class BingxFuturesExchangeExecutionUseCaseService {
  static const double _maxLiquidityZoneBoundaryDriftBps = 1.0;

  final BingxFuturesExchangeService _exchange;
  final BingxFuturesExecutionQueueService _queue;
  final BingxFuturesExchangeRiskInputService _riskInput;
  final BingxFuturesRiskGovernorService _riskGovernor;
  final BingxFuturesRiskHistoryService _riskHistory;
  final BingxFuturesObservabilityEnvelopeService _observability;
  final BingxFuturesOrderTrackingStore? _orderTrackingStore;
  final DateTime Function() _nowUtc;

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
    DateTime Function()? nowUtc,
  }) : _exchange = exchange,
       _queue = queue,
       _riskInput = riskInput,
       _riskGovernor = riskGovernor,
       _riskHistory = riskHistory,
       _orderTrackingStore = orderTrackingStore,
       _observability = observability,
       _nowUtc = nowUtc ?? DateTime.now;

  Future<BingxFuturesExchangeExecutionUseCaseResult> execute({
    required String screen,
    required Map<String, dynamic> rawIntentResult,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesRiskPolicy riskPolicy,
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
    final executionCapsuleRootHex = _orderTrackingStore?.activeCapsuleRootHex;
    final initialControlBlock = await _tradingControlBlock(
      payload: payload,
      capsuleRootHex: executionCapsuleRootHex,
      credentials: credentials,
      riskPolicy: riskPolicy,
      testOrder: testOrder,
      orderNotionalQuoteDecimal: null,
    );
    if (initialControlBlock != null) return initialControlBlock;

    final liquidityEventId = preparedDecision?.liquidityEventId?.trim() ?? '';
    if (payload.entryMode == 'zone_pending') {
      if (!await isPreparedLiquidityDecisionFresh(
        payload: payload,
        rawIntentResult: rawIntentResult,
        preparedDecision: preparedDecision,
        refreshDecision: refreshDecision,
      )) {
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

    final finalControlBlock = await _tradingControlBlock(
      payload: payload,
      capsuleRootHex: executionCapsuleRootHex,
      credentials: credentials,
      riskPolicy: riskPolicy,
      testOrder: testOrder,
      orderNotionalQuoteDecimal: risk.decision!.orderNotionalQuoteDecimal,
    );
    if (finalControlBlock != null) return finalControlBlock;

    if (liquidityEventId.isEmpty) {
      return _result(
        status: BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked,
        payload: payload,
        riskDecision: risk.decision,
        errorCode: 'trading_mandate_event_required',
        errorMessage:
            'Bounded trading requires a fresh claimed liquidity event.',
        diagnostics: risk.diagnostics,
      );
    }

    if (!testOrder) {
      final orderTrackingStore = _orderTrackingStore!;
      final mandateId =
          (await orderTrackingStore.loadForCapsule(
            executionCapsuleRootHex!,
          ))?.tradingMandate?.mandateId;
      if (mandateId == null) {
        return _result(
          status:
              BingxFuturesExchangeExecutionUseCaseStatus.effectClaimUnavailable,
          payload: payload,
          riskDecision: risk.decision,
          errorCode: 'trading_mandate_unavailable',
          errorMessage:
              'Execution blocked because the trading mandate is unavailable.',
          diagnostics: risk.diagnostics,
        );
      }
      BingxLiquidityEventEffectReservation reservation;
      try {
        reservation = await orderTrackingStore
            .reserveLiquidityEventEffectForCapsule(
              capsuleRootHex: executionCapsuleRootHex,
              liquidityEventId: liquidityEventId,
              clientOrderId: payload.clientOrderId,
              symbol: payload.symbol,
              side: payload.side,
              intentHashHex: payload.intentHashHex,
              canonicalIntentJson:
                  rawIntentResult['canonical_intent_json']?.toString(),
              testOrder: testOrder,
              recordedAtUtc: _nowUtc().toUtc().toIso8601String(),
              accountBindingHashHex: accountBindingHashHex(credentials),
              mandateId: mandateId,
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
    if (!testOrder && queued.execution.isSuccess) {
      try {
        await _orderTrackingStore!.confirmLiquidityEventEffectForCapsule(
          capsuleRootHex: executionCapsuleRootHex!,
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
    final executionSucceeded = queued.execution.isSuccess;
    return _result(
      status:
          !executionSucceeded
              ? BingxFuturesExchangeExecutionUseCaseStatus.executionFailed
              : testOrder
              ? BingxFuturesExchangeExecutionUseCaseStatus.validated
              : BingxFuturesExchangeExecutionUseCaseStatus.executed,
      payload: payload,
      riskDecision: risk.decision,
      queuedExecution: queued,
      executionEnvelope: envelope,
      errorCode: executionSucceeded ? null : 'exchange_effect_failed',
      errorMessage:
          executionSucceeded
              ? null
              : (_nonEmpty(queued.execution.exchangeMessage) ??
                  'Exchange effect failed without a success receipt.'),
      diagnostics: executionDiagnostics,
    );
  }

  Future<bool> isPreparedLiquidityDecisionFresh({
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> rawIntentResult,
    required BingxFuturesLiveDecisionResult? preparedDecision,
    required Future<BingxFuturesLiveDecisionResult?> Function()?
    refreshDecision,
  }) async {
    if (payload.entryMode != 'zone_pending') return true;
    final liquidityEventId = preparedDecision?.liquidityEventId?.trim() ?? '';
    final liquidityEventAtUtc =
        preparedDecision?.liquidityEventAtUtc?.trim() ?? '';
    final preparedBar =
        preparedDecision?.latestClosedMicroBarAtUtc?.trim() ?? '';
    if (liquidityEventId.isEmpty ||
        liquidityEventAtUtc.isEmpty ||
        preparedBar.isEmpty ||
        refreshDecision == null) {
      return false;
    }
    final fresh = await refreshDecision();
    if (fresh == null || !fresh.canPrepareIntent || fresh.zoneConflict) {
      return false;
    }
    final freshBar = fresh.latestClosedMicroBarAtUtc?.trim() ?? '';
    final preparedBarAt = DateTime.tryParse(preparedBar)?.toUtc();
    final freshBarAt = DateTime.tryParse(freshBar)?.toUtc();
    if (preparedBarAt == null ||
        freshBarAt == null ||
        freshBarAt.isBefore(preparedBarAt)) {
      return false;
    }
    return fresh.liquidityEventId == liquidityEventId &&
        fresh.liquidityEventAtUtc?.trim() == liquidityEventAtUtc &&
        fresh.side == payload.side &&
        fresh.zoneSide == rawIntentResult['zone_side']?.toString().trim() &&
        fresh.zoneAnchorSource == preparedDecision!.zoneAnchorSource &&
        fresh.zoneAnchorLifecycle == preparedDecision.zoneAnchorLifecycle &&
        fresh.zoneAnchorExecutable == preparedDecision.zoneAnchorExecutable &&
        fresh.zoneEvaluationSide == preparedDecision.zoneEvaluationSide &&
        _zoneBoundaryWithinFreshnessDrift(
          preparedDecision.zoneLowDecimal,
          fresh.zoneLowDecimal,
        ) &&
        _zoneBoundaryWithinFreshnessDrift(
          preparedDecision.zoneHighDecimal,
          fresh.zoneHighDecimal,
        );
  }

  bool _zoneBoundaryWithinFreshnessDrift(
    String? preparedDecimal,
    String? freshDecimal,
  ) {
    final prepared = double.tryParse(preparedDecimal?.trim() ?? '');
    final fresh = double.tryParse(freshDecimal?.trim() ?? '');
    if (prepared == null || fresh == null || prepared <= 0 || fresh <= 0) {
      return false;
    }
    final driftBps = ((fresh - prepared).abs() / prepared) * 10000;
    return driftBps <= _maxLiquidityZoneBoundaryDriftBps;
  }

  static String accountBindingHashHex(BingxFuturesApiCredentials credentials) {
    return sha256
        .convert(utf8.encode(credentials.normalized().apiKey))
        .toString();
  }

  Future<BingxFuturesOrderTrackingState> retainRemoteCompletedEffects({
    required BingxFuturesRemoteMandateAdmission session,
    required List<ExternalEffectOperation> operations,
    required String expectedAccountBindingHashHex,
  }) async {
    final store = _orderTrackingStore;
    final capsuleRootHex = store?.activeCapsuleRootHex;
    final accountBinding = expectedAccountBindingHashHex.trim().toLowerCase();
    if (store == null ||
        capsuleRootHex == null ||
        !session.isDeterministicSession ||
        session.mandate.capsuleRootHex != capsuleRootHex ||
        session.mandate.accountBindingHashHex != accountBinding ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(accountBinding) ||
        (session.mandate.testOrder && operations.isNotEmpty) ||
        operations.length > session.mandate.maxEffects) {
      throw StateError('Remote completed effect authority is invalid.');
    }
    final cycleOperationIds = <String>{
      for (var index = 0; index < session.authorizedUses; index += 1)
        session.deterministicCycleOperationId(index)!,
    };
    final current =
        await store.loadForCapsule(capsuleRootHex) ??
        const BingxFuturesOrderTrackingState(
          trackedSymbol: null,
          trackedOrderId: null,
          managedOrderIds: <String>[],
          managedOrderSymbols: <String, String>{},
          stopLossPercent: null,
          takeProfitRiskReward: null,
        );
    final provenance = <String, BingxManagedOrderProvenance>{
      ...current.managedOrderProvenance,
    };
    final importedOperations = <String>{};
    final importedOrders = <String>{};
    for (final operation in operations) {
      operation.validate();
      if (!importedOperations.add(operation.operationId) ||
          operation.ownerCapsuleHex != capsuleRootHex ||
          operation.pluginId != bingxFuturesTradingPluginId ||
          operation.providerId !=
              BingxFuturesExternalEffectAdapter.providerId ||
          operation.accountBindingId != accountBinding ||
          operation.effectKind !=
              BingxFuturesExternalEffectAdapter.exactOrderEffectKind ||
          operation.approvalEvidenceHashHex != session.operationId ||
          !cycleOperationIds.contains(operation.operationId) ||
          operation.state != ExternalEffectState.succeeded ||
          operation.receipt == null ||
          (operation.providerReferenceId != null &&
              operation.providerReferenceId !=
                  operation.receipt!.providerReceiptId) ||
          sha256
                  .convert(utf8.encode(operation.canonicalPayloadJson))
                  .toString() !=
              operation.payloadHashHex) {
        throw const FormatException(
          'Remote completed effect binding is invalid.',
        );
      }
      final decoded = jsonDecode(operation.canonicalPayloadJson);
      if (decoded is! Map<String, dynamic> ||
          decoded['test_order'] is! bool ||
          decoded['test_order'] != session.mandate.testOrder) {
        throw const FormatException(
          'Remote completed effect payload is invalid.',
        );
      }
      final payload = BingxFuturesIntentPayload.fromPluginResult(decoded);
      final intentHash = payload.intentHashHex?.trim().toLowerCase() ?? '';
      if (payload.symbol != session.mandate.symbol ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(intentHash) ||
          jsonEncode(
                payload.toExactOrderJson(testOrder: session.mandate.testOrder),
              ) !=
              operation.canonicalPayloadJson) {
        throw const FormatException(
          'Remote completed effect payload is invalid.',
        );
      }
      final orderId = operation.receipt!.providerReceiptId.trim();
      if (!importedOrders.add(orderId)) {
        throw const FormatException(
          'Remote completed effect receipt is duplicated.',
        );
      }
      final proposed = BingxManagedOrderProvenance(
        orderId: orderId,
        symbol: payload.symbol,
        side: payload.side,
        testOrder: session.mandate.testOrder,
        intentHashHex: intentHash,
        canonicalIntentJson: operation.canonicalPayloadJson,
        clientOrderId: payload.clientOrderId,
        accountBindingHashHex: accountBinding,
        externalEffectOperationId: operation.operationId,
        lifecycleStatus: BingxManagedOrderLifecycleStatus.unresolved,
        lifecycleEvidenceAtUtc: operation.receipt!.receivedAtUtc,
        lifecycleDiagnostic: 'remote_effect_receipt_imported',
        marketSnapshotHashHex: null,
        featureHashHex: null,
        tvhDecisionHashHex: null,
        liveDecisionHashHex: null,
        recordedAtUtc: operation.receipt!.receivedAtUtc,
      );
      BingxManagedOrderProvenance? sameOperation;
      for (final existing in provenance.values) {
        if (existing.externalEffectOperationId == operation.operationId) {
          sameOperation = existing;
          break;
        }
      }
      if (sameOperation != null) {
        if (!_sameRemoteEffectLineage(sameOperation, proposed)) {
          throw StateError(
            'Remote effect operation is already bound to another order.',
          );
        }
        continue;
      }
      final sameOrder = provenance[orderId];
      if (sameOrder != null && !_sameRemoteEffectLineage(sameOrder, proposed)) {
        throw StateError(
          'Remote effect receipt is already bound to another operation.',
        );
      }
      provenance[orderId] = proposed;
    }
    final next = BingxFuturesOrderTrackingState(
      trackedSymbol: current.trackedSymbol,
      trackedOrderId: current.trackedOrderId,
      managedOrderIds: current.managedOrderIds,
      managedOrderSymbols: current.managedOrderSymbols,
      managedOrderProvenance:
          Map<String, BingxManagedOrderProvenance>.unmodifiable(provenance),
      liquidityEventEffectClaims: current.liquidityEventEffectClaims,
      droneEnabled: current.droneEnabled,
      tradingMandate: current.tradingMandate,
      stopLossPercent: current.stopLossPercent,
      takeProfitRiskReward: current.takeProfitRiskReward,
    );
    await store.saveReconciledForCapsule(capsuleRootHex, next);
    return next;
  }

  bool _sameRemoteEffectLineage(
    BingxManagedOrderProvenance left,
    BingxManagedOrderProvenance right,
  ) =>
      left.orderId == right.orderId &&
      left.symbol == right.symbol &&
      left.side == right.side &&
      left.testOrder == right.testOrder &&
      left.intentHashHex == right.intentHashHex &&
      left.canonicalIntentJson == right.canonicalIntentJson &&
      left.clientOrderId == right.clientOrderId &&
      left.accountBindingHashHex == right.accountBindingHashHex &&
      left.externalEffectOperationId == right.externalEffectOperationId;

  Future<BingxFuturesManagedOrderReconciliationResult> reconcileManagedOrders({
    required BingxFuturesApiCredentials credentials,
    BingxFuturesOpenOrdersResult? openOrders,
  }) async {
    final store = _orderTrackingStore;
    final capsuleRootHex = store?.activeCapsuleRootHex;
    if (store == null || capsuleRootHex == null) {
      return const BingxFuturesManagedOrderReconciliationResult(
        status: BingxFuturesManagedOrderReconciliationStatus.unavailable,
        capsuleRootHex: null,
        state: null,
        activeCount: 0,
        terminalCount: 0,
        unresolvedCount: 0,
        diagnostics: <String>['managed_order_store_unavailable'],
      );
    }
    final current = await store.loadForCapsule(capsuleRootHex);
    if (current == null) {
      return BingxFuturesManagedOrderReconciliationResult(
        status: BingxFuturesManagedOrderReconciliationStatus.noState,
        capsuleRootHex: capsuleRootHex,
        state: null,
        activeCount: 0,
        terminalCount: 0,
        unresolvedCount: 0,
        diagnostics: const <String>[],
      );
    }

    final bindingHash = accountBindingHashHex(credentials);
    final evidenceAtUtc = DateTime.now().toUtc().toIso8601String();
    final openById = <String, BingxFuturesOpenOrder>{
      if (openOrders?.isSuccess == true)
        for (final order in openOrders!.orders) order.orderId: order,
    };
    final queryCache = <String, Future<BingxFuturesOrderQueryResult>>{};
    final diagnostics = <String>[];

    Future<
      ({
        BingxManagedOrderLifecycleStatus status,
        BingxFuturesOpenOrder? order,
        String? diagnostic,
      })
    >
    readEvidence({
      required String symbol,
      required String side,
      String? orderId,
      String? clientOrderId,
    }) async {
      final normalizedOrderId = orderId?.trim() ?? '';
      final normalizedClientOrderId = clientOrderId?.trim() ?? '';
      BingxFuturesOpenOrder? order = openById[normalizedOrderId];
      if (order == null) {
        final key =
            normalizedOrderId.isNotEmpty
                ? '${symbol.toUpperCase()}|id|$normalizedOrderId'
                : '${symbol.toUpperCase()}|client|$normalizedClientOrderId';
        try {
          final query = await queryCache.putIfAbsent(
            key,
            () => _exchange.getOrder(
              credentials: credentials,
              symbol: symbol,
              orderId: normalizedOrderId.isEmpty ? null : normalizedOrderId,
              clientOrderId:
                  normalizedOrderId.isEmpty ? normalizedClientOrderId : null,
            ),
          );
          if (!query.isSuccess) {
            return (
              status: BingxManagedOrderLifecycleStatus.unresolved,
              order: null,
              diagnostic: 'provider_query_${query.exchangeCode}',
            );
          }
          order = query.order;
        } catch (error) {
          return (
            status: BingxManagedOrderLifecycleStatus.unresolved,
            order: null,
            diagnostic: 'provider_query_error:${error.runtimeType}',
          );
        }
      }
      if (order == null) {
        return (
          status: BingxManagedOrderLifecycleStatus.unresolved,
          order: null,
          diagnostic: 'provider_evidence_missing',
        );
      }
      if ((normalizedOrderId.isNotEmpty &&
              order.orderId != normalizedOrderId) ||
          order.symbol.trim().toUpperCase() != symbol.trim().toUpperCase() ||
          order.side.trim().toLowerCase() != side.trim().toLowerCase() ||
          (normalizedOrderId.isEmpty &&
              order.clientOrderId?.trim().toLowerCase() !=
                  normalizedClientOrderId.toLowerCase())) {
        return (
          status: BingxManagedOrderLifecycleStatus.unresolved,
          order: order,
          diagnostic: 'provider_evidence_identity_mismatch',
        );
      }
      final lifecycle = switch (order.status.trim().toUpperCase()) {
        'NEW' || 'PARTIALLY_FILLED' => BingxManagedOrderLifecycleStatus.active,
        'FILLED' => BingxManagedOrderLifecycleStatus.filled,
        'CANCELED' || 'CANCELLED' => BingxManagedOrderLifecycleStatus.cancelled,
        'REJECTED' => BingxManagedOrderLifecycleStatus.rejected,
        'EXPIRED' => BingxManagedOrderLifecycleStatus.expired,
        _ => BingxManagedOrderLifecycleStatus.unresolved,
      };
      return (
        status: lifecycle,
        order: order,
        diagnostic:
            lifecycle == BingxManagedOrderLifecycleStatus.unresolved
                ? 'provider_status_unknown:${order.status}'
                : null,
      );
    }

    final provenance = <String, BingxManagedOrderProvenance>{
      ...current.managedOrderProvenance,
    };
    final activeIds = <String>{};
    final activeSymbols = <String, String>{};
    for (final entry in current.managedOrderProvenance.entries) {
      final record = entry.value;
      if (record.testOrder) {
        provenance[entry.key] = record.withLifecycle(
          status: BingxManagedOrderLifecycleStatus.unresolved,
          evidenceAtUtc: evidenceAtUtc,
          diagnostic: 'test_order_has_no_provider_lifecycle',
        );
        continue;
      }
      if (record.accountBindingHashHex != bindingHash) {
        provenance[entry.key] = record.withLifecycle(
          status: BingxManagedOrderLifecycleStatus.unresolved,
          evidenceAtUtc: evidenceAtUtc,
          diagnostic:
              record.accountBindingHashHex == null
                  ? 'account_binding_legacy_missing'
                  : 'account_binding_mismatch',
        );
        continue;
      }
      final evidence = await readEvidence(
        symbol: record.symbol,
        side: record.side,
        orderId: record.orderId,
        clientOrderId: record.clientOrderId,
      );
      provenance[entry.key] = record.withLifecycle(
        status: evidence.status,
        evidenceAtUtc: evidenceAtUtc,
        diagnostic: evidence.diagnostic,
      );
      if (evidence.status == BingxManagedOrderLifecycleStatus.active) {
        activeIds.add(record.orderId);
        activeSymbols[record.orderId] = record.symbol;
      }
    }

    final claims = <String, BingxLiquidityEventEffectClaim>{
      ...current.liquidityEventEffectClaims,
    };
    for (final entry in current.liquidityEventEffectClaims.entries) {
      final claim = entry.value;
      if (claim.testOrder) {
        claims[entry.key] = claim.withLifecycle(
          lifecycleStatus: BingxManagedOrderLifecycleStatus.unresolved,
          evidenceAtUtc: evidenceAtUtc,
          diagnostic: 'test_order_has_no_provider_lifecycle',
        );
        continue;
      }
      if (claim.accountBindingHashHex != bindingHash) {
        claims[entry.key] = claim.withLifecycle(
          lifecycleStatus: BingxManagedOrderLifecycleStatus.unresolved,
          evidenceAtUtc: evidenceAtUtc,
          diagnostic:
              claim.accountBindingHashHex == null
                  ? 'account_binding_legacy_missing'
                  : 'account_binding_mismatch',
        );
        continue;
      }
      final knownOrderId = claim.orderId?.trim() ?? '';
      final knownProvenance = provenance[knownOrderId];
      final evidence =
          knownProvenance != null
              ? (
                status: knownProvenance.lifecycleStatus,
                order: openById[knownOrderId],
                diagnostic: knownProvenance.lifecycleDiagnostic,
              )
              : await readEvidence(
                symbol: claim.symbol,
                side: claim.side,
                orderId: knownOrderId.isEmpty ? null : knownOrderId,
                clientOrderId: claim.clientOrderId,
              );
      final recoveredOrderId = evidence.order?.orderId.trim();
      claims[entry.key] = claim.withLifecycle(
        lifecycleStatus: evidence.status,
        evidenceAtUtc: evidenceAtUtc,
        diagnostic: evidence.diagnostic,
        confirmedOrderId: recoveredOrderId,
      );
      if (evidence.status == BingxManagedOrderLifecycleStatus.active &&
          recoveredOrderId != null &&
          recoveredOrderId.isNotEmpty) {
        activeIds.add(recoveredOrderId);
        activeSymbols[recoveredOrderId] = claim.symbol;
        if (!provenance.containsKey(recoveredOrderId) &&
            claim.intentHashHex != null &&
            claim.canonicalIntentJson != null) {
          provenance[recoveredOrderId] = BingxManagedOrderProvenance(
            orderId: recoveredOrderId,
            symbol: claim.symbol,
            side: claim.side,
            testOrder: claim.testOrder,
            intentHashHex: claim.intentHashHex!,
            canonicalIntentJson: claim.canonicalIntentJson!,
            clientOrderId: claim.clientOrderId,
            accountBindingHashHex: claim.accountBindingHashHex,
            lifecycleStatus: evidence.status,
            lifecycleEvidenceAtUtc: evidenceAtUtc,
            lifecycleDiagnostic: evidence.diagnostic,
            marketSnapshotHashHex: null,
            featureHashHex: null,
            tvhDecisionHashHex: null,
            liveDecisionHashHex: null,
            recordedAtUtc: claim.recordedAtUtc,
          );
        }
      }
    }

    final sortedActiveIds = activeIds.toList()..sort();
    final previousTracked = current.trackedOrderId?.trim() ?? '';
    final trackedOrderId =
        activeIds.contains(previousTracked)
            ? previousTracked
            : sortedActiveIds.isEmpty
            ? null
            : sortedActiveIds.first;
    final next = BingxFuturesOrderTrackingState(
      trackedSymbol:
          trackedOrderId == null ? null : activeSymbols[trackedOrderId],
      trackedOrderId: trackedOrderId,
      managedOrderIds: List<String>.unmodifiable(sortedActiveIds),
      managedOrderSymbols: Map<String, String>.unmodifiable(activeSymbols),
      managedOrderProvenance:
          Map<String, BingxManagedOrderProvenance>.unmodifiable(provenance),
      liquidityEventEffectClaims:
          Map<String, BingxLiquidityEventEffectClaim>.unmodifiable(claims),
      droneEnabled: current.droneEnabled,
      tradingMandate: current.tradingMandate,
      stopLossPercent: current.stopLossPercent,
      takeProfitRiskReward: current.takeProfitRiskReward,
    );
    await store.saveReconciledForCapsule(capsuleRootHex, next);
    final lifecycleStates =
        <String, BingxManagedOrderLifecycleStatus>{
          for (final record in provenance.values)
            'order:${record.orderId}': record.lifecycleStatus,
          for (final claim in claims.values)
            if (claim.orderId?.trim().isNotEmpty == true)
              'order:${claim.orderId!.trim()}': claim.lifecycleStatus
            else
              'client:${claim.testOrder ? "test" : "live"}:${claim.clientOrderId}':
                  claim.lifecycleStatus,
        }.values;
    final terminalCount = lifecycleStates.where(_isTerminalLifecycle).length;
    final unresolvedCount =
        lifecycleStates
            .where(
              (value) => value == BingxManagedOrderLifecycleStatus.unresolved,
            )
            .length;
    diagnostics.addAll(
      provenance.values
          .map((value) => value.lifecycleDiagnostic)
          .whereType<String>(),
    );
    diagnostics.addAll(
      claims.values
          .map((value) => value.lifecycleDiagnostic)
          .whereType<String>(),
    );
    return BingxFuturesManagedOrderReconciliationResult(
      status: BingxFuturesManagedOrderReconciliationStatus.reconciled,
      capsuleRootHex: capsuleRootHex,
      state: next,
      activeCount: activeIds.length,
      terminalCount: terminalCount,
      unresolvedCount: unresolvedCount,
      diagnostics: List<String>.unmodifiable(diagnostics.toSet()),
    );
  }

  static bool _isTerminalLifecycle(BingxManagedOrderLifecycleStatus status) {
    return status == BingxManagedOrderLifecycleStatus.filled ||
        status == BingxManagedOrderLifecycleStatus.cancelled ||
        status == BingxManagedOrderLifecycleStatus.rejected ||
        status == BingxManagedOrderLifecycleStatus.expired;
  }

  Future<BingxFuturesRiskEvaluationResult> evaluateRisk({
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> rawIntentResult,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesRiskPolicy riskPolicy,
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
      exposureSymbol: payload.symbol,
      exchangeService: _exchange,
      riskHistoryService: _riskHistory,
      credentials: credentials,
      nowUtc: nowUtc,
    );
    diagnostics.add(
      'risk_inputs symbol=${payload.symbol} '
      'equity=${exchangeRiskInput.accountEquityQuoteDecimal} '
      'pnl=${exchangeRiskInput.realizedDailyPnlQuoteDecimal} '
      'positions=${exchangeRiskInput.concurrentPositions} '
      'loss_streak=${exchangeRiskInput.lossStreakCount} '
      'last_loss_at=${exchangeRiskInput.lastLossAtUtc ?? "-"} '
      'complete=${exchangeRiskInput.isComplete} '
      'exchange_reason=${exchangeRiskInput.firstUnavailableReason ?? "-"}',
    );
    if (!exchangeRiskInput.isComplete) {
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
        openingLeverage:
            payload.side == 'buy'
                ? exchangeRiskInput.longLeverage
                : exchangeRiskInput.shortLeverage,
        marginType: exchangeRiskInput.marginType,
        availableMarginQuoteDecimal:
            exchangeRiskInput.availableMarginQuoteDecimal,
        symbol: payload.symbol,
        quantityDecimal: payload.quantityDecimal,
        entryPriceDecimal: entryPriceDecimal,
        stopLossDecimal: stopLossDecimal,
        accountEquityQuoteDecimal: exchangeRiskInput.accountEquityQuoteDecimal!,
        realizedDailyPnlQuoteDecimal:
            exchangeRiskInput.realizedDailyPnlQuoteDecimal!,
        concurrentPositions: exchangeRiskInput.concurrentPositions!,
        lossStreakCount: exchangeRiskInput.lossStreakCount!,
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
