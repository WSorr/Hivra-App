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

    test('prefers ledger.json when both ledger and backup exist', () async {
      final ledger = '{"owner":[1],"events":[{"kind":"InvitationSent"}]}';
      final backup = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: '{"owner":[2],"events":[{"kind":"InvitationRejected"}]}',
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

    test('falls back to backup envelope when ledger.json is missing', () async {
      final ledgerFromBackup =
          '{"owner":[9],"events":[{"kind":"RelationshipEstablished"}]}';
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
          ledgerJson: '{"owner":[3],"events":[]}',
        ),
        const _FakeCapsuleSeedStore(null),
      );

      final bootstrap = await service.loadRuntimeBootstrap(
        pubKeyHex,
        bytesToHex: bytesToHex,
      );

      expect(bootstrap, isNull);
    });
  });
}
