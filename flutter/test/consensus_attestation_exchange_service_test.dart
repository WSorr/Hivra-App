import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/app_runtime_runtime.dart';
import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/ffi/ledger_view_runtime.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/consensus_attestation_sync_service.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';

void main() {
  group('ConsensusAttestationExchangeService', () {
    test('prefers contact-card transport for root-addressed peer', () async {
      const peerRootHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const peerTransportHex =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final sync = _FakeConsensusAttestationSyncService();

      final service = ConsensusAttestationExchangeService(
        sync: sync,
        loadRelationships:
            () => <Relationship>[
              Relationship(
                peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                ownStarterId: base64Encode(Uint8List(32)),
                peerStarterId: base64Encode(
                  Uint8List.fromList(List<int>.filled(32, 1)),
                ),
                establishedAt: DateTime.utc(2026, 7, 10),
              ),
            ],
        listTrustedCards:
            () async => const <CapsuleAddressCard>[
              CapsuleAddressCard(
                rootKey: 'h1peer',
                rootHex: peerRootHex,
                nostrNpub: 'npub1peer',
                nostrHex: peerTransportHex,
              ),
            ],
      );

      final result = await service.ensureForPeer(peerRootHex);

      expect(result.status, ConsensusAttestationExchangeStatus.syncing);
      expect(result.localEvidenceSent, isTrue);
      expect(sync.sentPeerRootHex, peerRootHex);
      expect(sync.sentPeerTransportHex, peerTransportHex);
    });

    test('blocks root-addressed peer without transport card', () async {
      const peerRootHex =
          '1111111111111111111111111111111111111111111111111111111111111111';
      final sync = _FakeConsensusAttestationSyncService();

      final service = ConsensusAttestationExchangeService(
        sync: sync,
        loadRelationships:
            () => <Relationship>[
              Relationship(
                peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                kind: StarterKind.juice,
                ownStarterId: base64Encode(Uint8List(32)),
                peerStarterId: base64Encode(
                  Uint8List.fromList(List<int>.filled(32, 1)),
                ),
                establishedAt: DateTime.utc(2026, 7, 10),
              ),
            ],
        listTrustedCards: () async => const <CapsuleAddressCard>[],
      );

      final result = await service.ensureForPeer(peerRootHex);

      expect(result.status, ConsensusAttestationExchangeStatus.blocked);
      expect(result.message, contains('No transport endpoint'));
      expect(sync.sentPeerRootHex, isNull);
      expect(sync.sentPeerTransportHex, isNull);
    });

    test(
      'recovers peer transport from incoming invitation ledger fact',
      () async {
        const peerRootHex =
            '1111111111111111111111111111111111111111111111111111111111111111';
        const peerTransportHex =
            '2222222222222222222222222222222222222222222222222222222222222222';
        const localRootHex =
            '3333333333333333333333333333333333333333333333333333333333333333';
        final sync = _FakeConsensusAttestationSyncService();
        final invitationPayload = <int>[
          ...Uint8List.fromList(List<int>.filled(32, 1)),
          ...Uint8List.fromList(List<int>.filled(32, 2)),
          ..._hexToBytes(localRootHex),
          ..._hexToBytes(peerRootHex),
          0,
          ..._hexToBytes(peerTransportHex),
        ];
        final ledgerJson = jsonEncode(<String, Object?>{
          'events': <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'InvitationReceived',
              'payload': invitationPayload,
            },
          ],
        });

        final service = ConsensusAttestationExchangeService(
          sync: sync,
          loadRelationships:
              () => <Relationship>[
                Relationship(
                  peerPubkey: base64Encode(_hexToBytes(peerRootHex)),
                  peerRootPubkey: base64Encode(_hexToBytes(peerRootHex)),
                  kind: StarterKind.juice,
                  ownStarterId: base64Encode(Uint8List(32)),
                  peerStarterId: base64Encode(
                    Uint8List.fromList(List<int>.filled(32, 1)),
                  ),
                  establishedAt: DateTime.utc(2026, 7, 10),
                ),
              ],
          listTrustedCards: () async => const <CapsuleAddressCard>[],
          exportLedger: () => ledgerJson,
        );

        final result = await service.ensureForPeer(peerRootHex);

        expect(result.status, ConsensusAttestationExchangeStatus.syncing);
        expect(result.localEvidenceSent, isTrue);
        expect(sync.sentPeerRootHex, peerRootHex);
        expect(sync.sentPeerTransportHex, peerTransportHex);
      },
    );

    test('ignores stale pair evidence from different snapshots', () async {
      const localRootHex =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const peerRootHex =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final sync = _FakeConsensusAttestationSyncService(
        pairEvidence: <ConsensusAttestationEvidence>[
          _evidence(
            localRootHex: localRootHex,
            peerRootHex: peerRootHex,
            snapshotHashHex:
                '1111111111111111111111111111111111111111111111111111111111111111',
            signerRootHex: localRootHex,
          ),
          _evidence(
            localRootHex: localRootHex,
            peerRootHex: peerRootHex,
            snapshotHashHex:
                '2222222222222222222222222222222222222222222222222222222222222222',
            signerRootHex: peerRootHex,
          ),
        ],
      );

      final service = ConsensusAttestationExchangeService(
        sync: sync,
        loadRelationships: () => <Relationship>[],
        listTrustedCards:
            () async => const <CapsuleAddressCard>[
              CapsuleAddressCard(
                rootKey: 'h1peer',
                rootHex: peerRootHex,
                nostrNpub: 'npub1peer',
                nostrHex:
                    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              ),
            ],
      );

      final result = await service.ensureForPeer(peerRootHex);

      expect(result.status, ConsensusAttestationExchangeStatus.syncing);
      expect(result.mismatchedEvidenceCount, 2);
      expect(result.message, contains('ignoring stale pair evidence'));
      expect(sync.sentPeerRootHex, peerRootHex);
    });

    test(
      'becomes ready when peer attestation arrives after local send',
      () async {
        const localRootHex =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        const peerRootHex =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        const snapshotHashHex =
            '3333333333333333333333333333333333333333333333333333333333333333';
        final sync = _FakeConsensusAttestationSyncService(
          verifiedResponses: <List<ConsensusAttestationEvidence>>[
            const <ConsensusAttestationEvidence>[],
            <ConsensusAttestationEvidence>[
              _evidence(
                localRootHex: localRootHex,
                peerRootHex: peerRootHex,
                snapshotHashHex: snapshotHashHex,
                signerRootHex: localRootHex,
              ),
              _evidence(
                localRootHex: localRootHex,
                peerRootHex: peerRootHex,
                snapshotHashHex: snapshotHashHex,
                signerRootHex: peerRootHex,
              ),
            ],
          ],
          receiveResults: const <ConsensusAttestationReceiveResult>[
            ConsensusAttestationReceiveResult(
              code: 0,
              errorMessage: null,
              receivedCount: 0,
              storedCount: 0,
              rejectedCount: 0,
            ),
            ConsensusAttestationReceiveResult(
              code: 0,
              errorMessage: null,
              receivedCount: 1,
              storedCount: 1,
              rejectedCount: 0,
            ),
          ],
        );

        final service = ConsensusAttestationExchangeService(
          sync: sync,
          loadRelationships: () => <Relationship>[],
          listTrustedCards:
              () async => const <CapsuleAddressCard>[
                CapsuleAddressCard(
                  rootKey: 'h1peer',
                  rootHex: peerRootHex,
                  nostrNpub: 'npub1peer',
                  nostrHex:
                      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                ),
              ],
        );

        final result = await service.ensureForPeer(peerRootHex);

        expect(result.status, ConsensusAttestationExchangeStatus.ready);
        expect(result.localEvidenceSent, isTrue);
        expect(result.receivedCount, 1);
        expect(result.storedCount, 1);
        expect(sync.receiveCalls, 2);
        expect(sync.sentPeerRootHex, peerRootHex);
      },
    );
  });
}

class _FakeConsensusAttestationSyncService
    extends ConsensusAttestationSyncService {
  final List<ConsensusAttestationEvidence> pairEvidence;
  final List<List<ConsensusAttestationEvidence>> verifiedResponses;
  final List<ConsensusAttestationReceiveResult> receiveResults;
  String? sentPeerRootHex;
  String? sentPeerTransportHex;
  int receiveCalls = 0;
  int verifiedCalls = 0;

  _FakeConsensusAttestationSyncService({
    this.pairEvidence = const <ConsensusAttestationEvidence>[],
    this.verifiedResponses = const <List<ConsensusAttestationEvidence>>[
      <ConsensusAttestationEvidence>[],
    ],
    this.receiveResults = const <ConsensusAttestationReceiveResult>[
      ConsensusAttestationReceiveResult(
        code: 0,
        errorMessage: null,
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      ),
    ],
  }) : super(
         runtime: _FakeRuntime(),
         consensus: ConsensusRuntimeService(
           exportLedger: () => null,
           readLocalTransportKey: () => null,
         ),
       );

  @override
  Future<ConsensusAttestationReceiveResult> receiveAndStore() async {
    final index =
        receiveCalls < receiveResults.length
            ? receiveCalls
            : receiveResults.length - 1;
    receiveCalls += 1;
    return receiveResults[index];
  }

  @override
  Future<List<ConsensusAttestationEvidence>> loadVerifiedForPair({
    required String peerRootHex,
  }) async {
    final index =
        verifiedCalls < verifiedResponses.length
            ? verifiedCalls
            : verifiedResponses.length - 1;
    verifiedCalls += 1;
    return verifiedResponses[index];
  }

  @override
  Future<List<ConsensusAttestationEvidence>> loadVerifiedPairEvidence({
    required String peerRootHex,
  }) async {
    return pairEvidence;
  }

  @override
  Future<ConsensusAttestationSendResult> sendLocalEvidence({
    required String peerRootHex,
    required String peerTransportHex,
  }) async {
    sentPeerRootHex = peerRootHex;
    sentPeerTransportHex = peerTransportHex;
    return const ConsensusAttestationSendResult(
      isSuccess: true,
      code: 0,
      errorMessage: null,
      evidence: null,
    );
  }
}

class _FakeRuntime implements AppRuntimeRuntime {
  @override
  LedgerViewRuntime get ledgerViewRuntime => throw UnimplementedError();

  @override
  InvitationActionsRuntime get invitationActionsRuntime =>
      throw UnimplementedError();

  @override
  CapsuleAddressRuntime get capsuleAddressRuntime => throw UnimplementedError();

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() => throw UnimplementedError();

  @override
  Future<void> persistLedgerSnapshot() => throw UnimplementedError();

  @override
  Uint8List? capsuleRootPublicKey() => throw UnimplementedError();

  @override
  Uint8List? capsuleNostrPublicKey() => throw UnimplementedError();

  @override
  Uint8List? loadSeed() => throw UnimplementedError();

  @override
  String? exportLedger() => throw UnimplementedError();

  @override
  String? invokeWasmJson({
    required Uint8List moduleBytes,
    required String entryExport,
    required Uint8List inputJsonBytes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() =>
      throw UnimplementedError();

  @override
  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) => throw UnimplementedError();

  @override
  Future<CapsuleTraceReport> diagnoseCapsuleTraces() =>
      throw UnimplementedError();

  @override
  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() =>
      throw UnimplementedError();

  @override
  bool verifyConsensusSignature({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  }) => throw UnimplementedError();

  @override
  String? signConsensusCommitment(String commitmentHashHex) =>
      throw UnimplementedError();
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i += 1) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

ConsensusAttestationEvidence _evidence({
  required String localRootHex,
  required String peerRootHex,
  required String snapshotHashHex,
  required String signerRootHex,
}) {
  final pairRoots = <String>[localRootHex, peerRootHex]..sort();
  return ConsensusAttestationEvidence(
    schemaVersion: 1,
    pairRootsSorted: pairRoots,
    snapshotHashHex: snapshotHashHex,
    commitmentHashHex: 'f' * 64,
    signerRootHex: signerRootHex,
    signatureHex: 'e' * 128,
    createdAtUtc: DateTime.utc(2026, 7, 10).toIso8601String(),
  );
}
