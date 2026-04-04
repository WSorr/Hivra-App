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

    test(
      'does not reopen pending break after local break when owner is resolved from ledger',
      () {
        const t0 = 1890003215000;
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

        final projected = service.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.isActive, isFalse);
        expect(projected.single.hasPendingRemoteBreak, isFalse);
      },
    );

    test(
      'groups mixed transport links under one peer when root anchor matches',
      () {
        const t0 = 1890003220000;
        final root = <String, dynamic>{
          'events': <Map<String, dynamic>>[
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayload(
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
            ),
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayload(
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
            ),
          ],
        };

        final groups = service.loadRelationshipGroups(root);

        expect(groups, hasLength(1));
        expect(groups.single.relationships, hasLength(2));
        expect(groups.single.preferredPeerRootPubkey, base64.encode(rep(0xcc)));
        expect(groups.single.peerPubkey, base64.encode(rep(0xb2)));
      },
    );

    test(
      'infers peer root from root-augmented invitation lineage for legacy relationship payload',
      () {
        const t0 = 1890003230000;
        final root = <String, dynamic>{
          'events': <Map<String, dynamic>>[
            event(
              kind: 'InvitationReceived',
              payload: <int>[
                ...rep(0x51), // invitation id
                ...rep(0x21), // starter id
                ...rep(0xaa), // to pubkey (self)
                ...rep(0xcc), // sender_root_pubkey
                1, // starter kind
              ],
              timestamp: t0 + 1,
              signer: rep(0xb1),
            ),
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayload(
                peerByte: 0xb1,
                ownStarterByte: 0x21,
                peerStarterByte: 0x31,
                kindByte: 1,
                invitationByte: 0x51,
                senderByte: 0xb1,
                senderStarterByte: 0x61,
              ),
              timestamp: t0 + 2,
            ),
          ],
        };

        final projected = service.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.peerRootPubkey, base64.encode(rep(0xcc)));
      },
    );

    test(
      'does not infer peer root from local root-augmented InvitationSent lineage',
      () {
        const t0 = 1890003240000;
        final localOwner = rep(0xaa);
        final root = <String, dynamic>{
          'owner': localOwner,
          'events': <Map<String, dynamic>>[
            event(
              kind: 'InvitationSent',
              payload: <int>[
                ...rep(0x61), // invitation id
                ...rep(0x21), // starter id
                ...rep(0xb1), // to_pubkey (peer transport)
                ...rep(0xaa), // sender_root_pubkey (local owner root)
                1, // starter kind
              ],
              timestamp: t0 + 1,
              signer: localOwner,
            ),
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayload(
                peerByte: 0xb1,
                ownStarterByte: 0x21,
                peerStarterByte: 0x31,
                kindByte: 1,
                invitationByte: 0x61,
                senderByte: 0xb1,
                senderStarterByte: 0x61,
              ),
              timestamp: t0 + 2,
            ),
          ],
        };

        final projected = service.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.peerRootPubkey, isNull);
      },
    );

    test(
      'does not infer peer root from local InvitationAccepted accepter_root lineage',
      () {
        const t0 = 1890003250000;
        final localOwner = rep(0xaa);
        final root = <String, dynamic>{
          'owner': localOwner,
          'events': <Map<String, dynamic>>[
            event(
              kind: 'InvitationAccepted',
              payload: <int>[
                ...rep(0x62), // invitation id
                ...rep(0xaa), // from_pubkey (local)
                ...rep(0x31), // created_starter_id
                ...rep(0xaa), // accepter_root_pubkey (local owner root)
              ],
              timestamp: t0 + 1,
              signer: localOwner,
            ),
            event(
              kind: 'RelationshipEstablished',
              payload: relationshipEstablishedPayload(
                peerByte: 0xb2,
                ownStarterByte: 0x21,
                peerStarterByte: 0x31,
                kindByte: 1,
                invitationByte: 0x62,
                senderByte: 0xb2,
                senderStarterByte: 0x61,
              ),
              timestamp: t0 + 2,
            ),
          ],
        };

        final projected = service.loadRelationships(root);

        expect(projected, hasLength(1));
        expect(projected.single.peerRootPubkey, isNull);
      },
    );
  });
}
