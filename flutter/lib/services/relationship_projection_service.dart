import 'dart:convert';
import 'dart:typed_data';

import '../models/relationship_peer_group.dart';
import '../models/relationship.dart';
import '../models/starter.dart';
import 'ledger_view_support.dart';

class RelationshipProjectionService {
  final LedgerViewSupport _support;
  final Uint8List? Function()? _runtimeOwnerPublicKey;

  const RelationshipProjectionService(
    this._support, {
    Uint8List? Function()? runtimeOwnerPublicKey,
  }) : _runtimeOwnerPublicKey = runtimeOwnerPublicKey;

  RelationshipProjectionService.withOwnerKeyProvider(
    Uint8List? Function() runtimeOwnerPublicKey,
    this._support,
  ) : _runtimeOwnerPublicKey = runtimeOwnerPublicKey;

  List<Relationship> loadRelationships(Map<String, dynamic> root) {
    final events = _support.events(root);
    final byKey = <String, Relationship>{};
    final localOwner = _runtimeOwnerPublicKey?.call();

    for (final e in events) {
      final kind = _support.kindCode(e['kind']);
      final payload = _support.payloadBytes(e['payload']);
      final timestamp = _support.eventTime(e['timestamp']);
      if (kind == 7) {
        final established = _parseRelationshipEstablished(payload);
        if (established == null) continue;
        final key = _support.relationshipKeyFromEstablishedPayload(payload);
        if (key == null) continue;
        byKey[key] = Relationship(
          peerPubkey: established.peerPubkey,
          kind: established.kind,
          ownStarterId: established.ownStarterId,
          peerStarterId: established.peerStarterId,
          establishedAt: timestamp,
          isActive: true,
          hasPendingRemoteBreak: false,
        );
      } else if (kind == 8) {
        final key = _support.relationshipKeyFromBrokenPayload(payload);
        if (key == null) continue;
        final current = byKey[key];
        if (current != null) {
          final signer = _support.bytes32(e['signer']);
          final hasLocalOwner = localOwner != null && localOwner.length == 32;
          final signerMatchesLocal = hasLocalOwner &&
              signer.length == 32 &&
              _support.eq32(signer, localOwner);
          final isPendingRemoteBreak =
              hasLocalOwner && signer.length == 32 && !signerMatchesLocal;
          if (isPendingRemoteBreak &&
              !current.isActive &&
              !current.hasPendingRemoteBreak) {
            // Local break finalization has higher precedence than replayed
            // remote break notifications.
            continue;
          }
          byKey[key] = Relationship(
            peerPubkey: current.peerPubkey,
            kind: current.kind,
            ownStarterId: current.ownStarterId,
            peerStarterId: current.peerStarterId,
            establishedAt: current.establishedAt,
            isActive: isPendingRemoteBreak ? true : false,
            hasPendingRemoteBreak: isPendingRemoteBreak,
          );
        }
      }
    }

    final list = byKey.values.toList();
    list.sort((a, b) => b.establishedAt.compareTo(a.establishedAt));
    return list;
  }

  List<RelationshipPeerGroup> loadRelationshipGroups(
      Map<String, dynamic> root) {
    final relationships = loadRelationships(root);
    final byPeer = <String, List<Relationship>>{};
    for (final relationship in relationships) {
      byPeer
          .putIfAbsent(relationship.peerPubkey, () => <Relationship>[])
          .add(relationship);
    }

    final groups = byPeer.entries
        .map(
          (entry) => RelationshipPeerGroup(
            peerPubkey: entry.key,
            relationships: entry.value,
          ),
        )
        .toList();
    groups
        .sort((a, b) => b.latestEstablishedAt.compareTo(a.latestEstablishedAt));
    return groups;
  }

  _ProjectedRelationship? _parseRelationshipEstablished(List<int> payload) {
    // Legacy payload:
    //   peer(32) + ownStarter(32) + peerStarter(32) + kind(1) = 97 bytes
    // Current payload adds provenance after the first 97 bytes:
    //   + invitationId(32) + senderPubkey(32) + senderStarterType(1) + senderStarterId(32)
    // Future payload revisions may append additional root-aware fields, but
    // projection keeps using the stable first 97 bytes for relationship anatomy.
    if (payload.length < 97) {
      return null;
    }

    return _ProjectedRelationship(
      peerPubkey: base64.encode(payload.sublist(0, 32)),
      ownStarterId: base64.encode(payload.sublist(32, 64)),
      peerStarterId: base64.encode(payload.sublist(64, 96)),
      kind: _support.starterKindFromByte(payload[96]),
    );
  }
}

class _ProjectedRelationship {
  final String peerPubkey;
  final String ownStarterId;
  final String peerStarterId;
  final StarterKind kind;

  const _ProjectedRelationship({
    required this.peerPubkey,
    required this.ownStarterId,
    required this.peerStarterId,
    required this.kind,
  });
}
