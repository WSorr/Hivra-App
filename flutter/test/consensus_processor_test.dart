import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';

void main() {
  group('ConsensusProcessor', () {
    const processor = ConsensusProcessor();

    List<int> bytes32(int value) => List<int>.filled(32, value);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    test('preview derives canonical hash from shared ledger projections', () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 1));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
      final sender = Uint8List.fromList(List<int>.filled(32, 6));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
      final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
      final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));
      final localTransport = Uint8List.fromList(List<int>.filled(32, 11));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerRoot,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...sender,
            1,
            ...senderStarter,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...acceptedFrom,
            ...acceptedCreated,
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.invitationCount, 1);
      expect(previews.first.relationshipCount, 1);
      expect(previews.first.blockingFacts, isEmpty);
      expect(previews.first.hashHex, hasLength(64));
      expect(previews.first.canonicalJson.contains('"status": "accepted"'),
          isTrue);
    });

    test('signable reports blocking facts for pending pairwise history', () {
      final acceptedInvitationId = Uint8List.fromList(List<int>.filled(32, 1));
      final pendingInvitationId = Uint8List.fromList(List<int>.filled(32, 12));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
      final ownStarter2 = Uint8List.fromList(List<int>.filled(32, 13));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
      final sender = Uint8List.fromList(List<int>.filled(32, 6));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
      final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
      final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));
      final localTransport = Uint8List.fromList(List<int>.filled(32, 11));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...acceptedInvitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerRoot,
            ...ownStarter,
            ...peerStarter,
            1,
            ...acceptedInvitationId,
            ...sender,
            1,
            ...senderStarter,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...acceptedInvitationId,
            ...acceptedFrom,
            ...acceptedCreated,
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...pendingInvitationId,
            ...ownStarter2,
            ...peerTransport,
            1,
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: List<int>.filled(32, 4)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      );

      expect(signable.preview, isNotNull);
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.key),
        contains(
          'pending_invitation:${List<int>.filled(32, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
        ),
      );
    });

    test('signable is blocked when there is no active relationship', () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 31));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 32));
      final localTransport = Uint8List.fromList(List<int>.filled(32, 33));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 34));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 35));
      final peerHex = List<int>.filled(32, 35)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 9,
          'payload': <int>[
            ...invitationId,
            ...peerStarter,
            ...localTransport,
            ...peerRoot,
            1,
          ],
          'signer': peerTransport,
        },
        <String, dynamic>{
          'kind': 3,
          'payload': <int>[
            ...invitationId,
            0,
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: peerHex,
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(0));
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('no_active_relationship'),
      );
    });

    test('verify checks hash equality and signature set shape', () {
      final result = processor.verify(
        expectedHashHex: 'a' * 64,
        participants: <ConsensusVerifyParticipant>[
          ConsensusVerifyParticipant(
            participantId: 'local',
            hashHex: 'a' * 64,
            signatureHex: 'b' * 128,
          ),
          ConsensusVerifyParticipant(
            participantId: 'peer',
            hashHex: 'c' * 64,
            signatureHex: '',
          ),
        ],
      );

      expect(result.state, ConsensusVerifyState.mismatch);
      expect(
        result.blockingFacts.map((fact) => fact.key),
        contains('hash_mismatch:peer'),
      );
      expect(
        result.blockingFacts.map((fact) => fact.key),
        contains('missing_signature:peer'),
      );
    });

    test(
        'preview ignores local starter-state events when pairwise facts are unchanged',
        () {
      final invitationId = Uint8List.fromList(bytes32(1));
      final ownStarter = Uint8List.fromList(bytes32(2));
      final peerTransport = Uint8List.fromList(bytes32(3));
      final peerRoot = Uint8List.fromList(bytes32(4));
      final peerStarter = Uint8List.fromList(bytes32(5));
      final sender = Uint8List.fromList(bytes32(6));
      final senderStarter = Uint8List.fromList(bytes32(7));
      final acceptedFrom = Uint8List.fromList(bytes32(8));
      final acceptedCreated = Uint8List.fromList(bytes32(9));
      final localTransport = Uint8List.fromList(bytes32(11));
      final localNoiseStarterA = Uint8List.fromList(bytes32(21));
      final localNoiseStarterB = Uint8List.fromList(bytes32(22));

      final pairwiseEvents = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerRoot,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...sender,
            1,
            ...senderStarter,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...acceptedFrom,
            ...acceptedCreated,
          ],
        },
      ];

      final withLocalNoise = <Map<String, dynamic>>[
        ...pairwiseEvents,
        <String, dynamic>{
          'kind': 5,
          'payload': <int>[
            ...localNoiseStarterA,
            ...bytes32(99),
            4,
            0,
          ],
        },
        <String, dynamic>{
          'kind': 6,
          'payload': <int>[
            ...localNoiseStarterB,
          ],
        },
      ];

      final basePreview = processor.preview(pairwiseEvents, localTransport);
      final noisePreview = processor.preview(withLocalNoise, localTransport);

      expect(basePreview, hasLength(1));
      expect(noisePreview, hasLength(1));
      expect(noisePreview.first.hashHex, equals(basePreview.first.hashHex));
      expect(noisePreview.first.canonicalJson,
          equals(basePreview.first.canonicalJson));
    });

    test(
        'preview hash is stable across event order and sender metadata noise',
        () {
      final invitationId = Uint8List.fromList(bytes32(31));
      final ownStarter = Uint8List.fromList(bytes32(32));
      final peerTransport = Uint8List.fromList(bytes32(33));
      final peerRoot = Uint8List.fromList(bytes32(34));
      final peerStarter = Uint8List.fromList(bytes32(35));
      final localTransport = Uint8List.fromList(bytes32(36));

      final baselineEvents = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...bytes32(37),
            1,
            ...bytes32(38),
            ...peerRoot,
            ...bytes32(39),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(40),
            ...bytes32(41),
          ],
        },
      ];

      final reorderedWithSenderNoise = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(52),
            ...bytes32(53),
          ],
        },
        <String, dynamic>{
          'kind': 5,
          'payload': <int>[
            ...bytes32(54),
            ...bytes32(55),
            2,
            0,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...bytes32(56),
            1,
            ...bytes32(57),
            ...peerRoot,
            ...bytes32(58),
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
      ];

      final baselinePreview = processor.preview(baselineEvents, localTransport);
      final variantPreview =
          processor.preview(reorderedWithSenderNoise, localTransport);

      expect(baselinePreview, hasLength(1));
      expect(variantPreview, hasLength(1));
      expect(variantPreview.first.blockingFacts, isEmpty);
      expect(variantPreview.first.hashHex, equals(baselinePreview.first.hashHex));
      expect(
        variantPreview.first.canonicalJson,
        equals(baselinePreview.first.canonicalJson),
      );
    });

    test('preview yields same hash for symmetric A/B pair perspectives', () {
      final invitationId = Uint8List.fromList(bytes32(71));
      final rootA = Uint8List.fromList(bytes32(72));
      final rootB = Uint8List.fromList(bytes32(73));
      final transportA = Uint8List.fromList(bytes32(74));
      final transportB = Uint8List.fromList(bytes32(75));
      final starterA = Uint8List.fromList(bytes32(76));
      final starterB = Uint8List.fromList(bytes32(77));

      final eventsFromA = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...starterA,
            ...transportB,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...transportB,
            ...starterB,
            ...rootB,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...transportB,
            ...starterA,
            ...starterB,
            1,
            ...invitationId,
            ...transportA,
            1,
            ...starterA,
            ...rootB,
            ...rootA,
          ],
        },
      ];

      final eventsFromB = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...starterB,
            ...transportA,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...transportA,
            ...starterA,
            ...rootA,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...transportA,
            ...starterB,
            ...starterA,
            1,
            ...invitationId,
            ...transportB,
            1,
            ...starterB,
            ...rootA,
            ...rootB,
          ],
        },
      ];

      final previewA = processor.preview(
        eventsFromA,
        transportA,
        localRootKey: rootA,
      );
      final previewB = processor.preview(
        eventsFromB,
        transportB,
        localRootKey: rootB,
      );

      expect(previewA, hasLength(1));
      expect(previewB, hasLength(1));
      expect(previewA.first.blockingFacts, isEmpty);
      expect(previewB.first.blockingFacts, isEmpty);
      expect(previewA.first.hashHex, equals(previewB.first.hashHex));
      expect(previewA.first.canonicalJson, equals(previewB.first.canonicalJson));
    });

    test(
        'preview applies terminal invitation precedence accepted over rejected and expired',
        () {
      final invitationId = Uint8List.fromList(bytes32(41));
      final ownStarter = Uint8List.fromList(bytes32(42));
      final peerTransport = Uint8List.fromList(bytes32(43));
      final peerRoot = Uint8List.fromList(bytes32(44));
      final peerStarter = Uint8List.fromList(bytes32(45));
      final sender = Uint8List.fromList(bytes32(46));
      final senderStarter = Uint8List.fromList(bytes32(47));
      final localTransport = Uint8List.fromList(bytes32(51));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerRoot,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...sender,
            1,
            ...senderStarter,
          ],
        },
        <String, dynamic>{
          'kind': 3,
          'payload': <int>[
            ...invitationId,
            0,
          ],
        },
        <String, dynamic>{
          'kind': 4,
          'payload': <int>[
            ...invitationId,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(48),
            ...bytes32(49),
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.invitationCount, equals(1));
      expect(previews.first.blockingFacts, isEmpty);
      expect(previews.first.canonicalJson.contains('"status": "accepted"'),
          isTrue);
      expect(previews.first.canonicalJson.contains('"status": "rejected"'),
          isFalse);
      expect(previews.first.canonicalJson.contains('"status": "expired"'),
          isFalse);
    });

    test(
        'preview prefers root-augmented relationship anchor when payload carries peer_root_pubkey',
        () {
      final invitationId = Uint8List.fromList(bytes32(61));
      final ownStarter = Uint8List.fromList(bytes32(62));
      final peerTransport = Uint8List.fromList(bytes32(63));
      final peerRoot = Uint8List.fromList(bytes32(64));
      final peerStarter = Uint8List.fromList(bytes32(65));
      final senderTransport = Uint8List.fromList(bytes32(66));
      final senderStarter = Uint8List.fromList(bytes32(67));
      final senderRoot = Uint8List.fromList(bytes32(68));
      final localTransport = Uint8List.fromList(bytes32(69));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...senderTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...senderRoot,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(70),
            ...bytes32(71),
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.peerHex, equals(hex(peerRoot)));
      expect(previews.first.canonicalJson.contains(hex(peerRoot)), isTrue);
    });

    test(
        'preview maps incoming invitation to peer root from root-augmented offer payload',
        () {
      final invitationId = Uint8List.fromList(bytes32(72));
      final peerStarter = Uint8List.fromList(bytes32(73));
      final localTransport = Uint8List.fromList(bytes32(74));
      final peerTransport = Uint8List.fromList(bytes32(75));
      final peerRoot = Uint8List.fromList(bytes32(76));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 9,
          'payload': <int>[
            ...invitationId,
            ...peerStarter,
            ...localTransport,
            ...peerRoot,
            2,
          ],
          'signer': peerTransport,
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.peerHex, equals(hex(peerRoot)));
      expect(
        previews.first.blockingFacts.map((fact) => fact.code),
        contains('pending_invitation'),
      );
    });

    test(
        'relationship break blocks only affected pair while other pairs stay signable',
        () {
      final localTransport = Uint8List.fromList(bytes32(90));

      final invitationA = Uint8List.fromList(bytes32(91));
      final ownStarterA = Uint8List.fromList(bytes32(92));
      final peerTransportA = Uint8List.fromList(bytes32(93));
      final peerRootA = Uint8List.fromList(bytes32(94));
      final peerStarterA = Uint8List.fromList(bytes32(95));
      final senderA = Uint8List.fromList(bytes32(96));
      final senderStarterA = Uint8List.fromList(bytes32(97));

      final invitationB = Uint8List.fromList(bytes32(101));
      final ownStarterB = Uint8List.fromList(bytes32(102));
      final peerTransportB = Uint8List.fromList(bytes32(103));
      final peerRootB = Uint8List.fromList(bytes32(104));
      final peerStarterB = Uint8List.fromList(bytes32(105));
      final senderB = Uint8List.fromList(bytes32(106));
      final senderStarterB = Uint8List.fromList(bytes32(107));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationA,
            ...ownStarterA,
            ...peerTransportA,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransportA,
            ...ownStarterA,
            ...peerStarterA,
            1,
            ...invitationA,
            ...senderA,
            1,
            ...senderStarterA,
            ...peerRootA,
            ...bytes32(98),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationA,
            ...bytes32(99),
            ...bytes32(100),
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationB,
            ...ownStarterB,
            ...peerTransportB,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransportB,
            ...ownStarterB,
            ...peerStarterB,
            1,
            ...invitationB,
            ...senderB,
            1,
            ...senderStarterB,
            ...peerRootB,
            ...bytes32(108),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationB,
            ...bytes32(109),
            ...bytes32(110),
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransportA,
            ...ownStarterA,
            ...peerRootA,
          ],
        },
      ];

      final signableA = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRootA),
      );
      final signableB = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRootB),
      );

      expect(signableA.isSignable, isFalse);
      expect(
        signableA.blockingFacts.map((fact) => fact.code),
        contains('relationship_broken'),
      );
      expect(signableB.isSignable, isTrue);
      expect(signableB.blockingFacts, isEmpty);
    });

    test(
        'uses local root key for root-anchored pair when root key is available',
        () {
      final invitationId = Uint8List.fromList(bytes32(121));
      final ownStarter = Uint8List.fromList(bytes32(122));
      final peerTransport = Uint8List.fromList(bytes32(123));
      final peerRoot = Uint8List.fromList(bytes32(124));
      final peerStarter = Uint8List.fromList(bytes32(125));
      final sender = Uint8List.fromList(bytes32(126));
      final senderStarter = Uint8List.fromList(bytes32(127));
      final localTransport = Uint8List.fromList(bytes32(128));
      final localRoot = Uint8List.fromList(bytes32(129));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...sender,
            1,
            ...senderStarter,
            ...peerRoot,
            ...bytes32(130),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(131),
            ...bytes32(132),
          ],
        },
      ];

      final previews = processor.preview(
        events,
        localTransport,
        localRootKey: localRoot,
      );

      expect(previews, hasLength(1));
      expect(previews.first.canonicalJson.contains(hex(localRoot)), isTrue);
      expect(
        previews.first.canonicalJson.contains(hex(localTransport)),
        isFalse,
      );
    });

    test(
        'falls back to local transport key for legacy pair without root anchor',
        () {
      final invitationId = Uint8List.fromList(bytes32(141));
      final ownStarter = Uint8List.fromList(bytes32(142));
      final peerTransport = Uint8List.fromList(bytes32(143));
      final peerStarter = Uint8List.fromList(bytes32(145));
      final sender = Uint8List.fromList(bytes32(146));
      final senderStarter = Uint8List.fromList(bytes32(147));
      final localTransport = Uint8List.fromList(bytes32(148));
      final localRoot = Uint8List.fromList(bytes32(149));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...sender,
            1,
            ...senderStarter,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...bytes32(150),
            ...bytes32(151),
          ],
        },
      ];

      final previews = processor.preview(
        events,
        localTransport,
        localRootKey: localRoot,
      );

      expect(previews, hasLength(1));
      expect(
          previews.first.canonicalJson.contains(hex(localTransport)), isTrue);
      expect(previews.first.canonicalJson.contains(hex(localRoot)), isFalse);
    });
  });
}
