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
      expect(display, equals('Capsule ${HivraIdFormat.short(rootKey)}'));
    });

    test('does not expose the transport key when root key is unknown', () {
      final display = PeerIdentityFormat.displayName(
        transportPubkeyB64: transportB64,
      );
      expect(display, equals('Unverified capsule'));
    });

    test('identity hint preserves root identity without transport details', () {
      final hint = PeerIdentityFormat.identityHint(
        transportPubkeyB64: transportB64,
        rootCapsuleKey: rootKey,
      );
      expect(hint, equals('Capsule ID ${HivraIdFormat.short(rootKey)}'));
    });

    test('root hex identity hint remains visible beside a local label', () {
      final rootHex = List<String>.filled(32, '09').join();
      expect(
        PeerIdentityFormat.capsuleLabelFromRootHex(
          rootHex,
          localLabel: 'Bernadett',
        ),
        equals('Bernadett'),
      );
      expect(
        PeerIdentityFormat.capsuleIdentityHintFromRootHex(rootHex),
        equals('Capsule ID ${HivraIdFormat.short(rootKey)}'),
      );
    });

    test('formats a root hex key only for internal selection state', () {
      final rootHex = List<String>.filled(32, '09').join();
      expect(
        PeerIdentityFormat.capsuleLabelFromRootHex(rootHex),
        equals('Capsule ${HivraIdFormat.short(rootKey)}'),
      );
    });
  });
}
