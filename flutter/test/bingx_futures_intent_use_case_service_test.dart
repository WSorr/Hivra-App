import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/bingx_futures_intent_use_case_service.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_host_contract_handler.dart';

void main() {
  group('BingxFuturesIntentUseCaseService', () {
    test('clears zone-only fields for direct entry', () async {
      final handler = _CapturingHandler();
      final service = _service(handler);

      await service.execute(
        _command(
          entryMode: 'direct',
          zonePriceRule: 'manual',
          manualEntryPriceDecimal: '60000',
        ),
      );

      final args = handler.lastRequest!.args;
      expect(args['entry_mode'], 'direct');
      expect(args['zone_side'], isNull);
      expect(args['zone_low_decimal'], isNull);
      expect(args['zone_high_decimal'], isNull);
      expect(args['zone_price_rule'], isNull);
      expect(args['manual_entry_price_decimal'], isNull);
      expect(args['stop_loss_decimal'], isNull);
      expect(args['take_profit_decimal'], isNull);
    });

    test('passes normalized zone pending fields to host', () async {
      final handler = _CapturingHandler();
      final service = _service(handler);

      final result = await service.execute(
        _command(
          entryMode: 'zone_pending',
          zonePriceRule: 'manual',
          manualEntryPriceDecimal: ' 60000 ',
        ),
      );

      final args = handler.lastRequest!.args;
      expect(args['zone_side'], 'buyside');
      expect(args['zone_low_decimal'], '58000');
      expect(args['zone_high_decimal'], '60000');
      expect(args['manual_entry_price_decimal'], '60000');
      expect(args['stop_loss_decimal'], '57000');
      expect(args['take_profit_decimal'], '66000');
      expect(result.response.status, PluginHostApiStatus.executed);
      expect(result.decisionEnvelope.envelopeHashHex, hasLength(64));
    });
  });
}

BingxFuturesIntentUseCaseService _service(_CapturingHandler handler) {
  return BingxFuturesIntentUseCaseService(
    hostApi: PluginHostApiService(
      handlers: <PluginHostContractHandler>[handler],
    ),
  );
}

BingxFuturesIntentCommand _command({
  required String entryMode,
  required String zonePriceRule,
  required String manualEntryPriceDecimal,
}) {
  return BingxFuturesIntentCommand(
    screen: 'test',
    peerHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    clientOrderId: 'ord-1',
    symbol: 'BTC-USDT',
    side: 'buy',
    orderType: 'limit',
    quantityDecimal: '0.01',
    limitPriceDecimal: null,
    timeInForce: 'GTC',
    entryMode: entryMode,
    zoneSide: 'buyside',
    zoneLowDecimal: '58000',
    zoneHighDecimal: '60000',
    zonePriceRule: zonePriceRule,
    manualEntryPriceDecimal: manualEntryPriceDecimal,
    triggerPriceDecimal: '60000',
    stopLossDecimal: '57000',
    takeProfitDecimal: '66000',
    createdAtUtc: '2026-06-13T00:00:00Z',
    strategyTag: 'tvh_long_breakout_v1',
    liveDecision: null,
  );
}

class _CapturingHandler implements PluginHostContractHandler {
  PluginHostApiRequest? lastRequest;

  @override
  String get pluginId => bingxFuturesTradingPluginId;

  @override
  String get contractKind => 'bingx_futures_order_intent';

  @override
  Set<String> get methods => const <String>{placeBingxFuturesOrderIntentMethod};

  @override
  bool get requiresExternalRuntime => false;

  @override
  Set<String> requiredCapabilities(String method) => const <String>{};

  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) => null;

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    lastRequest = request;
    return const PluginHostContractResult.executed(<String, dynamic>{
      'intent_hash_hex':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    });
  }
}
