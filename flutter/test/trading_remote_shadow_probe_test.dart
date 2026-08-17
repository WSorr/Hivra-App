import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
