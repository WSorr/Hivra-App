import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/services/bingx_futures_public_session_accumulator.dart';
import 'package:hivra_app/services/bingx_futures_public_session_stream_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';

import '../tool/trading_remote_shadow_probe.dart';
import '../tool/trading_remote_exact_order.dart';

void main() {
  test(
    'public stream consumes heartbeat, acknowledgement, and trade',
    () async {
      var nowUtc = DateTime.utc(2026, 8, 20, 8, 1);
      final accumulator = BingxFuturesPublicSessionAccumulator(
        symbol: 'BTC-USDT',
        clockUtc: () => nowUtc,
      );
      accumulator.beginConnection();
      final frames = StreamController<Object>();
      final sent = <Object>[];
      final consumption = consumeBingxPublicTradeFrames(
        frames: frames.stream,
        send: sent.add,
        accumulator: accumulator,
        subscriptionId: 'subscription-1',
      );

      frames.add(gzip.encode(utf8.encode('Ping')));
      frames.add(
        gzip.encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'id': 'subscription-1',
              'code': 0,
              'msg': '',
              'dataType': '',
              'data': null,
            }),
          ),
        ),
      );
      frames.add(
        gzip.encode(
          utf8.encode(
            jsonEncode(<String, Object>{
              'dataType': 'BTC-USDT@trade',
              'data': <Object>[
                <String, Object>{
                  'T': nowUtc.millisecondsSinceEpoch,
                  's': 'BTC-USDT',
                  'p': '100',
                  'q': '2',
                  'm': false,
                },
              ],
            }),
          ),
        ),
      );
      await frames.close();
      await consumption;

      expect(sent, <Object>['Pong']);
      expect(
        accumulator.snapshot().singleWhere((item) => item.session == 'london'),
        isA<dynamic>()
            .having((item) => item.volumeDecimal, 'volume', '200.00000000')
            .having((item) => item.coverageComplete, 'coverage', isFalse),
      );
      expect(accumulator.isConnected, isFalse);
    },
  );

  test('public stream parse failure disconnects and fails closed', () async {
    final accumulator = BingxFuturesPublicSessionAccumulator(
      symbol: 'BTC-USDT',
    );
    accumulator.beginConnection();
    final frames = StreamController<Object>();
    final consumption = consumeBingxPublicTradeFrames(
      frames: frames.stream,
      send: (_) {},
      accumulator: accumulator,
      subscriptionId: 'subscription-1',
    );

    frames.add('malformed');
    await expectLater(consumption, throwsFormatException);
    expect(accumulator.isConnected, isFalse);
    await frames.close();
  });

  test('public frame decoder enforces compressed and expanded bounds', () {
    expect(decodeBingxPublicFrame(gzip.encode(utf8.encode('Ping'))), 'Ping');
    expect(
      () => decodeBingxPublicFrame(
        gzip.encode(
          List<int>.filled(
            BingxFuturesPublicSessionAccumulator.maxDecodedMessageBytes + 1,
            65,
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeBingxPublicFrame(
        List<int>.filled(bingxPublicSessionMaxCompressedFrameBytes + 1, 0),
      ),
      throwsFormatException,
    );
  });

  test(
    'bounded scheduler runs serial cycles with delays between successes',
    () async {
      final cycles = <int>[];
      final delays = <Duration>[];
      var activeCycles = 0;
      var maximumActiveCycles = 0;

      await runBoundedShadowSchedule(
        runCount: 3,
        interval: const Duration(seconds: 60),
        runOnce: (cycleNumber) async {
          activeCycles++;
          maximumActiveCycles =
              activeCycles > maximumActiveCycles
                  ? activeCycles
                  : maximumActiveCycles;
          await Future<void>.delayed(Duration.zero);
          cycles.add(cycleNumber);
          activeCycles--;
        },
        delay: (duration) async {
          delays.add(duration);
        },
      );

      expect(cycles, <int>[1, 2, 3]);
      expect(maximumActiveCycles, 1);
      expect(delays, <Duration>[
        const Duration(seconds: 60),
        const Duration(seconds: 60),
      ]);
    },
  );

  test('bounded scheduler stops when the cadence delay fails', () async {
    final cycles = <int>[];

    await expectLater(
      runBoundedShadowSchedule(
        runCount: 3,
        interval: const Duration(seconds: 60),
        runOnce: (cycleNumber) async {
          cycles.add(cycleNumber);
        },
        delay: (_) async {
          throw StateError('delay failed');
        },
      ),
      throwsStateError,
    );

    expect(cycles, <int>[1]);
  });

  test(
    'bounded scheduler stops on first failed observation without retry',
    () async {
      final cycles = <int>[];
      final delays = <Duration>[];

      await expectLater(
        runBoundedShadowSchedule(
          runCount: 3,
          interval: const Duration(seconds: 60),
          runOnce: (cycleNumber) async {
            cycles.add(cycleNumber);
            if (cycleNumber == 2) throw StateError('observation failed');
          },
          delay: (duration) async {
            delays.add(duration);
          },
        ),
        throwsStateError,
      );

      expect(cycles, <int>[1, 2]);
      expect(delays, <Duration>[const Duration(seconds: 60)]);
    },
  );

  test('bounded scheduler rejects unbounded or ambiguous cadence', () async {
    Future<void> expectRejected(int runCount, Duration? interval) =>
        expectLater(
          runBoundedShadowSchedule(
            runCount: runCount,
            interval: interval,
            runOnce: (_) async {},
            delay: (_) async {},
          ),
          throwsFormatException,
        );

    await expectRejected(0, null);
    await expectRejected(maxScheduledRuns + 1, const Duration(seconds: 60));
    await expectRejected(1, const Duration(seconds: 60));
    await expectRejected(2, null);
    await expectRejected(2, const Duration(seconds: 59));
    await expectRejected(2, const Duration(seconds: 3601));
    await expectRejected(2, const Duration(milliseconds: 60001));
  });

  test(
    'runner seed file is strict and mutually exclusive with environment',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hivra-runner-seed-test.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final seed = List<String>.filled(32, '01').join();
      final seedFile = File('${directory.path}/runner-seed');
      await seedFile.writeAsString(seed, flush: true);
      expect(
        (await Process.run('chmod', <String>['600', seedFile.path])).exitCode,
        0,
      );

      expect(
        await readRunnerSeedBytes(<String, String>{
          'runner-seed-file': seedFile.path,
        }, environment: const <String, String>{}),
        List<int>.filled(32, 1),
      );
      expect(
        await readRunnerSeedBytes(
          const <String, String>{},
          environment: <String, String>{'HIVRA_SHADOW_RUNNER_SEED_HEX': seed},
        ),
        List<int>.filled(32, 1),
      );
      await expectLater(
        readRunnerSeedBytes(
          <String, String>{'runner-seed-file': seedFile.path},
          environment: <String, String>{'HIVRA_SHADOW_RUNNER_SEED_HEX': seed},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'runner seed file rejects relative, linked, and permissive files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hivra-runner-seed-adverse.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final seedFile = File('${directory.path}/runner-seed');
      await seedFile.writeAsString(List<String>.filled(32, '02').join());
      expect(
        (await Process.run('chmod', <String>['644', seedFile.path])).exitCode,
        0,
      );

      await expectLater(
        readRunnerSeedBytes(const <String, String>{
          'runner-seed-file': 'relative-seed',
        }, environment: const <String, String>{}),
        throwsFormatException,
      );
      await expectLater(
        readRunnerSeedBytes(<String, String>{
          'runner-seed-file': seedFile.path,
        }, environment: const <String, String>{}),
        throwsFormatException,
      );

      expect(
        (await Process.run('chmod', <String>['600', seedFile.path])).exitCode,
        0,
      );
      final link = Link('${directory.path}/runner-seed-link');
      await link.create(seedFile.path);
      await expectLater(
        readRunnerSeedBytes(<String, String>{
          'runner-seed-file': link.path,
        }, environment: const <String, String>{}),
        throwsFormatException,
      );
    },
  );

  test('runner seed permissions recognize only protected systemd delivery', () {
    expect(runnerSeedFilePermissionsAreSafe('/tmp/runner-seed', 0x180), isTrue);
    expect(
      runnerSeedFilePermissionsAreSafe('/tmp/runner-seed', 0x1a0),
      isFalse,
    );
    expect(
      runnerSeedFilePermissionsAreSafe(
        '/run/credentials/hivra-shadow.service/runner-seed',
        0x120,
      ),
      isTrue,
    );
    expect(
      runnerSeedFilePermissionsAreSafe(
        '/run/credentials/hivra-shadow.service/runner-seed',
        0x124,
      ),
      isFalse,
    );
    expect(
      runnerSeedFilePermissionsAreSafe('/tmp/runner-seed', 0x120),
      isFalse,
    );
  });

  test(
    'account read performs only three signed GETs and emits redacted evidence',
    () async {
      final fixture = await _accountReadFixture();
      addTearDown(fixture.dispose);
      final requests = <BingxHttpRequest>[];

      final evidence = await runMandateBoundAccountRead(
        options: fixture.options,
        runnerSeedBytes: fixture.seedBytes,
        nowUtc: () => fixture.nowUtc,
        clockMs: () => 1770000000000,
        requestSender: (request) async {
          requests.add(request);
          final body = switch (request.uri.path) {
            '/openApi/swap/v3/user/balance' =>
              '{"code":0,"data":[{"asset":"USDT","equity":"17"}]}',
            '/openApi/swap/v2/user/positions' => '{"code":0,"data":[]}',
            '/openApi/swap/v2/trade/openOrders' =>
              '{"code":0,"data":{"orders":[]}}',
            _ => throw StateError('unexpected account-read endpoint'),
          };
          return BingxHttpResponse(statusCode: 200, body: body);
        },
      );

      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(requests.map((request) => request.body), everyElement(isEmpty));
      expect(requests.map((request) => request.uri.path), <String>[
        '/openApi/swap/v3/user/balance',
        '/openApi/swap/v2/user/positions',
        '/openApi/swap/v2/trade/openOrders',
      ]);
      final decoded = jsonDecode(evidence) as Map<String, dynamic>;
      expect(decoded.keys, <String>[
        'contract_version',
        'account_read_operation_id',
        'runner_key_id',
        'account_binding_hash_hex',
        'read_scope',
        'max_uses',
        'observed_at_utc',
        'checks',
        'effect',
      ]);
      expect(decoded['contract_version'], accountReadEvidenceVersion);
      expect(decoded['account_read_operation_id'], fixture.operationId);
      expect(decoded['runner_key_id'], fixture.runnerKeyId);
      expect(decoded['account_binding_hash_hex'], fixture.accountBindingHash);
      expect(decoded['read_scope'], accountReadScope);
      expect(decoded['max_uses'], accountReadMaxUses);
      expect(decoded['observed_at_utc'], fixture.nowUtc.toIso8601String());
      expect(decoded['checks'], <Map<String, dynamic>>[
        <String, dynamic>{'name': 'balance', 'success': true},
        <String, dynamic>{'name': 'positions', 'success': true},
        <String, dynamic>{'name': 'open_orders', 'success': true},
      ]);
      expect(decoded['effect'], isFalse);
      expect(evidence, isNot(contains(fixture.apiKey)));
      expect(evidence, isNot(contains(fixture.apiSecret)));
      expect(evidence, isNot(contains('accountEquity')));
      expect(evidence, isNot(contains('quantityDecimal')));
      expect(evidence, isNot(contains('orderId')));
    },
  );

  test('account read rejects wrong binding before provider access', () async {
    final fixture = await _accountReadFixture();
    addTearDown(fixture.dispose);
    var requests = 0;
    final options = Map<String, String>.from(fixture.options)
      ..['expected-account-binding-hash'] = List<String>.filled(64, '0').join();

    await expectLater(
      runMandateBoundAccountRead(
        options: options,
        runnerSeedBytes: fixture.seedBytes,
        nowUtc: () => fixture.nowUtc,
        requestSender: (_) async {
          requests++;
          return const BingxHttpResponse(statusCode: 200, body: '{}');
        },
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });

  test('account read rejects expired mandate before provider access', () async {
    final fixture = await _accountReadFixture();
    addTearDown(fixture.dispose);
    var requests = 0;
    final options = Map<String, String>.from(fixture.options)
      ..['account-read-expires-at-utc'] =
          fixture.nowUtc.subtract(const Duration(seconds: 1)).toIso8601String();

    await expectLater(
      runMandateBoundAccountRead(
        options: options,
        runnerSeedBytes: fixture.seedBytes,
        nowUtc: () => fixture.nowUtc,
        requestSender: (_) async {
          requests++;
          return const BingxHttpResponse(statusCode: 200, body: '{}');
        },
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });

  test(
    'account read does not surface provider-controlled failure body',
    () async {
      final fixture = await _accountReadFixture();
      addTearDown(fixture.dispose);
      var requests = 0;

      await expectLater(
        runMandateBoundAccountRead(
          options: fixture.options,
          runnerSeedBytes: fixture.seedBytes,
          nowUtc: () => fixture.nowUtc,
          requestSender: (_) async {
            requests++;
            return const BingxHttpResponse(
              statusCode: 403,
              body: '{"code":100001,"msg":"provider-private-payload"}',
            );
          },
        ),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString() == 'Bad state: balance read failed' &&
                !error.toString().contains('provider-private-payload'),
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test('account read rejects mixed public-shadow options', () async {
    final fixture = await _accountReadFixture();
    addTearDown(fixture.dispose);
    final options = Map<String, String>.from(fixture.options)
      ..['symbol'] = 'BTC-USDT';

    await expectLater(
      runMandateBoundAccountRead(
        options: options,
        runnerSeedBytes: fixture.seedBytes,
      ),
      throwsFormatException,
    );
  });

  test('account read rejects widened or reusable authority', () async {
    final fixture = await _accountReadFixture();
    addTearDown(fixture.dispose);
    var requests = 0;
    for (final mutation in <Map<String, String>>[
      <String, String>{'account-read-scope': 'balance,positions,all_orders'},
      <String, String>{'account-read-max-uses': '2'},
    ]) {
      await expectLater(
        runMandateBoundAccountRead(
          options: Map<String, String>.from(fixture.options)..addAll(mutation),
          runnerSeedBytes: fixture.seedBytes,
          requestSender: (_) async {
            requests++;
            return const BingxHttpResponse(statusCode: 200, body: '{}');
          },
        ),
        throwsFormatException,
      );
    }
    expect(requests, 0);
  });

  test('account credential rejects links and permissive files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hivra-account-credential-adverse.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final credential = File('${directory.path}/credential.json');
    await credential.writeAsString(
      '{"contract_version":"bingx-exchange-credential-v1",'
      '"api_key":"key","api_secret":"secret"}',
    );
    expect(
      (await Process.run('chmod', <String>['644', credential.path])).exitCode,
      0,
    );
    await expectLater(
      readExchangeCredentialFile(credential.path),
      throwsFormatException,
    );

    expect(
      (await Process.run('chmod', <String>['600', credential.path])).exitCode,
      0,
    );
    final link = Link('${directory.path}/credential-link.json');
    await link.create(credential.path);
    await expectLater(
      readExchangeCredentialFile(link.path),
      throwsFormatException,
    );
  });

  test('legacy exact authority is inspectable but cannot deliver', () async {
    final fixture = await _exactOrderFixture(testOrder: true);
    addTearDown(fixture.dispose);
    var requests = 0;
    await expectLater(runMandateBoundExactOrder(
      options: fixture.options,
      runnerSeedBytes: fixture.runnerSeedBytes,
      nowUtc: () => fixture.nowUtc,
      requestSender: (_) async {
        requests++;
        throw StateError('unauthorized provider read');
      },
    ), throwsA(isA<FormatException>().having(
      (error) => error.message, 'reason', 'exposure_read_authority_missing')));
    expect(requests, 0);
  });

  test('legacy completed effect remains readable without provider access', () async {
    final fixture = await _exactOrderFixture(testOrder: true);
    addTearDown(fixture.dispose);
    final admission = BingxFuturesRemoteMandateAdmission.parseAndVerify(
      untrustedWireBytes: await File(fixture.options['exact-order-admission-file']!).readAsBytes(),
      verifySignature: ({required messageHashHex, required participantIdHex,
        required signatureHex}) => true,
    )!;
    final credentials = await readExchangeCredentialFile(
      fixture.options['exact-order-credential-file']!);
    final adapter = BingxFuturesExternalEffectAdapter(
      exchange: BingxFuturesExchangeService(requestSender: (_) async =>
        const BingxHttpResponse(statusCode: 200,
          body: '{"code":0,"data":{"order":{"orderID":"retained-test-order"}}}')),
      credentials: credentials,
      accountBindingId: admission.mandate.accountBindingHashHex,
      clock: () => fixture.nowUtc,
    );
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: () => admission.mandate.capsuleRootHex,
      resolveAdapter: (_) => adapter,
      fileStore: CapsuleFileStore(dirs: UserVisibleDataDirectoryService(
        homeOverride: fixture.options['exact-order-state-home']!)),
      clock: () => fixture.nowUtc,
    );
    final operationId = admission.exactOrder!['intent_hash_hex'] as String;
    await effects.prepare(operationId: operationId,
      pluginId: bingxFuturesTradingPluginId,
      providerId: BingxFuturesExternalEffectAdapter.providerId,
      accountBindingId: admission.mandate.accountBindingHashHex,
      effectKind: BingxFuturesExternalEffectAdapter.exactOrderEffectKind,
      canonicalPayloadJson: jsonEncode(admission.exactOrder));
    await effects.approve(pluginId: bingxFuturesTradingPluginId,
      operationId: operationId, approvalEvidenceHashHex: admission.commitmentHashHex);
    await effects.enqueue(pluginId: bingxFuturesTradingPluginId, operationId: operationId);
    final retained = await effects.process(pluginId: bingxFuturesTradingPluginId,
      operationId: operationId);
    var requests = 0;
    final replay = jsonDecode(await runMandateBoundExactOrder(
      options: fixture.options, runnerSeedBytes: fixture.runnerSeedBytes,
      nowUtc: () => fixture.nowUtc,
      requestSender: (_) async {
        requests++;
        throw StateError('completed effect must not query provider');
      },
    ));
    expect(replay['state'], 'succeeded');
    expect(replay['receipt_evidence_hash_hex'], retained.receipt!.evidenceHashHex);
    expect(replay['attempt_count'], 1);
    expect(requests, 0);
  });

  test('one deterministic authority cannot execute a second candidate', () async {
    final fixture = await _exactOrderFixture(testOrder: true);
    addTearDown(fixture.dispose);
    final exactAdmission =
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
          untrustedWireBytes:
              await File(
                fixture.options['exact-order-admission-file']!,
              ).readAsBytes(),
          verifySignature:
              ({
                required messageHashHex,
                required participantIdHex,
                required signatureHex,
              }) => true,
        )!;
    final deterministic =
        BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
          mandate: exactAdmission.mandate,
          runnerKeyId: exactAdmission.runnerKeyId,
          strategyPolicy: <String, dynamic>{
            'runner_build_id': 'runner-build',
            'plugin_id': 'hivra.bingx-futures-trading',
            'plugin_version': '0.2.7-plugins',
            'package_digest_hex': 'a' * 64,
            'host_abi': 'dart-headless-v1',
            'stop_loss_percent': 5,
            'minimum_risk_reward': 2,
            'account_read_scope': BingxFuturesRemoteMandateAdmission.exposureReadScope,
          },
          signCommitment: (_) => '8' * 128,
        )!;
    final credentials = await readExchangeCredentialFile(
      fixture.options['exact-order-credential-file']!,
    );
    final requests = <BingxHttpRequest>[];
    Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
      requests.add(request);
      if (request.method == 'GET') {
        final body = switch (request.uri.path) {
          '/openApi/swap/v3/user/balance' => '{"code":0,"data":[{"asset":"USDT","equity":"1000","availableMargin":"1000"}]}',
          '/openApi/swap/v2/trade/leverage' => '{"code":0,"data":{"longLeverage":2,"shortLeverage":2}}',
          '/openApi/swap/v2/trade/marginType' => '{"code":0,"data":{"marginType":"ISOLATED"}}',
          '/openApi/swap/v2/user/positions' || '/openApi/swap/v2/user/income' => '{"code":0,"data":[]}',
          _ => throw StateError('unexpected read'),
        };
        return BingxHttpResponse(statusCode: 200, body: body);
      }
      return const BingxHttpResponse(
        statusCode: 200,
        body:
            '{"code":0,"msg":"success","data":{"order":{"orderID":"test-order-1"}}}',
      );
    }

    final first = await runAuthorizedExactOrder(
      admission: deterministic,
      exactOrder: exactAdmission.exactOrder!,
      effectOperationId: deterministic.operationId,
      credentials: credentials,
      stateHome: fixture.options['exact-order-state-home']!,
      nowUtc: () => fixture.nowUtc,
      requestSender: sender,
    );
    final secondOrder =
        Map<String, dynamic>.from(exactAdmission.exactOrder!)
          ..['client_order_id'] = 'hivra-order-2'
          ..['intent_hash_hex'] = 'b' * 64;
    await expectLater(
      runAuthorizedExactOrder(
        admission: deterministic,
        exactOrder: secondOrder,
        effectOperationId: deterministic.operationId,
        credentials: credentials,
        stateHome: fixture.options['exact-order-state-home']!,
        nowUtc: () => fixture.nowUtc,
        requestSender: sender,
      ),
      throwsStateError,
    );

    expect(jsonDecode(first)['state'], 'succeeded');
    expect(jsonDecode(first)['operation_id'], deterministic.operationId);
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
  });

  test(
    'exact order rejects mutation and expiry before provider access',
    () async {
      final fixture = await _exactOrderFixture(testOrder: true);
      addTearDown(fixture.dispose);
      final admissionFile = File(
        fixture.options['exact-order-admission-file']!,
      );
      final original = await admissionFile.readAsString();
      final mutated = original.replaceFirst(
        '"quantity_decimal":"0.01"',
        '"quantity_decimal":"0.02"',
      );
      await admissionFile.writeAsString(mutated, flush: true);
      var requests = 0;
      Future<BingxHttpResponse> sender(BingxHttpRequest request) async {
        requests++;
        return const BingxHttpResponse(statusCode: 200, body: '{"code":0}');
      }

      await expectLater(
        runMandateBoundExactOrder(
          options: fixture.options,
          runnerSeedBytes: fixture.runnerSeedBytes,
          nowUtc: () => fixture.nowUtc,
          requestSender: sender,
        ),
        throwsFormatException,
      );
      await admissionFile.writeAsString(original, flush: true);
      await expectLater(
        runMandateBoundExactOrder(
          options: fixture.options,
          runnerSeedBytes: fixture.runnerSeedBytes,
          nowUtc: () => fixture.nowUtc.add(const Duration(hours: 2)),
          requestSender: sender,
        ),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );
}

Future<
  ({
    Directory directory,
    List<int> runnerSeedBytes,
    DateTime nowUtc,
    Map<String, String> options,
    String initialAdmissionOperationId,
    Future<String> Function(DateTime expiresAtUtc) replaceAdmission,
    Future<void> Function() dispose,
  })
>
_exactOrderFixture({required bool testOrder}) async {
  final directory = await Directory.systemTemp.createTemp(
    'hivra-exact-order-fixture.',
  );
  final runnerSeedBytes = List<int>.generate(32, (index) => index + 11);
  final runnerPublicKey =
      await (await Ed25519().newKeyPairFromSeed(
        runnerSeedBytes,
      )).extractPublicKey();
  final runnerKeyId = sha256.convert(runnerPublicKey.bytes).toString();
  final capsuleSeedBytes = List<int>.generate(32, (index) => 255 - index);
  final capsuleKeyPair = await Ed25519().newKeyPairFromSeed(capsuleSeedBytes);
  final capsulePublicKey = await capsuleKeyPair.extractPublicKey();
  final capsuleRootHex = _testHex(capsulePublicKey.bytes);
  const apiKey = 'exact-order-api-key';
  const apiSecret = 'exact-order-api-secret';
  final accountBinding = sha256.convert(utf8.encode(apiKey)).toString();
  final nowUtc = DateTime.utc(2026, 8, 19, 12);
  final exactOrder = <String, dynamic>{
    'client_order_id': 'hivra-order-1',
    'symbol': 'BTC-USDT',
    'side': 'buy',
    'order_type': 'limit',
    'quantity_decimal': '0.01',
    'limit_price_decimal': '100',
    'time_in_force': 'GTC',
    'entry_mode': 'zone_pending',
    'trigger_price_decimal': '99',
    'stop_loss_decimal': '95',
    'take_profit_decimal': null,
    'intent_hash_hex': List<String>.filled(64, 'a').join(),
    'test_order': testOrder,
  };
  final admissionFile = File('${directory.path}/admission.json');
  Future<String> replaceAdmission(DateTime expiresAtUtc) async {
    final mandate = BingxFuturesTradingMandate.issue(
      capsuleRootHex: capsuleRootHex,
      accountBindingHashHex: accountBinding,
      symbol: 'BTC-USDT',
      testOrder: testOrder,
      issuedAtUtc: nowUtc.subtract(const Duration(minutes: 1)),
      expiresAtUtc: expiresAtUtc,
      maxOrderNotionalQuoteDecimal: '2',
      maxRiskPerTradePercent: 1,
      maxDailyLossPercent: 3,
      maxConcurrentPositions: 1,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 10,
      maxEffects: 1,
    );
    final unsigned =
        BingxFuturesRemoteMandateAdmission.issueExactOrder(
          mandate: mandate,
          runnerKeyId: runnerKeyId,
          exactOrder: exactOrder,
          signCommitment: (_) => List<String>.filled(128, '0').join(),
        )!;
    final signature = await Ed25519().sign(
      _testDecodeHex(unsigned.commitmentHashHex),
      keyPair: capsuleKeyPair,
    );
    final admission =
        BingxFuturesRemoteMandateAdmission.issueExactOrder(
          mandate: mandate,
          runnerKeyId: runnerKeyId,
          exactOrder: exactOrder,
          signCommitment: (_) => _testHex(signature.bytes),
        )!;
    await admissionFile.writeAsString(admission.canonicalJson, flush: true);
    return admission.operationId;
  }

  final initialAdmissionOperationId = await replaceAdmission(
    nowUtc.add(const Duration(hours: 1)),
  );
  final credentialFile = File('${directory.path}/credential.json');
  await credentialFile.writeAsString(
    jsonEncode(<String, String>{
      'contract_version': 'bingx-exchange-credential-v1',
      'api_key': apiKey,
      'api_secret': apiSecret,
    }),
    flush: true,
  );
  expect(
    (await Process.run('chmod', <String>['600', credentialFile.path])).exitCode,
    0,
  );
  return (
    directory: directory,
    runnerSeedBytes: runnerSeedBytes,
    nowUtc: nowUtc,
    initialAdmissionOperationId: initialAdmissionOperationId,
    replaceAdmission: replaceAdmission,
    options: <String, String>{
      'mode': exactOrderMode,
      'runner-seed-file': '${directory.path}/unused-runner-seed',
      'expected-runner-key-id': runnerKeyId,
      'exact-order-admission-file': admissionFile.path,
      'exact-order-credential-file': credentialFile.path,
      'exact-order-state-home': '${directory.path}/state-home',
    },
    dispose: () => directory.delete(recursive: true),
  );
}

String _testHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

List<int> _testDecodeHex(String value) => List<int>.generate(
  value.length ~/ 2,
  (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
);

Future<
  ({
    Directory directory,
    List<int> seedBytes,
    String apiKey,
    String apiSecret,
    String runnerKeyId,
    String accountBindingHash,
    String operationId,
    DateTime nowUtc,
    Map<String, String> options,
    Future<void> Function() dispose,
  })
>
_accountReadFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'hivra-account-read-fixture.',
  );
  final seedBytes = List<int>.generate(32, (index) => index + 1);
  final publicKey =
      await (await Ed25519().newKeyPairFromSeed(seedBytes)).extractPublicKey();
  final runnerKeyId = sha256.convert(publicKey.bytes).toString();
  const apiKey = 'fixture-api-key';
  const apiSecret = 'fixture-api-secret';
  final accountBindingHash = sha256.convert(utf8.encode(apiKey)).toString();
  final credential = File('${directory.path}/bingx-exchange');
  await credential.writeAsString(
    jsonEncode(<String, String>{
      'contract_version': 'bingx-exchange-credential-v1',
      'api_key': apiKey,
      'api_secret': apiSecret,
    }),
    flush: true,
  );
  expect(
    (await Process.run('chmod', <String>['600', credential.path])).exitCode,
    0,
  );
  final nowUtc = DateTime.utc(2026, 8, 18, 18);
  final operationId = List<String>.filled(64, 'a').join();
  return (
    directory: directory,
    seedBytes: seedBytes,
    apiKey: apiKey,
    apiSecret: apiSecret,
    runnerKeyId: runnerKeyId,
    accountBindingHash: accountBindingHash,
    operationId: operationId,
    nowUtc: nowUtc,
    options: <String, String>{
      'mode': accountReadMode,
      'account-read-credential-file': credential.path,
      'expected-runner-key-id': runnerKeyId,
      'expected-account-binding-hash': accountBindingHash,
      'account-read-operation-id': operationId,
      'account-read-scope': accountReadScopeWire,
      'account-read-max-uses': '$accountReadMaxUses',
      'account-read-expires-at-utc':
          nowUtc.add(const Duration(hours: 1)).toIso8601String(),
    },
    dispose: () => directory.delete(recursive: true),
  );
}
