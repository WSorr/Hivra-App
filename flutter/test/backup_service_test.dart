import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/ffi/backup_runtime.dart';
import 'package:hivra_app/services/backup_service.dart';

class _FakeBackupRuntime implements BackupRuntime {
  Uint8List? mnemonicSeed;
  int? mnemonicWordCount;
  String mnemonicResult = '';

  String? exportPathArg;
  String? exportResult;

  Uint8List? persistSeed;
  bool? persistIsGenesis;
  bool? persistIsNeste;

  @override
  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24}) {
    mnemonicSeed = seed;
    mnemonicWordCount = wordCount;
    return mnemonicResult;
  }

  @override
  Future<String?> exportBackupEnvelopeToPath(String targetPath) async {
    exportPathArg = targetPath;
    return exportResult;
  }

  @override
  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste = true,
  }) async {
    persistSeed = seed;
    persistIsGenesis = isGenesis;
    persistIsNeste = isNeste;
  }
}

void main() {
  test('delegates mnemonic/export/persist operations to backup runtime',
      () async {
    final runtime = _FakeBackupRuntime()
      ..mnemonicResult = 'alpha beta gamma'
      ..exportResult = '/tmp/capsule-backup.json';
    final service = BackupService(runtime);
    final seed = Uint8List.fromList(List<int>.filled(32, 7));

    final mnemonic = service.mnemonicFromSeed(seed, wordCount: 12);
    final exported = await service.exportBackupEnvelopeToPath('/tmp/out.json');
    await service.persistAfterCreate(
      seed: seed,
      isGenesis: true,
      isNeste: false,
    );

    expect(mnemonic, 'alpha beta gamma');
    expect(runtime.mnemonicSeed, seed);
    expect(runtime.mnemonicWordCount, 12);
    expect(exported, '/tmp/capsule-backup.json');
    expect(runtime.exportPathArg, '/tmp/out.json');
    expect(runtime.persistSeed, seed);
    expect(runtime.persistIsGenesis, isTrue);
    expect(runtime.persistIsNeste, isFalse);
  });
}
