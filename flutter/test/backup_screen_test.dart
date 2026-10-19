import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/backup_runtime.dart';
import 'package:hivra_app/screens/backup_screen.dart';
import 'package:hivra_app/services/backup_service.dart';
import 'package:hivra_app/services/capsule_backup_codec.dart';

class _BackupRuntime implements BackupRuntime {
  final exports = <String>[];
  Future<String?> Function(String, Uint8List)? export;

  @override
  String mnemonicFromSeed(Uint8List seed, {int wordCount = 24}) =>
      List.filled(wordCount, 'test').join(' ');

  @override
  Future<String?> exportBackupEnvelopeToPath(String path, Uint8List seed) {
    exports.add(path);
    return export?.call(path, seed) ?? Future.value(path);
  }

  @override
  Future<void> persistAfterCreate({
    required Uint8List seed,
    required bool isGenesis,
    bool isNeste = true,
  }) async => throw StateError('Saving a backup must not persist a Capsule');
}

void main() {
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final seed = Uint8List.fromList(List.generate(32, (i) => i));
  late _BackupRuntime runtime;
  late Future<String?> Function() selectPath;
  late List<MethodCall> dialogs;

  setUp(() {
    runtime = _BackupRuntime();
    dialogs = [];
    selectPath = () async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          dialogs.add(call);
          expect(call.method, 'getSavePath');
          return selectPath();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> showBackup(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(
          seed: seed,
          isNewWallet: false,
          service: BackupService(runtime),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Backup'));
  }

  testWidgets('Save writes a recoverable file at the selected location', (
    tester,
  ) async {
    final directory =
        (await tester.runAsync(
          () => Directory.systemTemp.createTemp('hivra-save-test-'),
        ))!;
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/My Capsule — backup.json');
    final ledger = jsonEncode({
      'owner': List.filled(32, 0x42),
      'events': <Object>[],
    });
    final envelope =
        (await tester.runAsync(
          () => CapsuleBackupCodec.encodeEncryptedBackupEnvelope(
            ledgerJson: ledger,
            seed: seed,
            isGenesis: true,
          ),
        ))!;
    selectPath = () async => target.path;
    runtime.export = (path, exportSeed) async {
      expect(exportSeed, seed);
      File(path).writeAsStringSync(envelope, flush: true);
      return path;
    };

    await showBackup(tester);
    await tester.tap(find.text('Save Backup'));
    await tester.pumpAndSettle();
    expect(dialogs, hasLength(1));
    final options = dialogs.single.arguments as Map;
    expect(options['suggestedName'], endsWith('.json'));
    expect(options['acceptedTypeGroups'], [
      containsPair('extensions', ['json']),
    ]);
    await tester.pumpAndSettle();
    expect(runtime.exports, [target.path]);
    expect(find.textContaining('Backup file: ${target.path}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      final envelope = await target.readAsString();
      expect(CapsuleBackupCodec.isEncryptedEnvelope(envelope), isTrue);
      expect(envelope, isNot(contains('events')));
      expect(envelope, isNot(contains('owner')));
      final restored = await CapsuleBackupCodec.tryDecodeBackup(envelope, seed);
      expect(jsonDecode(restored!.ledgerJson), jsonDecode(ledger));
      expect(restored.isGenesis, isTrue);
    });
  });

  testWidgets('cancel does not export and allows a new save', (tester) async {
    await showBackup(tester);
    await tester.tap(find.text('Save Backup'));
    await tester.pumpAndSettle();
    expect(runtime.exports, isEmpty);
    expect(find.textContaining('Backup file:'), findsNothing);
    selectPath = () async => '/chosen/capsule.json';
    await tester.tap(find.text('Save Backup'));
    await tester.pumpAndSettle();
    expect(runtime.exports, ['/chosen/capsule.json']);
  });

  testWidgets('picker failure does not export and allows retry', (
    tester,
  ) async {
    selectPath = () async => throw PlatformException(code: 'dialog_failed');
    await showBackup(tester);
    await tester.tap(find.text('Save Backup'));
    await tester.pumpAndSettle();
    expect(runtime.exports, isEmpty);
    expect(find.textContaining('Backup export failed:'), findsOneWidget);
    selectPath = () async => '/chosen/retry.json';
    await tester.tap(find.text('Save Backup'));
    await tester.pumpAndSettle();
    expect(runtime.exports, ['/chosen/retry.json']);
  });

  for (final throwsError in [false, true]) {
    testWidgets('failed export ($throwsError) never reports a saved file', (
      tester,
    ) async {
      selectPath = () async => '/chosen/capsule.json';
      runtime.export = (_, _) async {
        if (throwsError) throw const FileSystemException('write failed');
        return null;
      };
      await showBackup(tester);
      await tester.tap(find.text('Save Backup'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Backup file:'), findsNothing);
      expect(find.textContaining('Capsule backup saved:'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save Backup'),
            )
            .onPressed,
        isNotNull,
      );
    });
  }

  testWidgets('only one save dialog can own an export at a time', (
    tester,
  ) async {
    final selection = Completer<String?>();
    selectPath = () => selection.future;
    await showBackup(tester);
    final save =
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save Backup'),
            )
            .onPressed!;
    save();
    save();
    await tester.pump();
    expect(dialogs, hasLength(1));
    expect(runtime.exports, isEmpty);
    selection.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('closing the screen while picking never starts an export', (
    tester,
  ) async {
    final selection = Completer<String?>();
    selectPath = () => selection.future;
    await showBackup(tester);
    await tester.tap(find.text('Save Backup'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    selection.complete('/chosen/abandoned.json');
    await tester.pumpAndSettle();
    expect(runtime.exports, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
