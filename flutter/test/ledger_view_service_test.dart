import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_ledger_summary_parser.dart';
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

    test(
      'keeps pending/relationship counters aligned with CapsuleLedgerSummaryParser',
      () {
        final owner = bytes32(0xaa);
        final transport = bytes32(0xab);
        final peerInvitation = bytes32(0x31);
        final peerRelationship = bytes32(0x32);
        final ownStarter = bytes32(0x41);
        final peerStarter = bytes32(0x42);
        final pendingInvitationId = bytes32(0x51);
        final relationshipInvitationId = bytes32(0x52);

        final invitationReceivedPayload = <int>[
          ...pendingInvitationId,
          ...peerStarter,
          ...transport,
          1,
        ];

        final relationshipEstablishedPayload = <int>[
          ...peerRelationship,
          ...ownStarter,
          ...peerStarter,
          0,
          ...relationshipInvitationId,
          ...peerRelationship,
          0,
          ...peerStarter,
        ];

        final ledgerJson = jsonEncode(<String, dynamic>{
          'owner': owner,
          'events': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'CapsuleCreated',
              'payload': <int>[1, 0],
              'timestamp': 1891000000000,
              'signer': owner,
            },
            <String, dynamic>{
              'kind': 'InvitationReceived',
              'payload': invitationReceivedPayload,
              'timestamp': 1891000001000,
              'signer': peerInvitation,
            },
            <String, dynamic>{
              'kind': 'RelationshipEstablished',
              'payload': relationshipEstablishedPayload,
              'timestamp': 1891000002000,
              'signer': peerRelationship,
            },
          ],
          'last_hash': '0xfeed',
        });

        final service = LedgerViewService.withSources(
          exportLedger: () => ledgerJson,
          exportCapsuleState: () => jsonEncode(<String, dynamic>{
            'public_key': owner,
            'version': 3,
            'ledger_hash': 'feed',
            'slots': <Object?>[
              ownStarter,
              null,
              null,
              null,
              null,
            ],
          }),
          readRuntimeOwnerPublicKey: () => Uint8List.fromList(owner),
          readRuntimeTransportPublicKey: () => Uint8List.fromList(transport),
        );

        final parser = const CapsuleLedgerSummaryParser();
        final summary = parser.parse(
          ledgerJson,
          (bytes) =>
              bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          runtimeTransportPublicKey: Uint8List.fromList(transport),
        );
        final snapshot = service.loadCapsuleSnapshot();

        expect(snapshot.pendingInvitations, equals(summary.pendingInvitations));
        expect(snapshot.relationshipCount, equals(summary.relationshipCount));
        expect(snapshot.pendingInvitations, equals(1));
        expect(snapshot.relationshipCount, equals(1));
      },
    );
  });
}
