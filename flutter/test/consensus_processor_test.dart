import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';

void main() {
  group('ConsensusProcessor', () {
    const processor = ConsensusProcessor();

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
  });
}
