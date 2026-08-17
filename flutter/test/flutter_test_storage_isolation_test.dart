import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  test('default filesystem owners stay beneath the suite sandbox', () async {
    final sandbox = UserVisibleDataDirectoryService.testHomeOverride;
    expect(sandbox, isNotNull);

    final realHome = Platform.environment['HOME'];
    if (realHome != null && realHome.isNotEmpty) {
      expect(
        Directory(sandbox!).absolute.path,
        isNot(Directory(realHome).absolute.path),
      );
    }

    final uniqueHex = '${pid.toRadixString(16)}'
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
        .padLeft(64, '0');
    final realState =
        realHome == null || realHome.isEmpty
            ? null
            : File(
              '$realHome/Library/Application Support/Hivra/'
              'capsules/$uniqueHex/${CapsuleFileStore.stateFileName}',
            );
    if (realState != null) {
      expect(await realState.exists(), isFalse);
    }

    const fileStore = CapsuleFileStore();
    final capsuleDirectory = await fileStore.capsuleDirForHex(
      uniqueHex,
      create: true,
    );
    await fileStore.writeState(capsuleDirectory, const <String, dynamic>{
      'fixture': true,
    });
    UiEventLogService.resetForTest();
    await const UiEventLogService().log(
      'test.storage.isolation',
      'sandbox probe',
    );

    expect(
      capsuleDirectory.absolute.path,
      startsWith(Directory(sandbox!).absolute.path),
    );
    expect(await fileStore.stateFile(capsuleDirectory).exists(), isTrue);
    expect(
      await File(
        '$sandbox/Library/Application Support/Hivra/logs/ui_events.log',
      ).exists(),
      isTrue,
    );
    if (realState != null) {
      expect(await realState.exists(), isFalse);
    }
  });
}
