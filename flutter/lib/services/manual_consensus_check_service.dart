import 'consensus_runtime_service.dart';

typedef ManualConsensusCheck = ConsensusCheck;

class ManualConsensusCheckService {
  final ConsensusRuntimeService _consensus;

  const ManualConsensusCheckService({
    required ConsensusRuntimeService consensus,
  }) : _consensus = consensus;

  List<ManualConsensusCheck> loadChecks() {
    return _consensus.checks();
  }
}
