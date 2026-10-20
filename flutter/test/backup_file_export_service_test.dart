import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/backup_file_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hivra/file_documents');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('deletes temporary export after successful share', () async {
    final root = await Directory.systemTemp.createTemp('hivra-share-test-');
    String? sharedPath;
    final service = BackupFileExportService(
      createTemporaryDirectory: (_) async => root,
      shareFile: (path) async {
        sharedPath = path;
        expect(await File(path).readAsString(), 'encrypted');
      },
    );

    await service.share(
      exportToPath: (path) async {
        await File(path).writeAsString('encrypted');
        return path;
      },
    );

    expect(sharedPath, isNotNull);
    expect(await root.exists(), isFalse);
  });

  test('deletes temporary export when sharing throws', () async {
    final root = await Directory.systemTemp.createTemp('hivra-share-test-');
    final service = BackupFileExportService(
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

  for (final outcome in ['saved', 'canceled', 'write_failed']) {
    test('Android save $outcome cleans the encrypted staging file', () async {
      final root = await Directory.systemTemp.createTemp('hivra-save-test-');
      final selected = Completer<String?>();
      final opened = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'saveJsonDocument');
            final args = call.arguments as Map;
            final source = File(args['sourcePath'] as String);
            expect(source.parent.path, root.path);
            expect(
              await source.readAsString(),
              'authenticated encrypted envelope',
            );
            expect(args['suggestedName'], endsWith('.json'));
            opened.complete();
            final result = await selected.future;
            if (outcome == 'write_failed') {
              throw PlatformException(code: 'write_failed');
            }
            return result;
          });
      final service = BackupFileExportService(
        isAndroid: true,
        createTemporaryDirectory: (_) async => root,
      );
      var exports = 0;
      final saving = service.save(
        exportToPath: (path) async {
          exports++;
          await File(path).writeAsString('authenticated encrypted envelope');
          return path;
        },
        isCurrent: () => true,
      );
      final assertion =
          outcome == 'write_failed'
              ? expectLater(saving, throwsA(isA<PlatformException>()))
              : expectLater(
                saving,
                completion(
                  outcome == 'saved' ? 'content://documents/backup' : isNull,
                ),
              );
      await opened.future;
      expect(exports, 1);
      expect(await root.exists(), isTrue);
      selected.complete(
        outcome == 'canceled' ? null : 'content://documents/backup',
      );
      await assertion;
      expect(await root.exists(), isFalse);
    });
  }

  test(
    'Android failed encryption never opens a document or leaves staging',
    () async {
      final root = await Directory.systemTemp.createTemp('hivra-save-test-');
      var opened = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            opened = true;
            return 'content://documents/backup';
          });
      final service = BackupFileExportService(
        isAndroid: true,
        createTemporaryDirectory: (_) async => root,
      );
      await expectLater(
        service.save(exportToPath: (_) async => null, isCurrent: () => true),
        throwsStateError,
      );
      expect(opened, isFalse);
      expect(await root.exists(), isFalse);
    },
  );

  test('closed Android backup screen never opens the save dialog', () async {
    final root = await Directory.systemTemp.createTemp('hivra-save-test-');
    var opened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          opened = true;
          return 'content://documents/backup';
        });
    final service = BackupFileExportService(
      isAndroid: true,
      createTemporaryDirectory: (_) async => root,
    );
    expect(
      await service.save(
        exportToPath: (path) async {
          await File(path).writeAsString('encrypted');
          return path;
        },
        isCurrent: () => false,
      ),
      isNull,
    );
    expect(opened, isFalse);
    expect(await root.exists(), isFalse);
  });
}
