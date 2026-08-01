import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/plugin_execution_guard_service.dart';

void main() {
  PluginExecutionGuardService guard({String? blocker}) {
    return PluginExecutionGuardService(
      consensus: ConsensusRuntimeService(
        exportLedger: () => '{"events":[]}',
        readLocalTransportKey:
            () => Uint8List.fromList(List<int>.filled(32, 11)),
        projectPairView: (_, unused) => _pairView(blocker: blocker),
      ),
    );
  }

  test('reports ready when every Core pair is signable', () {
    final snapshot = guard().inspectHostReadiness();

    expect(snapshot.state, ConsensusGuardState.ready);
    expect(snapshot.readyPairCount, 1);
    expect(snapshot.blockedPairCount, 0);
    expect(snapshot.blockingFacts, isEmpty);
  });

  test('reports blocked when Core projects a pending invitation', () {
    final snapshot =
        guard(blocker: 'pending_invitation').inspectHostReadiness();

    expect(snapshot.state, ConsensusGuardState.blocked);
    expect(snapshot.readyPairCount, 0);
    expect(snapshot.blockedPairCount, 1);
    expect(
      snapshot.blockingFacts.map((fact) => fact.code),
      contains('pending_invitation'),
    );
  });

  test('pending remote break blocks without removing the active pair', () {
    final snapshot =
        guard(blocker: 'pending_remote_break').inspectHostReadiness();
    final factCodes = snapshot.blockingFacts.map((fact) => fact.code);

    expect(snapshot.state, ConsensusGuardState.blocked);
    expect(snapshot.blockedPairCount, 1);
    expect(factCodes, contains('pending_remote_break'));
    expect(factCodes, isNot(contains('relationship_broken')));
    expect(factCodes, isNot(contains('no_active_relationship')));
  });
}

String _pairView({String? blocker}) => jsonEncode(<String, Object?>{
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
      'blockers':
          blocker == null
              ? <Object?>[]
              : <Object?>[
                <String, Object?>{
                  'code': blocker,
                  'subject_id': List<int>.filled(32, 5),
                },
              ],
    },
  ],
});
