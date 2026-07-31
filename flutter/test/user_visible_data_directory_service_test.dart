import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  test('runtime migration runs once and does not rehydrate deleted data', () async {
    final tempHome = await Directory.systemTemp.createTemp(
      'hivra-user-visible-dirs-',
    );
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final service = UserVisibleDataDirectoryService(
      homeOverride: tempHome.path,
    );

    final legacyRoot = Directory(
      '${tempHome.path}/Library/Containers/com.hivra.hivraApp/Data/Documents/Hivra',
    );
    final legacyCapsulesDir = Directory('${legacyRoot.path}/capsules');
    await legacyCapsulesDir.create(recursive: true);
    final legacyIndexFile = File(
      '${legacyCapsulesDir.path}/capsules_index.json',
    );
    await legacyIndexFile.writeAsString(
      '{"active":null,"capsules":{}}',
      flush: true,
    );

    final root = await service.rootDirectory(create: true);
    expect(root.path, '${tempHome.path}/Library/Application Support/Hivra');
    final migratedIndex = File('${root.path}/capsules/capsules_index.json');
    expect(await migratedIndex.exists(), isTrue);

    await migratedIndex.delete();
    expect(await migratedIndex.exists(), isFalse);

    await service.rootDirectory(create: true);
    expect(
      await migratedIndex.exists(),
      isFalse,
      reason:
          'legacy migration must be one-shot; deleted canonical data must not be re-imported',
    );

    final marker = File('${root.path}/.documents_runtime_migration_v1.done');
    expect(await marker.exists(), isTrue);
  });

  test('moves runtime data but keeps backups user-visible', () async {
    final tempHome = await Directory.systemTemp.createTemp(
      'hivra-runtime-split-',
    );
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final visibleRoot = Directory('${tempHome.path}/Documents/Hivra');
    final capsules = Directory('${visibleRoot.path}/capsules');
    final backups = Directory('${visibleRoot.path}/Backups');
    await capsules.create(recursive: true);
    await backups.create(recursive: true);
    await File(
      '${capsules.path}/capsules_index.json',
    ).writeAsString('{"active":null,"capsules":{}}', flush: true);
    await File(
      '${backups.path}/manual-backup.json',
    ).writeAsString('{"backup":true}', flush: true);

    final service = UserVisibleDataDirectoryService(
      homeOverride: tempHome.path,
    );
    final runtimeRoot = await service.rootDirectory(create: true);
    final visibleBackups = await service.backupsDirectory();

    expect(
      await File('${runtimeRoot.path}/capsules/capsules_index.json').exists(),
      isTrue,
    );
    expect(
      await File('${runtimeRoot.path}/Backups/manual-backup.json').exists(),
      isFalse,
    );
    expect(visibleBackups.path, backups.path);
    expect(await File('${backups.path}/manual-backup.json').exists(), isTrue);
  });
}
