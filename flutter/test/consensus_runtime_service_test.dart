import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';

void main() {
  String pairView() => jsonEncode(<String, Object?>{
    'schema': 'hivra.pair_view',
    'version': 1,
    'ledger_version': 1,
    'pairs': <Object?>[
      <String, Object?>{
        'local_identity': List<int>.filled(32, 1),
        'peer_identity': List<int>.filled(32, 2),
        'finalized_invitation_count': 1,
        'active_relationships': <Object?>[
          <String, Object?>{
            'relationship_kind': 1,
            'starter_pair': <Object?>[
              List<int>.filled(32, 3),
              List<int>.filled(32, 4),
            ],
          },
        ],
        'blockers': <Object?>[],
      },
    ],
  });

  test('projects the ledger once and exposes preview plus signable', () {
    var exportCalls = 0;
    var projectionCalls = 0;
    final service = ConsensusRuntimeService(
      exportLedger: () {
        exportCalls += 1;
        return '{"events":[]}';
      },
      readLocalTransportKey: () => Uint8List.fromList(List<int>.filled(32, 8)),
      projectPairView: (ledger, transport) {
        projectionCalls += 1;
        expect(ledger, '{"events":[]}');
        expect(transport, hasLength(32));
        return pairView();
      },
    );

    final previews = service.preview();
    final signable = service.signable('02' * 32);

    expect(previews.single.isSignable, isTrue);
    expect(signable.isSignable, isTrue);
    expect(signable.hashHex, previews.single.hashHex);
    expect(exportCalls, 2);
    expect(projectionCalls, 2);
  });

  test(
    'fails closed when ledger, identity, or Core PairView is unavailable',
    () {
      ConsensusRuntimeService service({
        String? ledger = '{}',
        Uint8List? key,
        String? view,
      }) => ConsensusRuntimeService(
        exportLedger: () => ledger,
        readLocalTransportKey: () => key,
        projectPairView: (_, unused) => view,
      );

      expect(service(key: Uint8List(32), view: null).preview(), isEmpty);
      expect(service(ledger: null, key: Uint8List(32)).preview(), isEmpty);
      expect(service(key: null, view: pairView()).preview(), isEmpty);
      expect(
        service(
          key: Uint8List(32),
          view: null,
        ).signable('02' * 32).blockingFacts.single.code,
        'consensus_runtime_unavailable',
      );
    },
  );

  test('verify forwards the host signature verifier', () {
    var calls = 0;
    final service = ConsensusRuntimeService(
      exportLedger: () => null,
      readLocalTransportKey: () => null,
      verifySignature: ({
        required String messageHashHex,
        required String participantIdHex,
        required String signatureHex,
      }) {
        calls += 1;
        return true;
      },
    );

    final result = service.verify(
      expectedHashHex: 'a' * 64,
      participants: <ConsensusVerifyParticipant>[
        ConsensusVerifyParticipant(
          participantId: 'b' * 64,
          hashHex: 'a' * 64,
          signatureHex: 'c' * 128,
        ),
      ],
    );

    expect(calls, 1);
    expect(result.state, ConsensusVerifyState.match);
  });
}
