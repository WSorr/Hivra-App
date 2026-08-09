import 'dart:async';

import '../models/moltbook_ambassador_models.dart';

typedef MoltbookCycleRunner = Future<MoltbookCycleSummary> Function();
typedef MoltbookCycleDelay = Future<void> Function(Duration duration);

class MoltbookCycleTriggerService {
  static const Duration defaultContinuousInterval = Duration(minutes: 5);

  final Duration continuousInterval;
  final MoltbookCycleDelay _delay;
  final Set<String> _sessionStarted = <String>{};
  final Map<String, _ContinuousRun> _continuousRuns =
      <String, _ContinuousRun>{};
  final Map<String, MoltbookCycleTriggerSnapshot> _snapshots =
      <String, MoltbookCycleTriggerSnapshot>{};
  int _generation = 0;

  MoltbookCycleTriggerService({
    this.continuousInterval = defaultContinuousInterval,
    MoltbookCycleDelay? delay,
  }) : _delay = delay ?? Future<void>.delayed {
    if (continuousInterval <= Duration.zero) {
      throw ArgumentError.value(
        continuousInterval,
        'continuousInterval',
        'must be positive',
      );
    }
  }

  MoltbookCycleTriggerSnapshot? snapshot(String scope) => _snapshots[scope];

  Future<MoltbookCycleSummary> runOnDemand({
    required String scope,
    required MoltbookCycleRunner runCycle,
  }) {
    _validateScope(scope);
    return _runOnce(
      scope: scope,
      policy: MoltbookAmbassadorConfiguration.triggerOnDemand,
      runCycle: runCycle,
    );
  }

  Future<MoltbookCycleSummary?> startSession({
    required String scope,
    required MoltbookCycleRunner runCycle,
  }) async {
    _validateScope(scope);
    if (!_sessionStarted.add(scope)) return null;
    return _runOnce(
      scope: scope,
      policy: MoltbookAmbassadorConfiguration.triggerSession,
      runCycle: runCycle,
    );
  }

  Future<MoltbookCycleSummary> startContinuous({
    required String scope,
    required MoltbookCycleRunner runCycle,
  }) {
    _validateScope(scope);
    final existing = _continuousRuns[scope];
    if (existing != null && existing.active) return existing.firstCycle;

    final firstCycle = Completer<MoltbookCycleSummary>();
    final run = _ContinuousRun(firstCycle.future);
    _continuousRuns[scope] = run;
    unawaited(
      _driveContinuous(
        scope: scope,
        run: run,
        runCycle: runCycle,
        firstCycle: firstCycle,
      ),
    );
    return firstCycle.future;
  }

  void stopAll() {
    _generation++;
    _sessionStarted.clear();
    for (final entry in _continuousRuns.entries) {
      final run = entry.value;
      run.active = false;
    }
    for (final entry in _snapshots.entries.toList(growable: false)) {
      final previous = entry.value;
      _snapshots[entry.key] = MoltbookCycleTriggerSnapshot(
        scope: entry.key,
        policy: previous.policy,
        phase: MoltbookCycleTriggerPhase.stopped,
        lastSummary: previous.lastSummary,
        lastError: null,
      );
    }
    _continuousRuns.clear();
  }

  Future<MoltbookCycleSummary> _runOnce({
    required String scope,
    required String policy,
    required MoltbookCycleRunner runCycle,
    bool Function()? isCurrent,
  }) async {
    final runGeneration = _generation;
    final suppliedOwnership = isCurrent ?? () => true;
    bool ownsProjection() =>
        runGeneration == _generation && suppliedOwnership();
    if (ownsProjection()) {
      _snapshots[scope] = MoltbookCycleTriggerSnapshot(
        scope: scope,
        policy: policy,
        phase: MoltbookCycleTriggerPhase.running,
        lastSummary: _snapshots[scope]?.lastSummary,
        lastError: null,
      );
    }
    try {
      final summary = await runCycle();
      if (ownsProjection()) {
        _snapshots[scope] = MoltbookCycleTriggerSnapshot(
          scope: scope,
          policy: policy,
          phase: MoltbookCycleTriggerPhase.idle,
          lastSummary: summary,
          lastError: null,
        );
      }
      return summary;
    } catch (error) {
      if (ownsProjection()) {
        _snapshots[scope] = MoltbookCycleTriggerSnapshot(
          scope: scope,
          policy: policy,
          phase: MoltbookCycleTriggerPhase.failed,
          lastSummary: _snapshots[scope]?.lastSummary,
          lastError: error.toString(),
        );
      }
      rethrow;
    }
  }

  Future<void> _driveContinuous({
    required String scope,
    required _ContinuousRun run,
    required MoltbookCycleRunner runCycle,
    required Completer<MoltbookCycleSummary> firstCycle,
  }) async {
    while (run.active && identical(_continuousRuns[scope], run)) {
      try {
        final summary = await _runOnce(
          scope: scope,
          policy: MoltbookAmbassadorConfiguration.triggerContinuous,
          runCycle: runCycle,
          isCurrent: () => run.active && identical(_continuousRuns[scope], run),
        );
        if (!firstCycle.isCompleted) firstCycle.complete(summary);
        if (!run.active || !identical(_continuousRuns[scope], run)) {
          if (_continuousRuns[scope] == null) {
            _snapshots[scope] = MoltbookCycleTriggerSnapshot(
              scope: scope,
              policy: MoltbookAmbassadorConfiguration.triggerContinuous,
              phase: MoltbookCycleTriggerPhase.stopped,
              lastSummary: summary,
              lastError: null,
            );
          }
          return;
        }
      } catch (error, stackTrace) {
        run.active = false;
        if (!firstCycle.isCompleted) {
          firstCycle.completeError(error, stackTrace);
        }
        if (identical(_continuousRuns[scope], run)) {
          _continuousRuns.remove(scope);
        }
        return;
      }
      final previous = _snapshots[scope];
      _snapshots[scope] = MoltbookCycleTriggerSnapshot(
        scope: scope,
        policy: MoltbookAmbassadorConfiguration.triggerContinuous,
        phase: MoltbookCycleTriggerPhase.waiting,
        lastSummary: previous?.lastSummary,
        lastError: null,
      );
      try {
        await _delay(continuousInterval);
      } catch (error) {
        run.active = false;
        _snapshots[scope] = MoltbookCycleTriggerSnapshot(
          scope: scope,
          policy: MoltbookAmbassadorConfiguration.triggerContinuous,
          phase: MoltbookCycleTriggerPhase.failed,
          lastSummary: previous?.lastSummary,
          lastError: error.toString(),
        );
        if (identical(_continuousRuns[scope], run)) {
          _continuousRuns.remove(scope);
        }
        return;
      }
    }
  }

  void _validateScope(String scope) {
    if (scope.trim() != scope || scope.isEmpty || scope.length > 512) {
      throw ArgumentError.value(scope, 'scope', 'must be a bounded identifier');
    }
  }
}

class _ContinuousRun {
  final Future<MoltbookCycleSummary> firstCycle;
  bool active = true;

  _ContinuousRun(this.firstCycle);
}
