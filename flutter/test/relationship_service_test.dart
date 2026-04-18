import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/relationship_peer_group.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/relationship_service.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';

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

  test('confirmRemoteBreak returns false for invalid ids', () async {
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

    final ok = await service.confirmRemoteBreak(
      sampleRelationship(peerStarterId: 'invalid'),
    );

    expect(ok, isFalse);
    expect(breakCalls, equals(0));
    expect(persistCalls, equals(0));
  });

  test('confirmRemoteBreak does not persist when breaker rejects', () async {
    var breakCalls = 0;
    var persistCalls = 0;
    final service = RelationshipService(
      loadRelationshipGroups: () => const [],
      breakRelationship: (_, __, ___) {
        breakCalls += 1;
        return false;
      },
      persistLedgerSnapshot: () async {
        persistCalls += 1;
      },
    );

    final ok = await service.confirmRemoteBreak(sampleRelationship());

    expect(ok, isFalse);
    expect(breakCalls, equals(1));
    expect(persistCalls, equals(0));
  });

  test(
      'loadPeerRootKeysByTransportBase64 resolves via normalized transport hex',
      () async {
    final peerBytes = List<int>.filled(32, 0x11);
    final rootBytes = List<int>.filled(32, 0x22);
    final peerBase64 = base64.encode(peerBytes);
    final rootHex =
        rootBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
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
    final rootHex =
        rootBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

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

  test(
      'loadPeerRootKeysByTransportBase64 resolves projected root from relationship groups',
      () async {
    final peerBytes = List<int>.filled(32, 0x41);
    final rootBytes = List<int>.filled(32, 0x51);
    final peerBase64 = base64.encode(peerBytes);
    final rootBase64 = base64.encode(rootBytes);
    final expectedRoot =
        HivraIdFormat.formatCapsuleKeyBytes(Uint8List.fromList(rootBytes));

    final groups = <RelationshipPeerGroup>[
      RelationshipPeerGroup(
        peerPubkey: peerBase64,
        relationships: <Relationship>[
          Relationship(
            peerPubkey: peerBase64,
            peerRootPubkey: rootBase64,
            kind: StarterKind.juice,
            ownStarterId: base64.encode(List<int>.filled(32, 0x21)),
            peerStarterId: base64.encode(List<int>.filled(32, 0x31)),
            establishedAt: DateTime.utc(2026, 4, 16, 20),
          ),
        ],
      ),
    ];

    final service = RelationshipService(
      loadRelationshipGroups: () => groups,
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService:
          const _FakeCapsuleAddressService(cards: <CapsuleAddressCard>[]),
    );

    final resolved = await service.loadPeerRootKeysByTransportBase64(
      <String>[peerBase64],
    );

    expect(resolved[peerBase64], expectedRoot);
  });

  test(
      'loadPeerRootKeysByTransportBase64 prefers latest projected root by establishedAt',
      () async {
    final peerBase64 = base64.encode(List<int>.filled(32, 0x61));
    final olderRootBytes = Uint8List.fromList(List<int>.filled(32, 0x71));
    final newerRootBytes = Uint8List.fromList(List<int>.filled(32, 0x72));
    final olderRootBase64 = base64.encode(olderRootBytes);
    final newerRootBase64 = base64.encode(newerRootBytes);
    final expectedNewestRoot =
        HivraIdFormat.formatCapsuleKeyBytes(newerRootBytes);

    final groups = <RelationshipPeerGroup>[
      RelationshipPeerGroup(
        peerPubkey: peerBase64,
        relationships: <Relationship>[
          Relationship(
            peerPubkey: peerBase64,
            peerRootPubkey: olderRootBase64,
            kind: StarterKind.kick,
            ownStarterId: base64.encode(List<int>.filled(32, 0x41)),
            peerStarterId: base64.encode(List<int>.filled(32, 0x42)),
            establishedAt: DateTime.utc(2026, 4, 16, 10),
          ),
          Relationship(
            peerPubkey: peerBase64,
            peerRootPubkey: newerRootBase64,
            kind: StarterKind.spark,
            ownStarterId: base64.encode(List<int>.filled(32, 0x43)),
            peerStarterId: base64.encode(List<int>.filled(32, 0x44)),
            establishedAt: DateTime.utc(2026, 4, 16, 11),
          ),
        ],
      ),
    ];

    final service = RelationshipService(
      loadRelationshipGroups: () => groups,
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService:
          const _FakeCapsuleAddressService(cards: <CapsuleAddressCard>[]),
    );

    final resolved = await service.loadPeerRootKeysByTransportBase64(
      <String>[peerBase64],
    );

    expect(resolved[peerBase64], expectedNewestRoot);
  });

  test(
      'loadPeerRootKeysForGroups resolves non-representative transport keys from relationships',
      () async {
    String b64(int value) => base64.encode(List<int>.filled(32, value));
    String hex32(int value) => List<int>.filled(32, value)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final representativePeerB64 = b64(11);
    final linkedPeerWithCardB64 = b64(12);
    final rootBytes = Uint8List.fromList(List<int>.filled(32, 21));
    final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);

    final groups = <RelationshipPeerGroup>[
      RelationshipPeerGroup(
        peerPubkey: representativePeerB64,
        relationships: <Relationship>[
          Relationship(
            peerPubkey: representativePeerB64,
            kind: StarterKind.kick,
            ownStarterId: b64(31),
            peerStarterId: b64(41),
            establishedAt: DateTime.utc(2026, 4, 1, 9),
          ),
          Relationship(
            peerPubkey: linkedPeerWithCardB64,
            kind: StarterKind.spark,
            ownStarterId: b64(32),
            peerStarterId: b64(42),
            establishedAt: DateTime.utc(2026, 4, 1, 10),
          ),
        ],
      ),
    ];

    final service = RelationshipService(
      loadRelationshipGroups: () => groups,
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService: _FakeCapsuleAddressService(
        cards: <CapsuleAddressCard>[
          CapsuleAddressCard(
            rootKey: rootKey,
            rootHex: hex32(21),
            nostrNpub: 'npub1test',
            nostrHex: hex32(12),
          ),
        ],
      ),
    );

    final resolved = await service.loadPeerRootKeysForGroups(groups);

    expect(resolved[representativePeerB64], isNull);
    expect(resolved[linkedPeerWithCardB64], rootKey);
  });

  test('loadPeerRootKeysForInvitations resolves incoming and outgoing peers',
      () async {
    String b64(int value) => base64.encode(List<int>.filled(32, value));
    String hex32(int value) => List<int>.filled(32, value)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final incomingPeerB64 = b64(131);
    final outgoingPeerB64 = b64(132);
    final incomingRootBytes = Uint8List.fromList(List<int>.filled(32, 141));
    final outgoingRootBytes = Uint8List.fromList(List<int>.filled(32, 142));
    final incomingRootKey =
        HivraIdFormat.formatCapsuleKeyBytes(incomingRootBytes);
    final outgoingRootKey =
        HivraIdFormat.formatCapsuleKeyBytes(outgoingRootBytes);

    final service = RelationshipService(
      loadRelationshipGroups: () => const <RelationshipPeerGroup>[],
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
      addressService: _FakeCapsuleAddressService(
        cards: <CapsuleAddressCard>[
          CapsuleAddressCard(
            rootKey: incomingRootKey,
            rootHex: hex32(141),
            nostrNpub: 'npub1incoming',
            nostrHex: hex32(131),
          ),
          CapsuleAddressCard(
            rootKey: outgoingRootKey,
            rootHex: hex32(142),
            nostrNpub: 'npub1outgoing',
            nostrHex: hex32(132),
          ),
        ],
      ),
    );

    final resolved = await service.loadPeerRootKeysForInvitations(
      <Invitation>[
        Invitation(
          id: 'incoming-id',
          fromPubkey: incomingPeerB64,
          kind: StarterKind.juice,
          status: InvitationStatus.pending,
          sentAt: DateTime.utc(2026, 4, 16, 12),
          expiresAt: DateTime.utc(2026, 4, 17, 12),
        ),
        Invitation(
          id: 'outgoing-id',
          fromPubkey: b64(201),
          toPubkey: outgoingPeerB64,
          kind: StarterKind.kick,
          status: InvitationStatus.pending,
          sentAt: DateTime.utc(2026, 4, 16, 12),
          expiresAt: DateTime.utc(2026, 4, 17, 12),
        ),
      ],
    );

    expect(resolved[incomingPeerB64], incomingRootKey);
    expect(resolved[outgoingPeerB64], outgoingRootKey);
  });

  test('resolvePeerRootDisplayKey prefers projected root from group', () {
    String b64(int value) => base64.encode(List<int>.filled(32, value));
    final peerB64 = b64(91);
    final projectedRoot = b64(92);
    final expectedRoot =
        HivraIdFormat.formatCapsuleKeyFromBase64(projectedRoot);

    final group = RelationshipPeerGroup(
      peerPubkey: peerB64,
      relationships: <Relationship>[
        Relationship(
          peerPubkey: peerB64,
          peerRootPubkey: projectedRoot,
          kind: StarterKind.juice,
          ownStarterId: b64(93),
          peerStarterId: b64(94),
          establishedAt: DateTime.utc(2026, 4, 16, 9),
        ),
      ],
    );

    final service = RelationshipService(
      loadRelationshipGroups: () => <RelationshipPeerGroup>[group],
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
    );

    final resolved = service.resolvePeerRootDisplayKey(
      group: group,
      importedRootKeyByTransportB64: const <String, String>{},
    );

    expect(resolved, expectedRoot);
  });

  test(
      'resolvePeerRootDisplayKey falls back to latest imported relationship transport key',
      () {
    String b64(int value) => base64.encode(List<int>.filled(32, value));
    final representativePeerB64 = b64(101);
    final linkedOldPeerB64 = b64(102);
    final linkedNewPeerB64 = b64(103);
    const oldRoot = 'h1oldrootkey';
    const newRoot = 'h1newrootkey';

    final group = RelationshipPeerGroup(
      peerPubkey: representativePeerB64,
      relationships: <Relationship>[
        Relationship(
          peerPubkey: linkedOldPeerB64,
          kind: StarterKind.kick,
          ownStarterId: b64(104),
          peerStarterId: b64(105),
          establishedAt: DateTime.utc(2026, 4, 16, 9),
        ),
        Relationship(
          peerPubkey: linkedNewPeerB64,
          kind: StarterKind.spark,
          ownStarterId: b64(106),
          peerStarterId: b64(107),
          establishedAt: DateTime.utc(2026, 4, 16, 10),
        ),
      ],
    );

    final service = RelationshipService(
      loadRelationshipGroups: () => <RelationshipPeerGroup>[group],
      breakRelationship: (_, __, ___) => true,
      persistLedgerSnapshot: () async {},
    );

    final resolved = service.resolvePeerRootDisplayKey(
      group: group,
      importedRootKeyByTransportB64: <String, String>{
        linkedOldPeerB64: oldRoot,
        linkedNewPeerB64: newRoot,
      },
    );

    expect(resolved, newRoot);
  });
}

class _FakeCapsuleAddressService extends CapsuleAddressService {
  final List<CapsuleAddressCard> cards;

  const _FakeCapsuleAddressService({required this.cards});

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async => cards;
}
