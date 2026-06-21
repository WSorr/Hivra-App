import 'dart:io';

import 'package:hivra_app/services/bingx_futures_observability_envelope_service.dart';

void main(List<String> args) {
  final options = _parseArgs(args);
  final platform = options['platform'] ?? 'macOS';
  final mode = options['mode'] ?? 'interactive';
  final riskPath = options['risk-path'] ?? 'risk_allowed';
  final nowUtc = DateTime.utc(2026, 6, 21, 0, 0);

  final service = BingxFuturesObservabilityEnvelopeService();
  final decision = service.buildDecisionEnvelope(
    screen: 'trading_drone',
    pluginId: 'hivra.contract.bingx-futures-trading.v1',
    method: 'place_bingx_futures_order_intent',
    status: riskPath == 'risk_blocked' ? 'blocked' : 'executed',
    symbol: 'BTC-USDT',
    side: 'buy',
    orderType: 'limit',
    entryMode: 'zone_pending',
    executionSource: 'deterministic_fixture',
    intentHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    errorCode: riskPath == 'risk_blocked' ? 'risk_blocked' : null,
    marketSnapshotHashHex:
        '1111111111111111111111111111111111111111111111111111111111111111',
    featureHashHex:
        '2222222222222222222222222222222222222222222222222222222222222222',
    tvhDecisionHashHex:
        '3333333333333333333333333333333333333333333333333333333333333333',
    liveDecisionHashHex:
        '4444444444444444444444444444444444444444444444444444444444444444',
    blockingFactCodes: riskPath == 'risk_blocked'
        ? const <String>['exchange_minimum_exceeds_risk_budget']
        : const <String>[],
    nowUtc: nowUtc,
  );

  final execution = service.buildExecutionEnvelope(
    screen: 'trading_drone',
    symbol: 'BTC-USDT',
    side: 'buy',
    orderType: 'limit',
    idempotencyKey: 'fixture|$platform|$mode|$riskPath',
    attempts: 1,
    fromIdempotentCache: false,
    isSuccess: riskPath != 'risk_blocked',
    httpStatusCode: riskPath == 'risk_blocked' ? 0 : 200,
    exchangeCode: riskPath == 'risk_blocked' ? 'risk_blocked' : '0',
    endpointPath: riskPath == 'risk_blocked'
        ? 'risk_governor'
        : '/openApi/swap/v2/trade/order',
    orderId: riskPath == 'risk_blocked' ? null : 'fixture-order',
    intentHashHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    riskDecisionCode: riskPath,
    riskDecisionHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    marketSnapshotHashHex:
        '1111111111111111111111111111111111111111111111111111111111111111',
    featureHashHex:
        '2222222222222222222222222222222222222222222222222222222222222222',
    tvhDecisionHashHex:
        '3333333333333333333333333333333333333333333333333333333333333333',
    liveDecisionHashHex:
        '4444444444444444444444444444444444444444444444444444444444444444',
    nowUtc: nowUtc,
  );

  stdout.writeln('platform=$platform');
  stdout.writeln('mode=$mode');
  stdout.writeln('risk_path=$riskPath');
  stdout.writeln('decision_hash=${decision.envelopeHashHex}');
  stdout.writeln('execution_hash=${execution.envelopeHashHex}');
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    final key = arg.substring(2);
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      throw FormatException('Missing value for: $arg');
    }
    parsed[key] = args[++i];
  }
  return parsed;
}
