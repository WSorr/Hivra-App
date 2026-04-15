import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  setUp(() {
    UiEventLogService.resetForTest();
  });

  test('serializes concurrent writes into complete log lines', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-ui-log-');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final service = UiEventLogService(
      directories: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    const burst = 120;
    await Future.wait(
      List.generate(
        burst,
        (i) => service.log('test.source', 'msg-$i'),
      ),
    );

    final logFile = File('${tempHome.path}/Documents/Hivra/logs/ui_events.log');
    expect(await logFile.exists(), isTrue);

    final raw = await logFile.readAsString();
    final lines = const LineSplitter()
        .convert(raw)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    expect(lines.length, burst);
    for (final line in lines) {
      expect(line.contains('[test.source] msg-'), isTrue);
      expect(line.startsWith('['), isTrue);
      expect(line.endsWith(']'), isFalse);
    }
  });

  test('normalizes multiline source and message into single-line log entry',
      () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-ui-log-');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final service = UiEventLogService(
      directories: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    await service.log('source\npart', 'hello\r\nworld');

    final logFile = File('${tempHome.path}/Documents/Hivra/logs/ui_events.log');
    final lines = const LineSplitter().convert(await logFile.readAsString());
    expect(lines.length, 1);
    expect(lines.single.contains('[source part] hello world'), isTrue);
  });

  test('sanitizes legacy torn lines once before appending new log entries',
      () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-ui-log-');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final logDir = Directory('${tempHome.path}/Documents/Hivra/logs');
    await logDir.create(recursive: true);
    final logFile = File('${logDir.path}/ui_events.log');
    await logFile.writeAsString(
      [
        '[2026-04-10T19:31:24.605581] [invitations.reject] Invitation rejected',
        'leased=true retainLocallyResolved=true',
        '=true',
      ].join('\n'),
      flush: true,
    );

    final service = UiEventLogService(
      directories: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    await service.log('post.reboot', 'entry');

    final lines = const LineSplitter().convert(await logFile.readAsString());
    expect(lines.length, 2);
    expect(lines[0], contains('[invitations.reject] Invitation rejected'));
    expect(lines[1], contains('[post.reboot] entry'));
  });
}
