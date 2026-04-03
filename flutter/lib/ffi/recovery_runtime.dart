import 'dart:typed_data';

import '../services/capsule_persistence_service.dart';
import 'hivra_bindings.dart';

abstract class RecoveryRuntime {
  bool validateMnemonic(String phrase);

  Uint8List mnemonicToSeed(String phrase);

  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
  });

  Uint8List? capsuleRuntimeOwnerPublicKey();

  bool importLedger(String ledgerJson);

  String? exportLedger();

  Future<bool> importLedgerIfExists();

  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste,
  });
}

class HivraRecoveryRuntime implements RecoveryRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  HivraRecoveryRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  bool validateMnemonic(String phrase) => _hivra.validateMnemonic(phrase);

  @override
  Uint8List mnemonicToSeed(String phrase) => _hivra.mnemonicToSeed(phrase);

  @override
  String? createCapsuleError(
    Uint8List seed, {
    required bool isGenesis,
  }) {
    return _hivra.createCapsuleError(
      seed,
      isGenesis: isGenesis,
      ownerMode: HivraBindings.rootOwnerMode,
    );
  }

  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() =>
      _hivra.capsuleRuntimeOwnerPublicKey();

  @override
  bool importLedger(String ledgerJson) => _hivra.importLedger(ledgerJson);

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  Future<bool> importLedgerIfExists() =>
      _persistence.importLedgerIfExists(_hivra);

  @override
  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste = true,
  }) {
    return _persistence.persistAfterCreate(
      hivra: _hivra,
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
    );
  }
}
