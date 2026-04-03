import 'relationship.dart';
import 'starter.dart';
import '../utils/hivra_id_format.dart';

class RelationshipPeerGroup {
  final String peerPubkey;
  final List<Relationship> relationships;

  const RelationshipPeerGroup({
    required this.peerPubkey,
    required this.relationships,
  });

  List<Relationship> get activeRelationships =>
      relationships.where((relationship) => relationship.isActive).toList()
        ..sort((a, b) => b.establishedAt.compareTo(a.establishedAt));

  List<Relationship> get brokenRelationships =>
      relationships.where((relationship) => !relationship.isActive).toList()
        ..sort((a, b) => b.establishedAt.compareTo(a.establishedAt));

  List<Relationship> get pendingRemoteBreakRelationships => relationships
      .where(
        (relationship) =>
            relationship.isActive && relationship.hasPendingRemoteBreak,
      )
      .toList()
    ..sort((a, b) => b.establishedAt.compareTo(a.establishedAt));

  DateTime get latestEstablishedAt => relationships
      .map((relationship) => relationship.establishedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);

  String get peerDisplayName {
    if (peerPubkey.isEmpty) return 'Unknown';
    return HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(peerPubkey),
    );
  }

  List<StarterKind> get activeKinds {
    final seen = <StarterKind>{};
    final result = <StarterKind>[];
    for (final relationship in activeRelationships) {
      if (seen.add(relationship.kind)) {
        result.add(relationship.kind);
      }
    }
    return result;
  }

  bool get isActive => activeRelationships.isNotEmpty;
}
