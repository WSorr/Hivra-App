part of 'bingx_futures_exchange_execution_use_case_service.dart';

extension on BingxFuturesExchangeExecutionUseCaseService {
  Future<BingxFuturesExchangeExecutionUseCaseResult?> _tradingControlBlock({
    required BingxFuturesIntentPayload payload,
    required String? capsuleRootHex,
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesRiskPolicy riskPolicy,
    required bool testOrder,
    required String? orderNotionalQuoteDecimal,
  }) async {
    final orderTrackingStore = _orderTrackingStore;
    if (orderTrackingStore == null || capsuleRootHex == null) {
      return _tradingControlUnavailable(payload);
    }
    try {
      final control = await orderTrackingStore.loadForCapsule(capsuleRootHex);
      if (control?.droneEnabled != true) {
        return _result(
          status: BingxFuturesExchangeExecutionUseCaseStatus.executionPaused,
          payload: payload,
          errorCode: 'trading_paused',
          errorMessage: 'Trading is paused for this Capsule.',
        );
      }
      final mandate = control?.tradingMandate;
      final quantity = double.tryParse(payload.quantityDecimal);
      final price = double.tryParse(
        payload.limitPriceDecimal ?? payload.triggerPriceDecimal ?? '',
      );
      final maxNotional = double.tryParse(
        mandate?.maxOrderNotionalQuoteDecimal ?? '',
      );
      final evaluatedNotional = double.tryParse(
        orderNotionalQuoteDecimal ?? '',
      );
      final policyMatches =
          mandate != null &&
          mandate.maxRiskPerTradePercent == riskPolicy.maxRiskPerTradePercent &&
          mandate.maxDailyLossPercent == riskPolicy.maxDailyLossPercent &&
          mandate.maxConcurrentPositions == riskPolicy.maxConcurrentPositions &&
          mandate.cooldownAfterLossStreak ==
              riskPolicy.cooldownAfterLossStreak &&
          mandate.cooldownMinutes == riskPolicy.cooldownMinutes;
      final effectCount =
          mandate == null
              ? 0
              : control!.liquidityEventEffectClaims.values
                  .where((claim) => claim.mandateId == mandate.mandateId)
                  .length;
      BingxFuturesExchangeExecutionUseCaseResult blocked(String code) {
        return _result(
          status: BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked,
          payload: payload,
          errorCode: code,
          errorMessage:
              'Execution is outside the active Capsule trading mandate.',
        );
      }

      if (mandate == null) return blocked('trading_mandate_missing');
      if (mandate.capsuleRootHex != capsuleRootHex) {
        return blocked('trading_mandate_capsule_mismatch');
      }
      if (mandate.accountBindingHashHex !=
          BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
            credentials,
          )) {
        return blocked('trading_mandate_account_mismatch');
      }
      if (mandate.symbol != payload.symbol) {
        return blocked('trading_mandate_symbol_mismatch');
      }
      if (mandate.testOrder != testOrder) {
        return blocked('trading_mandate_mode_mismatch');
      }
      if (!mandate.isActiveAt(_nowUtc().toUtc())) {
        return blocked('trading_mandate_inactive');
      }
      if (!policyMatches) return blocked('trading_mandate_policy_mismatch');
      if (quantity == null || quantity <= 0 || maxNotional == null) {
        return blocked('trading_mandate_notional_invalid');
      }
      if (price != null && (price <= 0 || quantity * price > maxNotional)) {
        return blocked('trading_mandate_notional_exceeded');
      }
      if (orderNotionalQuoteDecimal != null &&
          (evaluatedNotional == null || evaluatedNotional <= 0)) {
        return blocked('trading_mandate_notional_invalid');
      }
      if (evaluatedNotional != null && evaluatedNotional > maxNotional) {
        return blocked('trading_mandate_notional_exceeded');
      }
      if (effectCount >= mandate.maxEffects) {
        return blocked('trading_mandate_effect_budget_exhausted');
      }
      return null;
    } catch (_) {
      return _tradingControlUnavailable(payload);
    }
  }

  BingxFuturesExchangeExecutionUseCaseResult _tradingControlUnavailable(
    BingxFuturesIntentPayload payload,
  ) {
    return _result(
      status: BingxFuturesExchangeExecutionUseCaseStatus.executionPaused,
      payload: payload,
      errorCode: 'trading_control_unavailable',
      errorMessage: 'Execution blocked because trading control is unavailable.',
    );
  }
}
