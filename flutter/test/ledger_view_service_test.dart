import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/ledger_view_service.dart';

void main() {
  group('LedgerViewService', () {
    List<int> bytes32(int value) => List<int>.filled(32, value);

    test('keeps awaiting-history state when ledger has zero events', () {
      final owner = bytes32(0xaa);
      final starterInState = bytes32(0x21);

      final service = LedgerViewService.withSources(
        exportLedger: () => jsonEncode(<String, dynamic>{
          'owner': owner,
          'events': <Object>[],
          'last_hash': '0xdeadbeef',
        }),
        exportCapsuleState: () => jsonEncode(<String, dynamic>{
          'public_key': owner,
          'version': 7,
          'ledger_hash': 'abc',
          'slots': <Object?>[
            starterInState,
            null,
            null,
            null,
            null,
          ],
        }),
        readRuntimeOwnerPublicKey: () => Uint8List.fromList(owner),
      );

      final snapshot = service.loadCapsuleSnapshot();

      expect(snapshot.hasLedgerHistory, isFalse);
      expect(snapshot.starterCount, equals(0));
      expect(snapshot.relationshipCount, equals(0));
      expect(snapshot.pendingInvitations, equals(0));
      expect(snapshot.version, equals(0));
      expect(snapshot.ledgerHashHex, equals('0'));
      expect(snapshot.starterIds.whereType<Uint8List>(), isEmpty);
      expect(snapshot.lockedStarterSlots, isEmpty);
    });

    test('treats non-empty ledger as history and keeps slot projection', () {
      final owner = bytes32(0xaa);
      final starterInState = bytes32(0x21);

      final service = LedgerViewService.withSources(
        exportLedger: () => jsonEncode(<String, dynamic>{
          'owner': owner,
          'events': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'CapsuleCreated',
              'payload': <int>[1, 1],
              'timestamp': 1891000000000,
              'signer': owner,
            },
          ],
          'last_hash': '0xbeef',
        }),
        exportCapsuleState: () => jsonEncode(<String, dynamic>{
          'public_key': owner,
          'version': 9,
          'ledger_hash': '123',
          'slots': <Object?>[
            starterInState,
            null,
            null,
            null,
            null,
          ],
        }),
        readRuntimeOwnerPublicKey: () => Uint8List.fromList(owner),
      );

      final snapshot = service.loadCapsuleSnapshot();

      expect(snapshot.hasLedgerHistory, isTrue);
      expect(snapshot.starterCount, equals(1));
      expect(snapshot.pendingInvitations, equals(0));
      expect(snapshot.relationshipCount, equals(0));
      expect(snapshot.version, equals(9));
      expect(snapshot.ledgerHashHex, equals('123'));
      expect(snapshot.starterIds.whereType<Uint8List>(), hasLength(1));
    });
  });
}
