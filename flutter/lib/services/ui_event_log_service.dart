import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'user_visible_data_directory_service.dart';

class UiEventLogService {
  static Future<void> _writeQueue = Future<void>.value();
  static bool _didSanitizeLogFile = false;
  static final RegExp _logLinePattern =
      RegExp(r'^\[[^\]]+\] \[[^\]]+\] .+$');

  final UserVisibleDataDirectoryService _directories;

  const UiEventLogService({
    UserVisibleDataDirectoryService directories =
        const UserVisibleDataDirectoryService(),
  }) : _directories = directories;

  Future<void> log(String source, String message) async {
    final ts = DateTime.now().toIso8601String();
    final normalizedSource = _normalize(source);
    final normalizedMessage = _normalize(message);
    final line = '[$ts] [$normalizedSource] $normalizedMessage';
    debugPrint(line);

    try {
      await _enqueueWrite(line);
    } catch (_) {
      // Logging failures must never break UI actions.
    }
  }

  Future<void> _enqueueWrite(String line) {
    final next = _writeQueue
        .catchError((_) {})
        .then<void>((_) => _appendLine(line));
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _appendLine(String line) async {
    final root = await _directories.rootDirectory(create: true);
    final logsDir = Directory('${root.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final file = File('${logsDir.path}/ui_events.log');
    await _sanitizeLogFileIfNeeded(file);
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> _sanitizeLogFileIfNeeded(File file) async {
    if (_didSanitizeLogFile) return;
    _didSanitizeLogFile = true;

    if (!await file.exists()) return;
    final raw = await file.readAsString();
    final lines = const LineSplitter().convert(raw);
    final cleaned = lines.where(_isValidLogLine).toList(growable: false);
    if (cleaned.length == lines.length) return;

    final normalized = cleaned.isEmpty ? '' : '${cleaned.join('\n')}\n';
    await file.writeAsString(normalized, flush: true);
  }

  bool _isValidLogLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    return _logLinePattern.hasMatch(trimmed);
  }

  String _normalize(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.isEmpty ? '-' : compact;
  }

  @visibleForTesting
  static void resetForTest() {
    _writeQueue = Future<void>.value();
    _didSanitizeLogFile = false;
  }
}
