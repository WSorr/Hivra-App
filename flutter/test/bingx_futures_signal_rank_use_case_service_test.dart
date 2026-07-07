import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_live_decision_models.dart';
import 'package:hivra_app/models/bingx_futures_signal_rank_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/bingx_futures_signal_rank_use_case_service.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_host_contract_handler.dart';

void main() {
  group('BingxFuturesSignalRankUseCaseService', () {
    test('calls plugin signal rank method and parses ranked entries', () async {
      final handler = _CapturingRankHandler();
      final service = BingxFuturesSignalRankUseCaseService(
        hostApi: PluginHostApiService(
          handlers: <PluginHostContractHandler>[handler],
        ),
      );

      final result = await service.execute(
        BingxFuturesSignalRankCommand(
          candidates: <BingxFuturesSignalRankCandidate>[
            BingxFuturesSignalRankCandidate(
              symbol: 'sol-usdt',
              decision: _decision(),
            ),
          ],
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(handler.lastRequest?.method, rankBingxFuturesSignalsMethod);
      expect(handler.lastRequest?.args['candidates'], isA<List>());
      final candidates = handler.lastRequest!.args['candidates'] as List;
      expect((candidates.first as Map)['symbol'], 'SOL-USDT');
      expect(result.scanHashHex, _hash);
      expect(result.entries.single.symbol, 'SOL-USDT');
      expect(result.entries.single.bucket, 'ready');
      expect(result.entries.single.score, 10800);
    });
  });
}

class _CapturingRankHandler implements PluginHostContractHandler {
  PluginHostApiRequest? lastRequest;

  @override
  String get pluginId => bingxFuturesTradingPluginId;

  @override
  String get contractKind => bingxFuturesContractKind;

  @override
  Set<String> get methods => const <String>{rankBingxFuturesSignalsMethod};

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
      'scan_hash_hex': _hash,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'symbol': 'SOL-USDT',
          'bucket': 'ready',
          'score': 10800,
          'decision': 'short',
          'side': 'sell',
          'zone_low_decimal': '89',
          'zone_high_decimal': '91',
          'trend_gate_code': 'ok',
          'can_prepare_intent': true,
          'live_decision_hash_hex': _hash,
          'failed_reason_codes': <String>[],
        },
      ],
    });
  }
}

BingxFuturesLiveDecisionResult _decision() {
  return const BingxFuturesLiveDecisionResult(
    canPrepareIntent: true,
    decision: BingxTvhDecisionKind.short,
    side: 'sell',
    zoneSide: 'buyside',
    zoneLowDecimal: '89',
    zoneHighDecimal: '91',
    zoneConflict: false,
    marketSnapshotHashHex: _hash,
    featureHashHex: _hash,
    tvhDecisionHashHex: _hash,
    liveDecisionHashHex: _hash,
    canonicalJson: '{}',
    reasons: <BingxTvhDecisionReason>[],
    trend15m: 'bear',
    trend4h: 'bear',
    trend1d: 'bear',
    trendGateBlocked: false,
    trendGateCode: 'ok',
    zoneAnchorSource: 'liquidation',
    zoneAnchorExecutable: true,
    zoneAnchorLifecycle: 'fresh',
    zoneEvaluationSide: 'sell',
  );
}

const String _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
