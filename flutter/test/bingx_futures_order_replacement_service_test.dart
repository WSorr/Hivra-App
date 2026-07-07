import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_risk_models.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_execution_queue_service.dart';
import 'package:hivra_app/services/bingx_futures_live_decision_service.dart';
import 'package:hivra_app/services/bingx_futures_order_replacement_service.dart';
import 'package:hivra_app/services/bingx_futures_tvh_rule_engine_service.dart';

void main() {
  group('BingxFuturesOrderReplacementService', () {
    const service = BingxFuturesOrderReplacementService();

    test('builds deterministic same-side replacement for stale zone', () {
      final first = service.plan(
        provenance: _provenance(),
        liveDecision: _decision(),
        cancellationReasonCode: 'live_zone_mismatch',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
      );
      final second = service.plan(
        provenance: _provenance(),
        liveDecision: _decision(),
        cancellationReasonCode: 'live_zone_mismatch',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
      );

      expect(first.isReady, isTrue);
      expect(first.hostArgs, second.hostArgs);
      expect(first.hostArgs!['client_order_id'], startsWith('repl-'));
      expect(first.hostArgs!['symbol'], 'BNB-USDT');
      expect(first.hostArgs!['side'], 'sell');
      expect(first.hostArgs!['zone_low_decimal'], '110');
      expect(first.hostArgs!['zone_high_decimal'], '112');
      expect(first.hostArgs!['trigger_price_decimal'], '110');
      expect(first.hostArgs!['stop_loss_decimal'], '116.55');
      expect(first.hostArgs!['take_profit_decimal'], '99.9');
      expect(first.hostArgs!['quantity_decimal'], '0.25');
      expect(first.hostArgs!['strategy_tag'], 'tvh_short_breakdown_v1');
      expect(first.hostArgs!['live_decision_hash_hex'], _liveHash);
    });

    test('does not replace market-dead cancellation', () {
      final result = service.plan(
        provenance: _provenance(),
        liveDecision: _decision(canPrepareIntent: false),
        cancellationReasonCode: 'momentum_gate_short_missed_retest',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
      );

      expect(result.isReady, isFalse);
      expect(result.reasonCode, 'replacement_not_allowed_for_reason');
    });

    test('does not reverse side automatically', () {
      final result = service.plan(
        provenance: _provenance(),
        liveDecision: _decision(side: 'buy'),
        cancellationReasonCode: 'live_zone_mismatch',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
      );

      expect(result.isReady, isFalse);
      expect(result.reasonCode, 'replacement_side_flip_forbidden');
    });

    test('requires complete risk lineage', () {
      final canonical = jsonDecode(_canonicalIntent()) as Map<String, dynamic>;
      canonical['stop_loss_decimal'] = null;
      final result = service.plan(
        provenance: _provenance(
          canonicalIntentJson: jsonEncode(canonical),
        ),
        liveDecision: _decision(),
        cancellationReasonCode: 'live_zone_mismatch',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
      );

      expect(result.isReady, isFalse);
      expect(result.reasonCode, 'replacement_risk_lineage_missing');
    });

    test('runtime executes host, risk, and queue in strict order', () async {
      final calls = <String>[];
      bool? observedTestOrder;
      final result = await service.execute(
        provenance: _provenance(),
        liveDecision: _decision(),
        cancellationReasonCode: 'live_zone_mismatch',
        cycleAtUtc: '2026-06-12T12:00:00.000Z',
        prepareIntent: (hostArgs) async {
          calls.add('host');
          return _hostExecuted(hostArgs);
        },
        evaluateRisk: (payload, rawIntentResult) async {
          calls.add('risk');
          return _riskAllowed();
        },
        executeOrder: (payload, testOrder) async {
          calls.add('queue');
          observedTestOrder = testOrder;
          return _queuedSuccess();
        },
      );

      expect(calls, <String>['host', 'risk', 'queue']);
      expect(observedTestOrder, isFalse);
      expect(result.status, BingxFuturesReplacementRuntimeStatus.executed);
      expect(result.isExecuted, isTrue);
      expect(result.queuedExecution!.execution.orderId, 'ord-new');
    });
  });
}

const _liveHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

BingxManagedOrderProvenance _provenance({
  String? canonicalIntentJson,
}) {
  return BingxManagedOrderProvenance(
    orderId: 'ord-old',
    symbol: 'BNB-USDT',
    side: 'sell',
    testOrder: false,
    intentHashHex:
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    canonicalIntentJson: canonicalIntentJson ?? _canonicalIntent(),
    marketSnapshotHashHex: 'old-market',
    featureHashHex: 'old-feature',
    tvhDecisionHashHex: 'old-tvh',
    liveDecisionHashHex: 'old-live',
    recordedAtUtc: '2026-06-12T11:00:00.000Z',
  );
}

String _canonicalIntent() {
  return jsonEncode(<String, dynamic>{
    'peer_hex':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'client_order_id': 'old-client',
    'symbol': 'BNB-USDT',
    'side': 'sell',
    'order_type': 'limit',
    'quantity_decimal': '0.25',
    'limit_price_decimal': '100',
    'time_in_force': 'GTC',
    'entry_mode': 'zone_pending',
    'zone_side': 'sellside',
    'zone_low_decimal': '99',
    'zone_high_decimal': '101',
    'zone_price_rule': 'zone_mid',
    'trigger_price_decimal': '99',
    'stop_loss_decimal': '105',
    'take_profit_decimal': '90',
    'created_at_utc': '2026-06-12T11:00:00.000Z',
    'strategy_tag': 'interactive',
  });
}

BingxFuturesLiveDecisionResult _decision({
  String side = 'sell',
  bool canPrepareIntent = true,
}) {
  return BingxFuturesLiveDecisionResult(
    canPrepareIntent: canPrepareIntent,
    decision:
        side == 'buy' ? BingxTvhDecisionKind.long : BingxTvhDecisionKind.short,
    side: side,
    zoneSide: side == 'buy' ? 'buyside' : 'sellside',
    zoneLowDecimal: '110',
    zoneHighDecimal: '112',
    zoneConflict: false,
    marketSnapshotHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    featureHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    tvhDecisionHashHex:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    liveDecisionHashHex: _liveHash,
    canonicalJson: '{"decision":"short"}',
    reasons: const <BingxTvhDecisionReason>[],
    trend15m: side == 'buy' ? 'bullish' : 'bearish',
    trend4h: side == 'buy' ? 'bull' : 'bear',
    trend1d: side == 'buy' ? 'bull' : 'bear',
    trendGateBlocked: false,
    trendGateCode: 'ok',
  );
}

PluginHostApiResponse _hostExecuted(Map<String, dynamic> hostArgs) {
  return PluginHostApiResponse(
    status: PluginHostApiStatus.executed,
    pluginId: 'hivra.contract.bingx-futures-trading.v1',
    method: 'place_bingx_futures_order_intent',
    executionSource: 'wasm_runtime',
    executionPackageId: 'pkg',
    executionPackageVersion: '1',
    executionPackageKind: 'wasm',
    executionPackageDigestHex: 'pkg-digest',
    executionContractKind: 'bingx_futures_order_intent',
    executionRuntimeMode: 'wasmi_v1',
    executionRuntimeAbi: 'hivra_plugin_v1',
    executionRuntimeEntryExport: 'hivra_invoke',
    executionRuntimeModulePath: 'plugin/module.wasm',
    executionRuntimeModuleSelection: 'manifest',
    executionRuntimeModuleDigestHex: 'module-digest',
    executionRuntimeInvokeDigestHex: 'invoke-digest',
    executionCapabilities: const <String>[
      'consensus_guard.read',
      'exchange.trade.bingx.futures',
    ],
    errorCode: null,
    errorMessage: null,
    blockingFacts: const [],
    result: <String, dynamic>{
      ...hostArgs,
      'limit_price_decimal': '111',
      'intent_hash_hex':
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      'canonical_intent_json': jsonEncode(hostArgs),
    },
    canonicalJson: '{"status":"executed"}',
    responseHashHex:
        'abababababababababababababababababababababababababababababababab',
  );
}

BingxFuturesRiskDecision _riskAllowed() {
  return const BingxFuturesRiskDecision(
    status: BingxFuturesRiskDecisionStatus.allowed,
    reasonCode: 'risk_allowed',
    reasonMessage: 'ok',
    canonicalJson: '{}',
    decisionHashHex:
        '1212121212121212121212121212121212121212121212121212121212121212',
    maxAllowedQuantityDecimal: '1',
    tradeRiskQuoteDecimal: '1',
    tradeRiskLimitQuoteDecimal: '2',
    dailyLossQuoteDecimal: '0',
    dailyLossLimitQuoteDecimal: '5',
  );
}

BingxQueuedExecutionResult _queuedSuccess() {
  return BingxQueuedExecutionResult(
    execution: const BingxFuturesOrderExecutionResult(
      isSuccess: true,
      httpStatusCode: 200,
      exchangeCode: '0',
      exchangeMessage: 'ok',
      orderId: 'ord-new',
      endpointPath: '/openApi/swap/v2/trade/order',
      signedPayloadHashHex:
          '3434343434343434343434343434343434343434343434343434343434343434',
      responseBody: '{"code":0}',
      intentHashHex:
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    ),
    idempotencyKey: 'live|intent',
    attempts: 1,
    fromIdempotentCache: false,
    exhaustedRetries: false,
    pendingTracked: true,
  );
}
