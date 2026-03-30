import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/ledger_view_support.dart';

void main() {
  group('LedgerViewSupport.kindLabel', () {
    const support = LedgerViewSupport();

    test('maps known numeric kinds', () {
      expect(support.kindLabel(1), equals('InvitationSent'));
      expect(support.kindLabel(9), equals('InvitationReceived'));
    });

    test('keeps string kind as-is and formats unknown int', () {
      expect(support.kindLabel('CustomKind'), equals('CustomKind'));
      expect(support.kindLabel(42), equals('Kind(42)'));
    });

    test('stays consistent with kindCode for canonical event names', () {
      const canonicalKinds = <String, int>{
        'CapsuleCreated': 0,
        'InvitationSent': 1,
        'InvitationReceived': 9,
        'InvitationAccepted': 2,
        'InvitationRejected': 3,
        'InvitationExpired': 4,
        'StarterCreated': 5,
        'StarterBurned': 6,
        'RelationshipEstablished': 7,
        'RelationshipBroken': 8,
      };

      canonicalKinds.forEach((name, code) {
        expect(support.kindCode(name), equals(code));
        expect(support.kindLabel(code), equals(name));
      });
    });
  });

  group('LedgerViewSupport.payloadBytes', () {
    const support = LedgerViewSupport();

    test('decodes hex payload string', () {
      final bytes = support.payloadBytes('0a0b0c');
      expect(bytes, equals(Uint8List.fromList([10, 11, 12])));
    });

    test('decodes base64 payload string', () {
      final bytes = support.payloadBytes('AQID');
      expect(bytes, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('rejects invalid list byte values', () {
      final bytes = support.payloadBytes(<dynamic>[1, 300, 3]);
      expect(bytes, isEmpty);
    });
  });

  group('LedgerViewSupport.inferGenesisFromLedgerRoot', () {
    const support = LedgerViewSupport();

    test('returns true when CapsuleCreated payload marks relay capsule', () {
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'CapsuleCreated',
            'payload': <int>[1, 1],
          },
        ],
      };

      expect(support.inferGenesisFromLedgerRoot(root), isTrue);
    });

    test('returns false when CapsuleCreated payload marks leaf capsule', () {
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 0,
            'payload': <int>[1, 0],
          },
        ],
      };

      expect(support.inferGenesisFromLedgerRoot(root), isFalse);
    });

    test('returns null when capsule-created payload is malformed', () {
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'CapsuleCreated',
            'payload': <int>[1],
          },
        ],
      };

      expect(support.inferGenesisFromLedgerRoot(root), isNull);
    });

    test('returns null when ledger has no capsule-created event', () {
      final root = <String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'InvitationSent',
            'payload': <int>[0, 1]
          },
        ],
      };

      expect(support.inferGenesisFromLedgerRoot(root), isNull);
    });
  });
}
