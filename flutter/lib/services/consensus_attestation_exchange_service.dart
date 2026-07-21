import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/consensus_models.dart';
import '../models/relationship.dart';
import 'capsule_address_service.dart';
import 'consensus_attestation_sync_service.dart';
import 'ledger_view_support.dart';

typedef AttestationRelationshipsLoader = List<Relationship> Function();
typedef AttestationTrustedCardsLoader =
    Future<List<CapsuleAddressCard>> Function();
typedef AttestationLedgerExporter = String? Function();

enum ConsensusAttestationExchangeStatus { ready, syncing, blocked }

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
  final AttestationLedgerExporter _exportLedger;
  final LedgerViewSupport _ledgerSupport = const LedgerViewSupport();

  ConsensusAttestationExchangeService({
    required ConsensusAttestationSyncService sync,
    required AttestationRelationshipsLoader loadRelationships,
    required AttestationTrustedCardsLoader listTrustedCards,
    AttestationLedgerExporter? exportLedger,
  }) : _sync = sync,
       _loadRelationships = loadRelationships,
       _listTrustedCards = listTrustedCards,
       _exportLedger = exportLedger ?? _nullAttestationLedgerExport;

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
      final peerTransportHex = await _resolvePeerTransportHex(normalizedPeer);
      if (peerTransportHex != null) {
        _announceReadyEvidence(
          peerRootHex: normalizedPeer,
          peerTransportHex: peerTransportHex,
        );
      }
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
    var effectiveReceive = received;
    if (sent.isSuccess) {
      effectiveReceive = _combineReceiveResults(
        received,
        await _sync.receiveAndStore(),
      );
    }
    verified = await _sync.loadVerifiedForPair(peerRootHex: normalizedPeer);
    if (_hasTwoRootEvidence(verified)) {
      return ConsensusAttestationExchangeResult(
        status: ConsensusAttestationExchangeStatus.ready,
        message: null,
        receiveCode: effectiveReceive.code,
        receivedCount: effectiveReceive.receivedCount,
        storedCount: effectiveReceive.storedCount,
        localEvidenceSent: sent.isSuccess,
        sendCode: sent.code,
      );
    }

    final pairEvidence = await _sync.loadVerifiedPairEvidence(
      peerRootHex: normalizedPeer,
    );
    final mismatchedEvidenceCount = _mismatchedEvidenceCount(
      pairEvidence,
      verified,
    );
    return ConsensusAttestationExchangeResult(
      status: ConsensusAttestationExchangeStatus.syncing,
      message:
          sent.isSuccess
              ? _syncingMessage(mismatchedEvidenceCount)
              : sent.errorMessage ?? 'Pair consensus attestation send failed',
      receiveCode: effectiveReceive.code,
      receivedCount: effectiveReceive.receivedCount,
      storedCount: effectiveReceive.storedCount,
      mismatchedEvidenceCount: mismatchedEvidenceCount,
      localEvidenceSent: sent.isSuccess,
      sendCode: sent.code,
    );
  }

  Future<ConsensusAttestationSendResult> announceForPeer(
    String peerRootHex,
  ) async {
    final normalizedPeer = _normalizeHex64(peerRootHex);
    if (normalizedPeer == null) {
      return const ConsensusAttestationSendResult(
        isSuccess: false,
        code: -1,
        errorMessage: 'Invalid consensus peer',
        evidence: null,
      );
    }
    final peerTransportHex = await _resolvePeerTransportHex(normalizedPeer);
    if (peerTransportHex == null) {
      return const ConsensusAttestationSendResult(
        isSuccess: false,
        code: -1,
        errorMessage: 'No transport endpoint mapped for consensus peer',
        evidence: null,
      );
    }
    return _sync.sendLocalEvidence(
      peerRootHex: normalizedPeer,
      peerTransportHex: peerTransportHex,
    );
  }

  Future<ConsensusAttestationReceiveResult> receiveAndAnswerStored() async {
    final receive = await _sync.receiveAndStore();
    if (receive.storedEvidence.isEmpty) {
      return receive;
    }
    final localRootHex = _sync.localRootHex();
    if (localRootHex == null) {
      return receive;
    }
    final peers = <String>{};
    for (final evidence in receive.storedEvidence) {
      if (evidence.pairRootsSorted.length != 2 ||
          !evidence.pairRootsSorted.contains(localRootHex)) {
        continue;
      }
      for (final root in evidence.pairRootsSorted) {
        if (root != localRootHex) {
          peers.add(root);
        }
      }
    }
    for (final peerRootHex in peers) {
      await announceForPeer(peerRootHex);
    }
    return receive;
  }

  void _announceReadyEvidence({
    required String peerRootHex,
    required String peerTransportHex,
  }) {
    unawaited(
      _sync
          .sendLocalEvidence(
            peerRootHex: peerRootHex,
            peerTransportHex: peerTransportHex,
          )
          .catchError(
            (_) => const ConsensusAttestationSendResult(
              isSuccess: false,
              code: -1,
              errorMessage: 'Pair consensus attestation announce failed',
              evidence: null,
            ),
          ),
    );
  }

  ConsensusAttestationReceiveResult _combineReceiveResults(
    ConsensusAttestationReceiveResult first,
    ConsensusAttestationReceiveResult second,
  ) {
    final effectiveCode = second.code < 0 ? second.code : first.code;
    return ConsensusAttestationReceiveResult(
      code: effectiveCode,
      errorMessage: second.errorMessage ?? first.errorMessage,
      receivedCount: first.receivedCount + second.receivedCount,
      storedCount: first.storedCount + second.storedCount,
      rejectedCount: first.rejectedCount + second.rejectedCount,
      storedEvidence: <ConsensusAttestationEvidence>[
        ...first.storedEvidence,
        ...second.storedEvidence,
      ],
    );
  }

  String _syncingMessage(int mismatchedEvidenceCount) {
    if (mismatchedEvidenceCount > 0) {
      return 'Pair consensus attestation sent; ignoring stale pair evidence and waiting for current peer attestation';
    }
    return 'Pair consensus attestation sent; waiting for peer attestation';
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
      if (transportHex != null && transportHex != rootHex) {
        rootToTransport.putIfAbsent(rootHex, () => transportHex);
      }
    }

    final cards = await _safeTrustedCards();
    for (final card in cards) {
      if (_normalizeHex64(card.rootHex) != peerRootHex) continue;
      final transportHex = _normalizeHex64(card.nostrHex);
      if (transportHex != null && transportHex != peerRootHex) {
        rootToTransport[peerRootHex] = transportHex;
      }
    }

    final ledgerRoot = _ledgerSupport.exportLedgerRoot(_exportLedger());
    if (ledgerRoot != null) {
      for (final raw in _ledgerSupport.events(ledgerRoot)) {
        if (raw is! Map) continue;
        final event = Map<String, dynamic>.from(raw);
        if (_ledgerSupport.kindCode(event['kind']) != 9) continue;
        final payload = _ledgerSupport.payloadBytes(event['payload']);
        if (payload.length < 161) continue;
        final senderRoot = _hex(Uint8List.fromList(payload.sublist(96, 128)));
        if (senderRoot != peerRootHex) continue;
        final senderTransport = _hex(
          Uint8List.fromList(payload.sublist(129, 161)),
        );
        if (senderTransport != peerRootHex) {
          rootToTransport[peerRootHex] = senderTransport;
        }
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

String? _nullAttestationLedgerExport() => null;
