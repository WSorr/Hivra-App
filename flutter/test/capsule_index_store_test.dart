import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/capsule_index_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDocsDir;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('hivra_index_store_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDocsDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('preserves active capsule across write/read roundtrip', () async {
    const capsuleA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const capsuleB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const store = CapsuleIndexStore();

    await store.upsert(capsuleA, isGenesis: true, isNeste: true);
    await store.upsert(capsuleB, isGenesis: false, isNeste: true);
    await store.setActive(capsuleB);

    final index = await store.read();
    expect(index.activePubKeyHex, equals(capsuleB));
    expect(index.capsules.keys.toSet(), equals({capsuleA, capsuleB}));
  });

  test('drops stale active pointer when capsule entry is missing', () async {
    const staleActive =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    const existingCapsule =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    final capsulesRoot = Directory('${tempDocsDir.path}/capsules');
    await capsulesRoot.create(recursive: true);
    final indexFile = File('${capsulesRoot.path}/capsules_index.json');

    await indexFile.writeAsString(
      '{"active":"$staleActive","capsules":{"$existingCapsule":{"pubKeyHex":"$existingCapsule","createdAt":"2026-03-28T00:00:00.000Z","lastActive":"2026-03-28T00:00:00.000Z","isGenesis":false,"isNeste":true,"identityMode":"root_owner"}}}',
      flush: true,
    );

    const store = CapsuleIndexStore();
    final index = await store.read();

    expect(index.activePubKeyHex, isNull);
    expect(index.capsules.containsKey(existingCapsule), isTrue);
  });
}
