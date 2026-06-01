import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/bingx_trading_contract_service.dart';
import 'package:hivra_app/services/capsule_chat_contract_service.dart';
import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';

void main() {
  group('PluginHostApiService', () {
    test('rejects unsupported plugin id', () {
      final service = _service();
      final response = service.execute(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.unknown.v1',
          method: 'unknown_method',
          args: <String, dynamic>{},
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'unsupported_plugin');
    });

    test('executes bingx spot intent', () {
      final service = _service(
        runBingxSpotOrder: ({
          required peerHex,
          required clientOrderId,
          required symbol,
          required side,
          required orderType,
          required quantityDecimal,
          required limitPriceDecimal,
          required timeInForce,
          required entryMode,
          required zoneSide,
          required zoneLowDecimal,
          required zoneHighDecimal,
          required zonePriceRule,
          required manualEntryPriceDecimal,
          required triggerPriceDecimal,
          required stopLossDecimal,
          required takeProfitDecimal,
          required createdAtUtc,
          required strategyTag,
        }) =>
            const BingxTradingExecutionResult(
          intent: BingxSpotOrderIntent(
            pluginId: BingxTradingContractService.spotPluginId,
            peerHex: _peerHex,
            clientOrderId: 'ord-1',
            symbol: 'BTC-USDT',
            side: BingxOrderSide.buy,
            orderType: BingxOrderType.limit,
            quantityDecimal: '0.01',
            limitPriceDecimal: '60000',
            timeInForce: 'GTC',
            entryMode: BingxEntryMode.direct,
            zoneSide: null,
            zoneLowDecimal: null,
            zoneHighDecimal: null,
            zonePriceRule: null,
            triggerPriceDecimal: null,
            stopLossDecimal: null,
            takeProfitDecimal: null,
            createdAtUtc: '2026-01-01T00:00:00Z',
            strategyTag: 'test',
            canonicalJson: '{"ok":true}',
            intentHashHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );
      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.bingxSpotTradingPluginId,
          method: PluginHostApiService.placeBingxSpotOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.errorCode, isNull);
      expect(response.result?['plugin_id'],
          BingxTradingContractService.spotPluginId);
    });

    test('returns blocked when chat runner reports blocking facts', () {
      final service = _service(
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(code: 'pending_remote_break'),
          ],
        ),
      );
      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.capsuleChatPluginId,
          method: PluginHostApiService.postCapsuleChatMethod,
          args: _validChatArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.blocked);
      expect(response.blockingFacts.length, 1);
      expect(response.blockingFacts.first.code, 'pending_remote_break');
    });
  });
}

PluginHostApiService _service({
  BingxSpotOrderRunner? runBingxSpotOrder,
  BingxSpotOrderRunner? runBingxFuturesOrder,
  CapsuleChatRunner? runCapsuleChat,
}) {
  return PluginHostApiService(
    runBingxSpotOrder: runBingxSpotOrder ?? _noopBingx,
    runBingxFuturesOrder: runBingxFuturesOrder ?? _noopBingx,
    runCapsuleChat: runCapsuleChat ??
        ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
              envelope: null,
              blockingFacts: <ConsensusBlockingFact>[],
            ),
  );
}

BingxTradingExecutionResult _noopBingx({
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
}) {
  return const BingxTradingExecutionResult(
    intent: null,
    blockingFacts: <ConsensusBlockingFact>[
      ConsensusBlockingFact(code: 'pending_invitation'),
    ],
  );
}

Map<String, dynamic> _validBingxArgs() {
  return <String, dynamic>{
    'peer_hex': _peerHex,
    'client_order_id': 'ord-1',
    'symbol': 'BTC-USDT',
    'side': 'buy',
    'order_type': 'limit',
    'quantity_decimal': '0.01',
    'limit_price_decimal': '60000',
    'time_in_force': 'GTC',
    'created_at_utc': '2026-01-01T00:00:00Z',
  };
}

Map<String, dynamic> _validChatArgs() {
  return <String, dynamic>{
    'peer_hex': _peerHex,
    'client_message_id': 'msg-1',
    'message_text': 'hello',
    'created_at_utc': '2026-01-01T00:00:00Z',
  };
}

const String _peerHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
