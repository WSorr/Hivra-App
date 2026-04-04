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
    final localOwner = _resolveLocalOwner(root);
    final peerRootByInvitationId =
        _collectPeerRootsByInvitationId(events, localOwner);
    final byKey = <String, Relationship>{};

    for (final e in events) {
      final kind = _support.kindCode(e['kind']);
      final payload = _support.payloadBytes(e['payload']);
      final timestamp = _support.eventTime(e['timestamp']);
      if (kind == 7) {
        final established = _parseRelationshipEstablished(payload);
        if (established == null) continue;
        final resolvedPeerRoot = established.peerRootPubkey ??
            (established.invitationId == null
                ? null
                : peerRootByInvitationId[established.invitationId!]);
        final key = _support.relationshipKeyFromEstablishedPayload(payload);
        if (key == null) continue;
        byKey[key] = Relationship(
          peerPubkey: established.peerPubkey,
          peerRootPubkey: resolvedPeerRoot,
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
            peerRootPubkey: current.peerRootPubkey,
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

  Map<String, String> _collectPeerRootsByInvitationId(
    List<dynamic> events,
    Uint8List? localOwner,
  ) {
    final map = <String, String>{};
    final hasLocalOwner = localOwner != null && localOwner.length == 32;
    for (final eventRaw in events) {
      if (eventRaw is! Map) continue;
      final event = Map<String, dynamic>.from(eventRaw);
      final kind = _support.kindCode(event['kind']);
      final payload = _support.payloadBytes(event['payload']);
      final signer = _support.bytes32(event['signer']);
      final signerMatchesLocal = hasLocalOwner &&
          signer.length == 32 &&
          _support.eq32(signer, localOwner);

      if (kind == 9 && (payload.length == 128 || payload.length == 129)) {
        if (signerMatchesLocal) {
          continue;
        }
        final invitationId = base64.encode(payload.sublist(0, 32));
        final senderRoot = base64.encode(payload.sublist(96, 128));
        map[invitationId] = senderRoot;
        continue;
      }

      if (kind == 2 && payload.length == 128) {
        if (!(hasLocalOwner && signer.length == 32 && !signerMatchesLocal)) {
          continue;
        }
        final invitationId = base64.encode(payload.sublist(0, 32));
        final accepterRoot = base64.encode(payload.sublist(96, 128));
        map[invitationId] = accepterRoot;
        continue;
      }

      if (kind == 7 && payload.length >= 226) {
        final invitationId = base64.encode(payload.sublist(97, 129));
        final peerRoot = base64.encode(payload.sublist(194, 226));
        map[invitationId] = peerRoot;
      }
    }
    return map;
  }

  Uint8List? _resolveLocalOwner(Map<String, dynamic> root) {
    final runtimeOwner = _runtimeOwnerPublicKey?.call();
    if (runtimeOwner != null && runtimeOwner.length == 32) {
      return Uint8List.fromList(runtimeOwner);
    }
    final ledgerOwner = _support.bytes32(root['owner']);
    if (ledgerOwner.length == 32) {
      return Uint8List.fromList(ledgerOwner);
    }
    return null;
  }

  List<RelationshipPeerGroup> loadRelationshipGroups(
      Map<String, dynamic> root) {
    final relationships = loadRelationships(root);
    final transportPeerToRootPeer = <String, String>{};
    for (final relationship in relationships) {
      final peerRoot = relationship.peerRootPubkey;
      if (peerRoot != null && peerRoot.isNotEmpty) {
        transportPeerToRootPeer[relationship.peerPubkey] = peerRoot;
      }
    }

    final byPeer = <String, List<Relationship>>{};
    final representativeByPeer = <String, Relationship>{};
    for (final relationship in relationships) {
      final peerIdentityKey = _canonicalPeerIdentityKey(
        relationship,
        transportPeerToRootPeer,
      );
      byPeer.putIfAbsent(peerIdentityKey, () => <Relationship>[]).add(
            relationship,
          );
      final currentRepresentative = representativeByPeer[peerIdentityKey];
      if (currentRepresentative == null ||
          relationship.establishedAt.isAfter(
            currentRepresentative.establishedAt,
          )) {
        representativeByPeer[peerIdentityKey] = relationship;
      }
    }

    final groups = byPeer.entries
        .map(
          (entry) => RelationshipPeerGroup(
            peerPubkey: representativeByPeer[entry.key]?.peerPubkey ??
                entry.value.first.peerPubkey,
            relationships: entry.value,
          ),
        )
        .toList();
    groups
        .sort((a, b) => b.latestEstablishedAt.compareTo(a.latestEstablishedAt));
    return groups;
  }

  String _canonicalPeerIdentityKey(
    Relationship relationship,
    Map<String, String> transportPeerToRootPeer,
  ) {
    final peerRoot = relationship.peerRootPubkey;
    if (peerRoot != null && peerRoot.isNotEmpty) {
      return peerRoot;
    }
    final mappedRoot = transportPeerToRootPeer[relationship.peerPubkey];
    if (mappedRoot != null && mappedRoot.isNotEmpty) {
      return mappedRoot;
    }
    return relationship.peerPubkey;
  }

  _ProjectedRelationship? _parseRelationshipEstablished(List<int> payload) {
    // Legacy payload:
    //   peer(32) + ownStarter(32) + peerStarter(32) + kind(1) = 97 bytes
    // Current payload adds provenance after the first 97 bytes:
    //   + invitationId(32) + senderPubkey(32) + senderStarterType(1) + senderStarterId(32)
    // Root-augmented payloads append:
    //   + peerRootPubkey(32) + senderRootPubkey(32)
    if (payload.length < 97) {
      return null;
    }

    return _ProjectedRelationship(
      peerPubkey: base64.encode(payload.sublist(0, 32)),
      invitationId: payload.length >= 129
          ? base64.encode(payload.sublist(97, 129))
          : null,
      peerRootPubkey: payload.length >= 226
          ? base64.encode(payload.sublist(194, 226))
          : null,
      ownStarterId: base64.encode(payload.sublist(32, 64)),
      peerStarterId: base64.encode(payload.sublist(64, 96)),
      kind: _support.starterKindFromByte(payload[96]),
    );
  }
}

class _ProjectedRelationship {
  final String peerPubkey;
  final String? invitationId;
  final String? peerRootPubkey;
  final String ownStarterId;
  final String peerStarterId;
  final StarterKind kind;

  const _ProjectedRelationship({
    required this.peerPubkey,
    this.invitationId,
    this.peerRootPubkey,
    required this.ownStarterId,
    required this.peerStarterId,
    required this.kind,
  });
}
