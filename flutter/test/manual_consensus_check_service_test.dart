import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';

void main() {
  group('ManualConsensusCheckService', () {
    test('builds inspector-facing rows from runtime consensus checks', () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 1));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
      final sender = Uint8List.fromList(List<int>.filled(32, 6));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
      final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
      final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));

      final ledgerJson = jsonEncode(<String, dynamic>{
        'events': <Map<String, dynamic>>[
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
        ],
      });

      final service = ManualConsensusCheckService(
        consensus: ConsensusRuntimeService(
          exportLedger: () => ledgerJson,
          readLocalTransportKey: () =>
              Uint8List.fromList(List<int>.filled(32, 11)),
        ),
      );

      final checks = service.loadChecks();

      expect(checks, hasLength(1));
      expect(checks.first.isSignable, isTrue);
      expect(checks.first.blockingFacts, isEmpty);
      expect(checks.first.hashHex, hasLength(64));
      expect(
          checks.first.canonicalJson.contains('"schema_version": 1'), isTrue);
    });
  });
}
