import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';

void main() {
  group('ManualConsensusCheckService', () {
    test('builds inspector-facing rows from runtime consensus checks', () {
      final pairViewJson = jsonEncode(<String, dynamic>{
        'schema': 'hivra.pair_view',
        'version': 1,
        'ledger_version': 3,
        'pairs': <Map<String, dynamic>>[
          <String, dynamic>{
            'local_identity': List<int>.filled(32, 1),
            'peer_identity': List<int>.filled(32, 2),
            'finalized_invitation_count': 1,
            'active_relationships': <Map<String, dynamic>>[
              <String, dynamic>{
                'relationship_kind': 1,
                'starter_pair': <List<int>>[
                  List<int>.filled(32, 3),
                  List<int>.filled(32, 4),
                ],
              },
            ],
            'blockers': <Map<String, dynamic>>[],
          },
        ],
      });

      final service = ManualConsensusCheckService(
        consensus: ConsensusRuntimeService(
          exportLedger: () => '{"events":[]}',
          readLocalTransportKey:
              () => Uint8List.fromList(List<int>.filled(32, 11)),
          projectPairView: (_, unused) => pairViewJson,
        ),
      );

      final checks = service.loadChecks();

      expect(checks, hasLength(1));
      expect(
        checks.first.isSignable,
        isTrue,
        reason: checks.first.blockingFacts
            .map((fact) => '${fact.code}:${fact.subjectId ?? "-"}')
            .join(','),
      );
      expect(checks.first.blockingFacts, isEmpty);
      expect(checks.first.hashHex, hasLength(64));
      expect(
        checks.first.canonicalJson.contains('"schema_version": 3'),
        isTrue,
      );
    });
  });
}
