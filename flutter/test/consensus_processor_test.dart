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
  });
}
