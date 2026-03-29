import 'consensus_runtime_service.dart';

class ManualConsensusCheckService {
  final ConsensusRuntimeService _consensus;

  const ManualConsensusCheckService({
    required ConsensusRuntimeService consensus,
  }) : _consensus = consensus;

  List<ConsensusCheck> loadChecks() {
    return _consensus.checks();
  }
}
