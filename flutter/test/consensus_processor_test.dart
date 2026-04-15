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
      expect(
        previews.first.canonicalJson.contains('"pair_roots_sorted"'),
        isTrue,
      );
      expect(
        previews.first.canonicalJson.contains('"pair_transport_keys_sorted"'),
        isFalse,
      );
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

    test('signable accepts uppercase peer hex input', () {
      final invitationId = Uint8List.fromList(bytes32(36));
      final ownStarter = Uint8List.fromList(bytes32(37));
      final peerTransport = Uint8List.fromList(bytes32(38));
      final peerRoot = Uint8List.fromList(bytes32(39));
      final peerStarter = Uint8List.fromList(bytes32(40));
      final sender = Uint8List.fromList(bytes32(41));
      final senderStarter = Uint8List.fromList(bytes32(42));
      final localTransport = Uint8List.fromList(bytes32(43));
      final peerHexUpper = hex(peerRoot).toUpperCase();

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
            ...bytes32(44),
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: peerHexUpper,
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.peerHex, equals(hex(peerRoot)));
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('pending_invitation'),
      );
    });

    test(
      'preview orients mirrored root-augmented relationship away from local self',
      () {
        final localTransport = Uint8List.fromList(bytes32(51));
        final localRoot = Uint8List.fromList(bytes32(52));
        final remoteTransport = Uint8List.fromList(bytes32(53));
        final remoteRoot = Uint8List.fromList(bytes32(54));
        final invitationId = Uint8List.fromList(bytes32(55));
        final localStarter = Uint8List.fromList(bytes32(56));
        final remoteStarter = Uint8List.fromList(bytes32(57));

        final events = <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 7,
            'payload': <int>[
              // Mirrored payload: peer points to local side.
              ...localTransport,
              ...remoteStarter,
              ...localStarter,
              1,
              ...invitationId,
              ...remoteTransport,
              1,
              ...remoteStarter,
              ...localRoot,
              ...remoteRoot,
            ],
            'signer': remoteRoot,
          },
        ];

        final previews = processor.preview(
          events,
          localTransport,
          localRootKey: localRoot,
        );

        expect(previews, hasLength(1));
        expect(previews.single.peerHex, equals(hex(remoteRoot)));
        expect(previews.single.relationshipCount, equals(1));
        expect(
          previews.any((row) => row.peerHex == hex(localRoot)),
          isFalse,
        );
      },
    );

    test('signable rejects malformed peer hex input', () {
      final localTransport = Uint8List.fromList(bytes32(45));
      final signable = processor.signable(
        const <Map<String, dynamic>>[],
        localTransport,
        peerHex: 'zz-not-hex',
      );

      expect(signable.preview, isNull);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('invalid_peer_id'),
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

    test('verify blocks duplicate participant entries', () {
      final result = processor.verify(
        expectedHashHex: 'a' * 64,
        participants: <ConsensusVerifyParticipant>[
          ConsensusVerifyParticipant(
            participantId: 'peer',
            hashHex: 'a' * 64,
            signatureHex: 'b' * 128,
          ),
          ConsensusVerifyParticipant(
            participantId: 'peer',
            hashHex: 'a' * 64,
            signatureHex: 'c' * 128,
          ),
        ],
      );

      expect(result.state, ConsensusVerifyState.mismatch);
      expect(
        result.blockingFacts.map((fact) => fact.key),
        contains('duplicate_participant:peer'),
      );
    });

    test(
      'verify treats uppercase/lowercase hex participant ids as duplicates',
      () {
        final participantHexLower = 'b' * 64;
        final participantHexUpper = participantHexLower.toUpperCase();
        final result = processor.verify(
          expectedHashHex: 'a' * 64,
          participants: <ConsensusVerifyParticipant>[
            ConsensusVerifyParticipant(
              participantId: participantHexLower,
              hashHex: 'a' * 64,
              signatureHex: 'c' * 128,
            ),
            ConsensusVerifyParticipant(
              participantId: participantHexUpper,
              hashHex: 'a' * 64,
              signatureHex: 'd' * 128,
            ),
          ],
        );

        expect(result.state, ConsensusVerifyState.mismatch);
        expect(
          result.blockingFacts.map((fact) => fact.key),
          contains('duplicate_participant:$participantHexLower'),
        );
      },
    );

    test('verify calls signature verifier callback for matching hashes', () {
      String? seenMessage;
      String? seenParticipant;
      String? seenSignature;
      final result = processor.verify(
        expectedHashHex: 'a' * 64,
        participants: <ConsensusVerifyParticipant>[
          ConsensusVerifyParticipant(
            participantId: 'b' * 64,
            hashHex: 'a' * 64,
            signatureHex: 'c' * 128,
          ),
        ],
        verifySignature: ({
          required String messageHashHex,
          required String participantIdHex,
          required String signatureHex,
        }) {
          seenMessage = messageHashHex;
          seenParticipant = participantIdHex;
          seenSignature = signatureHex;
          return true;
        },
      );

      expect(result.state, ConsensusVerifyState.match);
      expect(result.blockingFacts, isEmpty);
      expect(seenMessage, equals('a' * 64));
      expect(seenParticipant, equals('b' * 64));
      expect(seenSignature, equals('c' * 128));
    });

    test('verify marks invalid_signature when callback rejects signature', () {
      final participantHex = 'b' * 64;
      final result = processor.verify(
        expectedHashHex: 'a' * 64,
        participants: <ConsensusVerifyParticipant>[
          ConsensusVerifyParticipant(
            participantId: participantHex,
            hashHex: 'a' * 64,
            signatureHex: 'c' * 128,
          ),
        ],
        verifySignature: ({
          required String messageHashHex,
          required String participantIdHex,
          required String signatureHex,
        }) =>
            false,
      );

      expect(result.state, ConsensusVerifyState.mismatch);
      expect(
        result.blockingFacts.map((fact) => fact.key),
        contains('invalid_signature:$participantHex'),
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

    test('preview hash is stable across event order and sender metadata noise',
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
      expect(
          variantPreview.first.hashHex, equals(baselinePreview.first.hashHex));
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
      expect(
          previewA.first.canonicalJson, equals(previewB.first.canonicalJson));
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
        'preview ignores incoming invitation events not addressed to local transport key',
        () {
      final invitationId = Uint8List.fromList(bytes32(92));
      final peerStarter = Uint8List.fromList(bytes32(93));
      final localTransport = Uint8List.fromList(bytes32(94));
      final foreignTransport = Uint8List.fromList(bytes32(95));
      final senderTransport = Uint8List.fromList(bytes32(96));
      final peerRoot = Uint8List.fromList(bytes32(97));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 9,
          'payload': <int>[
            ...invitationId,
            ...peerStarter,
            ...foreignTransport,
            ...peerRoot,
            1,
          ],
          'signer': senderTransport,
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test('preview ignores foreign InvitationSent not addressed to local identity',
        () {
      final invitationId = Uint8List.fromList(bytes32(111));
      final ownStarter = Uint8List.fromList(bytes32(112));
      final localTransport = Uint8List.fromList(bytes32(113));
      final foreignTransport = Uint8List.fromList(bytes32(114));
      final peerTransport = Uint8List.fromList(bytes32(115));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...foreignTransport,
            1,
          ],
          'signer': peerTransport,
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test(
        'preview treats peer-signed InvitationSent addressed to local transport as incoming pending',
        () {
      final anchorInvitationId = Uint8List.fromList(bytes32(120));
      final anchorOwnStarter = Uint8List.fromList(bytes32(121));
      final anchorPeerStarter = Uint8List.fromList(bytes32(122));
      final peerRoot = Uint8List.fromList(bytes32(123));
      final senderTransport = Uint8List.fromList(bytes32(124));
      final senderStarter = Uint8List.fromList(bytes32(125));
      final senderRoot = Uint8List.fromList(bytes32(126));
      final invitationId = Uint8List.fromList(bytes32(116));
      final peerStarter = Uint8List.fromList(bytes32(117));
      final localTransport = Uint8List.fromList(bytes32(118));
      final peerTransport = Uint8List.fromList(bytes32(119));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...anchorOwnStarter,
            ...anchorPeerStarter,
            1,
            ...anchorInvitationId,
            ...senderTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...senderRoot,
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...peerStarter,
            ...localTransport,
            1,
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

    test('preview ignores self-addressed outgoing invitation events', () {
      final invitationId = Uint8List.fromList(bytes32(98));
      final ownStarter = Uint8List.fromList(bytes32(99));
      final localTransport = Uint8List.fromList(bytes32(100));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...localTransport,
            1,
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test('preview ignores self-signed incoming invitation events', () {
      final invitationId = Uint8List.fromList(bytes32(101));
      final peerStarter = Uint8List.fromList(bytes32(102));
      final localTransport = Uint8List.fromList(bytes32(103));
      final peerRoot = Uint8List.fromList(bytes32(104));

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
          'signer': localTransport,
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test('preview drops transport-self relationship peer rows', () {
      final localTransport = Uint8List.fromList(bytes32(105));
      final remoteTransport = Uint8List.fromList(bytes32(106));
      final invitationId = Uint8List.fromList(bytes32(107));
      final ownStarter = Uint8List.fromList(bytes32(108));
      final peerStarter = Uint8List.fromList(bytes32(109));
      final senderStarter = Uint8List.fromList(bytes32(110));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...localTransport,
            ...ownStarter,
            ...peerStarter,
            1,
            ...invitationId,
            ...remoteTransport,
            1,
            ...senderStarter,
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test(
        'preview maps remote acceptance root anchor when InvitationAccepted is remote-signed',
        () {
      final invitationId = Uint8List.fromList(bytes32(127));
      final ownStarter = Uint8List.fromList(bytes32(128));
      final peerTransport = Uint8List.fromList(bytes32(129));
      final peerRoot = Uint8List.fromList(bytes32(130));
      final localTransport = Uint8List.fromList(bytes32(131));
      final createdStarter = Uint8List.fromList(bytes32(132));

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
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...createdStarter,
            ...peerRoot,
          ],
          'signer': peerTransport,
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.peerHex, equals(hex(peerRoot)));
      expect(
        previews.first.blockingFacts.map((fact) => fact.code),
        contains('no_active_relationship'),
      );
    });

    test(
        'preview does not map remote acceptance root anchor when signer is absent',
        () {
      final invitationId = Uint8List.fromList(bytes32(86));
      final ownStarter = Uint8List.fromList(bytes32(87));
      final peerTransport = Uint8List.fromList(bytes32(88));
      final peerRoot = Uint8List.fromList(bytes32(89));
      final localTransport = Uint8List.fromList(bytes32(90));
      final createdStarter = Uint8List.fromList(bytes32(91));

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
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...createdStarter,
            ...peerRoot,
          ],
          // signer intentionally omitted to mimic legacy/imported records.
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, isEmpty);
    });

    test(
        'preview does not infer peer root from local invitation lineage root fields',
        () {
      final invitationId = Uint8List.fromList(bytes32(77));
      final ownStarter = Uint8List.fromList(bytes32(78));
      final peerTransport = Uint8List.fromList(bytes32(79));
      final peerStarter = Uint8List.fromList(bytes32(80));
      final senderTransport = Uint8List.fromList(bytes32(81));
      final senderStarter = Uint8List.fromList(bytes32(82));
      final localTransport = Uint8List.fromList(bytes32(83));
      final localRoot = Uint8List.fromList(bytes32(84));
      final acceptedCreated = Uint8List.fromList(bytes32(85));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationId,
            ...ownStarter,
            ...peerTransport,
            ...localRoot,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...acceptedCreated,
            ...localRoot,
          ],
          'signer': localTransport,
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
          ],
        },
      ];

      final previews = processor.preview(events, localTransport);

      expect(previews, hasLength(1));
      expect(previews.first.peerHex, equals(hex(peerTransport)));
      expect(previews.first.peerHex, isNot(equals(hex(localRoot))));
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
        're-established relationship clears prior break block for same own starter',
        () {
      final localTransport = Uint8List.fromList(bytes32(161));
      final invitationA = Uint8List.fromList(bytes32(162));
      final invitationB = Uint8List.fromList(bytes32(163));
      final ownStarter = Uint8List.fromList(bytes32(164));
      final peerTransport = Uint8List.fromList(bytes32(165));
      final peerRoot = Uint8List.fromList(bytes32(166));
      final peerStarterA = Uint8List.fromList(bytes32(167));
      final peerStarterB = Uint8List.fromList(bytes32(168));
      final sender = Uint8List.fromList(bytes32(169));
      final senderStarterA = Uint8List.fromList(bytes32(170));
      final senderStarterB = Uint8List.fromList(bytes32(171));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationA,
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
            ...peerStarterA,
            1,
            ...invitationA,
            ...sender,
            1,
            ...senderStarterA,
            ...peerRoot,
            ...bytes32(172),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationA,
            ...bytes32(173),
            ...bytes32(174),
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerRoot,
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationB,
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
            ...peerStarterB,
            1,
            ...invitationB,
            ...sender,
            1,
            ...senderStarterB,
            ...peerRoot,
            ...bytes32(175),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationB,
            ...bytes32(176),
            ...bytes32(177),
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.isSignable, isTrue);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
    });

    test(
        'partial break keeps pair signable when another active relationship remains',
        () {
      final localTransport = Uint8List.fromList(bytes32(181));
      final invitationA = Uint8List.fromList(bytes32(182));
      final invitationB = Uint8List.fromList(bytes32(183));
      final ownStarterA = Uint8List.fromList(bytes32(184));
      final ownStarterB = Uint8List.fromList(bytes32(185));
      final peerTransport = Uint8List.fromList(bytes32(186));
      final peerRoot = Uint8List.fromList(bytes32(187));
      final peerStarterA = Uint8List.fromList(bytes32(188));
      final peerStarterB = Uint8List.fromList(bytes32(189));
      final sender = Uint8List.fromList(bytes32(190));
      final senderStarterA = Uint8List.fromList(bytes32(191));
      final senderStarterB = Uint8List.fromList(bytes32(192));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationA,
            ...ownStarterA,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarterA,
            ...peerStarterA,
            1,
            ...invitationA,
            ...sender,
            1,
            ...senderStarterA,
            ...peerRoot,
            ...bytes32(193),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationA,
            ...bytes32(194),
            ...bytes32(195),
          ],
        },
        <String, dynamic>{
          'kind': 1,
          'payload': <int>[
            ...invitationB,
            ...ownStarterB,
            ...peerTransport,
            1,
          ],
        },
        <String, dynamic>{
          'kind': 7,
          'payload': <int>[
            ...peerTransport,
            ...ownStarterB,
            ...peerStarterB,
            1,
            ...invitationB,
            ...sender,
            1,
            ...senderStarterB,
            ...peerRoot,
            ...bytes32(196),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationB,
            ...bytes32(197),
            ...bytes32(198),
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarterA,
            ...peerRoot,
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(1));
      expect(signable.isSignable, isTrue);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('no_active_relationship')),
      );
    });

    test(
        'remote-signed break keeps relationship active but blocks signable as pending remote break',
        () {
      final localTransport = Uint8List.fromList(bytes32(241));
      final localRoot = Uint8List.fromList(bytes32(242));
      final invitationId = Uint8List.fromList(bytes32(243));
      final ownStarter = Uint8List.fromList(bytes32(244));
      final peerTransport = Uint8List.fromList(bytes32(245));
      final peerRoot = Uint8List.fromList(bytes32(246));
      final peerStarter = Uint8List.fromList(bytes32(247));
      final senderStarter = Uint8List.fromList(bytes32(248));

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
            ...localTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...localRoot,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...peerTransport,
            ...peerStarter,
            ...peerRoot,
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerRoot,
          ],
          'signer': peerTransport,
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        localRootKey: localRoot,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(1));
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('pending_remote_break'),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('no_active_relationship')),
      );
    });

    test('local-signed break finalizes relationship for consensus', () {
      final localTransport = Uint8List.fromList(bytes32(251));
      final localRoot = Uint8List.fromList(bytes32(252));
      final invitationId = Uint8List.fromList(bytes32(253));
      final ownStarter = Uint8List.fromList(bytes32(254));
      final peerTransport = Uint8List.fromList(bytes32(255));
      final peerRoot = Uint8List.fromList(bytes32(200));
      final peerStarter = Uint8List.fromList(bytes32(201));
      final senderStarter = Uint8List.fromList(bytes32(202));

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
            ...localTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...localRoot,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...peerTransport,
            ...peerStarter,
            ...peerRoot,
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerRoot,
          ],
          'signer': localTransport,
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        localRootKey: localRoot,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(0));
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('relationship_broken'),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('no_active_relationship'),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('pending_remote_break')),
      );
    });

    test(
        'unsigned break is ignored when local root identity is available',
        () {
      final localTransport = Uint8List.fromList(bytes32(260));
      final localRoot = Uint8List.fromList(bytes32(261));
      final invitationId = Uint8List.fromList(bytes32(262));
      final ownStarter = Uint8List.fromList(bytes32(263));
      final peerTransport = Uint8List.fromList(bytes32(264));
      final peerRoot = Uint8List.fromList(bytes32(265));
      final peerStarter = Uint8List.fromList(bytes32(266));
      final senderStarter = Uint8List.fromList(bytes32(267));

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
            ...localTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...localRoot,
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...peerTransport,
            ...peerStarter,
            ...peerRoot,
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerRoot,
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        localRootKey: localRoot,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(1));
      expect(signable.isSignable, isTrue);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('pending_remote_break')),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('no_active_relationship')),
      );
    });

    test('unsigned break still applies when local root identity is unavailable',
        () {
      final localTransport = Uint8List.fromList(bytes32(270));
      final invitationId = Uint8List.fromList(bytes32(271));
      final ownStarter = Uint8List.fromList(bytes32(272));
      final peerTransport = Uint8List.fromList(bytes32(273));
      final peerRoot = Uint8List.fromList(bytes32(274));
      final peerStarter = Uint8List.fromList(bytes32(275));
      final senderStarter = Uint8List.fromList(bytes32(276));

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
            ...localTransport,
            1,
            ...senderStarter,
            ...peerRoot,
            ...bytes32(277),
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...peerTransport,
            ...peerStarter,
            ...peerRoot,
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
            ...peerRoot,
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.relationshipCount, equals(0));
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('relationship_broken'),
      );
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('no_active_relationship'),
      );
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

    test(
        'legacy relationship keeps invitation-derived root anchor and uses local root key',
        () {
      final invitationId = Uint8List.fromList(bytes32(201));
      final ownStarter = Uint8List.fromList(bytes32(202));
      final peerStarter = Uint8List.fromList(bytes32(203));
      final peerTransport = Uint8List.fromList(bytes32(204));
      final peerRoot = Uint8List.fromList(bytes32(205));
      final senderTransport = Uint8List.fromList(bytes32(206));
      final senderStarter = Uint8List.fromList(bytes32(207));
      final localTransport = Uint8List.fromList(bytes32(208));
      final localRoot = Uint8List.fromList(bytes32(209));

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
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...bytes32(210),
          ],
        },
      ];

      final previews = processor.preview(
        events,
        localTransport,
        localRootKey: localRoot,
      );

      expect(previews, hasLength(1));
      expect(previews.first.peerHex, equals(hex(peerRoot)));
      expect(previews.first.canonicalJson.contains(hex(peerRoot)), isTrue);
      expect(previews.first.canonicalJson.contains(hex(localRoot)), isTrue);
      expect(
          previews.first.canonicalJson.contains(hex(localTransport)), isFalse);
    });

    test(
        'legacy relationship root anchor is stable regardless of invite/relationship order',
        () {
      final invitationId = Uint8List.fromList(bytes32(211));
      final ownStarter = Uint8List.fromList(bytes32(212));
      final peerStarter = Uint8List.fromList(bytes32(213));
      final peerTransport = Uint8List.fromList(bytes32(214));
      final peerRoot = Uint8List.fromList(bytes32(215));
      final senderTransport = Uint8List.fromList(bytes32(216));
      final senderStarter = Uint8List.fromList(bytes32(217));
      final localTransport = Uint8List.fromList(bytes32(218));
      final localRoot = Uint8List.fromList(bytes32(219));

      final invitationReceived = <String, dynamic>{
        'kind': 9,
        'payload': <int>[
          ...invitationId,
          ...peerStarter,
          ...localTransport,
          ...peerRoot,
          1,
        ],
        'signer': peerTransport,
      };
      final relationshipEstablishedLegacy = <String, dynamic>{
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
        ],
      };
      final accepted = <String, dynamic>{
        'kind': 2,
        'payload': <int>[
          ...invitationId,
          ...localTransport,
          ...bytes32(220),
        ],
      };

      final orderA = <Map<String, dynamic>>[
        invitationReceived,
        relationshipEstablishedLegacy,
        accepted,
      ];
      final orderB = <Map<String, dynamic>>[
        relationshipEstablishedLegacy,
        invitationReceived,
        accepted,
      ];

      final previewsA = processor.preview(
        orderA,
        localTransport,
        localRootKey: localRoot,
      );
      final previewsB = processor.preview(
        orderB,
        localTransport,
        localRootKey: localRoot,
      );

      expect(previewsA, hasLength(1));
      expect(previewsB, hasLength(1));
      expect(previewsA.first.peerHex, equals(hex(peerRoot)));
      expect(previewsB.first.peerHex, equals(hex(peerRoot)));
      expect(previewsA.first.hashHex, equals(previewsB.first.hashHex));
      expect(
          previewsA.first.canonicalJson, equals(previewsB.first.canonicalJson));
    });

    test(
        'unresolved legacy break does not override a later relationship establish',
        () {
      final invitationId = Uint8List.fromList(bytes32(221));
      final ownStarter = Uint8List.fromList(bytes32(222));
      final peerStarter = Uint8List.fromList(bytes32(223));
      final peerTransport = Uint8List.fromList(bytes32(224));
      final peerRoot = Uint8List.fromList(bytes32(225));
      final senderTransport = Uint8List.fromList(bytes32(226));
      final senderStarter = Uint8List.fromList(bytes32(227));
      final localTransport = Uint8List.fromList(bytes32(228));

      final events = <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
          ],
        },
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
          ],
        },
        <String, dynamic>{
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...bytes32(229),
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.peerHex, equals(hex(peerRoot)));
      expect(signable.preview!.relationshipCount, equals(1));
      expect(signable.isSignable, isTrue);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
    });

    test(
        'unresolved legacy break still applies when it is newer than relationship establish',
        () {
      final invitationId = Uint8List.fromList(bytes32(231));
      final ownStarter = Uint8List.fromList(bytes32(232));
      final peerStarter = Uint8List.fromList(bytes32(233));
      final peerTransport = Uint8List.fromList(bytes32(234));
      final peerRoot = Uint8List.fromList(bytes32(235));
      final senderTransport = Uint8List.fromList(bytes32(236));
      final senderStarter = Uint8List.fromList(bytes32(237));
      final localTransport = Uint8List.fromList(bytes32(238));

      final events = <Map<String, dynamic>>[
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
          ],
        },
        <String, dynamic>{
          'kind': 8,
          'payload': <int>[
            ...peerTransport,
            ...ownStarter,
          ],
        },
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
          'kind': 2,
          'payload': <int>[
            ...invitationId,
            ...localTransport,
            ...bytes32(239),
          ],
        },
      ];

      final signable = processor.signable(
        events,
        localTransport,
        peerHex: hex(peerRoot),
      );

      expect(signable.preview, isNotNull);
      expect(signable.preview!.peerHex, equals(hex(peerRoot)));
      expect(signable.preview!.relationshipCount, equals(0));
      expect(signable.isSignable, isFalse);
      expect(
        signable.blockingFacts.map((fact) => fact.code),
        contains('relationship_broken'),
      );
    });
  });
}
