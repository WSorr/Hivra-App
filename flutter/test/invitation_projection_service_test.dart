import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/services/invitation_projection_service.dart';
import 'package:hivra_app/services/ledger_view_support.dart';

List<int> _bytes32(int seed) =>
    List<int>.generate(32, (i) => (seed + i) & 0xff);

List<int> _offerPayload({
  required List<int> invitationId,
  required List<int> starterId,
  required List<int> toPubkey,
  int kindByte = 0,
}) {
  return <int>[
    ...invitationId,
    ...starterId,
    ...toPubkey,
    kindByte,
  ];
}

List<int> _acceptedPayload({
  required List<int> invitationId,
  required List<int> createdStarterId,
  required List<int> fromPubkey,
}) {
  return <int>[
    ...invitationId,
    ...createdStarterId,
    ...fromPubkey,
  ];
}

List<int> _rejectedPayload({
  required List<int> invitationId,
  required int reason,
}) {
  return <int>[
    ...invitationId,
    reason,
  ];
}

Map<String, dynamic> _event({
  required String kind,
  required List<int> payload,
  required List<int> signer,
  required int timestamp,
}) {
  return <String, dynamic>{
    'kind': kind,
    'payload': payload,
    'signer': signer,
    'timestamp': timestamp,
  };
}

void main() {
  group('InvitationProjectionService', () {
    const support = LedgerViewSupport();
    final self = Uint8List.fromList(_bytes32(1));
    final peer = Uint8List.fromList(_bytes32(101));

    InvitationProjectionService serviceForSelf(Uint8List selfKey) {
      return InvitationProjectionService.withOwnerKeyProvider(
        () => selfKey,
        support,
      );
    }

    test(
        'does not classify self-addressed self-signed sent invitation as incoming',
        () {
      final invitationId = _bytes32(11);
      final starterId = _bytes32(31);
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 0,
            ),
            signer: self,
            timestamp: 1774827000000,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.isIncoming, isFalse);
      expect(invitations.single.isOutgoing, isTrue);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('classifies sent invitation to local capsule from peer as incoming',
        () {
      final invitationId = _bytes32(12);
      final starterId = _bytes32(32);
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 1,
            ),
            signer: peer,
            timestamp: 1774827001000,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.isIncoming, isTrue);
      expect(invitations.single.toPubkey, isNull);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('keeps invitation rejected after duplicate incoming offer replay', () {
      final invitationId = _bytes32(13);
      final starterId = _bytes32(33);
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationReceived',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 2,
            ),
            signer: peer,
            timestamp: 1774827002000,
          ),
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: 1774827003000,
          ),
          _event(
            kind: 'InvitationReceived',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 2,
            ),
            signer: peer,
            timestamp: 1774827004000,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.status, InvitationStatus.rejected);
      expect(invitation.rejectionReason, RejectionReason.emptySlot);
    });

    test('enforces terminal precedence accepted > rejected', () {
      final invitationId = _bytes32(14);
      final starterId = _bytes32(34);
      final createdStarterId = _bytes32(54);
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationReceived',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 3,
            ),
            signer: peer,
            timestamp: 1774827005000,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: self,
            timestamp: 1774827006000,
          ),
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: 1774827007000,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.accepted);
    });

    test('updates outgoing invitation to accepted when response arrives', () {
      final invitationId = _bytes32(15);
      final starterId = _bytes32(35);
      final createdStarterId = _bytes32(55);
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 4,
            ),
            signer: self,
            timestamp: 1774827008000,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: 1774827009000,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.isOutgoing, isTrue);
      expect(invitation.status, InvitationStatus.accepted);
    });
  });
}
