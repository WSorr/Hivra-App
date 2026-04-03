import 'consensus_processor.dart';
import 'consensus_runtime_service.dart';
import 'temperature_tomorrow_contract_service.dart';

enum PluginDemoRunState {
  noPairwisePaths,
  blocked,
  partial,
  executed,
}

class PluginDemoPairRunResult {
  final String peerHex;
  final String? peerLabel;
  final TemperatureContractSettlement? settlement;
  final List<ConsensusBlockingFact> blockingFacts;

  const PluginDemoPairRunResult({
    required this.peerHex,
    required this.peerLabel,
    required this.settlement,
    required this.blockingFacts,
  });

  bool get isExecuted => settlement != null && blockingFacts.isEmpty;
}

class PluginDemoRunResult {
  final PluginDemoRunState state;
  final List<PluginDemoPairRunResult> pairResults;
  final List<ConsensusBlockingFact> blockingFacts;

  const PluginDemoRunResult({
    required this.state,
    required this.pairResults,
    required this.blockingFacts,
  });

  PluginDemoPairRunResult? get firstExecutedPair {
    for (final pair in pairResults) {
      if (pair.isExecuted) return pair;
    }
    return null;
  }

  PluginDemoPairRunResult? get firstPair =>
      pairResults.isEmpty ? null : pairResults.first;

  int get readyPairCount => pairResults.where((pair) => pair.isExecuted).length;

  int get blockedPairCount => pairResults.length - readyPairCount;

  String? get peerHex => firstExecutedPair?.peerHex ?? firstPair?.peerHex;

  String? get peerLabel => firstExecutedPair?.peerLabel ?? firstPair?.peerLabel;

  TemperatureContractSettlement? get settlement => firstExecutedPair?.settlement;

  bool get isExecuted => state == PluginDemoRunState.executed;
}

typedef ConsensusChecksReader = List<ConsensusCheck> Function();

class PluginDemoContractRunnerService {
  final ConsensusChecksReader _readChecks;
  final TemperatureTomorrowContractService _contractService;

  const PluginDemoContractRunnerService({
    required ConsensusChecksReader readChecks,
    required TemperatureTomorrowContractService contractService,
  })  : _readChecks = readChecks,
        _contractService = contractService;

  PluginDemoRunResult runTemperatureTomorrowDemo({
    required TemperatureTomorrowContractSpec contract,
    required TemperatureOracleObservation observation,
  }) {
    final checks = _readChecks();
    if (checks.isEmpty) {
      return const PluginDemoRunResult(
        state: PluginDemoRunState.noPairwisePaths,
        pairResults: <PluginDemoPairRunResult>[],
        blockingFacts: <ConsensusBlockingFact>[],
      );
    }

    final pairResults = <PluginDemoPairRunResult>[];
    final blockingByKey = <String, ConsensusBlockingFact>{};
    var readyPairCount = 0;
    var blockedPairCount = 0;

    for (final check in checks) {
      final execution = _contractService.execute(
        peerHex: check.peerHex,
        contract: contract,
        observation: observation,
      );

      if (execution.isExecutable) {
        readyPairCount += 1;
        pairResults.add(
          PluginDemoPairRunResult(
            peerHex: check.peerHex,
            peerLabel: check.peerLabel,
            settlement: execution.settlement,
            blockingFacts: const <ConsensusBlockingFact>[],
          ),
        );
        continue;
      }

      blockedPairCount += 1;
      final facts = execution.blockingFacts.isNotEmpty
          ? execution.blockingFacts
          : check.blockingFacts;
      for (final fact in facts) {
        blockingByKey[fact.key] = fact;
      }
      pairResults.add(
        PluginDemoPairRunResult(
          peerHex: check.peerHex,
          peerLabel: check.peerLabel,
          settlement: null,
          blockingFacts: facts,
        ),
      );
    }

    final state = blockedPairCount == 0
        ? PluginDemoRunState.executed
        : readyPairCount == 0
            ? PluginDemoRunState.blocked
            : PluginDemoRunState.partial;

    return PluginDemoRunResult(
      state: state,
      pairResults: pairResults,
      blockingFacts: blockingByKey.values.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
}
