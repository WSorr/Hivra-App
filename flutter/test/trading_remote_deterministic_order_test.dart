import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';

import '../tool/trading_remote_deterministic_order.dart';
import '../tool/trading_remote_exact_order.dart'
    show
        completedSessionEffectsMode,
        exportCompletedDeterministicSessionEffects,
        reconcileAuthorizedExactOrder,
        runAuthorizedExactOrder;

void main() {
  for (final scenario in ['legacy', 'leverage', 'margin', 'missing', 'changed']) {
    test('exposure $scenario blocks without an order', () async {
      final fixture = await _fixture(includeExposureScope: scenario != 'legacy');
      addTearDown(fixture.dispose);
      var requests = 0;
      var posts = 0;
      var leverageReads = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        requests++;
        if (request.method == 'POST') posts++;
        if (request.uri.path.endsWith('/leverage')) {
          leverageReads++;
          if (scenario == 'leverage' || (scenario == 'changed' && leverageReads > 1)) {
            return const BingxHttpResponse(statusCode: 200,
              body: '{"code":0,"data":{"longLeverage":60,"shortLeverage":2}}');
          }
        }
        if (request.uri.path.endsWith('/balance') &&
            (scenario == 'margin' || scenario == 'missing')) {
          return BingxHttpResponse(statusCode: 200, body: jsonEncode({
            'code': 0, 'data': [{'asset': 'USDT', 'equity': '1000',
              if (scenario == 'margin') 'availableMargin': '0.01'}],
          }));
        }
        return _providerResponse(request);
      }
      final result = runOneDeterministicOrder(
        options: fixture.options, runnerSeedBytes: fixture.runnerSeed,
        nowUtc: () => fixture.now, requestSender: sender,
        executeExactOrder: runAuthorizedExactOrder,
      );
      if (scenario == 'changed') {
        await expectLater(result, throwsA(isA<FormatException>().having(
          (error) => error.message, 'reason', 'risk_stop_outside_leverage_buffer')));
        expect(leverageReads, 2);
      } else {
        final value = jsonDecode(await result);
        expect(value['state'], 'blocked');
        expect(value['reason_code'], {
          'legacy': 'exposure_read_authority_missing',
          'leverage': 'risk_stop_outside_leverage_buffer',
          'margin': 'risk_available_margin_insufficient',
          'missing': 'risk_exposure_unknown',
        }[scenario]);
      }
      expect(posts, 0);
      if (scenario == 'legacy') expect(requests, 0);
    });
  }

  test('closed-candle reclaim reaches one remote effect and survives recovery', () async {
    const strategy = BingxFuturesDeterministicReplayHarnessService();
    final before = strategy.runPublicLiveMarket(
      fixtureId: 'live:BTC-USDT', snapshotInput: _reclaimSnapshot(confirmed: false),
    );
    final after = strategy.runPublicLiveMarket(
      fixtureId: 'live:BTC-USDT', snapshotInput: _reclaimSnapshot(confirmed: true),
    );
    expect(before.marketProposalStatus, 'BLOCKED', reason: before.marketProposalJson);
    expect(after.marketProposalStatus, 'READY', reason: after.marketProposalJson);
    final waiting = await _fixture(sessionCycleIndex: 0, publicRun: before, testOrder: false);
    final previousEvidence = strategy.parseShadowEvidence(
      await File(waiting.options['market-evidence-file']!).readAsBytes(),
    );
    final readyAt = waiting.now.add(const Duration(minutes: 5));
    final ready = await _fixture(
      sessionCycleIndex: 1, publicRun: after, evidenceAtUtc: readyAt, testOrder: false,
      evidenceSequence: 2, previousEvidenceHash: previousEvidence.evidenceHashHex,
    );
    addTearDown(waiting.dispose);
    addTearDown(ready.dispose);
    final requests = <BingxHttpRequest>[];
    Map<String, String>? acceptedOrder;
    Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
      requests.add(request);
      if (request.method == 'POST') {
        expect(acceptedOrder, isNull, reason: 'a second effect reached the provider');
        expect(request.uri.path, '/openApi/swap/v2/trade/order');
        acceptedOrder = Uri.splitQueryString(request.body);
        throw TimeoutException('receipt lost after provider accepted the order');
      }
      if (request.uri.path == '/openApi/swap/v2/trade/order') {
        final order = acceptedOrder!;
        expect(request.method, 'GET');
        expect(request.uri.queryParameters['clientOrderId'], order['clientOrderId']);
        return BingxHttpResponse(statusCode: 200, body: jsonEncode({
          'code': 0,
          'data': {'order': {
            'orderId': 'accepted-reclaim-order',
            'clientOrderId': order['clientOrderId'],
            'symbol': order['symbol'], 'side': order['side'],
            'positionSide': order['positionSide'], 'type': order['type'],
            'status': 'NEW', 'price': order['price'], 'stopPrice': order['stopPrice'],
            'origQty': order['quantity'], 'executedQty': '0',
            'time': readyAt.millisecondsSinceEpoch,
          }},
        }));
      }
      return _providerResponse(request);
    }
    final blocked = jsonDecode(await runOneDeterministicOrder(
      options: waiting.options, runnerSeedBytes: waiting.runnerSeed,
      executeExactOrder: runAuthorizedExactOrder, requestSender: sender,
      nowUtc: () => waiting.now,
    ));
    expect(blocked['state'], 'blocked');
    expect(blocked['reason_code'], 'market_proposal_blocked');
    expect(requests.where((request) => request.method == 'POST'), isEmpty);

    final nextOptions = <String, String>{
      ...waiting.options,
      'session-cycle-index': '1',
      'market-evidence-file': ready.options['market-evidence-file']!,
      'last-accepted-sequence': '1',
      'last-accepted-evidence-hash': previousEvidence.evidenceHashHex,
    };
    final result = jsonDecode(await runOneDeterministicOrder(
      options: nextOptions, runnerSeedBytes: waiting.runnerSeed,
      executeExactOrder: runAuthorizedExactOrder, requestSender: sender,
      nowUtc: () => readyAt,
    ));
    expect(result['state'], 'unresolved', reason: '$result');
    final order = acceptedOrder!;
    expect(order['symbol'], 'BTC-USDT');
    expect(order['side'], 'BUY');
    expect(order['type'], 'TRIGGER_LIMIT');
    expect(num.parse(order['quantity']!) * num.parse(order['price']!), lessThanOrEqualTo(10));
    expect(order['stopLoss'], isNotNull);
    expect(order['takeProfit'], isNotNull);
    final requestsBeforeRecovery = requests.length;
    final recovered = jsonDecode(await recoverOneDeterministicOrder(
      options: nextOptions, runnerSeedBytes: waiting.runnerSeed,
      reconcileExactOrder: reconcileAuthorizedExactOrder, requestSender: sender,
      nowUtc: () => readyAt.add(const Duration(seconds: 30)),
    ));
    expect(recovered['state'], 'succeeded', reason: '$recovered');
    expect(recovered['operation_id'], result['operation_id']);
    expect(recovered['provider_reference_id'], 'accepted-reclaim-order');
    expect(recovered['receipt_evidence_hash_hex'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(requests.skip(requestsBeforeRecovery).map((request) => request.method), ['GET']);
    final requestsAfterRecovery = requests.length;
    final replay = jsonDecode(await recoverOneDeterministicOrder(
      options: nextOptions, runnerSeedBytes: waiting.runnerSeed,
      reconcileExactOrder: reconcileAuthorizedExactOrder, requestSender: sender,
      nowUtc: () => readyAt.add(const Duration(seconds: 30)),
    ));
    expect(replay, recovered);
    expect(requests.length, requestsAfterRecovery);
    await expectLater(
      runOneDeterministicOrder(
        options: nextOptions, runnerSeedBytes: waiting.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder, requestSender: sender,
        nowUtc: () => readyAt.add(const Duration(seconds: 30)),
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message, 'message',
        'External effect operation id is already bound to another effect',
      )),
    );
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
  });

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

  test('bounded session derives one exact child operation', () async {
    final fixture = await _fixture(sessionCycleIndex: 3);
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
        nowUtc: () => fixture.now,
      ),
    );

    expect(result['state'], 'succeeded');
    expect(result['operation_id'], fixture.admissionOperationId);
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
  });

  test(
    'completed session export returns exact retained effect and rejects mutation',
    () async {
      final fixture = await _fixture(sessionCycleIndex: 0, testOrder: false);
      addTearDown(fixture.dispose);
      final requests = <BingxHttpRequest>[];
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: (request) async {
          requests.add(request);
          return _providerResponse(request);
        },
        nowUtc: () => fixture.now,
      );
      final requestCountBeforeExport = requests.length;
      final admission =
          BingxFuturesRemoteMandateAdmission.parseAndVerify(
            untrustedWireBytes:
                await File(
                  fixture.options['deterministic-admission-file']!,
                ).readAsBytes(),
            verifySignature:
                ({
                  required messageHashHex,
                  required participantIdHex,
                  required signatureHex,
                }) => true,
          )!;
      final exportOptions = <String, String>{
        'mode': completedSessionEffectsMode,
        'expected-runner-key-id': admission.runnerKeyId,
        'deterministic-admission-file':
            fixture.options['deterministic-admission-file']!,
        'deterministic-state-home':
            fixture.options['deterministic-state-home']!,
      };

      final exported =
          jsonDecode(
                await exportCompletedDeterministicSessionEffects(
                  options: exportOptions,
                ),
              )
              as List<dynamic>;
      expect(exported, hasLength(1));
      expect(exported.single['operation_id'], fixture.admissionOperationId);
      expect(exported.single['state'], 'succeeded');
      expect(requests, hasLength(requestCountBeforeExport));

      final journal = await Directory(
            fixture.options['deterministic-state-home']!,
          )
          .list(recursive: true)
          .map((entry) => entry.path)
          .firstWhere((path) => path.endsWith('/external_effects.v1.json'));
      final journalFile = File(journal);
      final decoded = jsonDecode(await journalFile.readAsString()) as Map;
      final operations = decoded['operations'] as List;
      (operations.single as Map)['approval_evidence_hash_hex'] = 'f' * 64;
      await journalFile.writeAsString(jsonEncode(decoded), flush: true);
      await expectLater(
        exportCompletedDeterministicSessionEffects(options: exportOptions),
        throwsFormatException,
      );
    },
  );

  test(
    'session recovery reconciles one existing effect without POST',
    () async {
      final fixture = await _fixture(sessionCycleIndex: 0, testOrder: false);
      addTearDown(fixture.dispose);
      final initialRequests = <BingxHttpRequest>[];
      final unresolved = jsonDecode(
        await runOneDeterministicOrder(
          options: fixture.options,
          runnerSeedBytes: fixture.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: (request) async {
            initialRequests.add(request);
            if (request.method == 'POST') {
              throw TimeoutException('provider timeout');
            }
            return _providerResponse(request);
          },
          nowUtc: () => fixture.now,
        ),
      );
      final recoveryRequests = <BingxHttpRequest>[];
      final recoveryOptions = <String, String>{
        'mode': deterministicOrderRecoveryMode,
        'runner-seed-file': fixture.options['runner-seed-file']!,
        'deterministic-admission-file':
            fixture.options['deterministic-admission-file']!,
        'deterministic-credential-file':
            fixture.options['deterministic-credential-file']!,
        'deterministic-state-home':
            fixture.options['deterministic-state-home']!,
        'session-cycle-index': '0',
      };
      final recovered = jsonDecode(
        await recoverOneDeterministicOrder(
          options: recoveryOptions,
          runnerSeedBytes: fixture.runnerSeed,
          reconcileExactOrder: reconcileAuthorizedExactOrder,
          requestSender: (request) async {
            recoveryRequests.add(request);
            if (request.method == 'POST') {
              throw StateError('recovery attempted delivery');
            }
            final clientOrderId =
                request.uri.queryParameters['clientOrderId'] ?? '';
            return BingxHttpResponse(
              statusCode: 200,
              body: jsonEncode(<String, dynamic>{
                'code': 0,
                'msg': 'success',
                'data': <String, dynamic>{
                  'order': <String, dynamic>{
                    'orderId': 'order-1',
                    'clientOrderId': clientOrderId,
                    'symbol': 'BTC-USDT',
                    'side': 'BUY',
                    'positionSide': 'LONG',
                    'type': 'TRIGGER_LIMIT',
                    'status': 'NEW',
                    'price': '100',
                    'stopPrice': '99',
                    'origQty': '0.01',
                    'executedQty': '0',
                    'time': 1770000000000,
                  },
                },
              }),
            );
          },
          nowUtc: () => fixture.now.add(const Duration(hours: 2)),
        ),
      );

      expect(unresolved['state'], 'unresolved');
      expect(recovered['state'], 'succeeded');
      expect(recovered['operation_id'], fixture.admissionOperationId);
      expect(
        initialRequests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
      expect(
        recoveryRequests.where((request) => request.method == 'POST'),
        isEmpty,
      );
      expect(
        recoveryRequests.where((request) => request.method == 'GET'),
        hasLength(1),
      );
    },
  );
}

BingxFuturesMarketSnapshotInput _reclaimSnapshot({required bool confirmed}) {
  final start = DateTime.utc(2026, 8, 22, 9, 15);
  BingxFuturesCandle candle(String timeframe, DateTime closeAt,
      int minutes, num open, num high, num low, num close) => BingxFuturesCandle(
    timeframe: timeframe,
    openTimeUtc: closeAt.subtract(Duration(minutes: minutes)).toIso8601String(),
    closeTimeUtc: closeAt.toIso8601String(),
    openDecimal: '$open', highDecimal: '$high', lowDecimal: '$low',
    closeDecimal: '$close', volumeBaseDecimal: '100',
    volumeQuoteDecimal: '10000', isClosed: true,
  );
  final observedAt = DateTime.utc(2026, 8, 22, 12, confirmed ? 5 : 0);
  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT', baseAsset: 'BTC', quoteAsset: 'USDT',
      tickSizeDecimal: '0.01', qtyStepDecimal: '0.001', minQtyDecimal: '0.001',
      maxLeverageDecimal: '10',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '100', markPriceDecimal: '100', indexPriceDecimal: '100',
    ),
    candles: [
      for (var index = 0; index < (confirmed ? 34 : 33); index++)
        candle('5m', start.add(Duration(minutes: (index + 1) * 5)), 5,
          index == 33 ? 96 : 101, 102,
          index == 32 ? 95 : index == 33 ? 96 : [8, 16, 24].contains(index) ? 98 : 100,
          index == 32 ? 96 : index == 33 ? 100 : 101),
      for (var index = 0; index < 220; index++)
        candle('15m', start.subtract(Duration(minutes: (220 - index) * 15)),
          15, 100, 102, 98, 100),
      for (var index = 0; index < 24; index++)
        candle('1h', start.subtract(Duration(hours: 24 - index)), 60,
          100, 104, 96, 100),
      for (var index = 0; index < 7; index++)
        candle('4h', start.subtract(Duration(hours: (7 - index) * 4)),
          240, 100, index == 3 ? 112 : 105, 98, 100),
      candle('1m', start, 1, 100, 102, 98, 100),
      candle('1d', DateTime.utc(2026, 8, 22), 1440, 100, 112, 98, 100),
      candle('1w', DateTime.utc(2026, 8, 17), 10080, 100, 112, 98, 100),
    ],
    trades: [BingxFuturesTrade(
      tradeId: 'observed-buy', timestampUtc: observedAt.toIso8601String(),
      side: 'buy', priceDecimal: '100', quantityDecimal: '1',
    )],
    openInterest: [BingxFuturesOpenInterestPoint(
      timestampUtc: observedAt.toIso8601String(), openInterestDecimal: '1000',
    )],
    funding: BingxFuturesFundingSnapshot(
      timestampUtc: observedAt.toIso8601String(), fundingRateDecimal: '0',
      nextFundingAtUtc: DateTime.utc(2026, 8, 22, 16).toIso8601String(),
    ),
    liquidityLevels: const [
      BingxFuturesLiquidityLevel(
        kind: 'external', side: 'buyside', timeframe: '4h', priceDecimal: '112',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal', side: 'sellside', timeframe: '5m', priceDecimal: '98',
      ),
    ],
    sessionVolumes: [
      for (final session in ['asia', 'london', 'newyork'])
        BingxFuturesSessionVolumePoint(
          session: session, bucketStartUtc: DateTime.utc(2026, 8, 22).toIso8601String(),
          volumeDecimal: '100', deltaDecimal: '10',
        ),
    ],
  );
}

BingxHttpResponse _providerResponse(BingxHttpRequest request) {
  final body = switch (request.uri.path) {
    '/openApi/swap/v3/user/balance' =>
      '{"code":0,"data":[{"asset":"USDT","equity":"1000","availableMargin":"1000"}]}',
    '/openApi/swap/v2/trade/leverage' =>
      '{"code":0,"data":{"longLeverage":2,"shortLeverage":2}}',
    '/openApi/swap/v2/trade/marginType' =>
      '{"code":0,"data":{"marginType":"ISOLATED"}}',
    '/openApi/swap/v2/user/positions' => '{"code":0,"data":[]}',
    '/openApi/swap/v2/user/income' => '{"code":0,"data":[]}',
    '/openApi/swap/v2/quote/contracts' =>
      '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001,"tradeMinUSDT":1,"quantityPrecision":3,"pricePrecision":2}]}',
    '/openApi/swap/v2/trade/order/test' =>
      '{"code":0,"msg":"success","data":{"order":{"orderID":"test-order-1"}}}',
    '/openApi/swap/v2/trade/order' =>
      '{"code":0,"msg":"success","data":{"order":{"orderID":"live-order-1"}}}',
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
_fixture({
  int? sessionCycleIndex,
  bool testOrder = true,
  bool includeExposureScope = true,
  BingxFuturesReplayRunResult? publicRun,
  DateTime? evidenceAtUtc,
  int evidenceSequence = 1,
  String previousEvidenceHash = _zeroHash,
}) async {
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
    testOrder: testOrder,
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
    if (includeExposureScope)
      'account_read_scope': BingxFuturesRemoteMandateAdmission.exposureReadScope,
  };
  BingxFuturesRemoteMandateAdmission issue(String? Function(String) signer) =>
      sessionCycleIndex == null
          ? BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
            mandate: mandate,
            runnerKeyId: runnerKeyId,
            strategyPolicy: policy,
            signCommitment: signer,
          )!
          : BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
            mandate: mandate,
            runnerKeyId: runnerKeyId,
            strategyPolicy: policy,
            startsAtUtc: now,
            intervalSeconds: 300,
            maxCycles: 12,
            signCommitment: signer,
          )!;
  final unsignedAdmission = issue((_) => '0' * 128);
  final admissionSignature = await Ed25519().sign(
    _decodeHex(unsignedAdmission.commitmentHashHex),
    keyPair: capsuleKeyPair,
  );
  final admission = issue((_) => _hex(admissionSignature.bytes));
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
      'anchor_lifecycle': 'reclaimed',
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
    publicRun: publicRun ?? BingxFuturesReplayRunResult(
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
    observedAtEpochMs: (evidenceAtUtc ?? now).millisecondsSinceEpoch,
    validUntilEpochMs:
        (evidenceAtUtc ?? now).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    sequence: evidenceSequence,
    previousEvidenceHashHex: previousEvidenceHash,
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
    admissionOperationId:
        admission.deterministicCycleOperationId(sessionCycleIndex ?? 0)!,
    options: <String, String>{
      'mode': deterministicOrderMode,
      'runner-seed-file': seedFile.path,
      'deterministic-admission-file': admissionFile.path,
      'market-evidence-file': evidenceFile.path,
      'deterministic-credential-file': credentialFile.path,
      'deterministic-state-home': '${directory.path}/state',
      'last-accepted-sequence': '0',
      'last-accepted-evidence-hash': _zeroHash,
      if (sessionCycleIndex != null)
        'session-cycle-index': sessionCycleIndex.toString(),
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
