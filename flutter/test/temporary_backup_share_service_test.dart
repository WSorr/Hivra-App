import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/temporary_backup_share_service.dart';

void main() {
  test('deletes temporary export after successful share', () async {
    final root = await Directory.systemTemp.createTemp('hivra-share-test-');
    String? sharedPath;
    final service = TemporaryBackupShareService(
      createTemporaryDirectory: (_) async => root,
      shareFile: (path) async {
        sharedPath = path;
        expect(await File(path).readAsString(), 'encrypted');
      },
    );

    final shared = await service.share(
      exportToPath: (path) async {
        await File(path).writeAsString('encrypted');
        return path;
      },
    );

    expect(shared, isTrue);
    expect(sharedPath, isNotNull);
    expect(await root.exists(), isFalse);
  });

  test('deletes temporary export when sharing throws', () async {
    final root = await Directory.systemTemp.createTemp('hivra-share-test-');
    final service = TemporaryBackupShareService(
      createTemporaryDirectory: (_) async => root,
      shareFile: (_) async => throw StateError('share failed'),
    );

    await expectLater(
      service.share(
        exportToPath: (path) async {
          await File(path).writeAsString('encrypted');
          return path;
        },
      ),
      throwsStateError,
    );
    expect(await root.exists(), isFalse);
  });
}
