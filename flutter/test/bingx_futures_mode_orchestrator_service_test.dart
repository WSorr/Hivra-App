import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_mode_orchestrator_service.dart';

void main() {
  const capsuleA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const capsuleB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('BingxFuturesModeOrchestratorService', () {
    test('runs situational mode once through the supplied cycle', () async {
      var calls = 0;
      final service = BingxFuturesModeOrchestratorService();

      final result = await service.runSituational(() async {
        calls += 1;
        return 'blocked:no_signal';
      });

      expect(calls, 1);
      expect(result, 'blocked:no_signal');
      expect(service.isRunning(capsuleA), isFalse);
    });

    test('runs interactive cycles serially at one cadence', () async {
      final delays = <Completer<void>>[];
      final observed = <BingxFuturesInteractiveRunnerSnapshot>[];
      var cycles = 0;
      var activeCycles = 0;
      var maximumConcurrentCycles = 0;
      final service = BingxFuturesModeOrchestratorService(
        interactiveInterval: const Duration(minutes: 5),
        delay: (_) {
          final completer = Completer<void>();
          delays.add(completer);
          return completer.future;
        },
        nowUtc: () => DateTime.utc(2026, 9, 8, 12),
      );

      final first = service.startInteractive(
        capsuleScope: capsuleA,
        runCycle: () async {
          activeCycles += 1;
          maximumConcurrentCycles =
              maximumConcurrentCycles < activeCycles
                  ? activeCycles
                  : maximumConcurrentCycles;
          cycles += 1;
          await Future<void>.delayed(Duration.zero);
          activeCycles -= 1;
          return 'blocked:cycle_$cycles';
        },
        onSnapshot: observed.add,
      );

      expect(await first, 'blocked:cycle_1');
      await _drainMicrotasks();
      expect(cycles, 1);
      expect(delays, hasLength(1));
      expect(
        service.snapshot(capsuleA)!.phase,
        BingxFuturesInteractiveRunnerPhase.waiting,
      );
      expect(
        service.snapshot(capsuleA)!.nextCycleAtUtc,
        DateTime.utc(2026, 9, 8, 12, 5),
      );

      delays.removeAt(0).complete();
      await _drainMicrotasks();
      expect(cycles, 2);
      expect(maximumConcurrentCycles, 1);
      expect(service.snapshot(capsuleA)!.completedCycles, 2);
      expect(observed.last.lastOutcome, 'blocked:cycle_2');

      expect(service.stop(capsuleA), isTrue);
      expect(service.isRunning(capsuleA), isFalse);
      expect(
        service.snapshot(capsuleA)!.phase,
        BingxFuturesInteractiveRunnerPhase.stopped,
      );
    });

    test('duplicate start shares one active run', () async {
      final cycle = Completer<String>();
      var calls = 0;
      final service = BingxFuturesModeOrchestratorService();

      final first = service.startInteractive(
        capsuleScope: capsuleA,
        runCycle: () {
          calls += 1;
          return cycle.future;
        },
      );
      final duplicate = service.startInteractive(
        capsuleScope: capsuleA,
        runCycle: () async => 'must_not_run',
      );

      expect(identical(first, duplicate), isTrue);
      expect(calls, 1);
      cycle.complete('blocked:no_signal');
      expect(await first, 'blocked:no_signal');
      expect(await duplicate, 'blocked:no_signal');
      service.stop(capsuleA);
    });

    test('starting another Capsule seals the previous local run', () async {
      final delays = <Completer<void>>[];
      final service = BingxFuturesModeOrchestratorService(
        delay: (_) {
          final completer = Completer<void>();
          delays.add(completer);
          return completer.future;
        },
      );

      expect(
        await service.startInteractive(
          capsuleScope: capsuleA,
          runCycle: () async => 'blocked:a',
        ),
        'blocked:a',
      );
      await _drainMicrotasks();
      expect(service.isRunning(capsuleA), isTrue);

      expect(
        await service.startInteractive(
          capsuleScope: capsuleB,
          runCycle: () async => 'blocked:b',
        ),
        'blocked:b',
      );
      await _drainMicrotasks();

      expect(service.isRunning(capsuleA), isFalse);
      expect(
        service.snapshot(capsuleA)!.phase,
        BingxFuturesInteractiveRunnerPhase.stopped,
      );
      expect(service.isRunning(capsuleB), isTrue);
      service.stop(capsuleB);
      for (final delay in delays) {
        if (!delay.isCompleted) delay.complete();
      }
    });

    test('cycle exception stops fail-closed without another cycle', () async {
      var calls = 0;
      final service = BingxFuturesModeOrchestratorService(delay: (_) async {});

      final first = service.startInteractive(
        capsuleScope: capsuleA,
        runCycle: () async {
          calls += 1;
          throw StateError('authority changed');
        },
      );

      await expectLater(first, throwsStateError);
      await _drainMicrotasks();
      expect(calls, 1);
      expect(service.isRunning(capsuleA), isFalse);
      expect(
        service.snapshot(capsuleA)!.phase,
        BingxFuturesInteractiveRunnerPhase.failed,
      );
      expect(
        service.snapshot(capsuleA)!.lastError,
        contains('authority changed'),
      );
    });

    test('rejects ambiguous Capsule scope and cadence', () {
      expect(
        () => BingxFuturesModeOrchestratorService(
          interactiveInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
      final service = BingxFuturesModeOrchestratorService();
      expect(
        () => service.startInteractive(
          capsuleScope: 'capsule-a',
          runCycle: () async => 'blocked',
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
