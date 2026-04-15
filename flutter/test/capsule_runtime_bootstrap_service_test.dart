import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_backup_codec.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/ffi/capsule_runtime_bootstrap_runtime.dart';
import 'package:hivra_app/services/capsule_runtime_bootstrap_service.dart';
import 'package:hivra_app/services/capsule_seed_store.dart';

class _FakeCapsuleFileStore extends CapsuleFileStore {
  _FakeCapsuleFileStore({
    this.state,
    this.ledgerJson,
    this.backupJson,
  });

  final Map<String, dynamic>? state;
  final String? ledgerJson;
  final String? backupJson;
  String? writtenLedgerJson;
  final Directory _dir =
      Directory('${Directory.systemTemp.path}/hivra_bootstrap_test');

  @override
  Future<Directory> capsuleDirForHex(
    String pubKeyHex, {
    bool create = false,
  }) async {
    return _dir;
  }

  @override
  Future<Map<String, dynamic>?> readState(Directory dir) async => state;

  @override
  Future<String?> readLedger(Directory dir) async => ledgerJson;

  @override
  Future<String?> readBackup(Directory dir) async => backupJson;

  @override
  Future<void> writeLedger(Directory dir, String ledgerJson) async {
    writtenLedgerJson = ledgerJson;
  }
}

class _FakeCapsuleSeedStore extends CapsuleSeedStore {
  _FakeCapsuleSeedStore(this.seed);

  final Uint8List? seed;

  Uint8List? lastStoredSeed;

  @override
  Future<Uint8List?> loadSeed(String pubKeyHex) async => seed;

  @override
  Future<Uint8List?> loadValidatedSeed(
    String pubKeyHex, {
    required Future<bool> Function(Uint8List seed) isValidSeed,
    required Future<void> Function(Uint8List seed) persistValidatedSeed,
  }) async {
    final current = seed;
    if (current == null) return null;
    if (!await isValidSeed(current)) return null;
    await persistValidatedSeed(current);
    return current;
  }

  @override
  Future<void> storeSeed(String pubKeyHex, Uint8List seed) async {
    lastStoredSeed = Uint8List.fromList(seed);
  }
}

class _FakeBootstrapRuntime implements CapsuleRuntimeBootstrapRuntime {
  _FakeBootstrapRuntime({
    required this.seedRootPubkey,
    required this.seedNostrPubkey,
    this.runtimeOwnerPubkey,
    this.runtimeOwnerSequence,
    this.loadedSeed,
    this.exportedLedger = '{"owner":[],"events":[]}',
    Map<String, bool>? importResultsByLedger,
  }) : _importResultsByLedger = importResultsByLedger ?? <String, bool>{};

  final Uint8List seedRootPubkey;
  final Uint8List seedNostrPubkey;
  final Uint8List? runtimeOwnerPubkey;
  final List<Uint8List>? runtimeOwnerSequence;
  final Uint8List? loadedSeed;
  final String? exportedLedger;
  final Map<String, bool> _importResultsByLedger;

  final List<String> importAttempts = <String>[];
  int runtimeOwnerReadCount = 0;
  Uint8List? savedSeed;
  bool createCapsuleCalled = false;
  bool createCapsuleIsGenesis = false;
  bool createCapsuleIsNeste = true;
  int? createCapsuleOwnerMode;

  @override
  int get legacyNostrOwnerMode => 2;

  @override
  int get rootOwnerMode => 1;

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() {
    runtimeOwnerReadCount += 1;
    final sequence = runtimeOwnerSequence;
    if (sequence != null && sequence.isNotEmpty) {
      final idx = runtimeOwnerReadCount - 1;
      if (idx < sequence.length) {
        return sequence[idx];
      }
      return sequence.last;
    }
    return runtimeOwnerPubkey;
  }

  @override
  Uint8List? capsuleRootPublicKey() => seedRootPubkey;

  @override
  Uint8List? loadSeed() => loadedSeed;

  @override
  String? exportLedger() => exportedLedger;

  @override
  bool saveSeed(Uint8List seed) {
    savedSeed = Uint8List.fromList(seed);
    return true;
  }

  @override
  bool createCapsule(
    Uint8List seed, {
    required bool isGenesis,
    required bool isNeste,
    required int ownerMode,
  }) {
    createCapsuleCalled = true;
    createCapsuleIsGenesis = isGenesis;
    createCapsuleIsNeste = isNeste;
    createCapsuleOwnerMode = ownerMode;
    return true;
  }

  @override
  bool importLedger(String ledgerJson) {
    importAttempts.add(ledgerJson);
    return _importResultsByLedger[ledgerJson] ?? false;
  }

  @override
  Uint8List? seedRootPublicKey(Uint8List seed) => seedRootPubkey;

  @override
  Uint8List? seedNostrPublicKey(Uint8List seed) => seedNostrPubkey;
}

void main() {
  group('CapsuleRuntimeBootstrapService', () {
    const pubKeyHex =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final seed = Uint8List.fromList(List<int>.filled(32, 7));

    String bytesToHex(Uint8List bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    String ledgerWithOwnerByte(
      int ownerByte, {
      required String kind,
    }) {
      return jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, ownerByte),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': kind},
        ],
      });
    }

    String ledgerWithEvents(
      int ownerByte,
      List<Map<String, dynamic>> events,
    ) {
      return jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, ownerByte),
        'events': events,
      });
    }

    String ledgerWithBase64Owner({
      required int ownerByte,
      required String kind,
    }) {
      return jsonEncode(<String, dynamic>{
        'owner': base64Encode(List<int>.filled(32, ownerByte)),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': kind},
        ],
      });
    }

    String ledgerWithCapsuleCreated({
      required int ownerByte,
      required int network,
      required int capsuleType,
    }) {
      return jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, ownerByte),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'kind': 'CapsuleCreated',
            'payload': <int>[network, capsuleType],
          },
          <String, dynamic>{'kind': 'InvitationSent'},
        ],
      });
    }

    test('prefers ledger.json when both ledger and backup exist', () async {
      final ledger = ledgerWithOwnerByte(0xaa, kind: 'InvitationSent');
      final backupLedger =
          ledgerWithOwnerByte(0xaa, kind: 'InvitationRejected');
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: backupLedger,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': true,
            'isNeste': false,
          },
          ledgerJson: ledger,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(ledger));
      expect(
        bootstrap.ledgerImportCandidates,
        equals(<String>[ledger, backupLedger]),
      );
      expect(bootstrap.isGenesis, isTrue);
      expect(bootstrap.isNeste, isFalse);
    });

    test('prefers backup when ledger history is shorter', () async {
      final shortLedger = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 0xaa),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent'},
        ],
      });
      final longLedger = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 0xaa),
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent'},
          <String, dynamic>{'kind': 'InvitationAccepted'},
          <String, dynamic>{'kind': 'RelationshipEstablished'},
        ],
      });
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: longLedger,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': true,
            'isNeste': false,
          },
          ledgerJson: shortLedger,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(longLedger));
      expect(
        bootstrap.ledgerImportCandidates,
        equals(<String>[longLedger, shortLedger]),
      );
    });

    test(
        'prefers newer tail timestamp when event counts are equal across ledger and backup',
        () async {
      final olderLedger = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 200},
      ]);
      final newerBackupLedger = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 400},
      ]);
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: newerBackupLedger,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': true,
            'isNeste': false,
          },
          ledgerJson: olderLedger,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(newerBackupLedger));
      expect(
        bootstrap.ledgerImportCandidates,
        equals(<String>[newerBackupLedger, olderLedger]),
      );
    });

    test('prefers ledger.json when event counts and tail timestamps are equal',
        () async {
      final ledgerJson = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 200},
      ]);
      final backupLedgerJson = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 200},
      ]);
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: backupLedgerJson,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': true,
            'isNeste': false,
          },
          ledgerJson: ledgerJson,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(ledgerJson));
      expect(
        bootstrap.ledgerImportCandidates,
        equals(<String>[ledgerJson, backupLedgerJson]),
      );
    });

    test('falls back to backup envelope when ledger.json is missing', () async {
      final ledgerFromBackup =
          ledgerWithOwnerByte(0xaa, kind: 'RelationshipEstablished');
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledgerFromBackup,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': false,
            'isNeste': true,
          },
          ledgerJson: null,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(ledgerFromBackup));
      expect(
        bootstrap.ledgerImportCandidates,
        equals(<String>[ledgerFromBackup]),
      );
      expect(bootstrap.isGenesis, isFalse);
      expect(bootstrap.isNeste, isTrue);
    });

    test('accepts base64 owner field in stored ledger candidate', () async {
      final ledger = ledgerWithBase64Owner(
        ownerByte: 0xaa,
        kind: 'InvitationSent',
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': false,
            'isNeste': true,
          },
          ledgerJson: ledger,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, equals(ledger));
      expect(bootstrap.ledgerImportCandidates, equals(<String>[ledger]));
    });

    test('derives capsule flags from ledger when state flags are missing',
        () async {
      final ledger = ledgerWithCapsuleCreated(
        ownerByte: 0xaa,
        network: 1,
        capsuleType: 1,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: const <String, dynamic>{},
          ledgerJson: ledger,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.isGenesis, isTrue);
      expect(bootstrap.isNeste, isTrue);
    });

    test('prefers ledger capsule-created flags over conflicting state',
        () async {
      final ledger = ledgerWithCapsuleCreated(
        ownerByte: 0xaa,
        network: 0,
        capsuleType: 0,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': true,
            'isNeste': true,
          },
          ledgerJson: ledger,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.isGenesis, isFalse);
      expect(bootstrap.isNeste, isFalse);
    });

    test('returns null when no seed is available', () async {
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ledgerJson: jsonEncode(<String, dynamic>{
            'owner': List<int>.filled(32, 0xaa),
            'events': <Object>[],
          }),
        ),
        _FakeCapsuleSeedStore(null),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNull);
    });

    test('falls back to backup when ledger owner mismatches active capsule',
        () async {
      final mismatchedLedger =
          ledgerWithOwnerByte(0xbb, kind: 'InvitationSent');
      final validBackupLedger =
          ledgerWithOwnerByte(0xaa, kind: 'RelationshipBroken');
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: validBackupLedger,
        isGenesis: false,
        isNeste: true,
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': false,
            'isNeste': true,
          },
          ledgerJson: mismatchedLedger,
          backupJson: backup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, isNotNull);
      expect(bootstrap.ledgerImportCandidates, isNotEmpty);
      final decoded = jsonDecode(bootstrap.ledgerJson!) as Map<String, dynamic>;
      expect(decoded['owner'], equals(List<int>.filled(32, 0xaa)));
      expect((decoded['events'] as List).first['kind'], 'RelationshipBroken');
    });

    test(
        'drops incompatible stored history when both ledger and backup invalid',
        () async {
      final malformedLedger = jsonEncode(<String, dynamic>{
        'owner': <int>[170, 170],
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent'},
        ],
      });
      final mismatchedBackup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledgerWithOwnerByte(0xbb, kind: 'InvitationAccepted'),
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{
            'isGenesis': false,
            'isNeste': true,
          },
          ledgerJson: malformedLedger,
          backupJson: mismatchedBackup,
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.ledgerJson, isNull);
      expect(bootstrap.ledgerImportCandidates, isEmpty);
    });

    test(
      'refreshCapsuleSnapshot falls back to next import candidate when primary import fails',
      () async {
        final shorterLedger = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        ]);
        final longerBackupLedger =
            ledgerWithEvents(0xaa, <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
          <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 200},
        ]);
        final backupEnvelope = CapsuleBackupCodec.encodeBackupEnvelope(
          ledgerJson: longerBackupLedger,
          isGenesis: false,
          isNeste: true,
        );
        final fileStore = _FakeCapsuleFileStore(
          state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ledgerJson: shorterLedger,
          backupJson: backupEnvelope,
        );
        final seedStore = _FakeCapsuleSeedStore(seed);
        final runtime = _FakeBootstrapRuntime(
          seedRootPubkey: Uint8List.fromList(List<int>.filled(32, 0xaa)),
          seedNostrPubkey: Uint8List.fromList(List<int>.filled(32, 0xbb)),
          exportedLedger:
              '{"owner":[170],"events":[{"kind":"CapsuleCreated"}]}',
          importResultsByLedger: <String, bool>{
            longerBackupLedger: false,
            shorterLedger: true,
          },
        );
        final service = CapsuleRuntimeBootstrapService(fileStore, seedStore);

        final restored = await service.refreshCapsuleSnapshot(
          runtime,
          pubKeyHex,
          bytesToHex: bytesToHex,
        );

        expect(restored, isTrue);
        expect(runtime.createCapsuleCalled, isTrue);
        expect(runtime.createCapsuleOwnerMode, equals(runtime.rootOwnerMode));
        expect(
            runtime.importAttempts,
            equals(<String>[
              longerBackupLedger,
              shorterLedger,
            ]));
        expect(fileStore.writtenLedgerJson, equals(runtime.exportedLedger));
      },
    );

    test(
      'refreshCapsuleSnapshot fails when stored history exists and no candidate imports',
      () async {
        final ledger = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        ]);
        final backupLedger = ledgerWithEvents(0xaa, <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
          <String, dynamic>{'kind': 'InvitationAccepted', 'timestamp': 200},
        ]);
        final backupEnvelope = CapsuleBackupCodec.encodeBackupEnvelope(
          ledgerJson: backupLedger,
          isGenesis: false,
          isNeste: true,
        );
        final fileStore = _FakeCapsuleFileStore(
          state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ledgerJson: ledger,
          backupJson: backupEnvelope,
        );
        final seedStore = _FakeCapsuleSeedStore(seed);
        final runtime = _FakeBootstrapRuntime(
          seedRootPubkey: Uint8List.fromList(List<int>.filled(32, 0xaa)),
          seedNostrPubkey: Uint8List.fromList(List<int>.filled(32, 0xbb)),
          exportedLedger:
              '{"owner":[170],"events":[{"kind":"CapsuleCreated"}]}',
          importResultsByLedger: <String, bool>{
            backupLedger: false,
            ledger: false,
          },
        );
        final service = CapsuleRuntimeBootstrapService(fileStore, seedStore);

        final restored = await service.refreshCapsuleSnapshot(
          runtime,
          pubKeyHex,
          bytesToHex: bytesToHex,
        );

        expect(restored, isFalse);
        expect(runtime.importAttempts, equals(<String>[backupLedger, ledger]));
        expect(fileStore.writtenLedgerJson, isNull);
      },
    );

    test(
      'refreshCapsuleSnapshot uses legacy owner mode when identityMode is legacy_nostr_owner',
      () async {
        final legacyPubKeyHex =
            bytesToHex(Uint8List.fromList(List<int>.filled(32, 0xbb)));
        final ledger = ledgerWithEvents(0xbb, <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'InvitationSent', 'timestamp': 100},
        ]);
        final fileStore = _FakeCapsuleFileStore(
          state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ledgerJson: ledger,
        );
        final seedStore = _FakeCapsuleSeedStore(seed);
        final runtime = _FakeBootstrapRuntime(
          seedRootPubkey: Uint8List.fromList(List<int>.filled(32, 0xaa)),
          seedNostrPubkey: Uint8List.fromList(List<int>.filled(32, 0xbb)),
          exportedLedger:
              '{"owner":[187],"events":[{"kind":"CapsuleCreated"}]}',
          importResultsByLedger: <String, bool>{ledger: true},
        );
        final service = CapsuleRuntimeBootstrapService(fileStore, seedStore);

        final restored = await service.refreshCapsuleSnapshot(
          runtime,
          legacyPubKeyHex,
          identityMode: 'legacy_nostr_owner',
          bytesToHex: bytesToHex,
        );

        expect(restored, isTrue);
        expect(runtime.createCapsuleCalled, isTrue);
        expect(
          runtime.createCapsuleOwnerMode,
          equals(runtime.legacyNostrOwnerMode),
        );
      },
    );

    test('loadRuntimeBootstrapForCurrent resolves root_owner identity mode',
        () async {
      final owner = Uint8List.fromList(List<int>.filled(32, 0xaa));
      final runtime = _FakeBootstrapRuntime(
        seedRootPubkey: owner,
        seedNostrPubkey: Uint8List.fromList(List<int>.filled(32, 0xbb)),
        runtimeOwnerPubkey: owner,
        loadedSeed: seed,
        exportedLedger: ledgerWithCapsuleCreated(
          ownerByte: 0xaa,
          network: 1,
          capsuleType: 1,
        ),
      );
      final service = CapsuleRuntimeBootstrapService(
        _FakeCapsuleFileStore(
          state: <String, dynamic>{'isGenesis': false, 'isNeste': false},
        ),
        _FakeCapsuleSeedStore(seed),
      );

      final bootstrap = await service.loadRuntimeBootstrapForCurrent(
        runtime,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNotNull);
      expect(bootstrap!.identityMode, equals('root_owner'));
      expect(bootstrap.pubKeyHex, equals(bytesToHex(owner)));
      expect(bootstrap.isGenesis, isTrue);
      expect(bootstrap.isNeste, isTrue);
      expect(bootstrap.ledgerImportCandidates, hasLength(1));
    });

    test(
      'loadRuntimeBootstrapForCurrent resolves legacy_nostr_owner when runtime owner differs from root',
      () async {
        final runtimeOwner = Uint8List.fromList(List<int>.filled(32, 0xbb));
        final runtime = _FakeBootstrapRuntime(
          seedRootPubkey: Uint8List.fromList(List<int>.filled(32, 0xaa)),
          seedNostrPubkey: runtimeOwner,
          runtimeOwnerPubkey: runtimeOwner,
          loadedSeed: seed,
          exportedLedger: null,
        );
        final service = CapsuleRuntimeBootstrapService(
          _FakeCapsuleFileStore(
            state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ),
          _FakeCapsuleSeedStore(seed),
        );

        final bootstrap = await service.loadRuntimeBootstrapForCurrent(
          runtime,
          bytesToHex: bytesToHex,
        );

        expect(bootstrap, isNotNull);
        expect(bootstrap!.identityMode, equals('legacy_nostr_owner'));
        expect(bootstrap.pubKeyHex, equals(bytesToHex(runtimeOwner)));
        expect(bootstrap.isGenesis, isFalse);
        expect(bootstrap.isNeste, isTrue);
        expect(bootstrap.ledgerImportCandidates, isEmpty);
      },
    );

    test(
      'loadRuntimeBootstrapForCurrent uses single runtime owner snapshot even when runtime owner changes between reads',
      () async {
        final ownerA = Uint8List.fromList(List<int>.filled(32, 0xaa));
        final ownerB = Uint8List.fromList(List<int>.filled(32, 0xbb));
        final runtime = _FakeBootstrapRuntime(
          seedRootPubkey: ownerA,
          seedNostrPubkey: ownerB,
          runtimeOwnerSequence: <Uint8List>[ownerA, ownerB, ownerB],
          loadedSeed: seed,
          exportedLedger: null,
        );
        final service = CapsuleRuntimeBootstrapService(
          _FakeCapsuleFileStore(
            state: <String, dynamic>{'isGenesis': false, 'isNeste': true},
          ),
          _FakeCapsuleSeedStore(seed),
        );

        final bootstrap = await service.loadRuntimeBootstrapForCurrent(
          runtime,
          bytesToHex: bytesToHex,
        );

        expect(bootstrap, isNotNull);
        expect(runtime.runtimeOwnerReadCount, equals(1));
        expect(bootstrap!.pubKeyHex, equals(bytesToHex(ownerA)));
        expect(bootstrap.identityMode, equals('root_owner'));
      },
    );
  });
}
