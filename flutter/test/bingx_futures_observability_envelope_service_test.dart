import 'dart:convert';
import 'dart:io';

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
        marketSnapshotHashHex:
            '1111111111111111111111111111111111111111111111111111111111111111',
        featureHashHex:
            '2222222222222222222222222222222222222222222222222222222222222222',
        tvhDecisionHashHex:
            '3333333333333333333333333333333333333333333333333333333333333333',
        liveDecisionHashHex:
            '4444444444444444444444444444444444444444444444444444444444444444',
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
        marketSnapshotHashHex:
            '1111111111111111111111111111111111111111111111111111111111111111',
        featureHashHex:
            '2222222222222222222222222222222222222222222222222222222222222222',
        tvhDecisionHashHex:
            '3333333333333333333333333333333333333333333333333333333333333333',
        liveDecisionHashHex:
            '4444444444444444444444444444444444444444444444444444444444444444',
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
        marketSnapshotHashHex:
            '1111111111111111111111111111111111111111111111111111111111111111',
        featureHashHex:
            '2222222222222222222222222222222222222222222222222222222222222222',
        tvhDecisionHashHex:
            '3333333333333333333333333333333333333333333333333333333333333333',
        liveDecisionHashHex:
            '4444444444444444444444444444444444444444444444444444444444444444',
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
        marketSnapshotHashHex:
            '1111111111111111111111111111111111111111111111111111111111111111',
        featureHashHex:
            '2222222222222222222222222222222222222222222222222222222222222222',
        tvhDecisionHashHex:
            '3333333333333333333333333333333333333333333333333333333333333333',
        liveDecisionHashHex:
            '4444444444444444444444444444444444444444444444444444444444444444',
        nowUtc: fixedTs,
      );

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.envelopeHashHex, second.envelopeHashHex);
      expect(first.envelopeHashHex.length, 64);
    });

    test('release evidence fixture matches production envelope hashes', () {
      final fixture =
          jsonDecode(
                File(
                  '../tools/release/trading_drone_evidence_fixture.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final decision = fixture['decision'] as Map<String, dynamic>;
      final decisionEnvelope = service.buildDecisionEnvelope(
        screen: decision['screen'] as String,
        pluginId: decision['plugin_id'] as String,
        method: decision['method'] as String,
        status: decision['status'] as String,
        symbol: decision['symbol'] as String,
        side: decision['side'] as String,
        orderType: decision['order_type'] as String,
        entryMode: decision['entry_mode'] as String,
        executionSource: decision['execution_source'] as String,
        intentHashHex: decision['intent_hash_hex'] as String?,
        errorCode: decision['error_code'] as String?,
        marketSnapshotHashHex: decision['market_snapshot_hash_hex'] as String?,
        featureHashHex: decision['feature_hash_hex'] as String?,
        tvhDecisionHashHex: decision['tvh_decision_hash_hex'] as String?,
        liveDecisionHashHex: decision['live_decision_hash_hex'] as String?,
        blockingFactCodes:
            (decision['blocking_fact_codes'] as List<dynamic>).cast<String>(),
        nowUtc: DateTime.parse(decision['timestamp_utc'] as String),
      );

      expect(decisionEnvelope.envelopeHashHex, decision['expected_hash']);

      final executions = fixture['executions'] as Map<String, dynamic>;
      for (final entry in executions.entries) {
        final execution = entry.value as Map<String, dynamic>;
        final executionEnvelope = service.buildExecutionEnvelope(
          screen: execution['screen'] as String,
          symbol: execution['symbol'] as String,
          side: execution['side'] as String,
          orderType: execution['order_type'] as String,
          idempotencyKey: execution['idempotency_key'] as String,
          attempts: execution['attempts'] as int,
          fromIdempotentCache: execution['from_idempotent_cache'] as bool,
          isSuccess: execution['success'] as bool,
          httpStatusCode: execution['http_status_code'] as int,
          exchangeCode: execution['exchange_code'] as String,
          endpointPath: execution['endpoint_path'] as String,
          orderId: execution['order_id'] as String?,
          intentHashHex: execution['intent_hash_hex'] as String?,
          riskDecisionCode: execution['risk_decision_code'] as String?,
          riskDecisionHashHex: execution['risk_decision_hash_hex'] as String?,
          marketSnapshotHashHex:
              execution['market_snapshot_hash_hex'] as String?,
          featureHashHex: execution['feature_hash_hex'] as String?,
          tvhDecisionHashHex: execution['tvh_decision_hash_hex'] as String?,
          liveDecisionHashHex: execution['live_decision_hash_hex'] as String?,
          nowUtc: DateTime.parse(execution['timestamp_utc'] as String),
        );

        expect(
          executionEnvelope.envelopeHashHex,
          execution['expected_hash'],
          reason: entry.key,
        );
      }
    });
  });
}
