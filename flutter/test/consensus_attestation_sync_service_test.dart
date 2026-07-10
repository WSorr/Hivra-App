import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/app_runtime_runtime.dart';
import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/ffi/invitation_actions_runtime.dart';
import 'package:hivra_app/ffi/ledger_view_runtime.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/consensus_attested_guard_service.dart';
import 'package:hivra_app/services/consensus_attestation_store.dart';
import 'package:hivra_app/services/consensus_attestation_sync_service.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _TestUserVisibleDataDirectoryService
    extends UserVisibleDataDirectoryService {
  final Directory _root;

  const _TestUserVisibleDataDirectoryService(this._root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await _root.exists()) {
      await _root.create(recursive: true);
    }
    return _root;
  }
}

class _FakeRuntime implements AppRuntimeRuntime {
  final String localRootHex;
  final bool Function({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  }) verifier;

  _FakeRuntime({
    required this.localRootHex,
    this.verifier = _alwaysVerify,
  });

  @override
  Uint8List? capsuleRootPublicKey() => _hexToBytes(localRootHex);

  @override
  String? signConsensusCommitment(String commitmentHashHex) => 'd' * 128;

  @override
  bool verifyConsensusSignature({
    required String messageHashHex,
    required String participantIdHex,
    required String signatureHex,
  }) {
    return verifier(
      messageHashHex: messageHashHex,
      participantIdHex: participantIdHex,
      signatureHex: signatureHex,
    );
  }

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() async {
    return <String, Object?>{
      'seed': Uint8List(32),
      'isGenesis': false,
      'isNeste': true,
      'identityMode': 'root_owner',
      'ledgerJson': null,
      'activeCapsuleHex': localRootHex,
    };
  }

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
  }) =>
      throw UnimplementedError();

  @override
  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) =>
      throw UnimplementedError();

  @override
  Future<CapsuleTraceReport> diagnoseCapsuleTraces() =>
      throw UnimplementedError();

  @override
  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() =>
      throw UnimplementedError();
}

class _FakeConsensusRuntimeService extends ConsensusRuntimeService {
  final String peerHex;
  final String snapshotHashHex;

  _FakeConsensusRuntimeService({
    required this.peerHex,
    required this.snapshotHashHex,
  }) : super(
          exportLedger: () => null,
          readLocalTransportKey: () => null,
        );

  @override
  ConsensusSignableResult signable(String requestedPeerHex) {
    if (requestedPeerHex.trim().toLowerCase() != peerHex) {
      return const ConsensusSignableResult(
        preview: null,
        blockingFacts: <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'consensus_peer_not_found'),
        ],
      );
    }
    return ConsensusSignableResult(
      preview: ConsensusPreview(
        peerHex: peerHex,
        peerLabel: 'peer',
        invitationCount: 1,
        relationshipCount: 1,
        hashHex: snapshotHashHex,
        canonicalJson: '{}',
        blockingFacts: const <ConsensusBlockingFact>[],
      ),
      blockingFacts: const <ConsensusBlockingFact>[],
    );
  }
}

bool _alwaysVerify({
  required String messageHashHex,
  required String participantIdHex,
  required String signatureHex,
}) =>
    true;

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i += 1) {
    final start = i * 2;
    out[i] = int.parse(hex.substring(start, start + 2), radix: 16);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsensusAttestationSyncService', () {
    late Directory tempDocsDir;
    late ConsensusAttestationStore store;

    final localRoot = 'a' * 64;
    final peerRoot = 'b' * 64;
    final peerTransport = 'c' * 64;
    final snapshotHash = '1' * 64;

    setUp(() async {
      tempDocsDir =
          await Directory.systemTemp.createTemp('hivra_attestation_test_');
      final fileStore = CapsuleFileStore(
        dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      );
      store = ConsensusAttestationStore(fileStore: fileStore);
    });

    tearDown(() async {
      if (await tempDocsDir.exists()) {
        await tempDocsDir.delete(recursive: true);
      }
    });

    test('creates and stores local root-signed attestation evidence', () async {
      final service = ConsensusAttestationSyncService(
        runtime: _FakeRuntime(localRootHex: localRoot),
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 10, 12),
      );

      final evidence = await service.createLocalEvidence(peerRootHex: peerRoot);
      final stored = await store.load(localRoot);

      expect(evidence, isNotNull);
      expect(evidence!.pairRootsSorted, <String>[localRoot, peerRoot]);
      expect(evidence.snapshotHashHex, snapshotHash);
      expect(evidence.signerRootHex, localRoot);
      expect(stored, hasLength(1));
      expect(stored.single.recordKey, evidence.recordKey);
    });

    test('sends local evidence over attestation transport worker', () async {
      Map<String, Object?>? capturedArgs;
      final service = ConsensusAttestationSyncService(
        runtime: _FakeRuntime(localRootHex: localRoot),
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        store: store,
        sendWorkerRunner: (args) async {
          capturedArgs = args;
          return <String, Object?>{
            'result': 0,
            'lastError': null,
            'deliveryReceiptsJson': '[{"transport":"nostr"}]',
          };
        },
        nowUtc: () => DateTime.utc(2026, 7, 10, 12),
      );

      final result = await service.sendLocalEvidence(
        peerRootHex: peerRoot,
        peerTransportHex: peerTransport,
      );

      expect(result.isSuccess, isTrue);
      expect(result.evidence, isNotNull);
      expect(capturedArgs?['toPubkey'], _hexToBytes(peerTransport));
      final payloadJson = capturedArgs?['payloadJson'] as String?;
      expect(payloadJson, isNotNull);
      expect(jsonDecode(payloadJson!)['signer_root'], localRoot);
    });

    test('receive stores only verified attestations for local pair', () async {
      final goodService = ConsensusAttestationSyncService(
        runtime: _FakeRuntime(localRootHex: localRoot),
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 10, 12),
      );
      final localEvidence =
          await goodService.createLocalEvidence(peerRootHex: peerRoot);
      expect(localEvidence, isNotNull);
      final peerEvidence = ConsensusAttestationEvidence(
        schemaVersion: 1,
        pairRootsSorted: localEvidence!.pairRootsSorted,
        snapshotHashHex: localEvidence.snapshotHashHex,
        commitmentHashHex: localEvidence.commitmentHashHex,
        signerRootHex: peerRoot,
        signatureHex: 'e' * 128,
        createdAtUtc: DateTime.utc(2026, 7, 10, 12, 1).toIso8601String(),
      );
      final forgedEvidence = ConsensusAttestationEvidence(
        schemaVersion: 1,
        pairRootsSorted: <String>[localRoot, peerRoot],
        snapshotHashHex: '2' * 64,
        commitmentHashHex: localEvidence.commitmentHashHex,
        signerRootHex: peerRoot,
        signatureHex: 'f' * 128,
        createdAtUtc: DateTime.utc(2026, 7, 10, 12, 2).toIso8601String(),
      );
      final service = ConsensusAttestationSyncService(
        runtime: _FakeRuntime(
          localRootHex: localRoot,
          verifier: ({
            required messageHashHex,
            required participantIdHex,
            required signatureHex,
          }) =>
              signatureHex == 'e' * 128,
        ),
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        store: store,
        receiveWorkerRunner: (_) async {
          return <String, Object?>{
            'result': 2,
            'json': jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{'payload_json': jsonEncode(peerEvidence)},
              <String, dynamic>{'payload_json': jsonEncode(forgedEvidence)},
            ]),
            'lastError': null,
          };
        },
      );

      final result = await service.receiveAndStore();
      final stored = await store.load(localRoot);

      expect(result.receivedCount, 2);
      expect(result.storedCount, 1);
      expect(result.rejectedCount, 1);
      expect(
        stored.map((item) => item.signerRootHex),
        containsAll(<String>[localRoot, peerRoot]),
      );
      expect(
        stored.any((item) => item.snapshotHashHex == '2' * 64),
        isFalse,
      );
    });

    test('attested guard requires both pair roots to sign same snapshot',
        () async {
      final attestationService = ConsensusAttestationSyncService(
        runtime: _FakeRuntime(localRootHex: localRoot),
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 10, 12),
      );
      final localEvidence = await attestationService.createLocalEvidence(
        peerRootHex: peerRoot,
      );
      expect(localEvidence, isNotNull);

      final guard = ConsensusAttestedGuardService(
        consensus: _FakeConsensusRuntimeService(
          peerHex: peerRoot,
          snapshotHashHex: snapshotHash,
        ),
        attestations: attestationService,
      );

      final localOnly = await guard.signable(peerRoot);
      expect(localOnly.isSignable, isFalse);
      expect(
        localOnly.blockingFacts.map((fact) => fact.code),
        contains('pair_attestation_incomplete'),
      );

      await store.merge(localRoot, <ConsensusAttestationEvidence>[
        ConsensusAttestationEvidence(
          schemaVersion: 1,
          pairRootsSorted: localEvidence!.pairRootsSorted,
          snapshotHashHex: localEvidence.snapshotHashHex,
          commitmentHashHex: localEvidence.commitmentHashHex,
          signerRootHex: peerRoot,
          signatureHex: 'e' * 128,
          createdAtUtc: DateTime.utc(2026, 7, 10, 12, 1).toIso8601String(),
        ),
      ]);

      final bothSigned = await guard.signable(peerRoot);
      expect(bothSigned.isSignable, isTrue);
      expect(bothSigned.blockingFacts, isEmpty);
    });
  });
}
