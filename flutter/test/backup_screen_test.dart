import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  String? capsulePublicKeyHex() => 'a' * 64;

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

  Future<void> showBackup(
    WidgetTester tester, {
    Size size = const Size(1200, 1000),
    bool isNewWallet = false,
    double textScale = 1,
    double bottomInset = 0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                padding: EdgeInsets.only(bottom: bottomInset),
                viewPadding: EdgeInsets.only(bottom: bottomInset),
              ),
              child: child!,
            ),
        home: BackupScreen(
          seed: seed,
          isNewWallet: isNewWallet,
          service: BackupService(runtime),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Backup'));
  }

  Future<void> expectReadableActions(
    WidgetTester tester, {
    required List<String> labels,
    required int columns,
    double textScale = 1,
    double bottomInset = 0,
  }) async {
    await tester.ensureVisible(find.text(labels.last));
    await tester.pump();
    final buttons = <Rect>[];
    for (final label in labels) {
      final text = find.text(label);
      final button = find.widgetWithText(ElevatedButton, label);
      final buttonRect = tester.getRect(button);
      final textRect = tester.getRect(text);
      buttons.add(buttonRect);
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(Scaffold)).bottom - bottomInset,
        ),
        reason: '$label must remain above system navigation',
      );
      expect(buttonRect.width, greaterThanOrEqualTo(48), reason: label);
      expect(buttonRect.height, greaterThanOrEqualTo(48), reason: label);
      expect(buttonRect.contains(textRect.topLeft), isTrue, reason: label);
      expect(buttonRect.contains(textRect.bottomRight), isTrue, reason: label);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: label);
      expect(paragraph.textScaler.scale(14), closeTo(14 * textScale, 0.01));
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      expect(
        painter.computeLineMetrics().length,
        lessThanOrEqualTo(2),
        reason: '$label must not wrap into a column of characters',
      );
      painter.dispose();
    }
    expect(buttons[0].center.dy, closeTo(buttons[1].center.dy, 1));
    if (columns == 2) {
      expect(buttons[2].top, greaterThanOrEqualTo(buttons[0].bottom));
      expect(buttons[0].left, closeTo(buttons[2].left, 1));
      expect(buttons[1].left, closeTo(buttons[3].left, 1));
    } else {
      expect(buttons[0].center.dy, closeTo(buttons[3].center.dy, 1));
    }
    expect(tester.takeException(), isNull);
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
            files: {},
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

  for (final width in [320.0, 360.0, 384.0, 411.0]) {
    for (final isNewWallet in [false, true]) {
      testWidgets('backup actions readable at $width, new: $isNewWallet', (
        tester,
      ) async {
        await showBackup(
          tester,
          size: Size(width, 800),
          isNewWallet: isNewWallet,
        );
        await expectReadableActions(
          tester,
          labels: [
            'Copy',
            'Save Backup',
            'Share',
            isNewWallet ? 'Continue' : 'Done',
          ],
          columns: 2,
        );
        await tester.tap(find.text('Save Backup'));
        await tester.pumpAndSettle();
        expect(dialogs, hasLength(1));
        expect(runtime.exports, isEmpty);
      });
    }
  }

  testWidgets('backup actions remain readable with enlarged phone text', (
    tester,
  ) async {
    await showBackup(
      tester,
      size: const Size(384, 800),
      isNewWallet: true,
      textScale: 1.3,
    );
    await expectReadableActions(
      tester,
      labels: ['Copy', 'Save Backup', 'Share', 'Continue'],
      columns: 2,
      textScale: 1.3,
    );
  });

  testWidgets('backup actions use one readable row on a wide screen', (
    tester,
  ) async {
    await showBackup(tester);
    await expectReadableActions(
      tester,
      labels: ['Copy', 'Save Backup', 'Share', 'Done'],
      columns: 4,
    );
  });

  testWidgets('backup actions stay above Android system navigation', (
    tester,
  ) async {
    await showBackup(tester, size: const Size(384, 800), bottomInset: 48);
    await expectReadableActions(
      tester,
      labels: ['Copy', 'Save Backup', 'Share', 'Done'],
      columns: 2,
      bottomInset: 48,
    );
  });

  testWidgets('saving label remains readable in the phone action grid', (
    tester,
  ) async {
    final selection = Completer<String?>();
    selectPath = () => selection.future;
    await showBackup(tester, size: const Size(384, 800));
    await tester.tap(find.text('Save Backup'));
    await tester.pump();
    await expectReadableActions(
      tester,
      labels: ['Copy', 'Saving...', 'Share', 'Done'],
      columns: 2,
    );
    expect(dialogs, hasLength(1));
    selection.complete(null);
    await tester.pumpAndSettle();
    expect(runtime.exports, isEmpty);
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
