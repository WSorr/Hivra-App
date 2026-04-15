import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
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

    test('verify forwards runtime signature verifier callback', () {
      final participantHex = 'b' * 64;
      var verifierCalls = 0;
      final service = ConsensusRuntimeService(
        exportLedger: () => null,
        readLocalTransportKey: () => null,
        verifySignature: ({
          required String messageHashHex,
          required String participantIdHex,
          required String signatureHex,
        }) {
          verifierCalls += 1;
          return false;
        },
      );

      final result = service.verify(
        expectedHashHex: 'a' * 64,
        participants: <ConsensusVerifyParticipant>[
          ConsensusVerifyParticipant(
            participantId: participantHex,
            hashHex: 'a' * 64,
            signatureHex: 'c' * 128,
          ),
        ],
      );

      expect(verifierCalls, equals(1));
      expect(result.state, equals(ConsensusVerifyState.mismatch));
      expect(
        result.blockingFacts.map((fact) => fact.key),
        contains('invalid_signature:$participantHex'),
      );
    });

    test('mirrored A/B ledgers produce identical pairwise consensus hash', () {
      List<int> bytes32(int value) => List<int>.filled(32, value);
      final invitationId = bytes32(31);
      final aTransport = bytes32(32);
      final bTransport = bytes32(33);
      final aRoot = bytes32(34);
      final bRoot = bytes32(35);
      final aStarter = bytes32(36);
      final bStarter = bytes32(37);
      final senderStarterA = bytes32(38);
      final senderStarterB = bytes32(39);

      final ledgerA = jsonEncode(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 7,
            'payload': <int>[
              ...bTransport,
              ...aStarter,
              ...bStarter,
              1,
              ...invitationId,
              ...aTransport,
              1,
              ...senderStarterA,
              ...bRoot,
              ...aRoot,
            ],
          },
        ],
      });

      final ledgerB = jsonEncode(<String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 7,
            'payload': <int>[
              ...aTransport,
              ...bStarter,
              ...aStarter,
              1,
              ...invitationId,
              ...bTransport,
              1,
              ...senderStarterB,
              ...aRoot,
              ...bRoot,
            ],
          },
        ],
      });

      final serviceA = ConsensusRuntimeService(
        exportLedger: () => ledgerA,
        readLocalTransportKey: () => Uint8List.fromList(aTransport),
        readLocalRootKey: () => Uint8List.fromList(aRoot),
      );
      final serviceB = ConsensusRuntimeService(
        exportLedger: () => ledgerB,
        readLocalTransportKey: () => Uint8List.fromList(bTransport),
        readLocalRootKey: () => Uint8List.fromList(bRoot),
      );

      final checksA = serviceA.checks();
      final checksB = serviceB.checks();
      String hex(List<int> bytes) =>
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(checksA, hasLength(1));
      expect(checksB, hasLength(1));
      expect(checksA.single.peerHex, equals(hex(bRoot)));
      expect(checksB.single.peerHex, equals(hex(aRoot)));
      expect(checksA.single.hashHex, checksB.single.hashHex);
      expect(checksA.single.isSignable, isTrue);
      expect(checksB.single.isSignable, isTrue);
    });

    test(
        'checks keeps remote break as pending_remote_break when local root is available',
        () {
      final invitationId = Uint8List.fromList(List<int>.filled(32, 21));
      final ownStarter = Uint8List.fromList(List<int>.filled(32, 22));
      final peerTransport = Uint8List.fromList(List<int>.filled(32, 23));
      final peerRoot = Uint8List.fromList(List<int>.filled(32, 24));
      final peerStarter = Uint8List.fromList(List<int>.filled(32, 25));
      final localTransport = Uint8List.fromList(List<int>.filled(32, 26));
      final localRoot = Uint8List.fromList(List<int>.filled(32, 27));
      final senderStarter = Uint8List.fromList(List<int>.filled(32, 28));

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
        ],
      });

      final service = ConsensusRuntimeService(
        exportLedger: () => ledgerJson,
        readLocalTransportKey: () => localTransport,
        readLocalRootKey: () => localRoot,
      );

      final checks = service.checks();

      expect(checks, hasLength(1));
      expect(checks.single.isSignable, isFalse);
      expect(checks.single.relationshipCount, equals(1));
      expect(
        checks.single.blockingFacts.map((fact) => fact.code),
        contains('pending_remote_break'),
      );
      expect(
        checks.single.blockingFacts.map((fact) => fact.code),
        isNot(contains('relationship_broken')),
      );
      expect(
        checks.single.blockingFacts.map((fact) => fact.code),
        isNot(contains('no_active_relationship')),
      );
    });
  });
}
