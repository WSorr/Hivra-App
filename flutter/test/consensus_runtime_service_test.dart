import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_runtime_service.dart';

void main() {
  group('ConsensusRuntimeService', () {
    test('reads ledger/runtime inputs and exposes preview plus signable', () {
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
      final peerHex = List<int>.filled(32, 4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

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

      final service = ConsensusRuntimeService(
        exportLedger: () => ledgerJson,
        readLocalTransportKey: () => localTransport,
      );

      final previews = service.preview();
      final signable = service.signable(peerHex);

      expect(previews, hasLength(1));
      expect(previews.first.hashHex, hasLength(64));
      expect(signable.isSignable, isTrue);
      expect(signable.hashHex, previews.first.hashHex);
    });

    test('reports runtime-unavailable when ledger or local key is missing', () {
      final missingLedger = ConsensusRuntimeService(
        exportLedger: () => null,
        readLocalTransportKey: () =>
            Uint8List.fromList(List<int>.filled(32, 1)),
      );
      final missingKey = ConsensusRuntimeService(
        exportLedger: () => jsonEncode(<String, dynamic>{'events': <Object>[]}),
        readLocalTransportKey: () => null,
      );
      final missingLedgerSignable = missingLedger.signable('ab');
      final missingKeySignable = missingKey.signable('ab');

      expect(missingLedger.preview(), isEmpty);
      expect(
        missingLedgerSignable.blockingFacts.map((fact) => fact.key),
        contains('consensus_runtime_unavailable'),
      );
      expect(missingKey.preview(), isEmpty);
      expect(
        missingKeySignable.blockingFacts.map((fact) => fact.key),
        contains('consensus_runtime_unavailable'),
      );
    });

    test('accepts root key when transport key is unavailable', () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 1));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 2));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 3));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 4));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 5));
      final sender = Uint8List.fromList(List<int>.filled(32, 6));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 7));
      final acceptedFrom = Uint8List.fromList(List<int>.filled(32, 8));
      final acceptedCreated = Uint8List.fromList(List<int>.filled(32, 9));
      final localRoot = Uint8List.fromList(List<int>.filled(32, 12));
      final peerHex = List<int>.filled(32, 4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

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
              ...peerTransport,
              ...ownStarter,
              ...peerStarter,
              1,
              ...invitationId,
              ...sender,
              1,
              ...senderStarter,
              ...peerRoot,
              ...List<int>.filled(32, 13),
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

      final service = ConsensusRuntimeService(
        exportLedger: () => ledgerJson,
        readLocalTransportKey: () => null,
        readLocalRootKey: () => localRoot,
      );

      final previews = service.preview();
      final signable = service.signable(peerHex);

      expect(previews, hasLength(1));
      expect(signable.isSignable, isTrue);
      expect(
          previews.first.canonicalJson.contains(
            localRoot.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          ),
          isTrue);
    });

    test('checks computes readiness from a single preview pass', () {
      var exportLedgerCalls = 0;
      var readTransportCalls = 0;
      final localTransport = Uint8List.fromList(List<int>.filled(32, 11));
      final service = ConsensusRuntimeService(
        exportLedger: () {
          exportLedgerCalls += 1;
          return jsonEncode(<String, dynamic>{
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 1,
                'payload': <int>[
                  ...List<int>.filled(32, 1),
                  ...List<int>.filled(32, 2),
                  ...List<int>.filled(32, 3),
                  1,
                ],
              },
              <String, dynamic>{
                'kind': 7,
                'payload': <int>[
                  ...List<int>.filled(32, 4),
                  ...List<int>.filled(32, 2),
                  ...List<int>.filled(32, 5),
                  1,
                  ...List<int>.filled(32, 1),
                  ...List<int>.filled(32, 6),
                  1,
                  ...List<int>.filled(32, 7),
                ],
              },
              <String, dynamic>{
                'kind': 2,
                'payload': <int>[
                  ...List<int>.filled(32, 1),
                  ...List<int>.filled(32, 8),
                  ...List<int>.filled(32, 9),
                ],
              },
            ],
          });
        },
        readLocalTransportKey: () {
          readTransportCalls += 1;
          return localTransport;
        },
      );

      final checks = service.checks();

      expect(checks, hasLength(1));
      expect(checks.first.isSignable, isTrue);
      expect(exportLedgerCalls, equals(1));
      expect(readTransportCalls, equals(1));
    });
  });
}
