import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/plugin_execution_guard_service.dart';

void main() {
  group('PluginExecutionGuardService', () {
    test('reports ready when all derived pairs are signable', () {
      final service = PluginExecutionGuardService(
        consensus: ConsensusRuntimeService(
          exportLedger: () => _acceptedLedgerJson(),
          readLocalTransportKey: () =>
              Uint8List.fromList(List<int>.filled(32, 11)),
        ),
      );

      final snapshot = service.inspectHostReadiness();

      expect(snapshot.state, ConsensusGuardState.ready);
      expect(snapshot.readyPairCount, 1);
      expect(snapshot.blockedPairCount, 0);
      expect(snapshot.blockingFacts, isEmpty);
    });

    test('reports blocked when pairwise history is unresolved', () {
      final service = PluginExecutionGuardService(
        consensus: ConsensusRuntimeService(
          exportLedger: () => _pendingLedgerJson(),
          readLocalTransportKey: () =>
              Uint8List.fromList(List<int>.filled(32, 11)),
        ),
      );

      final snapshot = service.inspectHostReadiness();
      final factCodes = snapshot.blockingFacts
          .map((fact) => fact.code)
          .toList(growable: false);

      expect(snapshot.state, ConsensusGuardState.blocked);
      expect(snapshot.readyPairCount, 0);
      expect(snapshot.blockedPairCount, 1);
      expect(factCodes, contains('pending_invitation'));
    });
  });
}

String _acceptedLedgerJson() {
  final invitationId = Uint8List.fromList(List<int>.filled(32, 1));
  final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
  final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
  final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
  final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
  final sender = Uint8List.fromList(List<int>.filled(32, 6));
  final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
  final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
  final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));

  return jsonEncode(<String, dynamic>{
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
}

String _pendingLedgerJson() {
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

  return jsonEncode(<String, dynamic>{
    'events': <Map<String, dynamic>>[
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
    ],
  });
}
