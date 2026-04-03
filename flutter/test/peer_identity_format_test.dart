import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';
import 'package:hivra_app/utils/peer_identity_format.dart';

void main() {
  group('PeerIdentityFormat', () {
    final transportB64 = base64.encode(List<int>.filled(32, 7));
    final rootKey = HivraIdFormat.formatCapsuleKeyBytes(
      Uint8List.fromList(List<int>.filled(32, 9)),
    );

    test('prefers root display when root key is known', () {
      final display = PeerIdentityFormat.displayName(
        transportPubkeyB64: transportB64,
        rootCapsuleKey: rootKey,
      );
      expect(display, equals(HivraIdFormat.short(rootKey)));
    });

    test('falls back to transport display when root key is unknown', () {
      final display = PeerIdentityFormat.displayName(
        transportPubkeyB64: transportB64,
      );
      expect(
        display,
        equals(
          HivraIdFormat.short(
              HivraIdFormat.formatNostrKeyFromBase64(transportB64)),
        ),
      );
    });

    test('identity hint includes both root and transport when available', () {
      final hint = PeerIdentityFormat.identityHint(
        transportPubkeyB64: transportB64,
        rootCapsuleKey: rootKey,
      );
      expect(hint, contains('Root '));
      expect(hint, contains('transport '));
    });
  });
}
