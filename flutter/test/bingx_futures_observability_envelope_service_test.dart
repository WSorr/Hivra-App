import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_observability_envelope_service.dart';

void main() {
  group('BingxFuturesObservabilityEnvelopeService', () {
    const service = BingxFuturesObservabilityEnvelopeService();
    final fixedTs = DateTime.utc(2026, 5, 13, 12, 34, 56);

    test('buildDecisionEnvelope is deterministic and sorts blocking facts', () {
      final first = service.buildDecisionEnvelope(
        screen: 'trading_drone',
        pluginId: 'hivra.contract.bingx-futures-trading.v1',
        method: 'place_bingx_futures_order_intent',
        status: 'blocked',
        symbol: 'btc-usdt',
        side: 'BUY',
        orderType: 'LIMIT',
        entryMode: 'zone_pending',
        executionSource: 'external_package',
        intentHashHex:
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        errorCode: 'blocked',
        blockingFactCodes: const <String>[
          'pending_remote_break',
          'pending_invitation',
        ],
        nowUtc: fixedTs,
      );
      final second = service.buildDecisionEnvelope(
        screen: 'trading_drone',
        pluginId: 'hivra.contract.bingx-futures-trading.v1',
        method: 'place_bingx_futures_order_intent',
        status: 'blocked',
        symbol: 'BTC-USDT',
        side: 'buy',
        orderType: 'limit',
        entryMode: 'zone_pending',
        executionSource: 'external_package',
        intentHashHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        errorCode: 'blocked',
        blockingFactCodes: const <String>[
          'pending_invitation',
          'pending_remote_break',
        ],
        nowUtc: fixedTs,
      );

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.envelopeHashHex, second.envelopeHashHex);
      expect(first.envelopeHashHex.length, 64);
    });

    test('buildExecutionEnvelope is deterministic for identical inputs', () {
      final first = service.buildExecutionEnvelope(
        screen: 'wasm_plugins',
        symbol: 'eth-usdt',
        side: 'SELL',
        orderType: 'limit',
        idempotencyKey: 'live|abc123',
        attempts: 2,
        fromIdempotentCache: false,
        isSuccess: true,
        httpStatusCode: 200,
        exchangeCode: '0',
        endpointPath: '/openApi/swap/v2/trade/order',
        orderId: 'ord-123',
        intentHashHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        riskDecisionCode: 'risk_allowed',
        riskDecisionHashHex:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        nowUtc: fixedTs,
      );
      final second = service.buildExecutionEnvelope(
        screen: 'wasm_plugins',
        symbol: 'ETH-USDT',
        side: 'sell',
        orderType: 'LIMIT',
        idempotencyKey: 'live|abc123',
        attempts: 2,
        fromIdempotentCache: false,
        isSuccess: true,
        httpStatusCode: 200,
        exchangeCode: '0',
        endpointPath: '/openApi/swap/v2/trade/order',
        orderId: 'ord-123',
        intentHashHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        riskDecisionCode: 'risk_allowed',
        riskDecisionHashHex:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        nowUtc: fixedTs,
      );

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.envelopeHashHex, second.envelopeHashHex);
      expect(first.envelopeHashHex.length, 64);
    });
  });
}
