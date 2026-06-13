import 'bingx_trading_contract_service.dart';
import 'capsule_chat_contract_service.dart';
import 'plugin_host_api_service.dart';
import 'plugin_host_contract_handler.dart';

const String bingxFuturesTradingPluginId =
    BingxTradingContractService.futuresPluginId;
const String placeBingxFuturesOrderIntentMethod =
    'place_bingx_futures_order_intent';
const String capsuleChatPluginId = CapsuleChatContractService.pluginId;
const String postCapsuleChatMethod = 'post_capsule_chat_message';

typedef CapsuleChatRunner = CapsuleChatExecutionResult Function({
  required String peerHex,
  required String clientMessageId,
  required String messageText,
  required String createdAtUtc,
});

typedef BingxFuturesOrderRunner = BingxTradingExecutionResult Function({
  required String peerHex,
  required String clientOrderId,
  required String symbol,
  required String side,
  required String orderType,
  required String quantityDecimal,
  required String? limitPriceDecimal,
  required String? timeInForce,
  required String? entryMode,
  required String? zoneSide,
  required String? zoneLowDecimal,
  required String? zoneHighDecimal,
  required String? zonePriceRule,
  required String? manualEntryPriceDecimal,
  required String? triggerPriceDecimal,
  required String? stopLossDecimal,
  required String? takeProfitDecimal,
  required String createdAtUtc,
  required String? strategyTag,
});

class CapsuleChatPluginContractHandler implements PluginHostContractHandler {
  final CapsuleChatRunner _run;

  const CapsuleChatPluginContractHandler({required CapsuleChatRunner run})
      : _run = run;

  @override
  String get pluginId => capsuleChatPluginId;

  @override
  String get contractKind => 'capsule_chat';

  @override
  Set<String> get methods => const <String>{postCapsuleChatMethod};

  @override
  bool get requiresExternalRuntime => false;

  @override
  Set<String> requiredCapabilities(String method) =>
      const <String>{'consensus_guard.read'};

  @override
  PluginHostContractResult execute(PluginHostApiRequest request) {
    final peerHex = request.args['peer_hex']?.toString().trim().toLowerCase();
    final clientMessageId =
        request.args['client_message_id']?.toString().trim();
    final messageText = request.args['message_text']?.toString();
    final createdAtUtc = request.args['created_at_utc']?.toString().trim();
    if (peerHex == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex) ||
        clientMessageId == null ||
        clientMessageId.isEmpty ||
        messageText == null ||
        messageText.trim().isEmpty ||
        createdAtUtc == null ||
        createdAtUtc.isEmpty) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_args',
        message:
            'peer_hex/client_message_id/message_text/created_at_utc are required',
      );
    }
    try {
      final runResult = _run(
        peerHex: peerHex,
        clientMessageId: clientMessageId,
        messageText: messageText,
        createdAtUtc: createdAtUtc,
      );
      final envelope = runResult.envelope;
      if (envelope == null) {
        return PluginHostContractResult.blocked(runResult.blockingFacts);
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        'peer_hex': envelope.peerHex,
        'client_message_id': envelope.clientMessageId,
        'message_text': envelope.messageText,
        'created_at_utc': envelope.createdAtUtc,
        'envelope_hash_hex': envelope.envelopeHashHex,
        'canonical_envelope_json': envelope.canonicalJson,
      });
    } on FormatException catch (error) {
      return PluginHostContractResult.rejected(
        code: 'invalid_args',
        message: error.message,
      );
    }
  }
}

class BingxFuturesPluginContractHandler implements PluginHostContractHandler {
  final BingxFuturesOrderRunner _run;

  const BingxFuturesPluginContractHandler({
    required BingxFuturesOrderRunner run,
  }) : _run = run;

  @override
  String get pluginId => bingxFuturesTradingPluginId;

  @override
  String get contractKind => BingxTradingContractService.futuresContractKind;

  @override
  Set<String> get methods => const <String>{placeBingxFuturesOrderIntentMethod};

  @override
  bool get requiresExternalRuntime => true;

  @override
  Set<String> requiredCapabilities(String method) => const <String>{
        'consensus_guard.read',
        'exchange.trade.bingx.futures',
      };

  @override
  PluginHostContractResult execute(PluginHostApiRequest request) {
    final args = request.args;
    final peerHex = args['peer_hex']?.toString().trim().toLowerCase();
    final clientOrderId = args['client_order_id']?.toString().trim();
    final symbol = args['symbol']?.toString().trim();
    final side = args['side']?.toString().trim();
    final orderType = args['order_type']?.toString().trim();
    final quantityDecimal = args['quantity_decimal']?.toString().trim();
    final createdAtUtc = args['created_at_utc']?.toString().trim();
    if (peerHex == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex) ||
        clientOrderId == null ||
        clientOrderId.isEmpty ||
        symbol == null ||
        symbol.isEmpty ||
        side == null ||
        side.isEmpty ||
        orderType == null ||
        orderType.isEmpty ||
        quantityDecimal == null ||
        quantityDecimal.isEmpty ||
        createdAtUtc == null ||
        createdAtUtc.isEmpty) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_args',
        message:
            'peer_hex/client_order_id/symbol/side/order_type/quantity_decimal/created_at_utc are required',
      );
    }
    try {
      final runResult = _run(
        peerHex: peerHex,
        clientOrderId: clientOrderId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        quantityDecimal: quantityDecimal,
        limitPriceDecimal: _optional(args, 'limit_price_decimal'),
        timeInForce: _optional(args, 'time_in_force'),
        entryMode: _optional(args, 'entry_mode'),
        zoneSide: _optional(args, 'zone_side'),
        zoneLowDecimal: _optional(args, 'zone_low_decimal'),
        zoneHighDecimal: _optional(args, 'zone_high_decimal'),
        zonePriceRule: _optional(args, 'zone_price_rule'),
        manualEntryPriceDecimal: _optional(args, 'manual_entry_price_decimal'),
        triggerPriceDecimal: _optional(args, 'trigger_price_decimal'),
        stopLossDecimal: _optional(args, 'stop_loss_decimal'),
        takeProfitDecimal: _optional(args, 'take_profit_decimal'),
        createdAtUtc: createdAtUtc,
        strategyTag: _optional(args, 'strategy_tag'),
      );
      final intent = runResult.intent;
      if (intent == null) {
        return PluginHostContractResult.blocked(runResult.blockingFacts);
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        'plugin_id': intent.pluginId,
        'contract_kind': contractKind,
        'peer_hex': intent.peerHex,
        'client_order_id': intent.clientOrderId,
        'symbol': intent.symbol,
        'side': intent.side.name,
        'order_type': intent.orderType.name,
        'quantity_decimal': intent.quantityDecimal,
        'limit_price_decimal': intent.limitPriceDecimal,
        'time_in_force': intent.timeInForce,
        'entry_mode': intent.entryMode == BingxEntryMode.zonePending
            ? 'zone_pending'
            : 'direct',
        'zone_side': intent.zoneSide?.name,
        'zone_low_decimal': intent.zoneLowDecimal,
        'zone_high_decimal': intent.zoneHighDecimal,
        'zone_price_rule': switch (intent.zonePriceRule) {
          BingxZonePriceRule.zoneLow => 'zone_low',
          BingxZonePriceRule.zoneMid => 'zone_mid',
          BingxZonePriceRule.zoneHigh => 'zone_high',
          BingxZonePriceRule.manual => 'manual',
          null => null,
        },
        'trigger_price_decimal': intent.triggerPriceDecimal,
        'stop_loss_decimal': intent.stopLossDecimal,
        'take_profit_decimal': intent.takeProfitDecimal,
        'created_at_utc': intent.createdAtUtc,
        'strategy_tag': intent.strategyTag,
        'intent_hash_hex': intent.intentHashHex,
        'canonical_intent_json': intent.canonicalJson,
        'market_snapshot_hash_hex': _optional(args, 'market_snapshot_hash_hex'),
        'feature_hash_hex': _optional(args, 'feature_hash_hex'),
        'tvh_decision_hash_hex': _optional(args, 'tvh_decision_hash_hex'),
        'live_decision_hash_hex': _optional(args, 'live_decision_hash_hex'),
      });
    } on FormatException catch (error) {
      return PluginHostContractResult.rejected(
        code: 'invalid_args',
        message: error.message,
      );
    }
  }

  String? _optional(Map<String, dynamic> args, String key) =>
      args[key]?.toString().trim();
}
