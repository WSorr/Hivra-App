import 'dart:convert';
import 'dart:typed_data';

import '../models/consensus_models.dart';
import '../models/relationship.dart';
import 'capsule_address_service.dart';
import 'consensus_attestation_sync_service.dart';

typedef AttestationRelationshipsLoader = List<Relationship> Function();
typedef AttestationTrustedCardsLoader = Future<List<CapsuleAddressCard>>
    Function();

enum ConsensusAttestationExchangeStatus {
  ready,
  syncing,
  blocked,
}

class ConsensusAttestationExchangeResult {
  final ConsensusAttestationExchangeStatus status;
  final String? message;
  final int receiveCode;
  final int receivedCount;
  final int storedCount;
  final int mismatchedEvidenceCount;
  final bool localEvidenceSent;
  final int? sendCode;

  const ConsensusAttestationExchangeResult({
    required this.status,
    required this.message,
    required this.receiveCode,
    required this.receivedCount,
    required this.storedCount,
    this.mismatchedEvidenceCount = 0,
    required this.localEvidenceSent,
    this.sendCode,
  });

  bool get isReady => status == ConsensusAttestationExchangeStatus.ready;
}

class ConsensusAttestationExchangeService {
  final ConsensusAttestationSyncService _sync;
  final AttestationRelationshipsLoader _loadRelationships;
  final AttestationTrustedCardsLoader _listTrustedCards;

  const ConsensusAttestationExchangeService({
    required ConsensusAttestationSyncService sync,
    required AttestationRelationshipsLoader loadRelationships,
    required AttestationTrustedCardsLoader listTrustedCards,
  })  : _sync = sync,
        _loadRelationships = loadRelationships,
        _listTrustedCards = listTrustedCards;

  Future<ConsensusAttestationExchangeResult> ensureForPeer(
    String peerRootHex,
  ) async {
    final normalizedPeer = _normalizeHex64(peerRootHex);
    if (normalizedPeer == null) {
      return const ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.blocked,
        message: 'Invalid consensus peer',
        receiveCode: 0,
        receivedCount: 0,
        storedCount: 0,
        localEvidenceSent: false,
      );
    }

    final received = await _sync.receiveAndStore();
    var verified = await _sync.loadVerifiedForPair(peerRootHex: normalizedPeer);
    if (_hasTwoRootEvidence(verified)) {
      return ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.ready,
        message: null,
        receiveCode: received.code,
        receivedCount: received.receivedCount,
        storedCount: received.storedCount,
        localEvidenceSent: false,
      );
    }

    final peerTransportHex = await _resolvePeerTransportHex(normalizedPeer);
    if (peerTransportHex == null) {
      return ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.blocked,
        message: 'No transport endpoint mapped for consensus peer',
        receiveCode: received.code,
        receivedCount: received.receivedCount,
        storedCount: received.storedCount,
        localEvidenceSent: false,
      );
    }

    final sent = await _sync.sendLocalEvidence(
      peerRootHex: normalizedPeer,
      peerTransportHex: peerTransportHex,
    );
    verified = await _sync.loadVerifiedForPair(peerRootHex: normalizedPeer);
    if (_hasTwoRootEvidence(verified)) {
      return ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.ready,
        message: null,
        receiveCode: received.code,
        receivedCount: received.receivedCount,
        storedCount: received.storedCount,
        localEvidenceSent: sent.isSuccess,
        sendCode: sent.code,
      );
    }

    final pairEvidence =
        await _sync.loadVerifiedPairEvidence(peerRootHex: normalizedPeer);
    final mismatchedEvidenceCount =
        _mismatchedEvidenceCount(pairEvidence, verified);
    if (_hasBothPairSigners(pairEvidence) && mismatchedEvidenceCount > 0) {
      return ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.blocked,
        message:
            'Pair consensus snapshots differ; sync ledgers before retrying',
        receiveCode: received.code,
        receivedCount: received.receivedCount,
        storedCount: received.storedCount,
        mismatchedEvidenceCount: mismatchedEvidenceCount,
        localEvidenceSent: sent.isSuccess,
        sendCode: sent.code,
      );
    }

    return ConsensusAttestationExchangeResult(
      status: ConsensusAttestationExchangeStatus.syncing,
      message: sent.isSuccess
          ? 'Pair consensus attestation sent; waiting for peer attestation'
          : sent.errorMessage ?? 'Pair consensus attestation send failed',
      receiveCode: received.code,
      receivedCount: received.receivedCount,
      storedCount: received.storedCount,
      mismatchedEvidenceCount: mismatchedEvidenceCount,
      localEvidenceSent: sent.isSuccess,
      sendCode: sent.code,
    );
  }

  bool _hasTwoRootEvidence(Iterable<ConsensusAttestationEvidence> evidence) {
    final signers = <String>{};
    List<String>? pairRoots;
    String? snapshotHash;
    for (final item in evidence) {
      final roots = item.pairRootsSorted;
      if (roots.length != 2) continue;
      pairRoots ??= roots;
      snapshotHash ??= item.snapshotHashHex;
      if (pairRoots[0] != roots[0] ||
          pairRoots[1] != roots[1] ||
          snapshotHash != item.snapshotHashHex) {
        continue;
      }
      signers.add(item.signerRootHex);
    }
    return pairRoots != null && pairRoots.every(signers.contains);
  }

  int _mismatchedEvidenceCount(
    List<ConsensusAttestationEvidence> pairEvidence,
    List<ConsensusAttestationEvidence> currentEvidence,
  ) {
    final currentKeys = currentEvidence.map((item) => item.recordKey).toSet();
    return pairEvidence
        .where((item) => !currentKeys.contains(item.recordKey))
        .length;
  }

  bool _hasBothPairSigners(List<ConsensusAttestationEvidence> evidence) {
    if (evidence.isEmpty) return false;
    final pairRoots = evidence.first.pairRootsSorted;
    if (pairRoots.length != 2) return false;
    final signers = evidence.map((item) => item.signerRootHex).toSet();
    return pairRoots.every(signers.contains);
  }

  Future<String?> _resolvePeerTransportHex(String peerRootHex) async {
    final rootToTransport = <String, String>{};
    for (final relationship in _loadRelationships()) {
      if (!relationship.isActive || relationship.hasPendingRemoteBreak) {
        continue;
      }
      final peerRoot = relationship.peerRootPubkey;
      if (peerRoot == null || peerRoot.isEmpty) continue;
      final rootHex = _decodeB64ToHex32(peerRoot);
      if (rootHex == null || rootHex != peerRootHex) continue;
      final transportHex = _decodeB64ToHex32(relationship.peerPubkey);
      if (transportHex != null) {
        rootToTransport.putIfAbsent(rootHex, () => transportHex);
      }
    }

    final cards = await _safeTrustedCards();
    for (final card in cards) {
      if (_normalizeHex64(card.rootHex) != peerRootHex) continue;
      final transportHex = _normalizeHex64(card.nostrHex);
      if (transportHex != null) {
        rootToTransport[peerRootHex] = transportHex;
      }
    }
    return rootToTransport[peerRootHex];
  }

  Future<List<CapsuleAddressCard>> _safeTrustedCards() async {
    try {
      return await _listTrustedCards();
    } catch (_) {
      return const <CapsuleAddressCard>[];
    }
  }

  String? _decodeB64ToHex32(String value) {
    try {
      final bytes = base64.decode(value);
      if (bytes.length != 32) return null;
      return _hex(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  String? _normalizeHex64(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }

  String _hex(Uint8List bytes) {
    final out = StringBuffer();
    for (final byte in bytes) {
      out.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }
}
