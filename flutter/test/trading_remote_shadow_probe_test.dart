import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';

import '../tool/trading_remote_shadow_probe.dart';

void main() {
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
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"data":{}}',
          );
        },
      );

      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(requests.map((request) => request.body), everyElement(isEmpty));
      expect(requests.map((request) => request.uri.path), <String>[
        '/openApi/swap/v2/user/balance',
        '/openApi/swap/v2/user/positions',
        '/openApi/swap/v2/trade/openOrders',
      ]);
      final decoded = jsonDecode(evidence) as Map<String, dynamic>;
      expect(decoded.keys, <String>[
        'contract_version',
        'mandate_operation_id',
        'runner_key_id',
        'account_binding_hash_hex',
        'observed_at_utc',
        'checks',
        'effect',
      ]);
      expect(decoded['contract_version'], accountReadEvidenceVersion);
      expect(decoded['mandate_operation_id'], fixture.operationId);
      expect(decoded['runner_key_id'], fixture.runnerKeyId);
      expect(decoded['account_binding_hash_hex'], fixture.accountBindingHash);
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
      ..['mandate-expires-at-utc'] =
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
}

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
      'mandate-operation-id': operationId,
      'mandate-expires-at-utc':
          nowUtc.add(const Duration(hours: 1)).toIso8601String(),
    },
    dispose: () => directory.delete(recursive: true),
  );
}
