import '../models/plugin_contract_ids.dart';
import 'bingx_futures_live_decision_service.dart';
import 'bingx_futures_observability_envelope_service.dart';
import 'plugin_host_api_service.dart';

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

class BingxFuturesIntentUseCaseService {
  final PluginHostApiService _hostApi;
  final BingxFuturesObservabilityEnvelopeService _observability;

  const BingxFuturesIntentUseCaseService({
    required PluginHostApiService hostApi,
    BingxFuturesObservabilityEnvelopeService observability =
        const BingxFuturesObservabilityEnvelopeService(),
  })  : _hostApi = hostApi,
        _observability = observability;

  Future<BingxFuturesIntentUseCaseResult> execute(
    BingxFuturesIntentCommand command,
  ) async {
    final isZonePending = command.entryMode == 'zone_pending';
    final response = await _hostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: PluginHostApiService.schemaVersion,
        pluginId: bingxFuturesTradingPluginId,
        method: placeBingxFuturesOrderIntentMethod,
        args: <String, dynamic>{
          'peer_hex': command.peerHex,
          'client_order_id': command.clientOrderId,
          'symbol': command.symbol,
          'side': command.side,
          'order_type': command.orderType,
          'quantity_decimal': command.quantityDecimal,
          'limit_price_decimal': command.limitPriceDecimal,
          'time_in_force': command.timeInForce,
          'entry_mode': command.entryMode,
          'zone_side': isZonePending ? command.zoneSide : null,
          'zone_low_decimal':
              isZonePending ? _nonEmpty(command.zoneLowDecimal) : null,
          'zone_high_decimal':
              isZonePending ? _nonEmpty(command.zoneHighDecimal) : null,
          'zone_price_rule': isZonePending ? command.zonePriceRule : null,
          'manual_entry_price_decimal':
              isZonePending && command.zonePriceRule == 'manual'
                  ? _nonEmpty(command.manualEntryPriceDecimal)
                  : null,
          'trigger_price_decimal':
              isZonePending ? _nonEmpty(command.triggerPriceDecimal) : null,
          'stop_loss_decimal':
              isZonePending ? _nonEmpty(command.stopLossDecimal) : null,
          'take_profit_decimal':
              isZonePending ? _nonEmpty(command.takeProfitDecimal) : null,
          'created_at_utc': command.createdAtUtc,
          'strategy_tag': _nonEmpty(command.strategyTag),
          'market_snapshot_hash_hex':
              command.liveDecision?.marketSnapshotHashHex,
          'feature_hash_hex': command.liveDecision?.featureHashHex,
          'tvh_decision_hash_hex': command.liveDecision?.tvhDecisionHashHex,
          'live_decision_hash_hex': command.liveDecision?.liveDecisionHashHex,
        },
      ),
    );
    final decisionEnvelope = _observability.buildDecisionEnvelope(
      screen: command.screen,
      pluginId: bingxFuturesTradingPluginId,
      method: placeBingxFuturesOrderIntentMethod,
      status: response.status.name,
      symbol: command.symbol,
      side: command.side,
      orderType: command.orderType,
      entryMode: command.entryMode,
      executionSource: response.executionSource,
      intentHashHex: response.result?['intent_hash_hex']?.toString(),
      errorCode: response.errorCode,
      marketSnapshotHashHex: command.liveDecision?.marketSnapshotHashHex ??
          response.result?['market_snapshot_hash_hex']?.toString(),
      featureHashHex: command.liveDecision?.featureHashHex ??
          response.result?['feature_hash_hex']?.toString(),
      tvhDecisionHashHex: command.liveDecision?.tvhDecisionHashHex ??
          response.result?['tvh_decision_hash_hex']?.toString(),
      liveDecisionHashHex: command.liveDecision?.liveDecisionHashHex ??
          response.result?['live_decision_hash_hex']?.toString(),
      blockingFactCodes:
          response.blockingFacts.map((fact) => fact.key).toList(),
    );
    return BingxFuturesIntentUseCaseResult(
      response: response,
      decisionEnvelope: decisionEnvelope,
    );
  }

  String? _nonEmpty(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
