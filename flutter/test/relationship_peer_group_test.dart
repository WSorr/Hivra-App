import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/relationship_peer_group.dart';
import 'package:hivra_app/models/starter.dart';

void main() {
  Relationship relationship({
    required bool isActive,
    required bool hasPendingRemoteBreak,
    required DateTime establishedAt,
    String? peerRootPubkey,
  }) {
    return Relationship(
      peerPubkey: '',
      peerRootPubkey: peerRootPubkey,
      kind: StarterKind.juice,
      ownStarterId: '',
      peerStarterId: '',
      establishedAt: establishedAt,
      isActive: isActive,
      hasPendingRemoteBreak: hasPendingRemoteBreak,
    );
  }

  test('exposes pending remote break relationships as active subset', () {
    final now = DateTime.now();
    final group = RelationshipPeerGroup(
      peerPubkey: '',
      relationships: <Relationship>[
        relationship(
          isActive: true,
          hasPendingRemoteBreak: false,
          establishedAt: now.subtract(const Duration(minutes: 3)),
        ),
        relationship(
          isActive: true,
          hasPendingRemoteBreak: true,
          establishedAt: now.subtract(const Duration(minutes: 2)),
        ),
        relationship(
          isActive: false,
          hasPendingRemoteBreak: false,
          establishedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
    );

    expect(group.isActive, isTrue);
    expect(group.activeRelationships.length, 2);
    expect(group.pendingRemoteBreakRelationships.length, 1);
    expect(group.pendingRemoteBreakRelationships.single.hasPendingRemoteBreak,
        isTrue);
  });

  test('prefers latest relationship root identity when available', () {
    final now = DateTime.now();
    final group = RelationshipPeerGroup(
      peerPubkey: '',
      relationships: <Relationship>[
        relationship(
          isActive: true,
          hasPendingRemoteBreak: false,
          establishedAt: now.subtract(const Duration(minutes: 3)),
          peerRootPubkey: 'old-root',
        ),
        relationship(
          isActive: true,
          hasPendingRemoteBreak: false,
          establishedAt: now.subtract(const Duration(minutes: 1)),
          peerRootPubkey: 'new-root',
        ),
      ],
    );

    expect(group.preferredPeerRootPubkey, 'new-root');
  });
}
