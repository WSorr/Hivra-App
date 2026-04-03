import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/ledger_view_support.dart';
import 'package:hivra_app/services/relationship_projection_service.dart';

void main() {
  group('RelationshipProjectionService', () {
    const support = LedgerViewSupport();
    const service = RelationshipProjectionService(support);

    List<int> rep(int value) => List<int>.filled(32, value);

    List<int> relationshipEstablishedPayload({
      required int peerByte,
      required int ownStarterByte,
      required int peerStarterByte,
      required int kindByte,
      required int invitationByte,
      required int senderByte,
      required int senderStarterByte,
      int? peerRootByte,
      int? senderRootByte,
    }) {
      final base = <int>[
        ...rep(peerByte),
        ...rep(ownStarterByte),
        ...rep(peerStarterByte),
        kindByte,
        ...rep(invitationByte),
        ...rep(senderByte),
        kindByte,
        ...rep(senderStarterByte),
      ];
      if (peerRootByte == null || senderRootByte == null) {
        return base;
      }
      return <int>[
        ...base,
        ...rep(peerRootByte),
        ...rep(senderRootByte),
      ];
    }

    Map<String, dynamic> event({
      required String kind,
      required List<int> payload,
      required int timestamp,
      List<int>? signer,
    }) {
      final map = <String, dynamic>{
        'kind': kind,
        'payload': payload,
        'timestamp': timestamp,
      };
      if (signer != null) {
        map['signer'] = signer;
      }
      return map;
    }

    test('projects relationship from root-augmented established payload', () {
      const t0 = 1890003000000;
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
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
              peerRootByte: 0xcc,
              senderRootByte: 0xaa,
            ),
            timestamp: t0 + 1,
          ),
        ],
      };

      final projected = service.loadRelationships(root);

      expect(projected, hasLength(1));
      expect(projected.single.isActive, isTrue);
      expect(projected.single.peerRootPubkey, base64.encode(rep(0xcc)));
    });

    test('marks relationship broken with root-augmented break payload', () {
      const t0 = 1890003100000;
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
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
              peerRootByte: 0xcc,
              senderRootByte: 0xaa,
            ),
            timestamp: t0 + 1,
          ),
          event(
            kind: 'RelationshipBroken',
            payload: <int>[
              ...rep(0xbb),
              ...rep(0x21),
              ...rep(0xcc),
            ],
            timestamp: t0 + 2,
          ),
        ],
      };

      final projected = service.loadRelationships(root);

      expect(projected, hasLength(1));
      expect(projected.single.isActive, isFalse);
    });

    test(
      'keeps relationship active and marks pending on remote break notification',
      () {
        const t0 = 1890003200000;
        final local = rep(0xaa);
        final peer = rep(0xbb);
        final serviceWithOwner =
            RelationshipProjectionService.withOwnerKeyProvider(
          () => Uint8List.fromList(local),
          support,
        );
        final root = <String, dynamic>{
          'events': <Map<String, dynamic>>[
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
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 1,
              signer: local,
            ),
            event(
              kind: 'RelationshipBroken',
              payload: <int>[
                ...rep(0xbb),
                ...rep(0x21),
                ...rep(0xcc),
              ],
              timestamp: t0 + 2,
              signer: peer,
            ),
          ],
        };

        final projected = serviceWithOwner.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.isActive, isTrue);
        expect(projected.single.hasPendingRemoteBreak, isTrue);
      },
    );

    test(
      'uses ledger owner fallback to preserve pending remote break semantics',
      () {
        const t0 = 1890003205000;
        final local = rep(0xaa);
        final peer = rep(0xbb);
        final root = <String, dynamic>{
          'owner': local,
          'events': <Map<String, dynamic>>[
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
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 1,
              signer: local,
            ),
            event(
              kind: 'RelationshipBroken',
              payload: <int>[
                ...rep(0xbb),
                ...rep(0x21),
                ...rep(0xcc),
              ],
              timestamp: t0 + 2,
              signer: peer,
            ),
          ],
        };

        final projected = service.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.isActive, isTrue);
        expect(projected.single.hasPendingRemoteBreak, isTrue);
      },
    );

    test(
      'does not reopen pending break after local break was finalized',
      () {
        const t0 = 1890003210000;
        final local = rep(0xaa);
        final peer = rep(0xbb);
        final serviceWithOwner =
            RelationshipProjectionService.withOwnerKeyProvider(
          () => Uint8List.fromList(local),
          support,
        );
        final root = <String, dynamic>{
          'events': <Map<String, dynamic>>[
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
                peerRootByte: 0xcc,
                senderRootByte: 0xaa,
              ),
              timestamp: t0 + 1,
              signer: local,
            ),
            event(
              kind: 'RelationshipBroken',
              payload: <int>[
                ...rep(0xbb),
                ...rep(0x21),
                ...rep(0xcc),
              ],
              timestamp: t0 + 2,
              signer: local,
            ),
            event(
              kind: 'RelationshipBroken',
              payload: <int>[
                ...rep(0xbb),
                ...rep(0x21),
                ...rep(0xcc),
              ],
              timestamp: t0 + 3,
              signer: peer,
            ),
          ],
        };

        final projected = serviceWithOwner.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.isActive, isFalse);
        expect(projected.single.hasPendingRemoteBreak, isFalse);
      },
    );
  });
}
