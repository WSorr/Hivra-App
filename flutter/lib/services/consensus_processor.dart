import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/consensus_models.dart';
import '../utils/hivra_id_format.dart';

class ConsensusProcessor {
  const ConsensusProcessor();

  ConsensusAttestationCommitment? buildAttestationCommitment({
    required String localRootHex,
    required String peerRootHex,
    required String snapshotHashHex,
  }) {
    final local = _normalizedHex(localRootHex);
    final peer = _normalizedHex(peerRootHex);
    final snapshot = _normalizedHex(snapshotHashHex);
    if (local == null ||
        peer == null ||
        snapshot == null ||
        local.length != 64 ||
        peer.length != 64 ||
        snapshot.length != 64 ||
        local == peer) {
      return null;
    }
    final roots = <String>[local, peer]..sort();
    final canonicalJson = jsonEncode(<String, dynamic>{
      'domain': 'hivra.pair_consensus.attestation',
      'schema_version': 1,
      'pair_roots_sorted': roots,
      'snapshot_hash': snapshot,
    });
    return ConsensusAttestationCommitment(
      pairRootsSorted: List<String>.unmodifiable(roots),
      snapshotHashHex: snapshot,
      canonicalJson: canonicalJson,
      commitmentHashHex: sha256.convert(utf8.encode(canonicalJson)).toString(),
    );
  }

  List<ConsensusPreview> preview(String pairViewJson) {
    final root = _decodePairView(pairViewJson);
    if (root == null) return const <ConsensusPreview>[];
    final rawPairs = root['pairs'];
    if (rawPairs is! List) return const <ConsensusPreview>[];

    final previews = <ConsensusPreview>[];
    for (final rawPair in rawPairs) {
      if (rawPair is! Map) continue;
      final pair = Map<String, dynamic>.from(rawPair);
      final localHex = _hex32(pair['local_identity']);
      final peerHex = _hex32(pair['peer_identity']);
      if (localHex == null || peerHex == null || localHex == peerHex) continue;

      final relationships = _relationships(pair['active_relationships']);
      final blockers = _blockers(pair['blockers']);
      final roots = <String>[localHex, peerHex]..sort();
      final snapshot = <String, dynamic>{
        'schema_version': 3,
        'pair_roots_sorted': roots,
        'active_relationships': relationships,
      };
      final compact = jsonEncode(snapshot);
      previews.add(
        ConsensusPreview(
          peerHex: peerHex,
          peerLabel: HivraIdFormat.short(
            HivraIdFormat.formatCapsuleKeyBytes(
              Uint8List.fromList(_bytesFromHex(peerHex)),
            ),
          ),
          invitationCount:
              _nonNegativeInt(pair['finalized_invitation_count']) ?? 0,
          relationshipCount: relationships.length,
          hashHex: sha256.convert(utf8.encode(compact)).toString(),
          canonicalJson: const JsonEncoder.withIndent('  ').convert(snapshot),
          blockingFacts: List<ConsensusBlockingFact>.unmodifiable(blockers),
        ),
      );
    }
    previews.sort((left, right) => left.peerHex.compareTo(right.peerHex));
    return List<ConsensusPreview>.unmodifiable(previews);
  }

  ConsensusSignableResult signable(
    String pairViewJson, {
    required String peerHex,
  }) {
    final normalizedPeerHex = _normalizedHex(peerHex);
    if (normalizedPeerHex == null || normalizedPeerHex.length != 64) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'invalid_peer_id'),
        ],
      );
    }
    final previewRow = preview(
      pairViewJson,
    ).where((row) => row.peerHex == normalizedPeerHex);
    if (previewRow.isEmpty) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'consensus_peer_not_found'),
        ],
      );
    }
    return ConsensusSignableResult(
      preview: previewRow.first,
      blockingFacts: previewRow.first.blockingFacts,
    );
  }

  ConsensusVerifyResult verify({
    required String expectedHashHex,
    required List<ConsensusVerifyParticipant> participants,
    ConsensusSignatureVerifier? verifySignature,
  }) {
    final blockingFacts = <ConsensusBlockingFact>[];
    if (verifySignature == null) {
      blockingFacts.add(
        const ConsensusBlockingFact(code: 'signature_verifier_unavailable'),
      );
    }
    final normalizedExpected = _normalizedHex(expectedHashHex);
    if (normalizedExpected == null || normalizedExpected.length != 64) {
      blockingFacts.add(
        const ConsensusBlockingFact(code: 'invalid_expected_hash'),
      );
    }
    if (participants.isEmpty) {
      blockingFacts.add(
        const ConsensusBlockingFact(code: 'empty_signature_set'),
      );
    }

    final seenParticipantIds = <String>{};
    for (final participant in participants) {
      final dedupeParticipantId = _normalizedParticipantIdForVerify(
        participant.participantId,
      );
      if (!seenParticipantIds.add(dedupeParticipantId)) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'duplicate_participant',
            subjectId: dedupeParticipantId,
          ),
        );
      }

      final participantHash = _normalizedHex(participant.hashHex);
      if (participantHash == null || participantHash.length != 64) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'invalid_hash',
            subjectId: participant.participantId,
          ),
        );
      } else if (normalizedExpected != null &&
          participantHash != normalizedExpected) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'hash_mismatch',
            subjectId: participant.participantId,
          ),
        );
      }

      final signature = _normalizedHex(participant.signatureHex);
      if (signature == null || signature.isEmpty) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'missing_signature',
            subjectId: participant.participantId,
          ),
        );
      } else if (signature.length != 128) {
        blockingFacts.add(
          ConsensusBlockingFact(
            code: 'invalid_signature',
            subjectId: participant.participantId,
          ),
        );
      } else if (verifySignature != null &&
          normalizedExpected != null &&
          participantHash == normalizedExpected) {
        final participantIdHex = _normalizedHex(participant.participantId);
        final isValid =
            participantIdHex != null &&
            participantIdHex.length == 64 &&
            verifySignature(
              messageHashHex: normalizedExpected,
              participantIdHex: participantIdHex,
              signatureHex: signature,
            );
        if (!isValid) {
          blockingFacts.add(
            ConsensusBlockingFact(
              code: 'invalid_signature',
              subjectId: participant.participantId,
            ),
          );
        }
      }
    }

    return ConsensusVerifyResult(
      state:
          blockingFacts.isEmpty
              ? ConsensusVerifyState.match
              : ConsensusVerifyState.mismatch,
      blockingFacts: List<ConsensusBlockingFact>.unmodifiable(blockingFacts),
    );
  }

  Map<String, dynamic>? _decodePairView(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final root = Map<String, dynamic>.from(decoded);
      if (root['schema'] != 'hivra.pair_view' || root['version'] != 1) {
        return null;
      }
      return root;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _relationships(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final byKey = <String, Map<String, dynamic>>{};
    for (final raw in value) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final kind = _nonNegativeInt(item['relationship_kind']);
      final rawPair = item['starter_pair'];
      if (kind == null || rawPair is! List || rawPair.length != 2) continue;
      final starterA = _hex32(rawPair[0]);
      final starterB = _hex32(rawPair[1]);
      if (starterA == null || starterB == null) continue;
      final pair = <String>[starterA, starterB]..sort();
      byKey['$kind:${pair.join(':')}'] = <String, dynamic>{
        'relationship_kind': kind,
        'starter_pair': pair,
      };
    }
    final relationships =
        byKey.values.toList()..sort((left, right) {
          final kind = (left['relationship_kind'] as int).compareTo(
            right['relationship_kind'] as int,
          );
          if (kind != 0) return kind;
          return (left['starter_pair'] as List)
              .join(':')
              .compareTo((right['starter_pair'] as List).join(':'));
        });
    return relationships;
  }

  List<ConsensusBlockingFact> _blockers(Object? value) {
    if (value is! List) return const <ConsensusBlockingFact>[];
    final blockers = <ConsensusBlockingFact>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final code = item['code']?.toString();
      final subject = _hex32(item['subject_id']);
      if (code == null || code.isEmpty || subject == null) continue;
      blockers.add(ConsensusBlockingFact(code: code, subjectId: subject));
    }
    return blockers;
  }

  String? _hex32(Object? value) {
    if (value is! List || value.length != 32) return null;
    final bytes = <int>[];
    for (final item in value) {
      if (item is! num || item.toInt() < 0 || item.toInt() > 255) return null;
      bytes.add(item.toInt());
    }
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _bytesFromHex(String hex) {
    return <int>[
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];
  }

  int? _nonNegativeInt(Object? value) {
    if (value is! num || value.toInt() < 0) return null;
    return value.toInt();
  }

  String? _normalizedHex(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || !RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  String _normalizedParticipantIdForVerify(String value) {
    final trimmed = value.trim();
    final normalizedHex = _normalizedHex(trimmed);
    if (normalizedHex != null && normalizedHex.length == 64) {
      return normalizedHex;
    }
    return trimmed.toLowerCase();
  }
}
