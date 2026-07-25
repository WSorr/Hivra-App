import 'consensus_runtime_service.dart';
import 'consensus_attested_guard_service.dart';

typedef ManualConsensusCheck = ConsensusCheck;

class ManualConsensusCheckService {
  final ConsensusRuntimeService _consensus;
  final ConsensusAttestedGuardService? _attestedGuard;

  const ManualConsensusCheckService({
    required ConsensusRuntimeService consensus,
    ConsensusAttestedGuardService? attestedGuard,
  }) : _consensus = consensus,
       _attestedGuard = attestedGuard;

  List<ManualConsensusCheck> loadChecks() {
    return _consensus.checks();
  }

  /// User-facing actions require both local facts and matching peer evidence.
  /// [loadChecks] remains available for raw ledger diagnostics.
  Future<List<ManualConsensusCheck>> loadAttestedChecks() async {
    final checks = loadChecks();
    final guard = _attestedGuard;
    if (guard == null || checks.isEmpty) return checks;
    final results = await Future.wait(
      checks.map((check) => guard.signable(check.peerHex)),
    );
    return List<ManualConsensusCheck>.generate(checks.length, (index) {
      final check = checks[index];
      final result = results[index];
      return ConsensusCheck(
        peerHex: check.peerHex,
        peerLabel: check.peerLabel,
        invitationCount: check.invitationCount,
        relationshipCount: check.relationshipCount,
        hashHex: check.hashHex,
        canonicalJson: check.canonicalJson,
        isSignable: result.isSignable,
        blockingFacts: result.blockingFacts,
      );
    });
  }
}
