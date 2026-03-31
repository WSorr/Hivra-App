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

  group('LedgerViewSupport.relationship payload compatibility', () {
    const support = LedgerViewSupport();

    List<int> rep(int value) => List<int>.filled(32, value);
    String hex(Uint8List bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    test('accepts root-augmented relationship established payload', () {
      final peer = rep(1);
      final ownStarter = rep(2);
      final payload = Uint8List.fromList(<int>[
        ...peer,
        ...ownStarter,
        ...rep(3),
        1,
        ...rep(4),
        ...rep(5),
        1,
        ...rep(6),
        ...rep(7), // peer_root_pubkey (future extension)
        ...rep(8), // sender_root_pubkey (future extension)
      ]);

      final key =
          support.relationshipKeyFromEstablishedPayload(payload, encode32: hex);
      final peerProjected = support
          .relationshipPeerFromEstablishedPayload(payload, encode32: hex);

      expect(
          key,
          equals(
              '${hex(Uint8List.fromList(peer))}:${hex(Uint8List.fromList(ownStarter))}'));
      expect(peerProjected, equals(hex(Uint8List.fromList(peer))));
    });

    test('accepts root-augmented relationship broken payload', () {
      final peer = rep(9);
      final ownStarter = rep(10);
      final payload = Uint8List.fromList(<int>[
        ...peer,
        ...ownStarter,
        ...rep(11), // peer_root_pubkey (future extension)
      ]);

      final key =
          support.relationshipKeyFromBrokenPayload(payload, encode32: hex);

      expect(
          key,
          equals(
              '${hex(Uint8List.fromList(peer))}:${hex(Uint8List.fromList(ownStarter))}'));
    });
  });
}
