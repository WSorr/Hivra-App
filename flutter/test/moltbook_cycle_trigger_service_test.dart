import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/services/moltbook_cycle_trigger_service.dart';

void main() {
  test('on-demand runs every requested cycle', () async {
    final service = MoltbookCycleTriggerService();
    var runs = 0;

    await service.runOnDemand(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    await service.runOnDemand(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );

    expect(runs, 2);
    expect(service.snapshot(_scopeA)?.phase, MoltbookCycleTriggerPhase.idle);
  });

  test('session starts once for one Capsule account scope', () async {
    final service = MoltbookCycleTriggerService();
    var runs = 0;

    final first = await service.startSession(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    final duplicate = await service.startSession(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    final otherScope = await service.startSession(
      scope: _scopeB,
      runCycle: () async => _summary(++runs),
    );

    expect(first, isNotNull);
    expect(duplicate, isNull);
    expect(otherScope, isNotNull);
    expect(runs, 2);
  });

  test('explicit stop allows one new session cycle for the scope', () async {
    final service = MoltbookCycleTriggerService();
    var runs = 0;

    await service.startSession(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    service.stopAll();
    final resumed = await service.startSession(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    final duplicate = await service.startSession(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );

    expect(resumed, isNotNull);
    expect(duplicate, isNull);
    expect(runs, 2);
  });

  test('failed session wake can resume after its dependency unlocks', () async {
    final service = MoltbookCycleTriggerService();
    var unlocked = false;
    var runs = 0;

    Future<MoltbookCycleSummary> runner() async {
      runs++;
      if (!unlocked) throw StateError('AI session locked');
      return _summary(runs);
    }

    await expectLater(
      service.startSession(scope: _scopeA, runCycle: runner),
      throwsStateError,
    );
    unlocked = true;
    final resumed = await service.startSession(
      scope: _scopeA,
      runCycle: runner,
    );
    final duplicate = await service.startSession(
      scope: _scopeA,
      runCycle: runner,
    );

    expect(resumed, isNotNull);
    expect(duplicate, isNull);
    expect(runs, 2);
  });

  test('duplicate continuous start shares one sequential driver', () async {
    final delays = <Completer<void>>[];
    final firstCycleGate = Completer<void>();
    var runs = 0;
    final service = MoltbookCycleTriggerService(
      continuousInterval: const Duration(minutes: 1),
      delay: (_) {
        final delay = Completer<void>();
        delays.add(delay);
        return delay.future;
      },
    );

    Future<MoltbookCycleSummary> runner() async {
      runs++;
      if (runs == 1) await firstCycleGate.future;
      return _summary(runs);
    }

    final first = service.startContinuous(scope: _scopeA, runCycle: runner);
    final duplicate = service.startContinuous(scope: _scopeA, runCycle: runner);
    await _pumpUntil(() => runs == 1);
    expect(identical(first, duplicate), isTrue);

    firstCycleGate.complete();
    await first;
    await _pumpUntil(() => delays.length == 1);
    delays.single.complete();
    await _pumpUntil(() => runs == 2);
    expect(runs, 2);

    service.stopAll();
  });

  test('stop while waiting prevents the next continuous wake', () async {
    final delay = Completer<void>();
    var runs = 0;
    final service = MoltbookCycleTriggerService(
      continuousInterval: const Duration(minutes: 1),
      delay: (_) => delay.future,
    );

    await service.startContinuous(
      scope: _scopeA,
      runCycle: () async => _summary(++runs),
    );
    await _pumpUntil(
      () =>
          service.snapshot(_scopeA)?.phase == MoltbookCycleTriggerPhase.waiting,
    );
    service.stopAll();
    delay.complete();
    await Future<void>.delayed(Duration.zero);

    expect(runs, 1);
    expect(service.snapshot(_scopeA)?.phase, MoltbookCycleTriggerPhase.stopped);
  });

  test(
    'stop keeps a late on-demand result from overwriting stopped state',
    () async {
      final cycle = Completer<MoltbookCycleSummary>();
      final service = MoltbookCycleTriggerService();

      final result = service.runOnDemand(
        scope: _scopeA,
        runCycle: () => cycle.future,
      );
      await _pumpUntil(
        () =>
            service.snapshot(_scopeA)?.phase ==
            MoltbookCycleTriggerPhase.running,
      );
      service.stopAll();
      cycle.complete(_summary(1));
      await result;

      expect(
        service.snapshot(_scopeA)?.phase,
        MoltbookCycleTriggerPhase.stopped,
      );
    },
  );

  test(
    'continuous failure stops its driver without scheduling retry',
    () async {
      var delays = 0;
      final service = MoltbookCycleTriggerService(
        continuousInterval: const Duration(minutes: 1),
        delay: (_) async => delays++,
      );

      await expectLater(
        service.startContinuous(
          scope: _scopeA,
          runCycle: () async => throw StateError('Capsule changed'),
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);

      expect(delays, 0);
      expect(
        service.snapshot(_scopeA)?.phase,
        MoltbookCycleTriggerPhase.failed,
      );
    },
  );

  test('late stopped cycle cannot overwrite a restarted driver', () async {
    final cycleGates = <Completer<MoltbookCycleSummary>>[];
    final delays = <Completer<void>>[];
    final service = MoltbookCycleTriggerService(
      continuousInterval: const Duration(minutes: 1),
      delay: (_) {
        final delay = Completer<void>();
        delays.add(delay);
        return delay.future;
      },
    );

    Future<MoltbookCycleSummary> runner() {
      final gate = Completer<MoltbookCycleSummary>();
      cycleGates.add(gate);
      return gate.future;
    }

    service.startContinuous(scope: _scopeA, runCycle: runner);
    await _pumpUntil(() => cycleGates.length == 1);
    service.stopAll();
    service.startContinuous(scope: _scopeA, runCycle: runner);
    await _pumpUntil(() => cycleGates.length == 2);

    cycleGates.first.complete(_summary(1));
    await Future<void>.delayed(Duration.zero);
    expect(service.snapshot(_scopeA)?.phase, MoltbookCycleTriggerPhase.running);

    cycleGates.last.complete(_summary(2));
    await _pumpUntil(() => delays.length == 1);
    expect(service.snapshot(_scopeA)?.phase, MoltbookCycleTriggerPhase.waiting);
    service.stopAll();
  });
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for asynchronous trigger state');
}

MoltbookCycleSummary _summary(int sequence) => MoltbookCycleSummary(
  ownerCapsuleHex:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  accountBindingId: 'agent-a',
  startedAtUtc: '2026-08-01T00:00:00.000Z',
  completedAtUtc: '2026-08-01T00:00:01.000Z',
  inspectedCount: sequence,
  candidateCount: 0,
  reconciledCount: 0,
  challengedCount: 0,
  blockedCount: 0,
  heartbeatPlan: const MoltbookHeartbeatPlan(
    observedAtUtc: '2026-08-01T00:00:00.000Z',
    priority: 'idle',
    reason: 'No candidates',
    candidatePostIds: <String>[],
    publishAllowed: false,
    humanReviewRequired: true,
    safetyFlags: <String>['no_external_effect'],
    planHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    canonicalPlanJson: '{}',
  ),
  checkpoint: const MoltbookFeedCheckpoint.empty(),
);

const String _scopeA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa::'
    'hivra.contract.moltbook-ambassador.v1::agent-a';
const String _scopeB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb::'
    'hivra.contract.moltbook-ambassador.v1::agent-b';
