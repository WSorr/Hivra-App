import 'consensus_processor.dart';
import 'consensus_runtime_service.dart';

enum ConsensusGuardState {
  pending,
  ready,
  blocked,
  partial,
}

class PluginExecutionGuardSnapshot {
  final ConsensusGuardState state;
  final int readyPairCount;
  final int blockedPairCount;
  final List<ConsensusBlockingFact> blockingFacts;

  const PluginExecutionGuardSnapshot({
    required this.state,
    required this.readyPairCount,
    required this.blockedPairCount,
    required this.blockingFacts,
  });
}

class PluginExecutionGuardService {
  final ConsensusRuntimeService _consensus;

  const PluginExecutionGuardService({
    required ConsensusRuntimeService consensus,
  }) : _consensus = consensus;

  PluginExecutionGuardSnapshot inspectHostReadiness() {
    final checks = _consensus.checks();
    if (checks.isEmpty) {
      return const PluginExecutionGuardSnapshot(
        state: ConsensusGuardState.pending,
        readyPairCount: 0,
        blockedPairCount: 0,
        blockingFacts: <ConsensusBlockingFact>[],
      );
    }

    var readyPairCount = 0;
    var blockedPairCount = 0;
    final blockingFacts = <String, ConsensusBlockingFact>{};

    for (final check in checks) {
      if (check.isSignable) {
        readyPairCount += 1;
      } else {
        blockedPairCount += 1;
        for (final fact in check.blockingFacts) {
          blockingFacts[fact.key] = fact;
        }
      }
    }

    final state = blockedPairCount == 0
        ? ConsensusGuardState.ready
        : readyPairCount == 0
            ? ConsensusGuardState.blocked
            : ConsensusGuardState.partial;

    return PluginExecutionGuardSnapshot(
      state: state,
      readyPairCount: readyPairCount,
      blockedPairCount: blockedPairCount,
      blockingFacts: (blockingFacts.values.toList()
        ..sort((a, b) => a.key.compareTo(b.key))),
    );
  }
}
