import 'dart:convert';

import '../models/invitation.dart';
import '../models/starter.dart';

typedef InvitationCurrentViewProjector = String? Function(String ledgerJson);

/// Maps the versioned Core invitation view into Flutter UI models.
///
/// Domain replay belongs to Core. This adapter must not inspect ledger events.
class InvitationProjectionService {
  final InvitationCurrentViewProjector _projectCurrentView;

  const InvitationProjectionService(this._projectCurrentView);

  List<Invitation> loadInvitations(Map<String, dynamic> ledgerRoot) {
    final projected = _projectCurrentView(jsonEncode(ledgerRoot));
    if (projected == null || projected.trim().isEmpty) {
      return <Invitation>[];
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(projected);
    } on FormatException {
      return <Invitation>[];
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'hivra.invitation_current_view' ||
        decoded['version'] != 1) {
      return <Invitation>[];
    }
    final rows = decoded['invitations'];
    if (rows is! List) return <Invitation>[];

    final invitations = <Invitation>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final invitationId = _bytes(row['invitation_id'], 32);
      final fromPubkey = _bytes(row['from_pubkey'], 32);
      if (invitationId == null || fromPubkey == null) continue;

      final direction = row['direction'];
      final toPubkey = _bytes(row['to_pubkey'], 32);
      if (direction != 'incoming' && direction != 'outgoing') continue;
      if (direction == 'outgoing' && toPubkey == null) continue;

      final status = switch (row['status']) {
        'pending' => InvitationStatus.pending,
        'accepted' => InvitationStatus.accepted,
        'rejected' => InvitationStatus.rejected,
        'expired' => InvitationStatus.expired,
        _ => null,
      };
      final starterKind = _starterKind(row['starter_kind']);
      final sentAt = _timestamp(row['sent_at']);
      if (status == null || starterKind == null || sentAt == null) continue;

      final respondedAt = _timestamp(row['responded_at']);
      final rejectionReason = switch (row['rejection_reason']) {
        'empty_slot' => RejectionReason.emptySlot,
        'other' => RejectionReason.other,
        _ => null,
      };
      final rootPubkey = _bytes(row['from_root_pubkey'], 32);
      final cardSignature = _bytes(row['from_card_signature'], 64);
      final starterSlot = row['starter_slot'];

      invitations.add(
        Invitation(
          id: base64.encode(invitationId),
          fromPubkey: base64.encode(fromPubkey),
          fromRootPubkey: rootPubkey == null ? null : base64.encode(rootPubkey),
          fromCardSignatureHex:
              cardSignature == null ? null : _hex(cardSignature),
          toPubkey: direction == 'incoming' ? null : base64.encode(toPubkey!),
          kind: starterKind,
          starterSlot:
              starterSlot is num && starterSlot >= 0 && starterSlot < 5
                  ? starterSlot.toInt()
                  : null,
          status: status,
          sentAt: sentAt,
          expiresAt: status == InvitationStatus.expired ? respondedAt : null,
          respondedAt: respondedAt,
          rejectionReason: rejectionReason,
        ),
      );
    }
    invitations.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return invitations;
  }

  List<int>? _bytes(Object? raw, int length) {
    if (raw is! List || raw.length != length) return null;
    final result = <int>[];
    for (final value in raw) {
      if (value is! num || value < 0 || value > 255) return null;
      result.add(value.toInt());
    }
    return result;
  }

  StarterKind? _starterKind(Object? raw) {
    if (raw is! num) return null;
    return switch (raw.toInt()) {
      0 => StarterKind.juice,
      1 => StarterKind.spark,
      2 => StarterKind.seed,
      3 => StarterKind.pulse,
      4 => StarterKind.kick,
      _ => null,
    };
  }

  DateTime? _timestamp(Object? raw) {
    if (raw is! num || raw <= 0) return null;
    final value = raw.toInt();
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
