import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/services/consensus_processor.dart';

void main() {
  const processor = ConsensusProcessor();

  String pairView({
    int finalizedInvitations = 1,
    List<Map<String, Object?>> relationships = const <Map<String, Object?>>[],
    List<Map<String, Object?>> blockers = const <Map<String, Object?>>[],
  }) => jsonEncode(<String, Object?>{
    'schema': 'hivra.pair_view',
    'version': 1,
    'ledger_version': 4,
    'pairs': <Object?>[
      <String, Object?>{
        'local_identity': List<int>.filled(32, 1),
        'peer_identity': List<int>.filled(32, 2),
        'finalized_invitation_count': finalizedInvitations,
        'active_relationships': relationships,
        'blockers': blockers,
      },
    ],
  });

  test('maps the versioned Core PairView into canonical snapshot v3', () {
    final preview =
        processor
            .preview(
              pairView(
                relationships: <Map<String, Object?>>[
                  <String, Object?>{
                    'relationship_kind': 1,
                    'starter_pair': <Object?>[
                      List<int>.filled(32, 4),
                      List<int>.filled(32, 3),
                    ],
                  },
                ],
              ),
            )
            .single;

    expect(preview.peerHex, '02' * 32);
    expect(preview.invitationCount, 1);
    expect(preview.relationshipCount, 1);
    expect(preview.hashHex, hasLength(64));
    expect(preview.canonicalJson, contains('"schema_version": 3'));
    expect(
      preview.canonicalJson.indexOf('03' * 32),
      lessThan(preview.canonicalJson.indexOf('04' * 32)),
    );
    expect(preview.isSignable, isTrue);
  });

  test('maps Core blockers and signable fails closed', () {
    final json = pairView(
      blockers: <Map<String, Object?>>[
        <String, Object?>{
          'code': 'pending_invitation',
          'subject_id': List<int>.filled(32, 9),
        },
      ],
    );
    final result = processor.signable(json, peerHex: '02' * 32);

    expect(result.isSignable, isFalse);
    expect(result.blockingFacts.single.key, 'pending_invitation:${'09' * 32}');
  });

  test('rejects malformed or wrong-version PairView', () {
    expect(processor.preview('{}'), isEmpty);
    expect(
      processor.preview(
        jsonEncode(<String, Object?>{
          'schema': 'hivra.pair_view',
          'version': 2,
          'pairs': <Object?>[],
        }),
      ),
      isEmpty,
    );
  });

  test('attestation commitment is symmetric and domain separated', () {
    final first = processor.buildAttestationCommitment(
      localRootHex: 'a' * 64,
      peerRootHex: 'b' * 64,
      snapshotHashHex: 'c' * 64,
    );
    final mirrored = processor.buildAttestationCommitment(
      localRootHex: 'b' * 64,
      peerRootHex: 'a' * 64,
      snapshotHashHex: 'c' * 64,
    );

    expect(first, isNotNull);
    expect(first!.canonicalJson, mirrored!.canonicalJson);
    expect(first.commitmentHashHex, mirrored.commitmentHashHex);
  });

  test('verify requires valid signatures for the expected hash', () {
    final result = processor.verify(
      expectedHashHex: 'a' * 64,
      participants: <ConsensusVerifyParticipant>[
        ConsensusVerifyParticipant(
          participantId: 'b' * 64,
          hashHex: 'a' * 64,
          signatureHex: 'c' * 128,
        ),
      ],
      verifySignature:
          ({
            required String messageHashHex,
            required String participantIdHex,
            required String signatureHex,
          }) => true,
    );

    expect(result.state, ConsensusVerifyState.match);
    expect(result.blockingFacts, isEmpty);
  });
}
