import 'hivra_id_format.dart';

class PeerIdentityFormat {
  static String? capsuleKeyFromRootHex(String rootHex) =>
      HivraIdFormat.tryFormatCapsuleKeyFromHex(rootHex);

  static String capsuleLabelFromRootHex(String rootHex, {String? localLabel}) {
    final label = localLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final capsuleKey = capsuleKeyFromRootHex(rootHex);
    if (capsuleKey == null) return 'Unknown capsule';
    return 'Capsule ${HivraIdFormat.short(capsuleKey)}';
  }

  static String displayName({
    required String transportPubkeyB64,
    String? rootCapsuleKey,
    String? localLabel,
  }) {
    final label = localLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final root = rootCapsuleKey?.trim();
    if (root != null && root.isNotEmpty) {
      return 'Capsule ${HivraIdFormat.short(root)}';
    }
    return 'Unverified capsule';
  }

  static String identityHint({
    required String transportPubkeyB64,
    String? rootCapsuleKey,
  }) {
    final root = rootCapsuleKey?.trim();
    if (root != null && root.isNotEmpty) {
      return 'Verified capsule identity';
    }
    return 'Awaiting a signed capsule card';
  }

  static String technicalHint({
    required String transportPubkeyB64,
    String? rootCapsuleKey,
  }) {
    final transportShort = HivraIdFormat.short(
      HivraIdFormat.formatNostrKeyFromBase64(transportPubkeyB64),
    );
    final root = rootCapsuleKey?.trim();
    if (root != null && root.isNotEmpty) {
      return 'Capsule ID ${HivraIdFormat.short(root)} · Nostr $transportShort';
    }
    return 'Nostr $transportShort';
  }
}
