import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/invitation_projection_service.dart';
import 'package:hivra_app/services/ledger_view_support.dart';

List<int> _bytes32(int seed) =>
    List<int>.generate(32, (i) => (seed + i) & 0xff);

List<int> _offerPayload({
  required List<int> invitationId,
  required List<int> starterId,
  required List<int> toPubkey,
  List<int>? senderRootPubkey,
  int? kindByte = 0,
}) {
  return <int>[
    ...invitationId,
    ...starterId,
    ...toPubkey,
    if (senderRootPubkey != null) ...senderRootPubkey,
    if (kindByte != null) kindByte,
  ];
}

List<int> _acceptedPayload({
  required List<int> invitationId,
  required List<int> createdStarterId,
  required List<int> fromPubkey,
  List<int>? accepterRootPubkey,
}) {
  return <int>[
    ...invitationId,
    ...createdStarterId,
    ...fromPubkey,
    if (accepterRootPubkey != null) ...accepterRootPubkey,
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

int _futureBaseTimestampMs() =>
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;

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

    InvitationProjectionService serviceWithoutRuntimeOwner() {
      return InvitationProjectionService.withOwnerKeyProvider(
        () => null,
        support,
      );
    }

    test(
        'does not classify self-addressed self-signed sent invitation as incoming',
        () {
      final invitationId = _bytes32(11);
      final starterId = _bytes32(31);
      final t0 = _futureBaseTimestampMs();
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
            timestamp: t0 + 1,
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
      final t0 = _futureBaseTimestampMs();
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
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.isIncoming, isTrue);
      expect(invitations.single.toPubkey, isNull);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('falls back to ledger owner when runtime owner is unavailable', () {
      final invitationId = _bytes32(122);
      final starterId = _bytes32(142);
      final t0 = _futureBaseTimestampMs();
      final service = serviceWithoutRuntimeOwner();

      final invitations = service.loadInvitations(<String, dynamic>{
        'owner': self.toList(),
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
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.isIncoming, isTrue);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('keeps invitation rejected after duplicate incoming offer replay', () {
      final invitationId = _bytes32(13);
      final starterId = _bytes32(33);
      final t0 = _futureBaseTimestampMs();
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
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: t0 + 2,
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
            timestamp: t0 + 3,
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
      final t0 = _futureBaseTimestampMs();
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
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: self,
            timestamp: t0 + 2,
          ),
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: t0 + 3,
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
      final t0 = _futureBaseTimestampMs();
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
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.isOutgoing, isTrue);
      expect(invitation.status, InvitationStatus.accepted);
    });

    test(
        'restore fallback keeps resolved outgoing invitation accepted after replayed offer',
        () {
      final invitationId = _bytes32(115);
      final starterId = _bytes32(135);
      final createdStarterId = _bytes32(155);
      final t0 = _futureBaseTimestampMs();
      final service = serviceWithoutRuntimeOwner();

      final invitations = service.loadInvitations(<String, dynamic>{
        'owner': self.toList(),
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
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 2,
          ),
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 4,
            ),
            signer: self,
            timestamp: t0 + 3,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.isOutgoing, isTrue);
      expect(invitation.status, InvitationStatus.accepted);
    });

    test(
        'restore fallback keeps rejected incoming invitation rejected after replayed offer',
        () {
      final invitationId = _bytes32(116);
      final starterId = _bytes32(136);
      final t0 = _futureBaseTimestampMs();
      final service = serviceWithoutRuntimeOwner();

      final invitations = service.loadInvitations(<String, dynamic>{
        'owner': self.toList(),
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
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: t0 + 2,
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
            timestamp: t0 + 3,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.isIncoming, isTrue);
      expect(invitation.status, InvitationStatus.rejected);
      expect(invitation.rejectionReason, RejectionReason.emptySlot);
    });

    test(
        'restore fallback keeps expired outgoing invitation expired after replayed offer',
        () {
      final invitationId = _bytes32(117);
      final starterId = _bytes32(137);
      final t0 = _futureBaseTimestampMs();
      final service = serviceWithoutRuntimeOwner();

      final invitations = service.loadInvitations(<String, dynamic>{
        'owner': self.toList(),
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 1,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationExpired',
            payload: invitationId,
            signer: self,
            timestamp: t0 + 2,
          ),
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 1,
            ),
            signer: self,
            timestamp: t0 + 3,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      final invitation = invitations.single;
      expect(invitation.isOutgoing, isTrue);
      expect(invitation.status, InvitationStatus.expired);
    });

    test('supports root-augmented invitation payload variants', () {
      final invitationId = _bytes32(16);
      final starterId = _bytes32(36);
      final createdStarterId = _bytes32(56);
      final senderRoot = _bytes32(66);
      final accepterRoot = _bytes32(76);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              senderRootPubkey: senderRoot,
              kindByte: 4,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
              accepterRootPubkey: accepterRoot,
            ),
            signer: peer,
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.accepted);
      expect(invitations.single.kind, StarterKind.kick);
    });
  });
}
