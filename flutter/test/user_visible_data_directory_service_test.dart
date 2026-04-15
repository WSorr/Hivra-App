import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  test('legacy documents migration runs once and does not rehydrate deleted data',
      () async {
    final tempHome =
        await Directory.systemTemp.createTemp('hivra-user-visible-dirs-');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final service = UserVisibleDataDirectoryService(homeOverride: tempHome.path);

    final legacyRoot = Directory(
      '${tempHome.path}/Library/Containers/com.hivra.hivraApp/Data/Documents/Hivra',
    );
    final legacyCapsulesDir = Directory('${legacyRoot.path}/capsules');
    await legacyCapsulesDir.create(recursive: true);
    final legacyIndexFile = File('${legacyCapsulesDir.path}/capsules_index.json');
    await legacyIndexFile.writeAsString(
      '{"active":null,"capsules":{}}',
      flush: true,
    );

    final root = await service.rootDirectory(create: true);
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

    final marker = File('${root.path}/.legacy_documents_migration_v1.done');
    expect(await marker.exists(), isTrue);
  });
}
