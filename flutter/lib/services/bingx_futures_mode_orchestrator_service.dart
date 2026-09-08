import 'dart:async';

enum BingxFuturesInteractiveRunnerPhase { running, waiting, stopped, failed }

class BingxFuturesInteractiveRunnerSnapshot {
  final String capsuleScope;
  final BingxFuturesInteractiveRunnerPhase phase;
  final int completedCycles;
  final String? lastOutcome;
  final DateTime? nextCycleAtUtc;
  final String? lastError;

  const BingxFuturesInteractiveRunnerSnapshot({
    required this.capsuleScope,
    required this.phase,
    required this.completedCycles,
    required this.lastOutcome,
    required this.nextCycleAtUtc,
    required this.lastError,
  });

  bool get isActive =>
      phase == BingxFuturesInteractiveRunnerPhase.running ||
      phase == BingxFuturesInteractiveRunnerPhase.waiting;
}

typedef BingxFuturesInteractiveCycleRunner = Future<String> Function();
typedef BingxFuturesInteractiveCycleDelay =
    Future<void> Function(Duration duration);
typedef BingxFuturesInteractiveRunnerObserver =
    void Function(BingxFuturesInteractiveRunnerSnapshot snapshot);

class BingxFuturesModeOrchestratorService {
  static const Duration defaultInteractiveInterval = Duration(minutes: 5);

  final Duration interactiveInterval;
  final BingxFuturesInteractiveCycleDelay _delay;
  final DateTime Function() _nowUtc;
  final Map<String, _InteractiveRun> _runs = <String, _InteractiveRun>{};
  final Map<String, BingxFuturesInteractiveRunnerSnapshot> _snapshots =
      <String, BingxFuturesInteractiveRunnerSnapshot>{};

  BingxFuturesModeOrchestratorService({
    this.interactiveInterval = defaultInteractiveInterval,
    BingxFuturesInteractiveCycleDelay? delay,
    DateTime Function()? nowUtc,
  }) : _delay = delay ?? Future<void>.delayed,
       _nowUtc = nowUtc ?? DateTime.now {
    if (interactiveInterval <= Duration.zero) {
      throw ArgumentError.value(
        interactiveInterval,
        'interactiveInterval',
        'must be positive',
      );
    }
  }

  BingxFuturesInteractiveRunnerSnapshot? snapshot(String capsuleScope) =>
      _snapshots[capsuleScope];

  bool isRunning(String capsuleScope) => _runs[capsuleScope]?.active == true;

  Future<String> runSituational(BingxFuturesInteractiveCycleRunner runCycle) =>
      runCycle();

  Future<String> startInteractive({
    required String capsuleScope,
    required BingxFuturesInteractiveCycleRunner runCycle,
    BingxFuturesInteractiveRunnerObserver? onSnapshot,
  }) {
    _validateScope(capsuleScope);
    final existing = _runs[capsuleScope];
    if (existing != null && existing.active) return existing.firstCycle.future;
    for (final otherScope in _runs.keys
        .where((scope) => scope != capsuleScope)
        .toList(growable: false)) {
      stop(otherScope);
    }

    final run = _InteractiveRun();
    _runs[capsuleScope] = run;
    unawaited(
      _driveInteractive(
        capsuleScope: capsuleScope,
        run: run,
        runCycle: runCycle,
        onSnapshot: onSnapshot,
      ),
    );
    return run.firstCycle.future;
  }

  bool stop(String capsuleScope) {
    final run = _runs.remove(capsuleScope);
    if (run == null) return false;
    run.active = false;
    final previous = _snapshots[capsuleScope];
    _snapshots[capsuleScope] = BingxFuturesInteractiveRunnerSnapshot(
      capsuleScope: capsuleScope,
      phase: BingxFuturesInteractiveRunnerPhase.stopped,
      completedCycles: previous?.completedCycles ?? 0,
      lastOutcome: previous?.lastOutcome,
      nextCycleAtUtc: null,
      lastError: null,
    );
    if (!run.firstCycle.isCompleted) {
      run.firstCycle.completeError(
        StateError('Interactive trading stopped before its first cycle.'),
      );
    }
    return true;
  }

  void stopAll() {
    for (final scope in _runs.keys.toList(growable: false)) {
      stop(scope);
    }
  }

  Future<void> _driveInteractive({
    required String capsuleScope,
    required _InteractiveRun run,
    required BingxFuturesInteractiveCycleRunner runCycle,
    required BingxFuturesInteractiveRunnerObserver? onSnapshot,
  }) async {
    var completedCycles = 0;
    String? lastOutcome;
    while (run.active && identical(_runs[capsuleScope], run)) {
      _publish(
        BingxFuturesInteractiveRunnerSnapshot(
          capsuleScope: capsuleScope,
          phase: BingxFuturesInteractiveRunnerPhase.running,
          completedCycles: completedCycles,
          lastOutcome: lastOutcome,
          nextCycleAtUtc: null,
          lastError: null,
        ),
        onSnapshot,
      );
      try {
        lastOutcome = await runCycle();
        completedCycles += 1;
        if (!run.firstCycle.isCompleted) {
          run.firstCycle.complete(lastOutcome);
        }
      } catch (error, stackTrace) {
        run.active = false;
        if (identical(_runs[capsuleScope], run)) {
          _runs.remove(capsuleScope);
        }
        _publish(
          BingxFuturesInteractiveRunnerSnapshot(
            capsuleScope: capsuleScope,
            phase: BingxFuturesInteractiveRunnerPhase.failed,
            completedCycles: completedCycles,
            lastOutcome: lastOutcome,
            nextCycleAtUtc: null,
            lastError: error.toString(),
          ),
          onSnapshot,
        );
        if (!run.firstCycle.isCompleted) {
          run.firstCycle.completeError(error, stackTrace);
        }
        return;
      }
      if (!run.active || !identical(_runs[capsuleScope], run)) return;

      final nextCycleAtUtc = _nowUtc().toUtc().add(interactiveInterval);
      _publish(
        BingxFuturesInteractiveRunnerSnapshot(
          capsuleScope: capsuleScope,
          phase: BingxFuturesInteractiveRunnerPhase.waiting,
          completedCycles: completedCycles,
          lastOutcome: lastOutcome,
          nextCycleAtUtc: nextCycleAtUtc,
          lastError: null,
        ),
        onSnapshot,
      );
      try {
        await _delay(interactiveInterval);
      } catch (error) {
        run.active = false;
        if (identical(_runs[capsuleScope], run)) {
          _runs.remove(capsuleScope);
        }
        _publish(
          BingxFuturesInteractiveRunnerSnapshot(
            capsuleScope: capsuleScope,
            phase: BingxFuturesInteractiveRunnerPhase.failed,
            completedCycles: completedCycles,
            lastOutcome: lastOutcome,
            nextCycleAtUtc: null,
            lastError: error.toString(),
          ),
          onSnapshot,
        );
        return;
      }
    }
  }

  void _publish(
    BingxFuturesInteractiveRunnerSnapshot snapshot,
    BingxFuturesInteractiveRunnerObserver? observer,
  ) {
    _snapshots[snapshot.capsuleScope] = snapshot;
    observer?.call(snapshot);
  }

  void _validateScope(String capsuleScope) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(capsuleScope)) {
      throw ArgumentError.value(
        capsuleScope,
        'capsuleScope',
        'must be a lowercase Capsule identifier',
      );
    }
  }
}

class _InteractiveRun {
  final Completer<String> firstCycle = Completer<String>();
  bool active = true;
}
