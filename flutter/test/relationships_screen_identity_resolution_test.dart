import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/relationship_peer_group.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/screens/relationships_screen.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/relationship_service.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';

void main() {
  testWidgets(
    'uses imported root key when contact card matches non-representative transport key in group',
    (tester) async {
      String b64(int value) => base64Encode(List<int>.filled(32, value));
      String hex32(int value) => List<int>.filled(32, value)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final representativePeerB64 = b64(11);
      final linkedPeerWithCardB64 = b64(12);
      final rootBytes = Uint8List.fromList(List<int>.filled(32, 21));
      final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);

      final relationships = <Relationship>[
        Relationship(
          peerPubkey: representativePeerB64,
          peerRootPubkey: null,
          kind: StarterKind.kick,
          ownStarterId: b64(31),
          peerStarterId: b64(41),
          establishedAt: DateTime.utc(2026, 4, 1, 9),
        ),
        Relationship(
          peerPubkey: linkedPeerWithCardB64,
          peerRootPubkey: null,
          kind: StarterKind.spark,
          ownStarterId: b64(32),
          peerStarterId: b64(42),
          establishedAt: DateTime.utc(2026, 4, 1, 10),
        ),
      ];
      final groups = <RelationshipPeerGroup>[
        RelationshipPeerGroup(
          peerPubkey: representativePeerB64,
          relationships: relationships,
        ),
      ];

      final service = RelationshipService(
        loadRelationshipGroups: () => groups,
        breakRelationship: (_, __, ___) => true,
        persistLedgerSnapshot: () async {},
        addressService: _FakeCapsuleAddressService(
          cards: <CapsuleAddressCard>[
            CapsuleAddressCard(
              rootKey: rootKey,
              rootHex: hex32(21),
              nostrNpub: 'npub1test',
              nostrHex: hex32(12),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RelationshipsScreen(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(HivraIdFormat.short(rootKey)),
        findsWidgets,
      );
      expect(find.textContaining('Unknown root'), findsNothing);
    },
  );
}

class _FakeCapsuleAddressService extends CapsuleAddressService {
  final List<CapsuleAddressCard> cards;

  const _FakeCapsuleAddressService({
    required this.cards,
  });

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async => cards;
}
