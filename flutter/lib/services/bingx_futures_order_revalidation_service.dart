import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_live_decision_service.dart';

enum BingxFuturesOrderRevalidationAction {
  keep,
  cancel,
}

class BingxFuturesOrderRevalidationResult {
  final BingxFuturesOrderRevalidationAction action;
  final String reasonCode;
  final String reasonMessage;

  const BingxFuturesOrderRevalidationResult({
    required this.action,
    required this.reasonCode,
    required this.reasonMessage,
  });

  bool get shouldCancel => action == BingxFuturesOrderRevalidationAction.cancel;
}

class BingxFuturesOrderRevalidationService {
  static const double _zoneTolerancePct = 0.0015;

  const BingxFuturesOrderRevalidationService();

  BingxFuturesOrderRevalidationResult revalidate({
    required BingxFuturesOpenOrder order,
    required BingxFuturesLiveDecisionResult liveDecision,
  }) {
    if (_hasMarketInvalidation(liveDecision)) {
      return BingxFuturesOrderRevalidationResult(
        action: BingxFuturesOrderRevalidationAction.cancel,
        reasonCode: liveDecision.trendGateCode,
        reasonMessage: 'Live market state invalidated the pending TVH setup.',
      );
    }

    if (!liveDecision.canPrepareIntent ||
        liveDecision.side == null ||
        liveDecision.zoneLowDecimal == null ||
        liveDecision.zoneHighDecimal == null) {
      return const BingxFuturesOrderRevalidationResult(
        action: BingxFuturesOrderRevalidationAction.keep,
        reasonCode: 'live_decision_not_actionable',
        reasonMessage: 'Live decision is not actionable but not market-dead.',
      );
    }

    final orderSide = _normalizeOrderSide(order.side);
    if (orderSide != null && orderSide != liveDecision.side) {
      return BingxFuturesOrderRevalidationResult(
        action: BingxFuturesOrderRevalidationAction.cancel,
        reasonCode: 'live_side_mismatch',
        reasonMessage:
            'Open order side $orderSide no longer matches live decision ${liveDecision.side}.',
      );
    }

    final orderPrice = _readOrderEntryPrice(order);
    final zoneLow = _parsePositiveDecimal(liveDecision.zoneLowDecimal);
    final zoneHigh = _parsePositiveDecimal(liveDecision.zoneHighDecimal);
    if (orderPrice == null || zoneLow == null || zoneHigh == null) {
      return const BingxFuturesOrderRevalidationResult(
        action: BingxFuturesOrderRevalidationAction.keep,
        reasonCode: 'insufficient_order_price',
        reasonMessage: 'Order price or live zone is not parseable.',
      );
    }

    final tolerance = orderPrice * _zoneTolerancePct;
    final min = zoneLow < zoneHigh ? zoneLow : zoneHigh;
    final max = zoneLow < zoneHigh ? zoneHigh : zoneLow;
    if (orderPrice < min - tolerance || orderPrice > max + tolerance) {
      return BingxFuturesOrderRevalidationResult(
        action: BingxFuturesOrderRevalidationAction.cancel,
        reasonCode: 'live_zone_mismatch',
        reasonMessage:
            'Open order price is outside the current deterministic TVH zone.',
      );
    }

    return const BingxFuturesOrderRevalidationResult(
      action: BingxFuturesOrderRevalidationAction.keep,
      reasonCode: 'live_setup_still_valid',
      reasonMessage: 'Open order remains aligned with live TVH setup.',
    );
  }

  bool _hasMarketInvalidation(BingxFuturesLiveDecisionResult liveDecision) {
    final code = liveDecision.trendGateCode.trim();
    return code == 'momentum_gate_short_missed_retest' ||
        code == 'momentum_gate_long_missed_retest' ||
        code == 'trend_gate_short_far_retest' ||
        code == 'trend_gate_long_far_retest';
  }

  String? _normalizeOrderSide(String side) {
    final normalized = side.trim().toLowerCase();
    return switch (normalized) {
      'buy' => 'buy',
      'sell' => 'sell',
      _ => null,
    };
  }

  double? _readOrderEntryPrice(BingxFuturesOpenOrder order) {
    return _parsePositiveDecimal(order.triggerPriceDecimal) ??
        _parsePositiveDecimal(order.priceDecimal);
  }

  double? _parsePositiveDecimal(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
