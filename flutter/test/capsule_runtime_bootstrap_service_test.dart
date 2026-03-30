import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_backup_codec.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
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
}

class _FakeCapsuleSeedStore extends CapsuleSeedStore {
  const _FakeCapsuleSeedStore(this.seed);

  final Uint8List? seed;

  @override
  Future<Uint8List?> loadSeed(String pubKeyHex) async => seed;
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

    test('prefers ledger.json when both ledger and backup exist', () async {
      final ledger = ledgerWithOwnerByte(0xaa, kind: 'InvitationSent');
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledgerWithOwnerByte(0xaa, kind: 'InvitationRejected'),
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
      expect(bootstrap.isGenesis, isFalse);
      expect(bootstrap.isNeste, isTrue);
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
        const _FakeCapsuleSeedStore(null),
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
    });
  });
}
