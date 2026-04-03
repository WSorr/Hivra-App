import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/relationship_service.dart';

void main() {
  Relationship sampleRelationship({
    String peerPubkey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
    String ownStarterId = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
    String peerStarterId = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=',
  }) {
    return Relationship(
      peerPubkey: peerPubkey,
      kind: StarterKind.juice,
      ownStarterId: ownStarterId,
      peerStarterId: peerStarterId,
      establishedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('breakRelationship returns false for invalid ids', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.breakRelationship(
      sampleRelationship(peerPubkey: 'invalid'),
    );

    expect(ok, isFalse);
    expect(breakCalls, equals(0));
    expect(persistCalls, equals(0));
  });

  test('breakRelationship calls breaker and persists on success', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.breakRelationship(sampleRelationship());

    expect(ok, isTrue);
    expect(breakCalls, equals(1));
    expect(persistCalls, equals(1));
  });

  test('confirmRemoteBreak delegates through break flow', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return true;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.confirmRemoteBreak(sampleRelationship());

    expect(ok, isTrue);
    expect(breakCalls, equals(1));
    expect(persistCalls, equals(1));
  });

  test('loadPeerRootKeysByTransportBase64 resolves via normalized transport hex',
      () async {
    final peerBytes = List<int>.filled(32, 0x11);
    final rootBytes = List<int>.filled(32, 0x22);
    final peerBase64 = base64.encode(peerBytes);
    final rootHex = rootBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final nostrHex = peerBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase()
        .replaceAllMapped(RegExp(r'..'), (m) => '${m.group(0)}:')
        .replaceFirst(RegExp(r':$'), '');

    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService: _FakeCapsuleAddressService(
        cards: <CapsuleAddressCard>[
          CapsuleAddressCard(
            rootKey: 'h1testroot',
            rootHex: rootHex,
            nostrNpub: 'npub1test',
            nostrHex: nostrHex,
          ),
        ],
      ),
    );

    final resolved = await service.loadPeerRootKeysByTransportBase64(
      <String>[peerBase64],
    );

    expect(resolved[peerBase64], 'h1testroot');
  });

  test('loadPeerRootKeysByTransportBase64 resolves when peer key is root key',
      () async {
    final rootBytes = List<int>.filled(32, 0x33);
    final rootBase64 = base64.encode(rootBytes);
    final rootHex = rootBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService: _FakeCapsuleAddressService(
        cards: <CapsuleAddressCard>[
          CapsuleAddressCard(
            rootKey: 'h1rootcapsule',
            rootHex: rootHex,
            nostrNpub: 'npub1rootcapsule',
            nostrHex:
                '4444444444444444444444444444444444444444444444444444444444444444',
          ),
        ],
      ),
    );

    final resolved = await service.loadPeerRootKeysByTransportBase64(
      <String>[rootBase64],
    );

    expect(resolved[rootBase64], 'h1rootcapsule');
  });
}

class _FakeCapsuleAddressService extends CapsuleAddressService {
  final List<CapsuleAddressCard> cards;

  const _FakeCapsuleAddressService({required this.cards});

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async => cards;
}
