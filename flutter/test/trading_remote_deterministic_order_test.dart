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
        runAuthorizedManagedOrderCancellation,
        runAuthorizedExactOrder;

void main() {
  for (final scenario in [
    'legacy',
    'leverage',
    'margin',
    'missing',
    'changed',
  ]) {
    test('exposure $scenario blocks without an order', () async {
      final fixture = await _fixture(
        includeExposureScope: scenario != 'legacy',
      );
      addTearDown(fixture.dispose);
      var requests = 0;
      var posts = 0;
      var leverageReads = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        requests++;
        if (request.method == 'POST') posts++;
        if (request.uri.path.endsWith('/leverage')) {
          leverageReads++;
          if (scenario == 'leverage' ||
              (scenario == 'changed' && leverageReads > 1)) {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"data":{"longLeverage":60,"shortLeverage":2}}',
            );
          }
        }
        if (request.uri.path.endsWith('/balance') &&
            (scenario == 'margin' || scenario == 'missing')) {
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'code': 0,
              'data': [
                {
                  'asset': 'USDT',
                  'equity': '1000',
                  if (scenario == 'margin') 'availableMargin': '0.01',
                },
              ],
            }),
          );
        }
        return _providerResponse(request);
      }

      final result = runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        nowUtc: () => fixture.now,
        requestSender: sender,
        executeExactOrder: runAuthorizedExactOrder,
      );
      if (scenario == 'changed') {
        await expectLater(
          result,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'reason',
              'risk_stop_outside_leverage_buffer',
            ),
          ),
        );
        expect(leverageReads, 2);
      } else {
        final value = jsonDecode(await result);
        expect(value['state'], 'blocked');
        expect(
          value['reason_code'],
          {
            'legacy': 'exposure_read_authority_missing',
            'leverage': 'risk_stop_outside_leverage_buffer',
            'margin': 'risk_available_margin_insufficient',
            'missing': 'risk_exposure_unknown',
          }[scenario],
        );
      }
      expect(posts, 0);
      if (scenario == 'legacy') expect(requests, 0);
    });
  }

  test(
    'closed-candle reclaim reaches one remote effect and survives recovery',
    () async {
      const strategy = BingxFuturesDeterministicReplayHarnessService();
      final before = strategy.runPublicLiveMarket(
        fixtureId: 'live:BTC-USDT',
        snapshotInput: _reclaimSnapshot(confirmed: false),
      );
      final after = strategy.runPublicLiveMarket(
        fixtureId: 'live:BTC-USDT',
        snapshotInput: _reclaimSnapshot(confirmed: true),
      );
      expect(
        before.marketProposalStatus,
        'BLOCKED',
        reason: before.marketProposalJson,
      );
      expect(
        after.marketProposalStatus,
        'READY',
        reason: after.marketProposalJson,
      );
      final waiting = await _fixture(
        sessionCycleIndex: 0,
        publicRun: before,
        testOrder: false,
      );
      final previousEvidence = strategy.parseShadowEvidence(
        await File(waiting.options['market-evidence-file']!).readAsBytes(),
      );
      final readyAt = waiting.now.add(const Duration(minutes: 5));
      final ready = await _fixture(
        sessionCycleIndex: 1,
        publicRun: after,
        evidenceAtUtc: readyAt,
        testOrder: false,
        evidenceSequence: 2,
        previousEvidenceHash: previousEvidence.evidenceHashHex,
      );
      addTearDown(waiting.dispose);
      addTearDown(ready.dispose);
      final requests = <BingxHttpRequest>[];
      Map<String, String>? acceptedOrder;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        requests.add(request);
        if (request.method == 'POST') {
          expect(
            acceptedOrder,
            isNull,
            reason: 'a second effect reached the provider',
          );
          expect(request.uri.path, '/openApi/swap/v2/trade/order');
          acceptedOrder = Uri.splitQueryString(request.body);
          throw TimeoutException(
            'receipt lost after provider accepted the order',
          );
        }
        if (request.uri.path == '/openApi/swap/v2/trade/order') {
          final order = acceptedOrder!;
          expect(request.method, 'GET');
          expect(
            request.uri.queryParameters['clientOrderId'],
            order['clientOrderId'],
          );
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'code': 0,
              'data': {
                'order': {
                  'orderId': 'accepted-reclaim-order',
                  'clientOrderId': order['clientOrderId'],
                  'symbol': order['symbol'],
                  'side': order['side'],
                  'positionSide': order['positionSide'],
                  'type': order['type'],
                  'status': 'NEW',
                  'price': order['price'],
                  'stopPrice': order['stopPrice'],
                  'origQty': order['quantity'],
                  'executedQty': '0',
                  'time': readyAt.millisecondsSinceEpoch,
                },
              },
            }),
          );
        }
        return _providerResponse(request);
      }

      final blocked = jsonDecode(
        await runOneDeterministicOrder(
          options: waiting.options,
          runnerSeedBytes: waiting.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => waiting.now,
        ),
      );
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
      final result = jsonDecode(
        await runOneDeterministicOrder(
          options: nextOptions,
          runnerSeedBytes: waiting.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => readyAt,
        ),
      );
      expect(result['state'], 'unresolved', reason: '$result');
      final order = acceptedOrder!;
      expect(order['symbol'], 'BTC-USDT');
      expect(order['side'], 'BUY');
      expect(order['type'], 'TRIGGER_LIMIT');
      expect(
        num.parse(order['quantity']!) * num.parse(order['price']!),
        lessThanOrEqualTo(10),
      );
      expect(order['stopLoss'], isNotNull);
      expect(order['takeProfit'], isNotNull);
      final requestsBeforeRecovery = requests.length;
      final recovered = jsonDecode(
        await recoverOneDeterministicOrder(
          options: nextOptions,
          runnerSeedBytes: waiting.runnerSeed,
          reconcileExactOrder: reconcileAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => readyAt.add(const Duration(seconds: 30)),
        ),
      );
      expect(recovered['state'], 'succeeded', reason: '$recovered');
      expect(recovered['operation_id'], result['operation_id']);
      expect(recovered['provider_reference_id'], 'accepted-reclaim-order');
      expect(
        recovered['receipt_evidence_hash_hex'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        requests.skip(requestsBeforeRecovery).map((request) => request.method),
        ['GET'],
      );
      final requestsAfterRecovery = requests.length;
      final replay = jsonDecode(
        await recoverOneDeterministicOrder(
          options: nextOptions,
          runnerSeedBytes: waiting.runnerSeed,
          reconcileExactOrder: reconcileAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => readyAt.add(const Duration(seconds: 30)),
        ),
      );
      expect(replay, recovered);
      expect(requests.length, requestsAfterRecovery);
      await expectLater(
        runOneDeterministicOrder(
          options: nextOptions,
          runnerSeedBytes: waiting.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => readyAt.add(const Duration(seconds: 30)),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'External effect operation id is already bound to another effect',
          ),
        ),
      );
      expect(
        requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
    },
  );

  test(
    'external symbol order blocks the next session effect before POST',
    () async {
      final fixture = await _fixture(sessionCycleIndex: 0, testOrder: false);
      addTearDown(fixture.dispose);
      var posts = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        if (request.method == 'POST') posts += 1;
        if (request.uri.path == '/openApi/swap/v2/trade/openOrders') {
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"orders":[{"orderId":"existing-order","clientOrderId":"manual-or-runner","symbol":"BTC-USDT","side":"BUY","positionSide":"LONG","type":"TRIGGER_LIMIT","status":"NEW","price":"100","stopPrice":"99","origQty":"0.01","executedQty":"0","time":1}]}}',
          );
        }
        return _providerResponse(request);
      }

      final result = jsonDecode(
        await runOneDeterministicOrder(
          options: fixture.options,
          runnerSeedBytes: fixture.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: sender,
          nowUtc: () => fixture.now,
        ),
      );

      expect(result['state'], 'blocked');
      expect(result['reason_code'], 'external_order_active');
      expect(posts, 0);
    },
  );

  test('two session cycles can create at most one active order', () async {
    final fixture = await _fixture(
      sessionCycleIndex: 0,
      testOrder: false,
      maxEffects: 2,
    );
    addTearDown(fixture.dispose);
    var posts = 0;
    var orderIsActive = false;
    String? activeClientOrderId;
    Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
      if (request.uri.path == '/openApi/swap/v2/trade/openOrders') {
        return BingxHttpResponse(
          statusCode: 200,
          body:
              orderIsActive
                  ? jsonEncode(<String, dynamic>{
                    'code': 0,
                    'msg': 'ok',
                    'data': <String, dynamic>{
                      'orders': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'orderId': 'live-order-1',
                          'clientOrderId': activeClientOrderId,
                          'symbol': 'BTC-USDT',
                          'side': 'BUY',
                          'positionSide': 'LONG',
                          'type': 'TRIGGER_LIMIT',
                          'status': 'NEW',
                          'price': '100',
                          'stopPrice': '99',
                          'origQty': '0.01',
                          'executedQty': '0',
                          'time': 1,
                        },
                      ],
                    },
                  })
                  : '{"code":0,"msg":"ok","data":{"orders":[]}}',
        );
      }
      if (request.method == 'POST') {
        posts += 1;
        activeClientOrderId =
            Uri.splitQueryString(request.body)['clientOrderId'];
        orderIsActive = true;
      }
      return _providerResponse(request);
    }

    final first = jsonDecode(
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
      ),
    );
    final second = jsonDecode(
      await runOneDeterministicOrder(
        options: <String, String>{
          ...fixture.options,
          'session-cycle-index': '1',
        },
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
      ),
    );

    expect(first['state'], 'succeeded');
    expect(second['state'], 'blocked');
    expect(second['reason_code'], 'managed_order_active');
    expect(posts, 1);
  });

  test(
    'fresh liquidity event cancels the managed order before next placement',
    () async {
      final first = await _fixture(
        sessionCycleIndex: 0,
        testOrder: false,
        maxEffects: 2,
        liquidityEventId: '4' * 64,
      );
      final harness = const BingxFuturesDeterministicReplayHarnessService();
      final firstEvidence = harness.parseShadowEvidence(
        await File(first.options['market-evidence-file']!).readAsBytes(),
      );
      final second = await _fixture(
        sessionCycleIndex: 1,
        testOrder: false,
        maxEffects: 2,
        liquidityEventId: '5' * 64,
        evidenceSequence: 2,
        previousEvidenceHash: firstEvidence.evidenceHashHex,
      );
      final secondEvidence = harness.parseShadowEvidence(
        await File(second.options['market-evidence-file']!).readAsBytes(),
      );
      final third = await _fixture(
        sessionCycleIndex: 2,
        testOrder: false,
        maxEffects: 2,
        liquidityEventId: '5' * 64,
        evidenceSequence: 3,
        previousEvidenceHash: secondEvidence.evidenceHashHex,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(third.dispose);

      var active = false;
      var activeOrderId = '';
      String? activeClientOrderId;
      var posts = 0;
      var deletes = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        if (request.uri.path == '/openApi/swap/v2/trade/openOrders') {
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, dynamic>{
              'code': 0,
              'msg': 'ok',
              'data': <String, dynamic>{
                'orders':
                    active
                        ? <Map<String, dynamic>>[
                          <String, dynamic>{
                            'orderId': activeOrderId,
                            'clientOrderId': activeClientOrderId,
                            'symbol': 'BTC-USDT',
                            'side': 'BUY',
                            'positionSide': 'LONG',
                            'type': 'TRIGGER_LIMIT',
                            'status': 'NEW',
                            'price': '100.5',
                            'stopPrice': '101',
                            'origQty': '0.01',
                            'executedQty': '0',
                            'time': 1,
                          },
                        ]
                        : <Map<String, dynamic>>[],
              },
            }),
          );
        }
        if (request.uri.path == '/openApi/swap/v2/trade/order' &&
            request.method == 'DELETE') {
          deletes += 1;
          active = false;
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, dynamic>{
              'code': 0,
              'msg': 'success',
              'data': <String, dynamic>{
                'order': <String, dynamic>{'orderID': activeOrderId},
              },
            }),
          );
        }
        if (request.uri.path == '/openApi/swap/v2/trade/order' &&
            request.method == 'POST') {
          posts += 1;
          activeOrderId = 'live-order-$posts';
          activeClientOrderId =
              Uri.splitQueryString(request.body)['clientOrderId'];
          active = true;
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, dynamic>{
              'code': 0,
              'msg': 'success',
              'data': <String, dynamic>{
                'order': <String, dynamic>{'orderID': activeOrderId},
              },
            }),
          );
        }
        return _providerResponse(request);
      }

      final placed = jsonDecode(
        await runOneDeterministicOrder(
          options: first.options,
          runnerSeedBytes: first.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          cancelManagedOrder: runAuthorizedManagedOrderCancellation,
          requestSender: sender,
          nowUtc: () => first.now,
        ),
      );
      final cancelled = jsonDecode(
        await runOneDeterministicOrder(
          options: <String, String>{
            ...first.options,
            'session-cycle-index': '1',
            'market-evidence-file': second.options['market-evidence-file']!,
            'last-accepted-sequence': '1',
            'last-accepted-evidence-hash': firstEvidence.evidenceHashHex,
          },
          runnerSeedBytes: first.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          cancelManagedOrder: runAuthorizedManagedOrderCancellation,
          requestSender: sender,
          nowUtc: () => first.now,
        ),
      );
      expect(placed['state'], 'succeeded');
      expect(cancelled['state'], 'succeeded');
      expect(
        cancelled['contract_version'],
        'hivra-trading-managed-order-cancellation-evidence-v1',
      );
      expect(posts, 1);
      expect(deletes, 1);
      expect(active, isFalse);

      final replaced = jsonDecode(
        await runOneDeterministicOrder(
          options: <String, String>{
            ...first.options,
            'session-cycle-index': '2',
            'market-evidence-file': third.options['market-evidence-file']!,
            'last-accepted-sequence': '2',
            'last-accepted-evidence-hash': secondEvidence.evidenceHashHex,
          },
          runnerSeedBytes: first.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          cancelManagedOrder: runAuthorizedManagedOrderCancellation,
          requestSender: sender,
          nowUtc: () => first.now,
        ),
      );
      expect(replaced['state'], 'succeeded');
      expect(posts, 2);
      expect(deletes, 1);
      expect(active, isTrue);
      expect(activeClientOrderId, 'hivra-${'5' * 32}');
    },
  );

  test(
    'ambiguous managed cancellation reconciles without a second DELETE',
    () async {
      final first = await _fixture(
        sessionCycleIndex: 0,
        testOrder: false,
        maxEffects: 2,
        liquidityEventId: '6' * 64,
      );
      final harness = const BingxFuturesDeterministicReplayHarnessService();
      final firstEvidence = harness.parseShadowEvidence(
        await File(first.options['market-evidence-file']!).readAsBytes(),
      );
      final second = await _fixture(
        sessionCycleIndex: 1,
        testOrder: false,
        maxEffects: 2,
        liquidityEventId: '7' * 64,
        evidenceSequence: 2,
        previousEvidenceHash: firstEvidence.evidenceHashHex,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      var active = false;
      var clientOrderId = '';
      var deletes = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        if (request.uri.path == '/openApi/swap/v2/trade/openOrders') {
          return BingxHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, dynamic>{
              'code': 0,
              'msg': 'ok',
              'data': <String, dynamic>{
                'orders':
                    active
                        ? <Map<String, dynamic>>[
                          <String, dynamic>{
                            'orderId': 'accepted-order',
                            'clientOrderId': clientOrderId,
                            'symbol': 'BTC-USDT',
                            'side': 'BUY',
                            'positionSide': 'LONG',
                            'type': 'TRIGGER_LIMIT',
                            'status': 'NEW',
                            'price': '100.5',
                            'stopPrice': '101',
                            'origQty': '0.01',
                            'executedQty': '0',
                            'time': 1,
                          },
                        ]
                        : <Map<String, dynamic>>[],
              },
            }),
          );
        }
        if (request.uri.path == '/openApi/swap/v2/trade/order' &&
            request.method == 'POST') {
          clientOrderId = Uri.splitQueryString(request.body)['clientOrderId']!;
          active = true;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"success","data":{"order":{"orderID":"accepted-order"}}}',
          );
        }
        if (request.uri.path == '/openApi/swap/v2/trade/order' &&
            request.method == 'DELETE') {
          deletes += 1;
          active = false;
          throw TimeoutException('response lost after cancellation');
        }
        return _providerResponse(request);
      }

      final placed = jsonDecode(
        await runOneDeterministicOrder(
          options: first.options,
          runnerSeedBytes: first.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          cancelManagedOrder: runAuthorizedManagedOrderCancellation,
          requestSender: sender,
          nowUtc: () => first.now,
        ),
      );
      final unresolved = jsonDecode(
        await runOneDeterministicOrder(
          options: <String, String>{
            ...first.options,
            'session-cycle-index': '1',
            'market-evidence-file': second.options['market-evidence-file']!,
            'last-accepted-sequence': '1',
            'last-accepted-evidence-hash': firstEvidence.evidenceHashHex,
          },
          runnerSeedBytes: first.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          cancelManagedOrder: runAuthorizedManagedOrderCancellation,
          requestSender: sender,
          nowUtc: () => first.now,
        ),
      );
      final recoveryRequests = <BingxHttpRequest>[];
      final recovered = jsonDecode(
        await recoverOneDeterministicOrder(
          options: <String, String>{
            'mode': deterministicOrderRecoveryMode,
            'runner-seed-file': first.options['runner-seed-file']!,
            'deterministic-admission-file':
                first.options['deterministic-admission-file']!,
            'deterministic-credential-file':
                first.options['deterministic-credential-file']!,
            'deterministic-state-home':
                first.options['deterministic-state-home']!,
            'session-cycle-index': '1',
          },
          runnerSeedBytes: first.runnerSeed,
          reconcileExactOrder: reconcileAuthorizedExactOrder,
          requestSender: (request) async {
            recoveryRequests.add(request);
            if (request.method == 'DELETE') {
              throw StateError('recovery attempted a second cancellation');
            }
            if (request.uri.path == '/openApi/swap/v2/trade/order' &&
                request.method == 'GET') {
              return BingxHttpResponse(
                statusCode: 200,
                body: jsonEncode(<String, dynamic>{
                  'code': 0,
                  'msg': 'success',
                  'data': <String, dynamic>{
                    'order': <String, dynamic>{
                      'orderId': 'accepted-order',
                      'clientOrderId': clientOrderId,
                      'symbol': 'BTC-USDT',
                      'side': 'BUY',
                      'positionSide': 'LONG',
                      'type': 'TRIGGER_LIMIT',
                      'status': 'CANCELED',
                      'price': '100.5',
                      'stopPrice': '101',
                      'origQty': '0.01',
                      'executedQty': '0',
                      'time': 1,
                    },
                  },
                }),
              );
            }
            return _providerResponse(request);
          },
          nowUtc: () => first.now.add(const Duration(minutes: 1)),
        ),
      );

      expect(placed['state'], 'succeeded');
      expect(unresolved['state'], 'unresolved');
      expect(recovered['state'], 'succeeded');
      expect(recovered['operation_id'], unresolved['operation_id']);
      expect(deletes, 1);
      expect(
        recoveryRequests.where((request) => request.method == 'DELETE'),
        isEmpty,
      );
      expect(
        recoveryRequests.where((request) => request.method == 'GET'),
        hasLength(1),
      );
    },
  );

  test('unavailable open orders blocks the session before POST', () async {
    final fixture = await _fixture(sessionCycleIndex: 0, testOrder: false);
    addTearDown(fixture.dispose);
    var posts = 0;
    Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
      if (request.method == 'POST') posts += 1;
      if (request.uri.path == '/openApi/swap/v2/trade/openOrders') {
        return const BingxHttpResponse(
          statusCode: 503,
          body: '{"code":503,"msg":"temporarily unavailable"}',
        );
      }
      return _providerResponse(request);
    }

    final result = jsonDecode(
      await runOneDeterministicOrder(
        options: fixture.options,
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
      ),
    );

    expect(result['state'], 'blocked');
    expect(result['reason_code'], 'open_orders_unavailable');
    expect(posts, 0);
  });

  test(
    'legacy v5 session remains verifiable but cannot create a new effect',
    () async {
      final fixture = await _fixture(
        sessionCycleIndex: 0,
        testOrder: false,
        legacySession: true,
      );
      addTearDown(fixture.dispose);
      var requests = 0;

      final result = jsonDecode(
        await runOneDeterministicOrder(
          options: fixture.options,
          runnerSeedBytes: fixture.runnerSeed,
          executeExactOrder: runAuthorizedExactOrder,
          requestSender: (request) async {
            requests += 1;
            return _providerResponse(request);
          },
          nowUtc: () => fixture.now,
        ),
      );

      expect(result['state'], 'blocked');
      expect(result['reason_code'], 'session_contract_upgrade_required');
      expect(requests, 0);
    },
  );

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

  test('one liquidity event cannot execute in two session cycles', () async {
    final fixture = await _fixture(sessionCycleIndex: 0, testOrder: false);
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
      ),
    );
    final second = jsonDecode(
      await runOneDeterministicOrder(
        options: <String, String>{
          ...fixture.options,
          'session-cycle-index': '1',
        },
        runnerSeedBytes: fixture.runnerSeed,
        executeExactOrder: runAuthorizedExactOrder,
        requestSender: sender,
        nowUtc: () => fixture.now,
      ),
    );

    expect(first['state'], 'succeeded');
    expect(second['state'], 'blocked');
    expect(second['reason_code'], 'liquidity_event_already_claimed');
    expect(second['operation_id'], isNot(first['operation_id']));
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
  BingxFuturesCandle candle(
    String timeframe,
    DateTime closeAt,
    int minutes,
    num open,
    num high,
    num low,
    num close,
  ) => BingxFuturesCandle(
    timeframe: timeframe,
    openTimeUtc: closeAt.subtract(Duration(minutes: minutes)).toIso8601String(),
    closeTimeUtc: closeAt.toIso8601String(),
    openDecimal: '$open',
    highDecimal: '$high',
    lowDecimal: '$low',
    closeDecimal: '$close',
    volumeBaseDecimal: '100',
    volumeQuoteDecimal: '10000',
    isClosed: true,
  );
  final observedAt = DateTime.utc(2026, 8, 22, 12, confirmed ? 5 : 0);
  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.01',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '10',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '100',
      markPriceDecimal: '100',
      indexPriceDecimal: '100',
    ),
    candles: [
      for (var index = 0; index < (confirmed ? 34 : 33); index++)
        candle(
          '5m',
          start.add(Duration(minutes: (index + 1) * 5)),
          5,
          index == 33 ? 96 : 101,
          102,
          index == 32
              ? 95
              : index == 33
              ? 96
              : [8, 16, 24].contains(index)
              ? 98
              : 100,
          index == 32
              ? 96
              : index == 33
              ? 100
              : 101,
        ),
      for (var index = 0; index < 220; index++)
        candle(
          '15m',
          start.subtract(Duration(minutes: (220 - index) * 15)),
          15,
          100,
          102,
          98,
          100,
        ),
      for (var index = 0; index < 24; index++)
        candle(
          '1h',
          start.subtract(Duration(hours: 24 - index)),
          60,
          100,
          104,
          96,
          100,
        ),
      for (var index = 0; index < 7; index++)
        candle(
          '4h',
          start.subtract(Duration(hours: (7 - index) * 4)),
          240,
          100,
          index == 3 ? 112 : 105,
          98,
          100,
        ),
      candle('1m', start, 1, 100, 102, 98, 100),
      candle('1d', DateTime.utc(2026, 8, 22), 1440, 100, 112, 98, 100),
      candle('1w', DateTime.utc(2026, 8, 17), 10080, 100, 112, 98, 100),
    ],
    trades: [
      BingxFuturesTrade(
        tradeId: 'observed-buy',
        timestampUtc: observedAt.toIso8601String(),
        side: 'buy',
        priceDecimal: '100',
        quantityDecimal: '1',
      ),
    ],
    openInterest: [
      BingxFuturesOpenInterestPoint(
        timestampUtc: observedAt.toIso8601String(),
        openInterestDecimal: '1000',
      ),
    ],
    funding: BingxFuturesFundingSnapshot(
      timestampUtc: observedAt.toIso8601String(),
      fundingRateDecimal: '0',
      nextFundingAtUtc: DateTime.utc(2026, 8, 22, 16).toIso8601String(),
    ),
    liquidityLevels: const [
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'buyside',
        timeframe: '4h',
        priceDecimal: '112',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'sellside',
        timeframe: '5m',
        priceDecimal: '98',
      ),
    ],
    sessionVolumes: [
      for (final session in ['asia', 'london', 'newyork'])
        BingxFuturesSessionVolumePoint(
          session: session,
          bucketStartUtc: DateTime.utc(2026, 8, 22).toIso8601String(),
          volumeDecimal: '100',
          deltaDecimal: '10',
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
    '/openApi/swap/v2/trade/openOrders' =>
      '{"code":0,"msg":"ok","data":{"orders":[]}}',
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
  bool legacySession = false,
  int maxEffects = 1,
  BingxFuturesReplayRunResult? publicRun,
  DateTime? evidenceAtUtc,
  int evidenceSequence = 1,
  String previousEvidenceHash = _zeroHash,
  String? liquidityEventId,
}) async {
  if (legacySession && sessionCycleIndex == null) {
    throw ArgumentError('legacySession requires a deterministic session');
  }
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
    maxEffects: maxEffects,
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
      'account_read_scope':
          sessionCycleIndex == null
              ? BingxFuturesRemoteMandateAdmission.legacyExposureReadScope
              : BingxFuturesRemoteMandateAdmission.exposureReadScope,
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
  late BingxFuturesRemoteMandateAdmission admission;
  if (legacySession) {
    final wire = unsignedAdmission.toJson();
    wire['contract_version'] =
        BingxFuturesRemoteMandateAdmission
            .legacyDeterministicSessionContractVersion;
    (wire['strategy_policy']! as Map<String, dynamic>)['account_read_scope'] =
        BingxFuturesRemoteMandateAdmission.legacyExposureReadScope;
    final semantic = <String, dynamic>{
      'contract_version': wire['contract_version'],
      'runner_key_id': wire['runner_key_id'],
      'operation_kind': wire['operation_kind'],
      'strategy_policy': wire['strategy_policy'],
      'session_policy': wire['session_policy'],
      'max_uses': wire['max_uses'],
      'mandate': wire['mandate'],
    };
    final commitment =
        sha256
            .convert(
              utf8.encode(
                'hivra:bingx-futures-remote-mandate-admission:v5\n'
                '${jsonEncode(semantic)}',
              ),
            )
            .toString();
    final signature = await Ed25519().sign(
      _decodeHex(commitment),
      keyPair: capsuleKeyPair,
    );
    wire['operation_id'] = commitment;
    wire['commitment_hash_hex'] = commitment;
    wire['signature_hex'] = _hex(signature.bytes);
    admission =
        await BingxFuturesRemoteMandateAdmission.parseAndVerifyAsync(
          untrustedWireBytes: utf8.encode(jsonEncode(wire)),
          verifySignature:
              ({
                required messageHashHex,
                required participantIdHex,
                required signatureHex,
              }) async => Ed25519().verify(
                _decodeHex(messageHashHex),
                signature: Signature(
                  _decodeHex(signatureHex),
                  publicKey: SimplePublicKey(
                    _decodeHex(participantIdHex),
                    type: KeyPairType.ed25519,
                  ),
                ),
              ),
        ) ??
        (throw StateError('legacy session fixture did not verify'));
  } else {
    final admissionSignature = await Ed25519().sign(
      _decodeHex(unsignedAdmission.commitmentHashHex),
      keyPair: capsuleKeyPair,
    );
    admission = issue((_) => _hex(admissionSignature.bytes));
  }
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
      'liquidity_event_id': liquidityEventId ?? '4' * 64,
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
    publicRun:
        publicRun ??
        BingxFuturesReplayRunResult(
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
        (evidenceAtUtc ?? now)
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
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
