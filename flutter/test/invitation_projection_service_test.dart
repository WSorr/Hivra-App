import 'dart:convert';
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

int _pastBaseTimestampMs() =>
    DateTime.now().subtract(const Duration(hours: 30)).millisecondsSinceEpoch;

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

    InvitationProjectionService serviceForIdentity({
      required Uint8List ownerKey,
      Uint8List? transportKey,
    }) {
      return InvitationProjectionService.withOwnerKeyProvider(
        () => ownerKey,
        support,
        runtimeTransportPublicKey:
            transportKey == null ? null : () => transportKey,
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

    test(
        'classifies sent invitation as incoming when addressed to local transport key',
        () {
      final localOwner = Uint8List.fromList(_bytes32(151));
      final localTransport = Uint8List.fromList(_bytes32(152));
      final invitationId = _bytes32(153);
      final starterId = _bytes32(154);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForIdentity(
        ownerKey: localOwner,
        transportKey: localTransport,
      );

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: localTransport,
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

    test(
        'keeps local outgoing when runtime owner is stale but ledger owner is current',
        () {
      final invitationId = _bytes32(123);
      final starterId = _bytes32(143);
      final staleRuntimeOwner = Uint8List.fromList(_bytes32(250));
      final t0 = _futureBaseTimestampMs();
      final service = serviceForIdentity(ownerKey: staleRuntimeOwner);

      final invitations = service.loadInvitations(<String, dynamic>{
        'owner': self.toList(),
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 2,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.isOutgoing, isTrue);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('ignores offer events with malformed or missing signer', () {
      final invitationId = _bytes32(124);
      final starterId = _bytes32(144);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'InvitationReceived',
            'payload': _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 1,
            ),
            // signer intentionally omitted
            'timestamp': t0 + 1,
          },
        ],
      });

      expect(invitations, isEmpty);
    });

    test('ignores foreign InvitationSent not addressed to local identity', () {
      final invitationId = _bytes32(125);
      final starterId = _bytes32(145);
      final foreignRecipient = Uint8List.fromList(_bytes32(205));
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: foreignRecipient,
              kindByte: 1,
            ),
            signer: peer,
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, isEmpty);
    });

    test(
        'keeps local outgoing InvitationSent when starter matches local slot and signer is unresolved',
        () {
      final invitationId = _bytes32(201);
      final localStarter = Uint8List.fromList(_bytes32(202));
      final foreignRecipient = Uint8List.fromList(_bytes32(203));
      final unresolvedSigner = Uint8List.fromList(_bytes32(204));
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(
        <String, dynamic>{
          'events': <Map<String, dynamic>>[
            _event(
              kind: 'InvitationSent',
              payload: _offerPayload(
                invitationId: invitationId,
                starterId: localStarter,
                toPubkey: foreignRecipient,
                kindByte: 1,
              ),
              signer: unresolvedSigner,
              timestamp: t0 + 1,
            ),
          ],
        },
        starterIds: <Uint8List?>[
          localStarter,
          null,
          null,
          null,
          null,
        ],
      );

      expect(invitations, hasLength(1));
      expect(invitations.single.isOutgoing, isTrue);
      expect(invitations.single.isIncoming, isFalse);
      expect(invitations.single.starterSlot, 0);
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('ignores InvitationReceived not addressed to local identity', () {
      final invitationId = _bytes32(126);
      final starterId = _bytes32(146);
      final foreignRecipient = Uint8List.fromList(_bytes32(206));
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationReceived',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: foreignRecipient,
              kindByte: 1,
            ),
            signer: peer,
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, isEmpty);
    });

    test('ignores self-signed InvitationReceived rows', () {
      final invitationId = _bytes32(127);
      final starterId = _bytes32(147);
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
              kindByte: 1,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
        ],
      });

      expect(invitations, isEmpty);
    });

    test(
      'does not project invitations when runtime owner unavailable and ledger owner is malformed',
      () {
        final invitationId = _bytes32(125);
        final starterId = _bytes32(145);
        final t0 = _futureBaseTimestampMs();
        final service = serviceWithoutRuntimeOwner();

        final invitations = service.loadInvitations(<String, dynamic>{
          'owner': 'not-a-valid-32-byte-owner',
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

        expect(invitations, isEmpty);
      },
    );

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

    test('keeps accepted precedence regardless terminal event order', () {
      final invitationId = _bytes32(240);
      final starterId = _bytes32(241);
      final createdStarterId = _bytes32(242);
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
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: peer,
            timestamp: t0 + 2,
          ),
          _event(
            kind: 'InvitationExpired',
            payload: invitationId,
            signer: self,
            timestamp: t0 + 3,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 4,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.accepted);
    });

    test('uses earliest accepted timestamp across duplicate accepted events',
        () {
      final invitationId = _bytes32(243);
      final starterId = _bytes32(244);
      final createdStarterIdA = _bytes32(245);
      final createdStarterIdB = _bytes32(246);
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
              createdStarterId: createdStarterIdA,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 5,
          ),
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterIdB,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 3,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.accepted);
      expect(
        invitations.single.respondedAt,
        equals(DateTime.fromMillisecondsSinceEpoch(t0 + 3)),
      );
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

    test('ignores accepted event with malformed signer and keeps pending', () {
      final invitationId = _bytes32(247);
      final starterId = _bytes32(248);
      final createdStarterId = _bytes32(249);
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
          <String, dynamic>{
            'kind': 'InvitationAccepted',
            'payload': _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            'signer': 'invalid-signer',
            'timestamp': t0 + 2,
          },
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('ignores rejected event with malformed signer and keeps pending', () {
      final invitationId = _bytes32(250);
      final starterId = _bytes32(251);
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
              kindByte: 1,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
          <String, dynamic>{
            'kind': 'InvitationRejected',
            'payload': _rejectedPayload(invitationId: invitationId, reason: 0),
            'signer': 12345,
            'timestamp': t0 + 2,
          },
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('ignores expired event with malformed signer and keeps pending', () {
      final invitationId = _bytes32(252);
      final starterId = _bytes32(253);
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
              kindByte: 2,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
          <String, dynamic>{
            'kind': 'InvitationExpired',
            'payload': invitationId,
            'signer': null,
            'timestamp': t0 + 2,
          },
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.pending);
    });

    test('applies accepted even when terminal arrives before local offer', () {
      final invitationId = _bytes32(215);
      final starterId = _bytes32(216);
      final createdStarterId = _bytes32(217);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationAccepted',
            payload: _acceptedPayload(
              invitationId: invitationId,
              createdStarterId: createdStarterId,
              fromPubkey: peer,
            ),
            signer: peer,
            timestamp: t0 + 1,
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
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.accepted);
    });

    test('applies rejected even when terminal arrives before local offer', () {
      final invitationId = _bytes32(218);
      final starterId = _bytes32(219);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationRejected',
            payload: _rejectedPayload(invitationId: invitationId, reason: 0),
            signer: self,
            timestamp: t0 + 1,
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
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.rejected);
    });

    test('applies expired even when terminal arrives before local offer', () {
      final invitationId = _bytes32(220);
      final starterId = _bytes32(221);
      final t0 = _futureBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationExpired',
            payload: invitationId,
            signer: self,
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: invitationId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 2,
            ),
            signer: self,
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(1));
      expect(invitations.single.status, InvitationStatus.expired);
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

    test(
        'auto-expire timeout applies to overdue outgoing only, not overdue incoming',
        () {
      final outgoingId = _bytes32(201);
      final incomingId = _bytes32(202);
      final starterId = _bytes32(203);
      final t0 = _pastBaseTimestampMs();
      final service = serviceForSelf(self);

      final invitations = service.loadInvitations(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          _event(
            kind: 'InvitationSent',
            payload: _offerPayload(
              invitationId: outgoingId,
              starterId: starterId,
              toPubkey: peer,
              kindByte: 1,
            ),
            signer: self,
            timestamp: t0 + 1,
          ),
          _event(
            kind: 'InvitationReceived',
            payload: _offerPayload(
              invitationId: incomingId,
              starterId: starterId,
              toPubkey: self,
              kindByte: 1,
            ),
            signer: peer,
            timestamp: t0 + 2,
          ),
        ],
      });

      expect(invitations, hasLength(2));
      final outgoing =
          invitations.firstWhere((inv) => inv.id == _id(outgoingId));
      final incoming =
          invitations.firstWhere((inv) => inv.id == _id(incomingId));

      expect(outgoing.isOutgoing, isTrue);
      expect(outgoing.status, InvitationStatus.expired);
      expect(outgoing.expiresAt, isNotNull);

      expect(incoming.isIncoming, isTrue);
      expect(incoming.status, InvitationStatus.pending);
      expect(incoming.expiresAt, isNull);
    });
  });
}

String _id(List<int> bytes) => _base64(bytes);

String _base64(List<int> bytes) => base64.encode(bytes);
