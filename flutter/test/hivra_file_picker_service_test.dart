import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/hivra_file_picker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const documents = MethodChannel('hivra/file_documents');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(documents, null);
  });

  test('Android JSON picker starts at local Downloads', () {
    expect(
      HivraFilePickerService.initialDirectoryFor(isAndroid: true),
      HivraFilePickerService.androidDownloadsDocumentUri,
    );
  });

  test('desktop picker keeps the platform default location', () {
    expect(
      HivraFilePickerService.initialDirectoryFor(isAndroid: false),
      isNull,
    );
  });

  test(
    'Android returns a readable staged document without channel file bytes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final directory = await Directory.systemTemp.createTemp(
        'hivra-open-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/owner-backup.json',
      ).writeAsString('{}');
      final types = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(documents, (call) async {
            expect(call.method, 'openDocument');
            final args = call.arguments as Map;
            types.add(args['mimeType'] as String);
            expect(
              args['initialDirectory'],
              HivraFilePickerService.androidDownloadsDocumentUri,
            );
            return file.path;
          });
      final selected = await HivraFilePickerService.openJsonDocument();
      expect(selected!.name, 'owner-backup.json');
      expect(await selected.readAsString(), '{}');
      final package = await HivraFilePickerService.openPluginPackage();
      expect(package!.path, file.path);
      expect(types, ['application/json', 'application/zip']);
    },
  );

  test(
    'Android cancel and copy failure do not open a second selector',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(documents, (_) async {
            calls++;
            if (calls == 1) return null;
            throw PlatformException(code: 'document_copy_failed');
          });
      expect(await HivraFilePickerService.openJsonDocument(), isNull);
      await expectLater(
        HivraFilePickerService.openJsonDocument(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, 2);
    },
  );
}
