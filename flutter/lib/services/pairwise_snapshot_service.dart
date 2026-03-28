import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/hivra_id_format.dart';

class PairwiseSnapshotRow {
  final String peerHex;
  final String peerLabel;
  final int invitationCount;
  final int relationshipCount;
  final String hashHex;
  final String canonicalJson;

  const PairwiseSnapshotRow({
    required this.peerHex,
    required this.peerLabel,
    required this.invitationCount,
    required this.relationshipCount,
    required this.hashHex,
    required this.canonicalJson,
  });
}

class PairwiseSnapshotService {
  const PairwiseSnapshotService();

  List<PairwiseSnapshotRow> buildSnapshots(
    List<Map<String, dynamic>> events,
    Uint8List localTransportKey,
  ) {
    if (localTransportKey.isEmpty || localTransportKey.length != 32) {
      return const <PairwiseSnapshotRow>[];
    }

    final localTransportHex = _hex(localTransportKey);
    final inviteFactsById = <String, _PairwiseInviteFact>{};
    final inviteTransportPeerById = <String, String>{};
    final inviteRootPeerById = <String, String>{};
    final transportPeerToRootPeer = <String, String>{};
    final relationshipFactsByPeer = <String, List<_PairwiseRelationshipFact>>{};

    for (final event in events) {
      final kind = _kindLabel(event['kind']);
      final payload = _payloadBytes(event['payload']);
      final signer = _bytes32(event['signer']);

      if ((kind == 'InvitationSent' || kind == 'InvitationReceived') && payload.length >= 96) {
        final invitationId = _hex(payload.sublist(0, 32));
        final fact = inviteFactsById.putIfAbsent(invitationId, () => _PairwiseInviteFact(invitationId));
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
        final relationship = _PairwiseRelationshipFact(
          invitationId: invitationId,
          relationshipKind: payload[96],
          starterPair: <String>[
            _hex(payload.sublist(32, 64)),
            _hex(payload.sublist(64, 96)),
          ]..sort(),
        );
        relationshipFactsByPeer.putIfAbsent(peerRootHex, () => <_PairwiseRelationshipFact>[]).add(relationship);
      }
    }

    for (final entry in inviteTransportPeerById.entries) {
      inviteRootPeerById.putIfAbsent(entry.key, () => transportPeerToRootPeer[entry.value] ?? '');
    }
    inviteRootPeerById.removeWhere((_, value) => value.isEmpty);

    for (final event in events) {
      final kind = _kindLabel(event['kind']);
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
      if (peerRootHex == null || peerRootHex.isEmpty || entry.value.status == 'pending') {
        continue;
      }
      inviteFactsByPeer.putIfAbsent(peerRootHex, () => <_PairwiseInviteFact>[]).add(entry.value);
    }

    final snapshots = <PairwiseSnapshotRow>[];
    final peers = <String>{...inviteFactsByPeer.keys, ...relationshipFactsByPeer.keys}.toList()
      ..sort();

    for (final peerRootHex in peers) {
      final pairRoots = <String>[localTransportHex, peerRootHex]..sort();
      final finalizedInvitations = (inviteFactsByPeer[peerRootHex] ?? <_PairwiseInviteFact>[])
        ..sort((a, b) => a.invitationId.compareTo(b.invitationId));
      final relationships = (relationshipFactsByPeer[peerRootHex] ?? <_PairwiseRelationshipFact>[])
        ..sort((a, b) {
          final inviteCmp = a.invitationId.compareTo(b.invitationId);
          if (inviteCmp != 0) return inviteCmp;
          final kindCmp = a.relationshipKind.compareTo(b.relationshipKind);
          if (kindCmp != 0) return kindCmp;
          return a.starterPair.join(':').compareTo(b.starterPair.join(':'));
        });

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
      snapshots.add(
        PairwiseSnapshotRow(
          peerHex: peerRootHex,
          peerLabel: HivraIdFormat.short(
            HivraIdFormat.formatCapsuleKeyBytes(_bytesFromHex(peerRootHex)),
          ),
          invitationCount: finalizedInvitations.length,
          relationshipCount: relationships.length,
          hashHex: digest,
          canonicalJson: const JsonEncoder.withIndent('  ').convert(snapshot),
        ),
      );
    }

    return snapshots;
  }

  String _kindLabel(dynamic kind) {
    if (kind is String) return kind;
    if (kind is int) {
      switch (kind) {
        case 0:
          return 'CapsuleCreated';
        case 1:
          return 'InvitationSent';
        case 9:
          return 'InvitationReceived';
        case 2:
          return 'InvitationAccepted';
        case 3:
          return 'InvitationRejected';
        case 4:
          return 'InvitationExpired';
        case 5:
          return 'StarterCreated';
        case 6:
          return 'StarterBurned';
        case 7:
          return 'RelationshipEstablished';
        case 8:
          return 'RelationshipBroken';
      }
      return 'Kind($kind)';
    }
    return 'Unknown';
  }

  Uint8List _payloadBytes(dynamic payload) {
    if (payload is List) {
      return Uint8List.fromList(
        payload.whereType<num>().map((v) => v.toInt()).toList(growable: false),
      );
    }
    if (payload is String) {
      try {
        return Uint8List.fromList(base64.decode(payload));
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }

  Uint8List? _bytes32(dynamic raw) {
    if (raw is List) {
      final bytes = raw.whereType<num>().map((v) => v.toInt()).toList(growable: false);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    }
    if (raw is String) {
      try {
        final decoded = base64.decode(raw);
        if (decoded.length == 32) return Uint8List.fromList(decoded);
      } catch (_) {}
    }
    return null;
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
