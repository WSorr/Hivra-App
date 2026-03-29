import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/hivra_id_format.dart';
import 'ledger_view_support.dart';

class ConsensusBlockingFact {
  final String code;
  final String? subjectId;

  const ConsensusBlockingFact({
    required this.code,
    this.subjectId,
  });

  String get key => subjectId == null ? code : '$code:$subjectId';

  String get label => switch (code) {
        'pending_invitation' => subjectId == null
            ? 'Pending invitation'
            : 'Pending invitation ${_shortId(subjectId!)}',
        'relationship_broken' => subjectId == null
            ? 'Relationship broken'
            : 'Relationship broken ${_shortId(subjectId!)}',
        'consensus_runtime_unavailable' => 'Consensus runtime unavailable',
        'invalid_local_transport_key' => 'Invalid local transport key',
        'consensus_peer_not_found' => 'Consensus peer not found',
        'invalid_expected_hash' => 'Invalid expected hash',
        'empty_signature_set' => 'Empty signature set',
        'invalid_hash' => subjectId == null
            ? 'Invalid participant hash'
            : 'Invalid participant hash ${_shortId(subjectId!)}',
        'hash_mismatch' => subjectId == null
            ? 'Hash mismatch'
            : 'Hash mismatch ${_shortId(subjectId!)}',
        'missing_signature' => subjectId == null
            ? 'Missing signature'
            : 'Missing signature ${_shortId(subjectId!)}',
        'invalid_signature' => subjectId == null
            ? 'Invalid signature'
            : 'Invalid signature ${_shortId(subjectId!)}',
        _ => key,
      };

  static String _shortId(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}..${value.substring(value.length - 6)}';
  }
}

enum ConsensusVerifyState {
  match,
  mismatch,
}

class ConsensusPreview {
  final String peerHex;
  final String peerLabel;
  final int invitationCount;
  final int relationshipCount;
  final String hashHex;
  final String canonicalJson;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusPreview({
    required this.peerHex,
    required this.peerLabel,
    required this.invitationCount,
    required this.relationshipCount,
    required this.hashHex,
    required this.canonicalJson,
    required this.blockingFacts,
  });

  bool get isSignable => blockingFacts.isEmpty;
}

class ConsensusSignableResult {
  final ConsensusPreview? preview;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusSignableResult({
    required this.preview,
    required this.blockingFacts,
  });

  bool get isSignable => preview != null && blockingFacts.isEmpty;

  String? get hashHex => isSignable ? preview!.hashHex : null;
}

class ConsensusVerifyParticipant {
  final String participantId;
  final String hashHex;
  final String? signatureHex;

  const ConsensusVerifyParticipant({
    required this.participantId,
    required this.hashHex,
    this.signatureHex,
  });
}

class ConsensusVerifyResult {
  final ConsensusVerifyState state;
  final List<ConsensusBlockingFact> blockingFacts;

  const ConsensusVerifyResult({
    required this.state,
    required this.blockingFacts,
  });

  bool get isMatch =>
      state == ConsensusVerifyState.match && blockingFacts.isEmpty;
}

class ConsensusProcessor {
  final LedgerViewSupport _support;

  const ConsensusProcessor({
    LedgerViewSupport support = const LedgerViewSupport(),
  }) : _support = support;

  List<ConsensusPreview> preview(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey,
  ) {
    if (localTransportKey.length != 32) {
      return const <ConsensusPreview>[];
    }

    final localTransportHex = _hex(localTransportKey);
    final inviteFactsById = <String, _PairwiseInviteFact>{};
    final inviteTransportPeerById = <String, String>{};
    final inviteRootPeerById = <String, String>{};
    final transportPeerToRootPeer = <String, String>{};
    final relationshipFactsByPeer = <String, List<_PairwiseRelationshipFact>>{};
    final pendingInvitationIdsByPeer = <String, Set<String>>{};
    final brokenRelationshipIdsByPeer = <String, Set<String>>{};

    for (final event in events) {
      final kind = _support.kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      final signer = _bytes32(event['signer']);

      if ((kind == 'InvitationSent' || kind == 'InvitationReceived') &&
          payload.length >= 96) {
        final invitationId = _hex(payload.sublist(0, 32));
        final fact = inviteFactsById.putIfAbsent(
          invitationId,
          () => _PairwiseInviteFact(invitationId),
        );
        final transportPeerHex = kind == 'InvitationReceived' && signer != null
            ? _hex(signer)
            : _hex(payload.sublist(64, 96));
        inviteTransportPeerById[invitationId] = transportPeerHex;
        final starterKind = payload.length >= 97 ? payload[96] : null;
        if (starterKind != null) {
          fact.starterKinds.add(starterKind);
        }
      } else if (kind == 'RelationshipEstablished' && payload.length == 194) {
        final peerRootHex = _hex(payload.sublist(0, 32));
        final invitationId = _hex(payload.sublist(97, 129));
        inviteRootPeerById[invitationId] = peerRootHex;
        final transportPeerHex = inviteTransportPeerById[invitationId];
        if (transportPeerHex != null) {
          transportPeerToRootPeer[transportPeerHex] = peerRootHex;
        }
        relationshipFactsByPeer
            .putIfAbsent(peerRootHex, () => <_PairwiseRelationshipFact>[])
            .add(
              _PairwiseRelationshipFact(
                invitationId: invitationId,
                relationshipKind: payload[96],
                starterPair: <String>[
                  _hex(payload.sublist(32, 64)),
                  _hex(payload.sublist(64, 96)),
                ]..sort(),
              ),
            );
      } else if (kind == 'RelationshipBroken' && payload.length >= 64) {
        final peerTransportHex = _hex(payload.sublist(0, 32));
        final peerRootHex = transportPeerToRootPeer[peerTransportHex];
        if (peerRootHex != null && peerRootHex.isNotEmpty) {
          brokenRelationshipIdsByPeer
              .putIfAbsent(peerRootHex, () => <String>{})
              .add(_hex(payload.sublist(32, 64)));
        }
      }
    }

    for (final entry in inviteTransportPeerById.entries) {
      inviteRootPeerById.putIfAbsent(
        entry.key,
        () => transportPeerToRootPeer[entry.value] ?? '',
      );
    }
    inviteRootPeerById.removeWhere((_, value) => value.isEmpty);

    for (final event in events) {
      final kind = _support.kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      if (payload.length < 32) continue;

      final invitationId = _hex(payload.sublist(0, 32));
      final fact = inviteFactsById[invitationId];
      if (fact == null) continue;

      switch (kind) {
        case 'InvitationAccepted':
          fact.accepted = true;
          break;
        case 'InvitationRejected':
          if (payload.length >= 33) {
            fact.rejected = true;
            fact.rejectReasons.add(payload[32]);
          }
          break;
        case 'InvitationExpired':
          fact.expired = true;
          break;
      }
    }

    final inviteFactsByPeer = <String, List<_PairwiseInviteFact>>{};
    for (final entry in inviteFactsById.entries) {
      final peerRootHex = inviteRootPeerById[entry.key];
      if (peerRootHex == null || peerRootHex.isEmpty) {
        continue;
      }
      if (entry.value.status == 'pending') {
        pendingInvitationIdsByPeer
            .putIfAbsent(peerRootHex, () => <String>{})
            .add(entry.key);
        continue;
      }
      inviteFactsByPeer
          .putIfAbsent(peerRootHex, () => <_PairwiseInviteFact>[])
          .add(entry.value);
    }

    final previews = <ConsensusPreview>[];
    final peers = <String>{
      ...inviteFactsByPeer.keys,
      ...relationshipFactsByPeer.keys,
      ...pendingInvitationIdsByPeer.keys,
      ...brokenRelationshipIdsByPeer.keys,
    }.toList()
      ..sort();

    for (final peerRootHex in peers) {
      final pairRoots = <String>[localTransportHex, peerRootHex]..sort();
      final finalizedInvitations = (inviteFactsByPeer[peerRootHex] ??
          <_PairwiseInviteFact>[])
        ..sort((a, b) => a.invitationId.compareTo(b.invitationId));
      final relationships = (relationshipFactsByPeer[peerRootHex] ??
          <_PairwiseRelationshipFact>[])
        ..sort((a, b) {
          final inviteCmp = a.invitationId.compareTo(b.invitationId);
          if (inviteCmp != 0) return inviteCmp;
          final kindCmp = a.relationshipKind.compareTo(b.relationshipKind);
          if (kindCmp != 0) return kindCmp;
          return a.starterPair.join(':').compareTo(b.starterPair.join(':'));
        });
      final blockingFacts = <ConsensusBlockingFact>[
        ...((pendingInvitationIdsByPeer[peerRootHex] ?? const <String>{})
                .toList()
              ..sort())
            .map(
          (id) => ConsensusBlockingFact(
            code: 'pending_invitation',
            subjectId: id,
          ),
        ),
        ...((brokenRelationshipIdsByPeer[peerRootHex] ?? const <String>{})
                .toList()
              ..sort())
            .map(
          (starterId) => ConsensusBlockingFact(
            code: 'relationship_broken',
            subjectId: starterId,
          ),
        ),
      ];

      final snapshot = <String, dynamic>{
        'schema_version': 1,
        'pair_transport_keys_sorted': pairRoots,
        'finalized_invitations': finalizedInvitations.map((fact) {
          final item = <String, dynamic>{
            'invitation_id': fact.invitationId,
            'status': fact.status,
          };
          if (fact.starterKinds.isNotEmpty) {
            item['starter_kinds'] = fact.starterKinds.toList()..sort();
          }
          if (fact.rejected && fact.rejectReasons.isNotEmpty) {
            item['reject_reason'] = (fact.rejectReasons.toList()..sort()).first;
          }
          return item;
        }).toList(growable: false),
        'active_relationships': relationships
            .map((rel) => <String, dynamic>{
                  'invitation_id': rel.invitationId,
                  'relationship_kind': rel.relationshipKind,
                  'starter_pair': rel.starterPair,
                })
            .toList(growable: false),
      };

      final canonical = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(canonical)).toString();

      previews.add(
        ConsensusPreview(
          peerHex: peerRootHex,
          peerLabel: HivraIdFormat.short(
            HivraIdFormat.formatCapsuleKeyBytes(_bytesFromHex(peerRootHex)),
          ),
          invitationCount: finalizedInvitations.length,
          relationshipCount: relationships.length,
          hashHex: digest,
          canonicalJson: const JsonEncoder.withIndent('  ').convert(snapshot),
          blockingFacts:
              List<ConsensusBlockingFact>.unmodifiable(blockingFacts),
        ),
      );
    }

    return previews;
  }

  ConsensusSignableResult signable(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey, {
    required String peerHex,
  }) {
    if (localTransportKey.length != 32) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'invalid_local_transport_key'),
        ],
      );
    }

    final previewRow = preview(events, localTransportKey).firstWhere(
      (row) => row.peerHex == peerHex,
      orElse: () => const ConsensusPreview(
        peerHex: '',
        peerLabel: '',
        invitationCount: 0,
        relationshipCount: 0,
        hashHex: '',
        canonicalJson: '',
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'consensus_peer_not_found'),
        ],
      ),
    );

    if (previewRow.peerHex.isEmpty) {
      return ConsensusSignableResult(
        preview: null,
        blockingFacts: previewRow.blockingFacts,
      );
    }

    return ConsensusSignableResult(
      preview: previewRow,
      blockingFacts: previewRow.blockingFacts,
    );
  }

  ConsensusVerifyResult verify({
    required String expectedHashHex,
    required List<ConsensusVerifyParticipant> participants,
  }) {
    final blockingFacts = <ConsensusBlockingFact>[];
    final normalizedExpected = _normalizedHex(expectedHashHex);
    if (normalizedExpected == null || normalizedExpected.length != 64) {
      blockingFacts
          .add(const ConsensusBlockingFact(code: 'invalid_expected_hash'));
    }
    if (participants.isEmpty) {
      blockingFacts
          .add(const ConsensusBlockingFact(code: 'empty_signature_set'));
    }

    for (final participant in participants) {
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
      }
    }

    return ConsensusVerifyResult(
      state: blockingFacts.isEmpty
          ? ConsensusVerifyState.match
          : ConsensusVerifyState.mismatch,
      blockingFacts: List<ConsensusBlockingFact>.unmodifiable(blockingFacts),
    );
  }

  Uint8List _payloadBytes(dynamic payload) => _support.payloadBytes(payload);

  Uint8List? _bytes32(dynamic raw) {
    final bytes = _support.payloadBytes(raw);
    return bytes.length == 32 ? bytes : null;
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _bytesFromHex(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(out);
  }

  String? _normalizedHex(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}

class _PairwiseInviteFact {
  final String invitationId;
  final Set<int> starterKinds = <int>{};
  final Set<int> rejectReasons = <int>{};
  bool accepted = false;
  bool rejected = false;
  bool expired = false;

  _PairwiseInviteFact(this.invitationId);

  String get status {
    if (accepted) return 'accepted';
    if (rejected) return 'rejected';
    if (expired) return 'expired';
    return 'pending';
  }
}

class _PairwiseRelationshipFact {
  final String invitationId;
  final int relationshipKind;
  final List<String> starterPair;

  const _PairwiseRelationshipFact({
    required this.invitationId,
    required this.relationshipKind,
    required this.starterPair,
  });
}
