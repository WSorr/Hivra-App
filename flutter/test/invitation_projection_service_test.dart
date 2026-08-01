import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/invitation_projection_service.dart';

void main() {
  List<int> bytes(int value, int length) => List<int>.filled(length, value);

  Map<String, Object?> row({
    required int id,
    required String direction,
    required String status,
    required int sentAt,
  }) => <String, Object?>{
    'invitation_id': bytes(id, 32),
    'starter_id': bytes(id + 1, 32),
    'direction': direction,
    'from_pubkey': bytes(id + 2, 32),
    'from_root_pubkey': direction == 'incoming' ? bytes(id + 3, 32) : null,
    'from_card_signature': direction == 'incoming' ? bytes(id + 4, 64) : null,
    'to_pubkey': direction == 'outgoing' ? bytes(id + 5, 32) : null,
    'starter_kind': 1,
    'starter_slot': direction == 'outgoing' ? 2 : null,
    'status': status,
    'sent_at': sentAt,
    'responded_at': status == 'pending' ? null : sentAt + 10,
    'rejection_reason': status == 'rejected' ? 'empty_slot' : null,
  };

  String view(List<Map<String, Object?>> rows, {int version = 1}) =>
      jsonEncode(<String, Object?>{
        'schema': 'hivra.invitation_current_view',
        'version': version,
        'ledger_version': 9,
        'invitations': rows,
      });

  test('maps the canonical Core view without reading ledger events', () {
    final service = InvitationProjectionService(
      (_) => view(<Map<String, Object?>>[
        row(id: 1, direction: 'incoming', status: 'rejected', sentAt: 100),
        row(id: 11, direction: 'outgoing', status: 'pending', sentAt: 200),
      ]),
    );

    final invitations = service.loadInvitations(<String, dynamic>{
      'events': <Object>[
        <String, Object>{'kind': 'deliberately-not-interpreted'},
      ],
    });

    expect(invitations, hasLength(2));
    expect(invitations.first.isOutgoing, isTrue);
    expect(invitations.first.kind, StarterKind.spark);
    expect(invitations.first.starterSlot, 2);
    expect(invitations.last.isIncoming, isTrue);
    expect(invitations.last.status, InvitationStatus.rejected);
    expect(invitations.last.rejectionReason, RejectionReason.emptySlot);
    expect(invitations.last.fromRootPubkey, isNotNull);
    expect(invitations.last.fromCardSignatureHex, hasLength(128));
  });

  test('fails closed for an unknown projection version', () {
    final service = InvitationProjectionService(
      (_) => view(<Map<String, Object?>>[], version: 2),
    );

    expect(service.loadInvitations(<String, dynamic>{}), isEmpty);
  });

  test('fails closed for malformed projection JSON', () {
    final service = InvitationProjectionService((_) => '{not-json');

    expect(service.loadInvitations(<String, dynamic>{}), isEmpty);
  });

  test('drops malformed rows rather than inventing UI state', () {
    final malformed = row(
      id: 1,
      direction: 'outgoing',
      status: 'pending',
      sentAt: 100,
    )..['to_pubkey'] = null;
    final service = InvitationProjectionService(
      (_) => view(<Map<String, Object?>>[malformed]),
    );

    expect(service.loadInvitations(<String, dynamic>{}), isEmpty);
  });
}
