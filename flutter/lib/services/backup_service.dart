import 'dart:typed_data';

import '../ffi/backup_runtime.dart';

class BackupService {
  final BackupRuntime _runtime;

  BackupService([BackupRuntime? runtime])
      : _runtime = runtime ?? HivraBackupRuntime();

  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24}) {
    return _runtime.mnemonicFromSeed(seed, wordCount: wordCount);
  }

  Future<String?> exportBackupEnvelopeToPath(String targetPath) {
    return _runtime.exportBackupEnvelopeToPath(targetPath);
  }

  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste = true,
  }) {
    return _runtime.persistAfterCreate(
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
    );
  }
}
