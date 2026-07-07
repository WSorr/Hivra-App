import 'bingx_futures_live_decision_models.dart';
import 'bingx_futures_observability_models.dart';
import 'plugin_host_api_models.dart';

class BingxFuturesIntentCommand {
  final String screen;
  final String peerHex;
  final String clientOrderId;
  final String symbol;
  final String side;
  final String orderType;
  final String quantityDecimal;
  final String? limitPriceDecimal;
  final String? timeInForce;
  final String entryMode;
  final String? zoneSide;
  final String? zoneLowDecimal;
  final String? zoneHighDecimal;
  final String? zonePriceRule;
  final String? manualEntryPriceDecimal;
  final String? triggerPriceDecimal;
  final String? stopLossDecimal;
  final String? takeProfitDecimal;
  final String createdAtUtc;
  final String? strategyTag;
  final BingxFuturesLiveDecisionResult? liveDecision;

  const BingxFuturesIntentCommand({
    required this.screen,
    required this.peerHex,
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.limitPriceDecimal,
    required this.timeInForce,
    required this.entryMode,
    required this.zoneSide,
    required this.zoneLowDecimal,
    required this.zoneHighDecimal,
    required this.zonePriceRule,
    required this.manualEntryPriceDecimal,
    required this.triggerPriceDecimal,
    required this.stopLossDecimal,
    required this.takeProfitDecimal,
    required this.createdAtUtc,
    required this.strategyTag,
    required this.liveDecision,
  });
}

class BingxFuturesIntentUseCaseResult {
  final PluginHostApiResponse response;
  final BingxFuturesLogEnvelope decisionEnvelope;

  const BingxFuturesIntentUseCaseResult({
    required this.response,
    required this.decisionEnvelope,
  });
}
