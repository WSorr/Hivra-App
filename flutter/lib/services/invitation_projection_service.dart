import 'dart:convert';
import 'dart:typed_data';

import '../models/invitation.dart';
import '../models/starter.dart';
import 'ledger_view_support.dart';

class InvitationProjectionService {
  final Uint8List? Function() _runtimeOwnerPublicKey;
  final Uint8List? Function()? _runtimeTransportPublicKey;
  final LedgerViewSupport _support;

  InvitationProjectionService.withOwnerKeyProvider(
    Uint8List? Function() runtimeOwnerPublicKey,
    this._support, {
    Uint8List? Function()? runtimeTransportPublicKey,
  })  : _runtimeOwnerPublicKey = runtimeOwnerPublicKey,
        _runtimeTransportPublicKey = runtimeTransportPublicKey;

  List<Invitation> loadInvitations(
    Map<String, dynamic> root, {
    List<Uint8List?> starterIds = const <Uint8List?>[],
  }) {
    final events = _support.events(root);
    final selfOwners = _resolveLocalOwners(root);
    final selfTransport = _resolveLocalTransport();
    if (selfOwners.isEmpty && selfTransport == null) return <Invitation>[];

    final starterKinds = <String, StarterKind>{};
    for (final e in events) {
      if (_support.kindCode(e['kind']) != 5) continue;
      final payload = _support.payloadBytes(e['payload']);
      if (payload.length != 66) continue;
      starterKinds[base64.encode(payload.sublist(0, 32))] =
          _support.starterKindFromByte(payload[64]);
    }

    final ownStarterBySlot = <int, Uint8List>{};
    for (var i = 0; i < starterIds.length; i++) {
      final id = starterIds[i];
      if (id != null) ownStarterBySlot[i] = id;
    }
    final localStarterIds = <String>{
      ...starterKinds.keys,
      ...ownStarterBySlot.values.map(base64.encode),
    };

    final offersById = <String, _ProjectedInvitationOffer>{};
    final acceptedAtById = <String, DateTime>{};
    final rejectedById = <String, ({DateTime at, RejectionReason reason})>{};
    final expiredAtById = <String, DateTime>{};

    for (final e in events) {
      final kind = _support.kindCode(e['kind']);
      final timestamp = _support.eventTime(e['timestamp']);
      final payload = _support.payloadBytes(e['payload']);

      if ((kind == 1 || kind == 9) &&
          (payload.length == 96 ||
              payload.length == 97 ||
              payload.length == 128 ||
              payload.length == 129)) {
        final signerBytes = _support.payloadBytes(e['signer']);
        if (signerBytes.length != 32) {
          continue;
        }
        final signer = Uint8List.fromList(signerBytes);
        final invitationId = payload.sublist(0, 32);
        final starterId = payload.sublist(32, 64);
        final toPubkey = payload.sublist(64, 96);
        final starterIdB64 = base64.encode(starterId);

        final hasKindByte = payload.length == 97 || payload.length == 129;
        final kindFromPayload = hasKindByte
            ? _support.starterKindFromByte(payload[payload.length - 1])
            : null;

        final id = base64.encode(invitationId);
        final current = offersById[id];
        final starterSlot =
            _support.slotForStarterId(starterId, ownStarterBySlot);
        final matchesOwnStarter = starterSlot != null;
        final localStarterKnownFromLedger =
            localStarterIds.contains(starterIdB64);
        final isIncomingByAddress = _matchesLocalIdentity(
          toPubkey,
          owners: selfOwners,
          transport: selfTransport,
        );
        final signerIsSelf = _matchesLocalIdentity(
          signer,
          owners: selfOwners,
          transport: selfTransport,
        );
        if (kind == 9) {
          // Ignore foreign or mirrored self-signed incoming rows.
          if (!isIncomingByAddress || signerIsSelf) {
            continue;
          }
        } else {
          // Receiver projection must be driven by InvitationReceived events.
          // Foreign InvitationSent rows addressed to local identity are
          // transport mirrors and are not actionable for accept/reject.
          if (isIncomingByAddress && !signerIsSelf) {
            continue;
          }
          final localOutgoingByIdentity = signerIsSelf;
          // Keep local outgoing events when signer identity is temporarily
          // unresolved, as long as invitation starter_id maps to own starter
          // slot or exists among local starter ids from ledger projection.
          // This avoids dropping local pending invites after capsule
          // restore/switch when runtime identity is transiently unavailable.
          final localOutgoingByStarter =
              matchesOwnStarter || localStarterKnownFromLedger;
          if (!localOutgoingByIdentity &&
              !localOutgoingByStarter &&
              !isIncomingByAddress) {
            // Ignore foreign outgoing-looking rows from merged/imported ledgers.
            continue;
          }
        }
        final isIncoming = kind == 9 || (isIncomingByAddress && !signerIsSelf);
        final candidateOffer = _ProjectedInvitationOffer(
          id: id,
          fromPubkey: base64.encode(signer),
          toPubkey: isIncoming ? null : base64.encode(toPubkey),
          kind: kindFromPayload ??
              starterKinds[starterIdB64] ??
              StarterKind.juice,
          starterSlot: isIncoming ? null : starterSlot,
          isIncoming: isIncoming,
          sentAt: timestamp,
        );
        if (current == null || timestamp.isBefore(current.sentAt)) {
          offersById[id] = candidateOffer;
        }
      } else if (kind == 2 && (payload.length == 96 || payload.length == 128)) {
        final signerBytes = _support.payloadBytes(e['signer']);
        if (signerBytes.length != 32) {
          continue;
        }
        final id = base64.encode(payload.sublist(0, 32));
        final existing = acceptedAtById[id];
        acceptedAtById[id] = existing == null || timestamp.isBefore(existing)
            ? timestamp
            : existing;
      } else if (kind == 3 && payload.length == 33) {
        final signerBytes = _support.payloadBytes(e['signer']);
        if (signerBytes.length != 32) {
          continue;
        }
        final id = base64.encode(payload.sublist(0, 32));
        final reason = payload[32] == 0
            ? RejectionReason.emptySlot
            : RejectionReason.other;
        final existing = rejectedById[id];
        rejectedById[id] = existing == null || timestamp.isBefore(existing.at)
            ? (at: timestamp, reason: reason)
            : existing;
      } else if (kind == 4 && payload.length == 32) {
        final signerBytes = _support.payloadBytes(e['signer']);
        if (signerBytes.length != 32) {
          continue;
        }
        final id = base64.encode(payload.sublist(0, 32));
        final existing = expiredAtById[id];
        expiredAtById[id] = existing == null || timestamp.isBefore(existing)
            ? timestamp
            : existing;
      }
    }

    final now = DateTime.now();
    final list = offersById.values.map((offer) {
      final expiresAt =
          offer.isIncoming ? null : offer.sentAt.add(const Duration(hours: 24));
      InvitationStatus status = InvitationStatus.pending;
      DateTime? respondedAt;
      RejectionReason? rejectionReason;
      if (acceptedAtById.containsKey(offer.id)) {
        status = InvitationStatus.accepted;
        respondedAt = acceptedAtById[offer.id];
      } else if (rejectedById.containsKey(offer.id)) {
        status = InvitationStatus.rejected;
        respondedAt = rejectedById[offer.id]!.at;
        rejectionReason = rejectedById[offer.id]!.reason;
      } else if (expiredAtById.containsKey(offer.id)) {
        status = InvitationStatus.expired;
        respondedAt = expiredAtById[offer.id];
      } else if (!offer.isIncoming &&
          expiresAt != null &&
          expiresAt.isBefore(now)) {
        status = InvitationStatus.expired;
        respondedAt = expiresAt;
      }
      return Invitation(
        id: offer.id,
        fromPubkey: offer.fromPubkey,
        toPubkey: offer.toPubkey,
        kind: offer.kind,
        starterSlot: offer.starterSlot,
        status: status,
        sentAt: offer.sentAt,
        expiresAt: expiresAt,
        respondedAt: respondedAt,
        rejectionReason: rejectionReason,
      );
    }).toList();
    list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  List<Uint8List> _resolveLocalOwners(Map<String, dynamic> root) {
    final owners = <Uint8List>[];
    final runtimeOwner = _runtimeOwnerPublicKey();
    if (runtimeOwner != null && runtimeOwner.length == 32) {
      owners.add(Uint8List.fromList(runtimeOwner));
    }
    final ledgerOwner = _support.payloadBytes(root['owner']);
    if (ledgerOwner.length == 32) {
      final owner = Uint8List.fromList(ledgerOwner);
      final exists = owners.any((existing) => _support.eq32(existing, owner));
      if (!exists) {
        owners.add(owner);
      }
    }
    return owners;
  }

  Uint8List? _resolveLocalTransport() {
    final runtimeTransport = _runtimeTransportPublicKey?.call();
    if (runtimeTransport != null && runtimeTransport.length == 32) {
      return Uint8List.fromList(runtimeTransport);
    }
    return null;
  }

  bool _matchesLocalIdentity(
    Uint8List key, {
    required List<Uint8List> owners,
    required Uint8List? transport,
  }) {
    for (final owner in owners) {
      if (_support.eq32(key, owner)) {
        return true;
      }
    }
    if (transport != null && _support.eq32(key, transport)) {
      return true;
    }
    return false;
  }
}

class _ProjectedInvitationOffer {
  final String id;
  final String fromPubkey;
  final String? toPubkey;
  final StarterKind kind;
  final int? starterSlot;
  final bool isIncoming;
  final DateTime sentAt;

  const _ProjectedInvitationOffer({
    required this.id,
    required this.fromPubkey,
    required this.toPubkey,
    required this.kind,
    required this.starterSlot,
    required this.isIncoming,
    required this.sentAt,
  });
}
