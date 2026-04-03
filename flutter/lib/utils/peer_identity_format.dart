import 'hivra_id_format.dart';

class PeerIdentityFormat {
  static String displayName({
    required String transportPubkeyB64,
    String? rootCapsuleKey,
  }) {
    final root = rootCapsuleKey?.trim();
    if (root != null && root.isNotEmpty) {
      return HivraIdFormat.short(root);
    }
    return HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(transportPubkeyB64),
    );
  }

  static String identityHint({
    required String transportPubkeyB64,
    String? rootCapsuleKey,
  }) {
    final transportShort = HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(transportPubkeyB64),
    );
    final root = rootCapsuleKey?.trim();
    if (root != null && root.isNotEmpty) {
      return 'Root ${HivraIdFormat.short(root)} · transport $transportShort';
    }
    return 'Unknown root · transport $transportShort';
  }
}
