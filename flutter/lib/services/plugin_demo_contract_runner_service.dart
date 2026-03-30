import 'consensus_processor.dart';
import 'consensus_runtime_service.dart';
import 'temperature_tomorrow_contract_service.dart';

enum PluginDemoRunState {
  noPairwisePaths,
  blocked,
  executed,
}

class PluginDemoRunResult {
  final PluginDemoRunState state;
  final String? peerHex;
  final String? peerLabel;
  final TemperatureContractSettlement? settlement;
  final List<ConsensusBlockingFact> blockingFacts;

  const PluginDemoRunResult({
    required this.state,
    required this.peerHex,
    required this.peerLabel,
    required this.settlement,
    required this.blockingFacts,
  });

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
        peerHex: null,
        peerLabel: null,
        settlement: null,
        blockingFacts: <ConsensusBlockingFact>[],
      );
    }

    final selected = checks.firstWhere(
      (check) => check.isSignable,
      orElse: () => checks.first,
    );
    final execution = _contractService.execute(
      peerHex: selected.peerHex,
      contract: contract,
      observation: observation,
    );

    if (!execution.isExecutable) {
      return PluginDemoRunResult(
        state: PluginDemoRunState.blocked,
        peerHex: selected.peerHex,
        peerLabel: selected.peerLabel,
        settlement: null,
        blockingFacts: execution.blockingFacts,
      );
    }

    return PluginDemoRunResult(
      state: PluginDemoRunState.executed,
      peerHex: selected.peerHex,
      peerLabel: selected.peerLabel,
      settlement: execution.settlement,
      blockingFacts: const <ConsensusBlockingFact>[],
    );
  }
}
