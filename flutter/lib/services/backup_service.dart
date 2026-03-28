import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';

class BackupService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  BackupService({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24}) {
    return _hivra.seedToMnemonic(seed, wordCount: wordCount);
  }

  Future<String?> exportBackupEnvelopeToPath(String targetPath) {
    return _persistence.exportBackupEnvelopeToPath(_hivra, targetPath);
  }

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
