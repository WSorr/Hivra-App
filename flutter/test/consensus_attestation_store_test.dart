import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/consensus_attestation_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _TestDirectories extends UserVisibleDataDirectoryService {
  final Directory root;

  const _TestDirectories(this.root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late CapsuleFileStore fileStore;
  late ConsensusAttestationStore store;

  const capsuleA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const capsuleB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const snapshotA =
      '1111111111111111111111111111111111111111111111111111111111111111';
  const snapshotB =
      '2222222222222222222222222222222222222222222222222222222222222222';

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'hivra_attestation_store_test_',
    );
    fileStore = CapsuleFileStore(dirs: _TestDirectories(tempRoot));
    store = ConsensusAttestationStore(fileStore: fileStore);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'v1 migrates and delivered response is bounded across restart',
    () async {
      final pair = _pair(
        localRootHex: capsuleA,
        peerRootHex: capsuleB,
        snapshotHashHex: snapshotA,
      );
      final dir = await fileStore.capsuleDirForHex(capsuleA, create: true);
      await fileStore.writePairConsensusAttestations(
        dir,
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'attestations': pair.map((item) => item.toJson()).toList(),
        }),
      );
      final now = DateTime.utc(2026, 8, 3, 12);

      final first = await store.reserveResponse(
        capsuleRootHex: capsuleA,
        peerEvidenceRecordKey: pair[1].recordKey,
        localEvidenceRecordKey: pair[0].recordKey,
        nowUtc: now,
      );
      final migrated =
          jsonDecode((await fileStore.readPairConsensusAttestations(dir))!)
              as Map<String, dynamic>;

      expect(
        first.status,
        ConsensusAttestationResponseReservationStatus.reserved,
      );
      expect(
        migrated['schema_version'],
        consensusAttestationStoreSchemaVersion,
      );
      expect(
        migrated['attestations'],
        pair.map((item) => item.toJson()).toList(),
      );
      expect((migrated['response_checkpoints'] as List), hasLength(1));

      final reopened = ConsensusAttestationStore(fileStore: fileStore);
      final coolingDown = await reopened.reserveResponse(
        capsuleRootHex: capsuleA,
        peerEvidenceRecordKey: pair[1].recordKey,
        localEvidenceRecordKey: pair[0].recordKey,
        nowUtc: now.add(const Duration(minutes: 1)),
      );
      expect(
        coolingDown.status,
        ConsensusAttestationResponseReservationStatus.coolingDown,
      );

      expect(
        await reopened.markResponseDelivered(
          capsuleRootHex: capsuleA,
          peerEvidenceRecordKey: pair[1].recordKey,
          localEvidenceRecordKey: pair[0].recordKey,
          nowUtc: now.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
      final deliveredCooldown = await ConsensusAttestationStore(
        fileStore: fileStore,
      ).reserveResponse(
        capsuleRootHex: capsuleA,
        peerEvidenceRecordKey: pair[1].recordKey,
        localEvidenceRecordKey: pair[0].recordKey,
        nowUtc: now.add(const Duration(minutes: 14)),
      );
      expect(
        deliveredCooldown.status,
        ConsensusAttestationResponseReservationStatus.delivered,
      );

      final recoveryRetry = await ConsensusAttestationStore(
        fileStore: fileStore,
      ).reserveResponse(
        capsuleRootHex: capsuleA,
        peerEvidenceRecordKey: pair[1].recordKey,
        localEvidenceRecordKey: pair[0].recordKey,
        nowUtc: now.add(consensusAttestationResponseRetryDelay),
      );
      expect(
        recoveryRetry.status,
        ConsensusAttestationResponseReservationStatus.reserved,
      );
    },
  );

  test('failed attempt becomes eligible only after retry boundary', () async {
    final pair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    await store.merge(capsuleA, pair);
    final now = DateTime.utc(2026, 8, 3, 12);

    expect(
      (await _reserve(store, capsuleA, pair, now)).status,
      ConsensusAttestationResponseReservationStatus.reserved,
    );
    expect(
      (await _reserve(
        store,
        capsuleA,
        pair,
        now.add(const Duration(minutes: 14, seconds: 59)),
      )).status,
      ConsensusAttestationResponseReservationStatus.coolingDown,
    );
    expect(
      (await _reserve(
        store,
        capsuleA,
        pair,
        now.add(consensusAttestationResponseRetryDelay),
      )).status,
      ConsensusAttestationResponseReservationStatus.reserved,
    );
  });

  test('a new valid snapshot has an independent response identity', () async {
    final firstPair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    final secondPair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotB,
    );
    await store.merge(capsuleA, <ConsensusAttestationEvidence>[
      ...firstPair,
      ...secondPair,
    ]);
    final now = DateTime.utc(2026, 8, 3, 12);

    expect((await _reserve(store, capsuleA, firstPair, now)).canSend, isTrue);
    expect((await _reserve(store, capsuleA, secondPair, now)).canSend, isTrue);
  });

  test(
    'response identity requires the exact stored peer and local evidence',
    () async {
      final firstPair = _pair(
        localRootHex: capsuleA,
        peerRootHex: capsuleB,
        snapshotHashHex: snapshotA,
      );
      final secondPair = _pair(
        localRootHex: capsuleA,
        peerRootHex: capsuleB,
        snapshotHashHex: snapshotB,
      );
      await store.merge(capsuleA, <ConsensusAttestationEvidence>[
        ...firstPair,
        ...secondPair,
      ]);
      final reservation = await store.reserveResponse(
        capsuleRootHex: capsuleA,
        peerEvidenceRecordKey: firstPair[1].recordKey,
        localEvidenceRecordKey: secondPair[0].recordKey,
        nowUtc: DateTime.utc(2026, 8, 3, 12),
      );

      expect(
        reservation.status,
        ConsensusAttestationResponseReservationStatus.unavailable,
      );
    },
  );

  for (final fault
      in <String, String>{'empty': '', 'whitespace-only': ' \r\n\t '}.entries) {
    test('${fault.key} evidence cannot restart a cooling response', () async {
      final pair = _pair(
        localRootHex: capsuleA,
        peerRootHex: capsuleB,
        snapshotHashHex: snapshotA,
      );
      final now = DateTime.utc(2026, 8, 3, 12);
      await store.merge(capsuleA, pair);
      expect((await _reserve(store, capsuleA, pair, now)).canSend, isTrue);
      final dir = await fileStore.capsuleDirForHex(capsuleA);
      final file = fileStore.pairConsensusAttestationsFile(dir);
      final saved = await file.readAsBytes();
      await file.writeAsString(fault.value, flush: true);

      Object? mergeError;
      try {
        await store.merge(capsuleA, pair);
      } catch (error) {
        mergeError = error;
      }
      final duringFailure = now.add(const Duration(minutes: 1));
      final blocked = await _reserve(store, capsuleA, pair, duringFailure);
      expect(blocked.canSend, isFalse);
      expect(
        blocked.status,
        ConsensusAttestationResponseReservationStatus.unavailable,
      );
      expect(mergeError, isA<StateError>());
      expect(
        await store.markResponseDelivered(
          capsuleRootHex: capsuleA,
          peerEvidenceRecordKey: pair[1].recordKey,
          localEvidenceRecordKey: pair[0].recordKey,
          nowUtc: duringFailure,
        ),
        isFalse,
      );
      expect(await store.load(capsuleA), isEmpty);
      expect(await file.readAsString(), fault.value);

      await file.writeAsBytes(saved, flush: true);
      final reopened = ConsensusAttestationStore(fileStore: fileStore);
      expect(
        (await reopened.load(capsuleA)).map((item) => item.recordKey),
        unorderedEquals(pair.map((item) => item.recordKey)),
      );
      expect(await reopened.merge(capsuleA, pair), isEmpty);
      expect(
        (await _reserve(reopened, capsuleA, pair, duringFailure)).status,
        ConsensusAttestationResponseReservationStatus.coolingDown,
      );
      expect(await file.readAsBytes(), saved);
    });
  }

  test('valid empty snapshot admits the first evidence and response', () async {
    final pair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    final dir = await fileStore.capsuleDirForHex(capsuleA, create: true);
    await fileStore.writePairConsensusAttestations(
      dir,
      jsonEncode(<String, Object?>{
        'schema_version': consensusAttestationStoreSchemaVersion,
        'attestations': <Object?>[],
        'response_checkpoints': <Object?>[],
      }),
    );
    expect(await store.load(capsuleA), isEmpty);
    expect(await store.merge(capsuleA, pair), hasLength(2));
    final now = DateTime.utc(2026, 8, 3, 12);
    expect((await _reserve(store, capsuleA, pair, now)).canSend, isTrue);
    expect(
      (await _reserve(
        ConsensusAttestationStore(fileStore: fileStore),
        capsuleA,
        pair,
        now.add(const Duration(minutes: 1)),
      )).status,
      ConsensusAttestationResponseReservationStatus.coolingDown,
    );
  });

  test(
    'unreadable evidence preserves bytes and retries the same store',
    () async {
      final pair = _pair(
        localRootHex: capsuleA,
        peerRootHex: capsuleB,
        snapshotHashHex: snapshotA,
      );
      final now = DateTime.utc(2026, 8, 3, 12);
      await store.merge(capsuleA, pair);
      expect((await _reserve(store, capsuleA, pair, now)).canSend, isTrue);
      final dir = await fileStore.capsuleDirForHex(capsuleA);
      final file = fileStore.pairConsensusAttestationsFile(dir);
      final saved = await file.readAsBytes();
      const invalidUtf8 = <int>[0xff, 0xfe];
      await file.writeAsBytes(invalidUtf8, flush: true);

      await expectLater(
        store.load(capsuleA),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.merge(capsuleA, pair),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        _reserve(store, capsuleA, pair, now.add(const Duration(minutes: 1))),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsBytes(), invalidUtf8);

      await file.writeAsBytes(saved, flush: true);
      expect(await store.merge(capsuleA, pair), isEmpty);
      expect(
        (await _reserve(
          store,
          capsuleA,
          pair,
          now.add(const Duration(minutes: 1)),
        )).status,
        ConsensusAttestationResponseReservationStatus.coolingDown,
      );
      expect(await file.readAsBytes(), saved);
    },
  );

  test('corrupt checkpoint storage suppresses automatic response', () async {
    final pair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    final dir = await fileStore.capsuleDirForHex(capsuleA, create: true);
    await fileStore.writePairConsensusAttestations(
      dir,
      jsonEncode(<String, Object?>{
        'schema_version': consensusAttestationStoreSchemaVersion,
        'attestations': pair.map((item) => item.toJson()).toList(),
        'response_checkpoints': <Object?>[
          <String, Object?>{'state': 'delivered'},
        ],
      }),
    );

    final reservation = await _reserve(
      store,
      capsuleA,
      pair,
      DateTime.utc(2026, 8, 3, 12),
    );

    expect(
      reservation.status,
      ConsensusAttestationResponseReservationStatus.unavailable,
    );
    expect(await store.load(capsuleA), isEmpty);
  });

  test('full checkpoint storage suppresses a new automatic response', () async {
    final pair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    final dir = await fileStore.capsuleDirForHex(capsuleA, create: true);
    final timestamp = DateTime.utc(2026, 8, 3, 12).toIso8601String();
    await fileStore.writePairConsensusAttestations(
      dir,
      jsonEncode(<String, Object?>{
        'schema_version': consensusAttestationStoreSchemaVersion,
        'attestations': pair.map((item) => item.toJson()).toList(),
        'response_checkpoints': List<Map<String, Object?>>.generate(
          consensusAttestationResponseCheckpointLimit,
          (index) => <String, Object?>{
            'peer_evidence_record_key': 'retained-peer-$index',
            'local_evidence_record_key': 'retained-local-$index',
            'state': 'delivered',
            'retry_after_utc': timestamp,
            'updated_at_utc': timestamp,
          },
        ),
      }),
    );

    final reservation = await _reserve(
      store,
      capsuleA,
      pair,
      DateTime.utc(2026, 8, 3, 13),
    );

    expect(
      reservation.status,
      ConsensusAttestationResponseReservationStatus.unavailable,
    );
  });

  test('concurrent callers create one reservation', () async {
    final pair = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    await store.merge(capsuleA, pair);
    final now = DateTime.utc(2026, 8, 3, 12);

    final results = await Future.wait(
      <Future<ConsensusAttestationResponseReservation>>[
        _reserve(store, capsuleA, pair, now),
        _reserve(store, capsuleA, pair, now),
      ],
    );

    expect(
      results.map((item) => item.status),
      containsAll(<ConsensusAttestationResponseReservationStatus>[
        ConsensusAttestationResponseReservationStatus.reserved,
        ConsensusAttestationResponseReservationStatus.coolingDown,
      ]),
    );
  });

  test('response checkpoints remain Capsule scoped', () async {
    final pairA = _pair(
      localRootHex: capsuleA,
      peerRootHex: capsuleB,
      snapshotHashHex: snapshotA,
    );
    final pairB = _pair(
      localRootHex: capsuleB,
      peerRootHex: capsuleA,
      snapshotHashHex: snapshotA,
    );
    await store.merge(capsuleA, pairA);
    await store.merge(capsuleB, pairB);
    final now = DateTime.utc(2026, 8, 3, 12);

    expect((await _reserve(store, capsuleA, pairA, now)).canSend, isTrue);
    expect((await _reserve(store, capsuleB, pairB, now)).canSend, isTrue);
  });
}

Future<ConsensusAttestationResponseReservation> _reserve(
  ConsensusAttestationStore store,
  String capsuleRootHex,
  List<ConsensusAttestationEvidence> pair,
  DateTime nowUtc,
) {
  return store.reserveResponse(
    capsuleRootHex: capsuleRootHex,
    peerEvidenceRecordKey: pair[1].recordKey,
    localEvidenceRecordKey: pair[0].recordKey,
    nowUtc: nowUtc,
  );
}

List<ConsensusAttestationEvidence> _pair({
  required String localRootHex,
  required String peerRootHex,
  required String snapshotHashHex,
}) {
  final roots = <String>[localRootHex, peerRootHex]..sort();
  return <ConsensusAttestationEvidence>[
    _evidence(
      roots: roots,
      snapshotHashHex: snapshotHashHex,
      signerRootHex: localRootHex,
    ),
    _evidence(
      roots: roots,
      snapshotHashHex: snapshotHashHex,
      signerRootHex: peerRootHex,
    ),
  ];
}

ConsensusAttestationEvidence _evidence({
  required List<String> roots,
  required String snapshotHashHex,
  required String signerRootHex,
}) {
  return ConsensusAttestationEvidence(
    schemaVersion: 1,
    pairRootsSorted: List<String>.unmodifiable(roots),
    snapshotHashHex: snapshotHashHex,
    commitmentHashHex: 'f' * 64,
    signerRootHex: signerRootHex,
    signatureHex: 'e' * 128,
    createdAtUtc: DateTime.utc(2026, 8, 3, 12).toIso8601String(),
  );
}
