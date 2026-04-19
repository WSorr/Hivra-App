import 'dart:convert';
import 'dart:typed_data';

import '../models/relationship_peer_group.dart';
import '../models/relationship.dart';
import '../models/starter.dart';
import 'ledger_view_support.dart';

class RelationshipProjectionService {
  final LedgerViewSupport _support;
  final Uint8List? Function()? _runtimeOwnerPublicKey;
  final Uint8List? Function()? _runtimeTransportPublicKey;

  const RelationshipProjectionService(
    this._support, {
    Uint8List? Function()? runtimeOwnerPublicKey,
    Uint8List? Function()? runtimeTransportPublicKey,
  })  : _runtimeOwnerPublicKey = runtimeOwnerPublicKey,
        _runtimeTransportPublicKey = runtimeTransportPublicKey;

  RelationshipProjectionService.withOwnerKeyProvider(
    Uint8List? Function() runtimeOwnerPublicKey,
    this._support, {
    Uint8List? Function()? runtimeTransportPublicKey,
  })  : _runtimeOwnerPublicKey = runtimeOwnerPublicKey,
        _runtimeTransportPublicKey = runtimeTransportPublicKey;

  List<Relationship> loadRelationships(Map<String, dynamic> root) {
    final events = _support.events(root);
    final localOwner = _resolveLocalOwner(root);
    final localTransport = _resolveLocalTransport();
    final localOwnerB64 = localOwner == null ? null : base64.encode(localOwner);
    final localTransportB64 =
        localTransport == null ? null : base64.encode(localTransport);
    final peerRootByInvitationId =
        _collectPeerRootsByInvitationId(events, localOwner, localTransport);
    final byKey = <String, Relationship>{};

    for (final e in events) {
      final kind = _support.kindCode(e['kind']);
      final payload = _support.payloadBytes(e['payload']);
      final timestamp = _support.eventTime(e['timestamp']);
      if (kind == 7) {
        final established = _parseRelationshipEstablished(payload);
        if (established == null) continue;
        final oriented = _orientEstablishedForLocal(
          established,
          localOwnerB64: localOwnerB64,
        );
        final resolvedPeerRoot = oriented.peerRootPubkey ??
            (oriented.invitationId == null
                ? null
                : peerRootByInvitationId[oriented.invitationId!]);
        if (localOwnerB64 != null && resolvedPeerRoot == localOwnerB64) {
          // Ignore mirrored self-looking records from remote payload orientation.
          continue;
        }
        if (localTransportB64 != null &&
            oriented.peerPubkey == localTransportB64) {
          // Ignore transport-self relationships (for mixed root/transport ledgers).
          continue;
        }
        final key = '${oriented.peerPubkey}:${oriented.ownStarterId}';
        byKey[key] = Relationship(
          peerPubkey: oriented.peerPubkey,
          peerRootPubkey: resolvedPeerRoot,
          kind: oriented.kind,
          ownStarterId: oriented.ownStarterId,
          peerStarterId: oriented.peerStarterId,
          establishedAt: timestamp,
          isActive: true,
          hasPendingRemoteBreak: false,
        );
      } else if (kind == 8) {
        final key = _support.relationshipKeyFromBrokenPayload(payload);
        if (key == null) continue;
        final current = byKey[key];
        if (current != null) {
          final signerBytes = _support.payloadBytes(e['signer']);
          final signerIsValid = signerBytes.length == 32;
          final signer =
              signerIsValid ? Uint8List.fromList(signerBytes) : Uint8List(0);
          final hasLocalOwner = localOwner != null && localOwner.length == 32;
          final hasLocalTransport =
              localTransport != null && localTransport.length == 32;
          final hasLocalIdentity = hasLocalOwner || hasLocalTransport;
          if (hasLocalIdentity && !signerIsValid) {
            // Without signer we cannot deterministically classify this break as
            // local-finalized vs remote-pending.
            continue;
          }
          final signerMatchesLocalOwner = hasLocalOwner &&
              signerIsValid &&
              _support.eq32(signer, localOwner);
          final signerMatchesLocalTransport = hasLocalTransport &&
              signerIsValid &&
              _support.eq32(signer, localTransport);
          final signerMatchesLocal =
              signerMatchesLocalOwner || signerMatchesLocalTransport;
          final peerTransport = _decodeB64_32(current.peerPubkey);
          final signerMatchesPeerTransport = signerIsValid &&
              peerTransport != null &&
              _support.eq32(signer, peerTransport);
          if (hasLocalIdentity &&
              signerIsValid &&
              !signerMatchesLocal &&
              !signerMatchesPeerTransport) {
            // Foreign signer cannot deterministically mutate local pairwise
            // break state when local identity is known.
            continue;
          }
          if (timestamp.isBefore(current.establishedAt)) {
            // A break older than the currently projected relationship episode
            // is stale replay noise and must not reopen pending/final break.
            continue;
          }
          final isPendingRemoteBreak = signerIsValid &&
              !signerMatchesLocal &&
              (signerMatchesPeerTransport || hasLocalIdentity);
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
    Uint8List? localTransport,
  ) {
    final map = <String, String>{};
    final hasLocalOwner = localOwner != null && localOwner.length == 32;
    final localOwnerB64 = hasLocalOwner ? base64.encode(localOwner) : null;
    final hasLocalTransport =
        localTransport != null && localTransport.length == 32;
    final localTransportB64 =
        hasLocalTransport ? base64.encode(localTransport) : null;
    final offerLineageIds = <String>{};

    for (final eventRaw in events) {
      if (eventRaw is! Map) continue;
      final event = Map<String, dynamic>.from(eventRaw);
      final kind = _support.kindCode(event['kind']);
      final payload = _support.payloadBytes(event['payload']);
      if ((kind != 1 && kind != 9) || payload.length < 96) {
        continue;
      }

      final signerBytes = _support.payloadBytes(event['signer']);
      final signerIsValid = signerBytes.length == 32;
      if (!signerIsValid) continue;
      final signer = Uint8List.fromList(signerBytes);
      final signerMatchesLocal =
          hasLocalOwner && _support.eq32(signer, localOwner);
      final toPubkey = base64.encode(payload.sublist(64, 96));

      if (kind == 1) {
        if (!signerMatchesLocal) continue;
      } else {
        if (signerMatchesLocal) continue;
        if (!_isAddressedToLocalIdentity(
          toPubkey: toPubkey,
          localOwnerB64: localOwnerB64,
          localTransportB64: localTransportB64,
        )) {
          continue;
        }
      }

      final invitationId = base64.encode(payload.sublist(0, 32));
      offerLineageIds.add(invitationId);
    }

    for (final eventRaw in events) {
      if (eventRaw is! Map) continue;
      final event = Map<String, dynamic>.from(eventRaw);
      final kind = _support.kindCode(event['kind']);
      final payload = _support.payloadBytes(event['payload']);
      final signerBytes = _support.payloadBytes(event['signer']);
      final signerIsValid = signerBytes.length == 32;
      final signer = signerIsValid
          ? Uint8List.fromList(signerBytes)
          : Uint8List(0);
      final signerMatchesLocal = hasLocalOwner &&
          signerIsValid &&
          _support.eq32(signer, localOwner);

      if (kind == 9 && (payload.length == 128 || payload.length == 129)) {
        if (!signerIsValid || signerMatchesLocal) {
          continue;
        }
        final toPubkey = base64.encode(payload.sublist(64, 96));
        if (!_isAddressedToLocalIdentity(
          toPubkey: toPubkey,
          localOwnerB64: localOwnerB64,
          localTransportB64: localTransportB64,
        )) {
          continue;
        }
        final invitationId = base64.encode(payload.sublist(0, 32));
        final senderRoot = base64.encode(payload.sublist(96, 128));
        map[invitationId] = senderRoot;
        continue;
      }

      if (kind == 2 && payload.length == 128) {
        if (localTransportB64 == null) {
          continue;
        }
        final fromPubkey = base64.encode(payload.sublist(32, 64));
        if (fromPubkey != localTransportB64) {
          continue;
        }
        final invitationId = base64.encode(payload.sublist(0, 32));
        if (!offerLineageIds.contains(invitationId)) {
          continue;
        }
        if (!(hasLocalOwner && signerIsValid && !signerMatchesLocal)) {
          continue;
        }
        final accepterRoot = base64.encode(payload.sublist(96, 128));
        map[invitationId] = accepterRoot;
        continue;
      }

      if (kind == 7 && payload.length >= 226) {
        final invitationId = base64.encode(payload.sublist(97, 129));
        final peerRoot = base64.encode(payload.sublist(194, 226));
        final senderRoot = payload.length >= 258
            ? base64.encode(payload.sublist(226, 258))
            : null;
        final resolvedPeerRoot = _resolvePeerRootForLocal(
          peerRootPubkey: peerRoot,
          senderRootPubkey: senderRoot,
          localOwnerB64: localOwnerB64,
        );
        if (resolvedPeerRoot == null || resolvedPeerRoot.isEmpty) {
          continue;
        }
        map[invitationId] = resolvedPeerRoot;
      }
    }
    return map;
  }

  bool _isAddressedToLocalIdentity({
    required String toPubkey,
    required String? localOwnerB64,
    required String? localTransportB64,
  }) {
    if (localTransportB64 != null && toPubkey == localTransportB64) {
      return true;
    }
    if (localOwnerB64 != null && toPubkey == localOwnerB64) {
      return true;
    }
    return false;
  }

  _ProjectedRelationship _orientEstablishedForLocal(
    _ProjectedRelationship established, {
    required String? localOwnerB64,
  }) {
    if (localOwnerB64 == null) {
      return established;
    }
    final resolvedPeerRoot = _resolvePeerRootForLocal(
      peerRootPubkey: established.peerRootPubkey,
      senderRootPubkey: established.senderRootPubkey,
      localOwnerB64: localOwnerB64,
    );
    final shouldSwapToSender = established.peerRootPubkey != null &&
        established.senderRootPubkey != null &&
        established.peerRootPubkey == localOwnerB64 &&
        established.senderRootPubkey != localOwnerB64 &&
        established.senderPubkey != null;

    if (!shouldSwapToSender) {
      return _ProjectedRelationship(
        peerPubkey: established.peerPubkey,
        senderPubkey: established.senderPubkey,
        invitationId: established.invitationId,
        peerRootPubkey: resolvedPeerRoot,
        senderRootPubkey: established.senderRootPubkey,
        ownStarterId: established.ownStarterId,
        peerStarterId: established.peerStarterId,
        senderStarterId: established.senderStarterId,
        kind: established.kind,
      );
    }

    return _ProjectedRelationship(
      peerPubkey: established.senderPubkey!,
      senderPubkey: established.peerPubkey,
      invitationId: established.invitationId,
      peerRootPubkey: resolvedPeerRoot,
      senderRootPubkey: established.peerRootPubkey,
      ownStarterId: established.peerStarterId,
      peerStarterId: established.ownStarterId,
      senderStarterId: established.senderStarterId,
      kind: established.kind,
    );
  }

  String? _resolvePeerRootForLocal({
    required String? peerRootPubkey,
    required String? senderRootPubkey,
    required String? localOwnerB64,
  }) {
    if (peerRootPubkey == null || peerRootPubkey.isEmpty) {
      return senderRootPubkey;
    }
    if (localOwnerB64 == null) return peerRootPubkey;
    if (senderRootPubkey != null &&
        senderRootPubkey.isNotEmpty &&
        peerRootPubkey == localOwnerB64 &&
        senderRootPubkey != localOwnerB64) {
      return senderRootPubkey;
    }
    if (senderRootPubkey != null &&
        senderRootPubkey.isNotEmpty &&
        senderRootPubkey == localOwnerB64 &&
        peerRootPubkey != localOwnerB64) {
      return peerRootPubkey;
    }
    return peerRootPubkey;
  }

  Uint8List? _resolveLocalOwner(Map<String, dynamic> root) {
    final runtimeOwner = _runtimeOwnerPublicKey?.call();
    if (runtimeOwner != null && runtimeOwner.length == 32) {
      return Uint8List.fromList(runtimeOwner);
    }
    final ledgerOwner = _support.payloadBytes(root['owner']);
    if (ledgerOwner.length == 32) {
      return Uint8List.fromList(ledgerOwner);
    }
    return null;
  }

  Uint8List? _resolveLocalTransport() {
    final runtimeTransport = _runtimeTransportPublicKey?.call();
    if (runtimeTransport != null && runtimeTransport.length == 32) {
      return Uint8List.fromList(runtimeTransport);
    }
    return null;
  }

  Uint8List? _decodeB64_32(String value) {
    try {
      final bytes = base64.decode(value);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
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
      senderPubkey: payload.length >= 161
          ? base64.encode(payload.sublist(129, 161))
          : null,
      invitationId: payload.length >= 129
          ? base64.encode(payload.sublist(97, 129))
          : null,
      peerRootPubkey: payload.length >= 226
          ? base64.encode(payload.sublist(194, 226))
          : null,
      senderRootPubkey: payload.length >= 258
          ? base64.encode(payload.sublist(226, 258))
          : null,
      ownStarterId: base64.encode(payload.sublist(32, 64)),
      peerStarterId: base64.encode(payload.sublist(64, 96)),
      senderStarterId: payload.length >= 194
          ? base64.encode(payload.sublist(162, 194))
          : null,
      kind: _support.starterKindFromByte(payload[96]),
    );
  }
}

class _ProjectedRelationship {
  final String peerPubkey;
  final String? senderPubkey;
  final String? invitationId;
  final String? peerRootPubkey;
  final String? senderRootPubkey;
  final String ownStarterId;
  final String peerStarterId;
  final String? senderStarterId;
  final StarterKind kind;

  const _ProjectedRelationship({
    required this.peerPubkey,
    this.senderPubkey,
    this.invitationId,
    this.peerRootPubkey,
    this.senderRootPubkey,
    required this.ownStarterId,
    required this.peerStarterId,
    this.senderStarterId,
    required this.kind,
  });
}
