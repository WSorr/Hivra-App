import '../models/consensus_models.dart';
import 'consensus_attestation_sync_service.dart';
import 'consensus_runtime_service.dart';

class ConsensusAttestedGuardService {
  final ConsensusRuntimeService _consensus;
  final ConsensusAttestationSyncService _attestations;

  const ConsensusAttestedGuardService({
    required ConsensusRuntimeService consensus,
    required ConsensusAttestationSyncService attestations,
  })  : _consensus = consensus,
        _attestations = attestations;

  Future<ConsensusSignableResult> signable(String peerRootHex) async {
    final local = _consensus.signable(peerRootHex);
    if (!local.isSignable) return local;

    final evidence =
        await _attestations.loadVerifiedForPair(peerRootHex: peerRootHex);
    if (evidence.isEmpty) {
      return _blocked(local, 'pair_attestation_missing');
    }

    final pairRoots = evidence.first.pairRootsSorted;
    final signers = evidence.map((item) => item.signerRootHex).toSet();
    final hasExactPair = pairRoots.length == 2 &&
        evidence.every(
          (item) =>
              item.pairRootsSorted.length == 2 &&
              item.pairRootsSorted[0] == pairRoots[0] &&
              item.pairRootsSorted[1] == pairRoots[1] &&
              item.snapshotHashHex == local.hashHex,
        );
    final hasBothSigners =
        hasExactPair && pairRoots.every((root) => signers.contains(root));
    if (!hasBothSigners) {
      return _blocked(local, 'pair_attestation_incomplete');
    }

    return local;
  }

  ConsensusSignableResult _blocked(
    ConsensusSignableResult local,
    String code,
  ) {
    return ConsensusSignableResult(
      preview: local.preview,
      blockingFacts: <ConsensusBlockingFact>[
        ...local.blockingFacts,
        ConsensusBlockingFact(code: code),
      ],
    );
  }
}
