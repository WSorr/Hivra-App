import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/services/capsule_ledger_summary_parser.dart';
import 'package:hivra_app/services/invitation_projection_service.dart';
import 'package:hivra_app/services/ledger_view_support.dart';
import 'package:hivra_app/services/relationship_projection_service.dart';

void main() {
  group('CapsuleLedgerSummaryParser', () {
    const parser = CapsuleLedgerSummaryParser();

    String toHex(Uint8List bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    List<int> rep(int value) => List<int>.filled(32, value);

    List<int> invitationSentPayload({
      required int invitationByte,
      required int starterByte,
      required List<int> toPubkey,
      int starterKindByte = 0,
    }) {
      return <int>[
        ...rep(invitationByte),
        ...rep(starterByte),
        ...toPubkey,
        starterKindByte,
      ];
    }

    List<int> invitationAcceptedPayload({
      required int invitationByte,
      required int fromByte,
      required int createdStarterByte,
    }) {
      return <int>[
        ...rep(invitationByte),
        ...rep(fromByte),
        ...rep(createdStarterByte),
      ];
    }

    List<int> invitationRejectedPayload({
      required int invitationByte,
      int reason = 1,
    }) {
      return <int>[
        ...rep(invitationByte),
        reason,
      ];
    }

    List<int> invitationExpiredPayload({
      required int invitationByte,
    }) {
      return rep(invitationByte);
    }

    List<int> starterCreatedPayload({
      required int starterByte,
      required int kindByte,
    }) {
      return <int>[
        ...rep(starterByte),
        ...rep(0xee),
        kindByte,
        0,
      ];
    }

    List<int> starterBurnedPayload({
      required int starterByte,
    }) {
      return rep(starterByte);
    }

    List<int> relationshipEstablishedPayload({
      required int peerByte,
      required int ownStarterByte,
      required int peerStarterByte,
      required int kindByte,
      required int invitationByte,
      required int senderByte,
      required int senderStarterByte,
    }) {
      return <int>[
        ...rep(peerByte),
        ...rep(ownStarterByte),
        ...rep(peerStarterByte),
        kindByte,
        ...rep(invitationByte),
        ...rep(senderByte),
        kindByte,
        ...rep(senderStarterByte),
      ];
    }

    List<int> relationshipBrokenPayload({
      required int peerByte,
      required int ownStarterByte,
    }) {
      return <int>[
        ...rep(peerByte),
        ...rep(ownStarterByte),
      ];
    }

    List<int> relationshipEstablishedPayloadWithRoots({
      required int peerByte,
      required int ownStarterByte,
      required int peerStarterByte,
      required int kindByte,
      required int invitationByte,
      required int senderByte,
      required int senderStarterByte,
      required int peerRootByte,
      required int senderRootByte,
    }) {
      return <int>[
        ...relationshipEstablishedPayload(
          peerByte: peerByte,
          ownStarterByte: ownStarterByte,
          peerStarterByte: peerStarterByte,
          kindByte: kindByte,
          invitationByte: invitationByte,
          senderByte: senderByte,
          senderStarterByte: senderStarterByte,
        ),
        ...rep(peerRootByte),
        ...rep(senderRootByte),
      ];
    }

    Map<String, dynamic> event({
      required String kind,
      required List<int> payload,
      required int timestamp,
      required List<int> signer,
    }) {
      return <String, dynamic>{
        'kind': kind,
        'payload': payload,
        'timestamp': timestamp,
        'signer': signer,
      };
    }

    test('pending count follows invitation terminal precedence', () {
      final self = rep(0xaa);
      final peer = rep(0xbb);
      final otherPeer = rep(0xcc);
      const t0 = 1800000000000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x11,
              starterByte: 0x21,
              toPubkey: peer,
            ),
            timestamp: t0 + 1,
            signer: self,
          ),
          event(
            kind: 'InvitationAccepted',
            payload: invitationAcceptedPayload(
              invitationByte: 0x11,
              fromByte: 0xbb,
              createdStarterByte: 0x31,
            ),
            timestamp: t0 + 2,
            signer: peer,
          ),
          event(
            kind: 'InvitationRejected',
            payload: invitationRejectedPayload(invitationByte: 0x11),
            timestamp: t0 + 3,
            signer: peer,
          ),
          event(
            kind: 'InvitationExpired',
            payload: invitationExpiredPayload(invitationByte: 0x11),
            timestamp: t0 + 4,
            signer: peer,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x12,
              starterByte: 0x22,
              toPubkey: otherPeer,
            ),
            timestamp: t0 + 5,
            signer: self,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.pendingInvitations, equals(1));
    });

    test('pending count includes incoming invitation offers', () {
      final self = rep(0xaa);
      final peer = rep(0xbb);
      const t0 = 1800000100000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x13,
              starterByte: 0x23,
              toPubkey: self,
            ),
            timestamp: t0 + 1,
            signer: peer,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.pendingInvitations, equals(1));
    });

    test('parseBytesField decodes hex and base64 payload strings', () {
      expect(parser.parseBytesField('0a0b0c'), equals(<int>[10, 11, 12]));
      expect(parser.parseBytesField('AQID'), equals(<int>[1, 2, 3]));
    });

    test('parseBytesField preserves empty list and rejects invalid values', () {
      expect(parser.parseBytesField(<int>[]), equals(<int>[]));
      expect(parser.parseBytesField(<dynamic>[1, 300]), isNull);
      expect(parser.parseBytesField(''), isNull);
      expect(parser.parseBytesField(42), isNull);
    });

    test(
        'update safety fixture keeps counters stable and aligned with projections',
        () {
      const support = LedgerViewSupport();
      final self = rep(0xaa);
      final relationshipProjection =
          RelationshipProjectionService.withOwnerKeyProvider(
        () => Uint8List.fromList(self),
        support,
      );
      final peerA = rep(0xbb);
      final peerB = rep(0xcc);
      const t0 = 1890000000000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'last_hash': '0xabc123',
        'events': <Map<String, dynamic>>[
          event(
            kind: 'StarterCreated',
            payload: starterCreatedPayload(starterByte: 0x21, kindByte: 1),
            timestamp: t0 + 1,
            signer: self,
          ),
          event(
            kind: 'StarterCreated',
            payload: starterCreatedPayload(starterByte: 0x22, kindByte: 2),
            timestamp: t0 + 2,
            signer: self,
          ),
          event(
            kind: 'StarterCreated',
            payload: starterCreatedPayload(starterByte: 0x23, kindByte: 3),
            timestamp: t0 + 3,
            signer: self,
          ),
          event(
            kind: 'StarterCreated',
            payload: starterCreatedPayload(starterByte: 0x24, kindByte: 4),
            timestamp: t0 + 4,
            signer: self,
          ),
          event(
            kind: 'StarterBurned',
            payload: starterBurnedPayload(starterByte: 0x22),
            timestamp: t0 + 5,
            signer: self,
          ),
          event(
            kind: 'RelationshipEstablished',
            payload: relationshipEstablishedPayload(
              peerByte: 0xbb,
              ownStarterByte: 0x21,
              peerStarterByte: 0x31,
              kindByte: 1,
              invitationByte: 0x41,
              senderByte: 0xbb,
              senderStarterByte: 0x61,
            ),
            timestamp: t0 + 6,
            signer: self,
          ),
          event(
            kind: 'RelationshipEstablished',
            payload: relationshipEstablishedPayload(
              peerByte: 0xcc,
              ownStarterByte: 0x23,
              peerStarterByte: 0x32,
              kindByte: 2,
              invitationByte: 0x42,
              senderByte: 0xcc,
              senderStarterByte: 0x62,
            ),
            timestamp: t0 + 7,
            signer: self,
          ),
          event(
            kind: 'RelationshipBroken',
            payload:
                relationshipBrokenPayload(peerByte: 0xbb, ownStarterByte: 0x21),
            timestamp: t0 + 8,
            signer: self,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x51,
              starterByte: 0x21,
              toPubkey: peerA,
              starterKindByte: 1,
            ),
            timestamp: t0 + 9,
            signer: self,
          ),
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x52,
              starterByte: 0x31,
              toPubkey: self,
              starterKindByte: 2,
            ),
            timestamp: t0 + 10,
            signer: peerA,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x53,
              starterByte: 0x23,
              toPubkey: peerB,
              starterKindByte: 3,
            ),
            timestamp: t0 + 11,
            signer: self,
          ),
          event(
            kind: 'InvitationAccepted',
            payload: invitationAcceptedPayload(
              invitationByte: 0x53,
              fromByte: 0xcc,
              createdStarterByte: 0x73,
            ),
            timestamp: t0 + 12,
            signer: peerB,
          ),
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x54,
              starterByte: 0x32,
              toPubkey: self,
              starterKindByte: 4,
            ),
            timestamp: t0 + 13,
            signer: peerB,
          ),
          event(
            kind: 'InvitationRejected',
            payload: invitationRejectedPayload(invitationByte: 0x54, reason: 0),
            timestamp: t0 + 14,
            signer: self,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x55,
              starterByte: 0x24,
              toPubkey: peerA,
            ),
            timestamp: t0 + 15,
            signer: self,
          ),
          event(
            kind: 'InvitationExpired',
            payload: invitationExpiredPayload(invitationByte: 0x55),
            timestamp: t0 + 16,
            signer: self,
          ),
        ],
      });

      final summaryA = parser.parse(ledger, toHex);
      final summaryB = parser.parse(ledger, toHex);
      final root = support.exportLedgerRoot(ledger)!;
      final invitationProjection =
          InvitationProjectionService.withOwnerKeyProvider(
        () => Uint8List.fromList(self),
        support,
      );
      final pendingFromProjection = invitationProjection
          .loadInvitations(root)
          .where((invitation) => invitation.status == InvitationStatus.pending)
          .length;
      final relationshipCountFromProjection = relationshipProjection
          .loadRelationshipGroups(root)
          .where((group) => group.isActive)
          .length;

      expect(summaryA.starterCount, equals(3));
      expect(summaryA.relationshipCount, equals(1));
      expect(summaryA.pendingInvitations, equals(2));
      expect(summaryA.ledgerVersion, equals(16));
      expect(summaryA.ledgerHashHex, equals('abc123'));

      expect(summaryB.starterCount, equals(summaryA.starterCount));
      expect(summaryB.relationshipCount, equals(summaryA.relationshipCount));
      expect(summaryB.pendingInvitations, equals(summaryA.pendingInvitations));
      expect(summaryB.ledgerVersion, equals(summaryA.ledgerVersion));
      expect(summaryB.ledgerHashHex, equals(summaryA.ledgerHashHex));

      expect(summaryA.pendingInvitations, equals(pendingFromProjection));
      expect(
        summaryA.relationshipCount,
        equals(relationshipCountFromProjection),
      );
    });

    test(
        'resolved invitations do not resurrect as pending after replayed offer events',
        () {
      final self = rep(0xaa);
      final peer = rep(0xbb);
      const t0 = 1890001000000;

      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x61,
              starterByte: 0x21,
              toPubkey: peer,
            ),
            timestamp: t0 + 1,
            signer: self,
          ),
          event(
            kind: 'InvitationAccepted',
            payload: invitationAcceptedPayload(
              invitationByte: 0x61,
              fromByte: 0xbb,
              createdStarterByte: 0x71,
            ),
            timestamp: t0 + 2,
            signer: peer,
          ),
          event(
            kind: 'InvitationSent',
            payload: invitationSentPayload(
              invitationByte: 0x61,
              starterByte: 0x21,
              toPubkey: peer,
            ),
            timestamp: t0 + 3,
            signer: self,
          ),
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x62,
              starterByte: 0x31,
              toPubkey: self,
            ),
            timestamp: t0 + 4,
            signer: peer,
          ),
          event(
            kind: 'InvitationRejected',
            payload: invitationRejectedPayload(invitationByte: 0x62),
            timestamp: t0 + 5,
            signer: self,
          ),
          event(
            kind: 'InvitationReceived',
            payload: invitationSentPayload(
              invitationByte: 0x62,
              starterByte: 0x31,
              toPubkey: self,
            ),
            timestamp: t0 + 6,
            signer: peer,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.pendingInvitations, equals(0));
    });

    test(
        'relationship count supports root-augmented RelationshipEstablished payload',
        () {
      final self = rep(0xaa);
      const t0 = 1890002000000;
      final ledger = jsonEncode(<String, dynamic>{
        'owner': self,
        'events': <Map<String, dynamic>>[
          event(
            kind: 'RelationshipEstablished',
            payload: relationshipEstablishedPayloadWithRoots(
              peerByte: 0xbb,
              ownStarterByte: 0x21,
              peerStarterByte: 0x31,
              kindByte: 1,
              invitationByte: 0x41,
              senderByte: 0xbb,
              senderStarterByte: 0x61,
              peerRootByte: 0xcc,
              senderRootByte: 0xaa,
            ),
            timestamp: t0 + 1,
            signer: self,
          ),
        ],
      });

      final summary = parser.parse(ledger, toHex);
      expect(summary.relationshipCount, equals(1));
    });

    test(
      'relationship count collapses mixed transport links with the same peer root',
      () {
        final self = rep(0xaa);
        const t0 = 1890002010000;
        final ledger = jsonEncode(<String, dynamic>{
          'owner': self,
          'events': <Map<String, dynamic>>[
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayloadWithRoots(
                peerByte: 0xb1,
                ownStarterByte: 0x21,
                peerStarterByte: 0x31,
                kindByte: 1,
                invitationByte: 0x41,
                senderByte: 0xb1,
                senderStarterByte: 0x61,
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 1,
              signer: self,
            ),
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayloadWithRoots(
                peerByte: 0xb2,
                ownStarterByte: 0x22,
                peerStarterByte: 0x32,
                kindByte: 1,
                invitationByte: 0x42,
                senderByte: 0xb2,
                senderStarterByte: 0x62,
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 2,
              signer: self,
            ),
          ],
        });

        final summary = parser.parse(ledger, toHex);
        expect(summary.relationshipCount, equals(1));
      },
    );

    test(
      'remote RelationshipBroken notification keeps relationship active in summary count',
      () {
        final self = rep(0xaa);
        final peer = rep(0xbb);
        const t0 = 1890003300000;
        final ledger = jsonEncode(<String, dynamic>{
          'owner': self,
          'events': <Map<String, dynamic>>[
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayloadWithRoots(
                peerByte: 0xbb,
                ownStarterByte: 0x21,
                peerStarterByte: 0x31,
                kindByte: 1,
                invitationByte: 0x41,
                senderByte: 0xbb,
                senderStarterByte: 0x61,
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 1,
              signer: self,
            ),
            event(
              kind: 'RelationshipBroken',
              payload: relationshipBrokenPayload(
                  peerByte: 0xbb, ownStarterByte: 0x21),
              timestamp: t0 + 2,
              signer: peer,
            ),
          ],
        });

        final summary = parser.parse(ledger, toHex);
        expect(summary.relationshipCount, equals(1));
      },
    );
  });
}
