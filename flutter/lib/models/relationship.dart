import 'starter.dart';
import '../utils/hivra_id_format.dart';

/// Relationship between two capsules
class Relationship {
  final String peerPubkey;
  final String? peerRootPubkey;
  final StarterKind kind;
  final String ownStarterId;
  final String peerStarterId;
  final DateTime establishedAt;
  final bool isActive;
  final bool hasPendingRemoteBreak;

  Relationship({
    required this.peerPubkey,
    this.peerRootPubkey,
    required this.kind,
    required this.ownStarterId,
    required this.peerStarterId,
    required this.establishedAt,
    this.isActive = true,
    this.hasPendingRemoteBreak = false,
  });

  /// Get display name for peer (safe short preview)
  String get peerDisplayName {
    if (peerPubkey.isEmpty) return 'Unknown';
    return HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(peerPubkey),
    );
  }

  String get ownStarterDisplayId => HivraIdFormat.short(
      HivraIdFormat.formatStarterIdFromBase64(ownStarterId));

  String get peerStarterDisplayId => HivraIdFormat.short(
      HivraIdFormat.formatStarterIdFromBase64(peerStarterId));

  /// For mock data
  static Relationship mock(int index) {
    final kinds = StarterKind.values;
    return Relationship(
      peerPubkey: '0x$index' '234567890123456789012345678901234567890123456789',
      kind: kinds[index % kinds.length],
      ownStarterId: 'starter_$index',
      peerStarterId: 'peer_starter_$index',
      establishedAt: DateTime.now().subtract(Duration(days: index)),
      isActive: index % 3 != 0, // every 3rd is broken
      hasPendingRemoteBreak: false,
    );
  }
}
