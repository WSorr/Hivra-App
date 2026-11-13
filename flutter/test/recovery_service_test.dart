import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/ffi/recovery_runtime.dart';
import 'package:hivra_app/services/recovery_service.dart';
import 'package:hivra_app/services/capsule_backup_codec.dart';

class _FakeRecoveryRuntime implements RecoveryRuntime {
  bool validateResult = true;
  Uint8List seed = Uint8List.fromList(List<int>.filled(32, 1));
  String? createError;
  String? exportedLedger;
  bool importLedgerIfExistsResult = false;
  Uint8List? persistedSeed;
  bool? persistedIsGenesis;
  bool? persistedIsNeste;

  int createCapsuleErrorCalls = 0;
  String? importedCompleteBackup;
  Uint8List? importedSeed;
  bool importCompleteResult = true;
  bool failImport = false;
  @override
  Future<bool> importCompleteBackup(String raw, Uint8List seed) async {
    importedCompleteBackup = raw;
    importedSeed = seed;
    if (failImport) throw StateError('existing Capsule cannot be replaced');
    return importCompleteResult;
  }

  @override
  bool validateMnemonic(String phrase) => validateResult;

  @override
  Uint8List mnemonicToSeed(String phrase) => seed;

  @override
  String? createCapsuleError(Uint8List seed, {required bool isGenesis}) {
    createCapsuleErrorCalls += 1;
    return createError;
  }

  @override
  String? exportLedger() => exportedLedger;

  @override
  Future<bool> importLedgerIfExists() async => importLedgerIfExistsResult;

  @override
  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste = true,
  }) async {
    persistedSeed = seed;
    persistedIsGenesis = isGenesis;
    persistedIsNeste = isNeste;
  }
}

void main() {
  test(
    'complete recovery uses the same full import owner without ledger-only fallback',
    () async {
      final runtime = _FakeRecoveryRuntime();
      final raw = await CapsuleBackupCodec.encodeEncryptedBackupEnvelope(
        ledgerJson: jsonEncode({'owner': List.filled(32, 1), 'events': []}),
        seed: runtime.seed,
        files: {
          'plugin_state/hivra.test.v1/workspace.v1.json': base64Encode(
            utf8.encode('{"opaque":7}'),
          ),
        },
        packages: {},
      );
      final result = await RecoveryService(
        runtime,
      ).recover(phrase: 'public test', selectedBackupJson: raw);
      expect(result.isSuccess, true);
      expect(runtime.importedCompleteBackup, raw);
      expect(runtime.createCapsuleErrorCalls, 0);
      expect(runtime.persistedSeed, isNull);
    },
  );

  test(
    'rejected selected backup cannot fall back to identity creation',
    () async {
      final runtime = _FakeRecoveryRuntime()..importCompleteResult = false;
      final service = RecoveryService(runtime);
      final backupLedgerJson =
          '{"owner":"2222222222222222222222222222222222222222222222222222222222222222","events":[]}';

      final result = await service.recover(
        phrase: 'alpha beta gamma',
        selectedBackupJson: backupLedgerJson,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Failed to restore Capsule backup');
      expect(runtime.importedCompleteBackup, backupLedgerJson);
      expect(runtime.createCapsuleErrorCalls, 0);
      expect(runtime.persistedSeed, isNull);
    },
  );

  test(
    'recover persists seed when no backup is selected and import is absent',
    () async {
      final runtime =
          _FakeRecoveryRuntime()..importLedgerIfExistsResult = false;
      final service = RecoveryService(runtime);

      final result = await service.recover(
        phrase: 'alpha beta gamma',
        selectedBackupJson: null,
      );

      expect(result.isSuccess, isTrue);
      expect(runtime.createCapsuleErrorCalls, 1);
      expect(runtime.persistedSeed, runtime.seed);
      expect(runtime.persistedIsGenesis, isFalse);
      expect(runtime.persistedIsNeste, isTrue);
    },
  );

  test(
    'v2 recovery delegates the original bytes and seed to atomic import',
    () async {
      final runtime =
          _FakeRecoveryRuntime()
            ..seed = Uint8List.fromList(List<int>.filled(32, 7));
      final service = RecoveryService(runtime);
      final ledger = jsonEncode(<String, dynamic>{
        'owner': List<int>.filled(32, 7),
        'events': <Object>[],
      });
      runtime.exportedLedger = ledger;
      final backup =
          await File('test/fixtures/capsule_backup_v2.json').readAsString();
      final result = await service.recover(
        phrase: 'alpha beta gamma',
        selectedBackupJson: backup,
      );

      expect(result.isSuccess, isTrue);
      expect(runtime.importedCompleteBackup, backup);
      expect(runtime.importedSeed, runtime.seed);
      expect(runtime.createCapsuleErrorCalls, 0);
      expect(runtime.persistedSeed, isNull);
    },
  );

  test(
    'failed selected-backup import never persists a replacement identity',
    () async {
      final runtime = _FakeRecoveryRuntime()..failImport = true;
      final result = await RecoveryService(runtime).recover(
        phrase: 'public test',
        selectedBackupJson: '{"untrusted":"input"}',
      );
      expect(result.isSuccess, false);
      expect(runtime.createCapsuleErrorCalls, 0);
      expect(runtime.persistedSeed, isNull);
    },
  );
}
