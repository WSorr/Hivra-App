import 'dart:io';

import 'package:flutter/foundation.dart';

import 'user_visible_data_directory_service.dart';

class UiEventLogService {
  final UserVisibleDataDirectoryService _directories;

  const UiEventLogService({
    UserVisibleDataDirectoryService directories =
        const UserVisibleDataDirectoryService(),
  }) : _directories = directories;

  Future<void> log(String source, String message) async {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] [$source] $message';
    debugPrint(line);

    try {
      final root = await _directories.rootDirectory(create: true);
      final logsDir = Directory('${root.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      final file = File('${logsDir.path}/ui_events.log');
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging failures must never break UI actions.
    }
  }
}
