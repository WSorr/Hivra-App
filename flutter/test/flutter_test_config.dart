import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = await Directory.systemTemp.createTemp(
    'hivra-flutter-test-home-',
  );
  UserVisibleDataDirectoryService.setTestHomeOverride(sandbox.path);
  var cleaned = false;
  Future<void> cleanup() async {
    if (cleaned) return;
    cleaned = true;
    UserVisibleDataDirectoryService.setTestHomeOverride(null);
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  }

  tearDownAll(cleanup);
  try {
    await testMain();
  } catch (_) {
    await cleanup();
    rethrow;
  }
}
