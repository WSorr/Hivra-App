import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';

import '../tool/trading_remote_deterministic_order.dart';
import '../tool/trading_remote_exact_order.dart' show runAuthorizedExactOrder;

void main() {
  test('one signed deterministic cycle composes and executes once', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final requests = <BingxHttpRequest>[];
    Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
      requests.add(request);
      return _providerResponse(request);
    }

    final first = jsonDecode(
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
        clockMs: () => 1770000000000,
      ),
    );
    final replay = jsonDecode(
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
        clockMs: () => 1770000001000,
      ),
    );

    expect(first['state'], 'succeeded');
    expect(first['operation_id'], fixture.admissionOperationId);
    expect(replay, first);
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
  });

  test('stale market evidence blocks without an exchange effect', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final requests = <BingxHttpRequest>[];

    final result = jsonDecode(
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: (request) async {
          requests.add(request);
          return _providerResponse(request);
        },
        nowUtc: () => fixture.now.add(const Duration(minutes: 2)),
      ),
    );

    expect(result['state'], 'blocked');
    expect(result['operation_id'], fixture.admissionOperationId);
    expect(result['reason_code'], 'market_evidence_stale');
    expect(result['effect'], isFalse);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });
}

BingxHttpResponse _providerResponse(BingxHttpRequest request) {
  final body = switch (request.uri.path) {
    '/openApi/swap/v3/user/balance' =>
      '{"code":0,"data":[{"asset":"USDT","equity":"1000"}]}',
    '/openApi/swap/v2/user/positions' => '{"code":0,"data":[]}',
    '/openApi/swap/v2/user/income' => '{"code":0,"data":[]}',
    '/openApi/swap/v2/quote/contracts' =>
      '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":1,"quantityPrecision":3,"pricePrecision":2}]}',
    '/openApi/swap/v2/trade/order/test' =>
      '{"code":0,"msg":"success","data":{"order":{"orderID":"test-order-1"}}}',
    _ => throw StateError('unexpected endpoint ${request.uri.path}'),
  };
  return BingxHttpResponse(statusCode: 200, body: body);
}

Future<
  ({
    Directory directory,
    List<int> runnerSeed,
    DateTime now,
    String admissionOperationId,
    Map<String, String> options,
    Future<void> Function() dispose,
  })
>
_fixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'hivra-deterministic-cycle.',
  );
  final now = DateTime.utc(2026, 8, 22, 12);
  final runnerSeed = List<int>.generate(32, (index) => index + 1);
  final runnerKeyPair = await Ed25519().newKeyPairFromSeed(runnerSeed);
  final runnerPublicKey = await runnerKeyPair.extractPublicKey();
  final runnerKeyId = sha256.convert(runnerPublicKey.bytes).toString();
  final capsuleKeyPair = await Ed25519().newKeyPairFromSeed(
    List<int>.generate(32, (index) => 255 - index),
  );
  final capsulePublicKey = await capsuleKeyPair.extractPublicKey();
  const apiKey = 'deterministic-api-key';
  const apiSecret = 'deterministic-api-secret';
  final mandate = BingxFuturesTradingMandate.issue(
    capsuleRootHex: _hex(capsulePublicKey.bytes),
    accountBindingHashHex: sha256.convert(utf8.encode(apiKey)).toString(),
    symbol: 'BTC-USDT',
    testOrder: true,
    issuedAtUtc: now.subtract(const Duration(minutes: 1)),
    expiresAtUtc: now.add(const Duration(hours: 1)),
    maxOrderNotionalQuoteDecimal: '10',
    maxRiskPerTradePercent: 2,
    maxDailyLossPercent: 3,
    maxConcurrentPositions: 1,
    cooldownAfterLossStreak: 2,
    cooldownMinutes: 10,
    maxEffects: 1,
  );
  final policy = <String, dynamic>{
    'runner_build_id': 'runner-build',
    'plugin_id': 'hivra.bingx-futures-trading',
    'plugin_version': '0.2.7-plugins',
    'package_digest_hex': 'a' * 64,
    'host_abi': 'dart-headless-v1',
    'stop_loss_percent': 5,
    'minimum_risk_reward': 2,
  };
  final unsignedAdmission =
      BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
        mandate: mandate,
        runnerKeyId: runnerKeyId,
        strategyPolicy: policy,
        signCommitment: (_) => '0' * 128,
      )!;
  final admissionSignature = await Ed25519().sign(
    _decodeHex(unsignedAdmission.commitmentHashHex),
    keyPair: capsuleKeyPair,
  );
  final admission =
      BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
        mandate: mandate,
        runnerKeyId: runnerKeyId,
        strategyPolicy: policy,
        signCommitment: (_) => _hex(admissionSignature.bytes),
      )!;
  final admissionFile = File('${directory.path}/admission.json');
  await admissionFile.writeAsString(admission.canonicalJson, flush: true);

  final proposal = <String, dynamic>{
    'schema_version': 2,
    'contract': 'bingx_futures_live_decision_v2',
    'market_snapshot_hash_hex': '1' * 64,
    'feature_hash_hex': '2' * 64,
    'tvh_decision_hash_hex': '3' * 64,
    'decision': 'long',
    'can_prepare_intent': true,
    'trend_bundle': <String, dynamic>{
      'trend_15m': 'bullish',
      'trend_4h': 'bull',
      'trend_1d': 'bull',
    },
    'trend_gate': <String, dynamic>{'blocked': false, 'code': 'ok'},
    'side': 'buy',
    'zone_evaluation_side': 'buy',
    'zone': <String, dynamic>{
      'side': 'buyside',
      'low_decimal': '100',
      'high_decimal': '101',
      'source': 'micro_sweep_reclaim',
      'side_reason': 'buy_signal',
      'conflict': false,
      'target_retest_pct': 0.01,
      'needs_farther_retest': false,
      'anchor_source': 'micro_sweep_reclaim',
      'anchor_executable': true,
      'anchor_lifecycle': 'fresh',
      'liquidity_event_id': '4' * 64,
      'liquidity_event_at_utc': '2026-08-22T11:50:00Z',
      'latest_closed_micro_bar_at_utc': '2026-08-22T11:55:00Z',
    },
    'profit_target': <String, dynamic>{
      'kind': 'opposite_external_liquidity',
      'price_decimal': '111',
      'source': '1d_fresh_high',
      'event_at_utc': '2026-08-21T00:00:00Z',
    },
    'reason_codes': <Map<String, dynamic>>[
      <String, dynamic>{'code': 'funding_guard', 'passed': true},
    ],
  };
  final proposalJson = jsonEncode(proposal);
  const harness = BingxFuturesDeterministicReplayHarnessService();
  final unsignedEvidence = harness.buildShadowEvidence(
    publicRun: BingxFuturesReplayRunResult(
      fixtureId: 'live:BTC-USDT',
      marketSnapshotHashHex: '1' * 64,
      featureHashHex: '2' * 64,
      decisionHashHex: sha256.convert(utf8.encode(proposalJson)).toString(),
      decision: BingxTvhDecisionKind.long,
      topReasonCode: 'funding_guard',
      marketSymbol: 'BTC-USDT',
      marketProposalStatus: 'READY',
      marketProposalJson: proposalJson,
    ),
    runnerBuildId: policy['runner_build_id'] as String,
    pluginId: policy['plugin_id'] as String,
    pluginVersion: policy['plugin_version'] as String,
    packageDigestHex: policy['package_digest_hex'] as String,
    hostAbi: policy['host_abi'] as String,
    observedAtEpochMs: now.millisecondsSinceEpoch,
    validUntilEpochMs:
        now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    sequence: 1,
    previousEvidenceHashHex: _zeroHash,
    runnerKeyId: runnerKeyId,
    contractVersion: 'trading-shadow-evidence-v2',
  );
  final evidenceSignature = await Ed25519().sign(
    unsignedEvidence.signingPayload,
    keyPair: runnerKeyPair,
  );
  final evidence = unsignedEvidence.withSignature(
    _hex(evidenceSignature.bytes),
  );
  final evidenceFile = File('${directory.path}/evidence.json');
  await evidenceFile.writeAsBytes(evidence.wireBytes, flush: true);

  final credentialFile = File('${directory.path}/credential.json');
  await credentialFile.writeAsString(
    jsonEncode(<String, String>{
      'contract_version': 'bingx-exchange-credential-v1',
      'api_key': apiKey,
      'api_secret': apiSecret,
    }),
    flush: true,
  );
  await Process.run('chmod', <String>['600', credentialFile.path]);
  final seedFile = File('${directory.path}/runner-seed');
  await seedFile.writeAsString(_hex(runnerSeed), flush: true);
  await Process.run('chmod', <String>['600', seedFile.path]);
  return (
    directory: directory,
    runnerSeed: runnerSeed,
    now: now,
    admissionOperationId: admission.operationId,
    options: <String, String>{
      'mode': deterministicOrderMode,
      'runner-seed-file': seedFile.path,
      'deterministic-admission-file': admissionFile.path,
      'market-evidence-file': evidenceFile.path,
      'deterministic-credential-file': credentialFile.path,
      'deterministic-state-home': '${directory.path}/state',
      'last-accepted-sequence': '0',
      'last-accepted-evidence-hash': _zeroHash,
    },
    dispose: () => directory.delete(recursive: true),
  );
}

const _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

List<int> _decodeHex(String value) => List<int>.generate(
  value.length ~/ 2,
  (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
);
