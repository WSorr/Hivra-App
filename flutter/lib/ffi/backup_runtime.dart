import 'dart:typed_data';

import '../services/capsule_persistence_service.dart';
import 'hivra_bindings.dart';

abstract class BackupRuntime {
  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24});

  Future<String?> exportBackupEnvelopeToPath(String targetPath);

  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste,
  });
}

class HivraBackupRuntime implements BackupRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  HivraBackupRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24}) {
    return _hivra.seedToMnemonic(seed, wordCount: wordCount);
  }

  @override
  Future<String?> exportBackupEnvelopeToPath(String targetPath) {
    return _persistence.exportBackupEnvelopeToPath(_hivra, targetPath);
  }

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
