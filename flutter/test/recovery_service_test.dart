import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/ffi/recovery_runtime.dart';
import 'package:hivra_app/services/recovery_service.dart';

class _FakeRecoveryRuntime implements RecoveryRuntime {
  bool validateResult = true;
  Uint8List seed = Uint8List.fromList(List<int>.filled(32, 1));
  String? createError;
  Uint8List? runtimeOwner;
  bool importLedgerResult = true;
  String? exportedLedger;
  bool importLedgerIfExistsResult = false;
  Uint8List? persistedSeed;
  bool? persistedIsGenesis;
  bool? persistedIsNeste;

  int createCapsuleErrorCalls = 0;
  int importLedgerCalls = 0;

  @override
  bool validateMnemonic(String phrase) => validateResult;

  @override
  Uint8List mnemonicToSeed(String phrase) => seed;

  @override
  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
  }) {
    createCapsuleErrorCalls += 1;
    return createError;
  }

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() => runtimeOwner;

  @override
  bool importLedger(String ledgerJson) {
    importLedgerCalls += 1;
    return importLedgerResult;
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
  test('recover rejects selected backup when owner mismatches runtime capsule',
      () async {
    final runtime = _FakeRecoveryRuntime()
      ..runtimeOwner = Uint8List.fromList(List<int>.filled(32, 0x11));
    final service = RecoveryService(runtime);
    final backupLedgerJson =
        '{"owner":"2222222222222222222222222222222222222222222222222222222222222222","events":[]}';

    final result = await service.recover(
      phrase: 'alpha beta gamma',
      selectedBackupLedgerJson: backupLedgerJson,
      selectedBackupIsGenesis: false,
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'Selected backup does not match this seed phrase',
    );
    expect(runtime.importLedgerCalls, 0);
    expect(runtime.persistedSeed, isNull);
  });

  test('recover persists seed when no backup is selected and import is absent',
      () async {
    final runtime = _FakeRecoveryRuntime()..importLedgerIfExistsResult = false;
    final service = RecoveryService(runtime);

    final result = await service.recover(
      phrase: 'alpha beta gamma',
      selectedBackupLedgerJson: null,
      selectedBackupIsGenesis: null,
    );

    expect(result.isSuccess, isTrue);
    expect(runtime.createCapsuleErrorCalls, 1);
    expect(runtime.persistedSeed, runtime.seed);
    expect(runtime.persistedIsGenesis, isFalse);
    expect(runtime.persistedIsNeste, isTrue);
  });
}
