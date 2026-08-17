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
}
