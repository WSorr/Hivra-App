import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_seed_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final Map<String, int> readCounts = <String, int>{};
  final List<String> writtenKeys = <String>[];
  String? failReadKey;
  String? failWriteKey;
  String? ignoreWriteKey;
  bool failDelete = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writtenKeys.add(key);
    if (key == failWriteKey) throw StateError('test secure write failure');
    if (key == ignoreWriteKey) return;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCounts[key] = (readCounts[key] ?? 0) + 1;
    if (key == failReadKey) throw StateError('test secure read failure');
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDelete) throw Exception('secure storage delete unavailable');
    values.remove(key);
  }
}

class _ThrowingSecureStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('secure storage unavailable');
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('secure storage unavailable');
  }
}

void main() {
  const capsuleHex =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final seed = Uint8List.fromList(List<int>.generate(32, (index) => index));

  test('stores seed only in secure storage', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    await store.storeSeed(capsuleHex, seed);

    expect(secureStorage.values['hivra.seed.$capsuleHex'], base64.encode(seed));
    expect(
      File(
        '${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json',
      ).existsSync(),
      isFalse,
    );
  });

  test('fails closed when secure storage is unavailable', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final store = CapsuleSeedStore(
      secureStorage: _ThrowingSecureStorage(),
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    await expectLater(
      store.storeSeed(capsuleHex, seed),
      throwsA(isA<StateError>()),
    );
    expect(
      File(
        '${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json',
      ).existsSync(),
      isFalse,
    );
  });

  test('does not report secure storage failure as a missing seed', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final store = CapsuleSeedStore(
      secureStorage: _ThrowingSecureStorage(),
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    await expectLater(
      store.loadSeed(capsuleHex),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Secure seed access is unavailable'),
        ),
      ),
    );
    await expectLater(
      store.hasStoredSeed(capsuleHex),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      store.loadValidatedSeed(
        capsuleHex,
        isValidSeed: (_) async => true,
        persistValidatedSeed: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      File(
        '${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json',
      ).existsSync(),
      isFalse,
    );
  });

  test('migrates legacy plaintext seed into secure storage', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final fallbackFile = File(
      '${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json',
    );
    await fallbackFile.parent.create(recursive: true);
    await fallbackFile.writeAsString(
      jsonEncode(<String, String>{capsuleHex: base64.encode(seed)}),
    );
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    final loaded = await store.loadSeed(capsuleHex);

    expect(loaded, orderedEquals(seed));
    expect(secureStorage.values['hivra.seed.$capsuleHex'], base64.encode(seed));
    expect(await fallbackFile.exists(), isFalse);
  });

  group('legacy seed migration preservation', () {
    late Directory root;
    late File source;
    late _FakeSecureStorage secureStorage;
    late CapsuleSeedStore store;
    final otherCapsule = List<String>.filled(64, 'b').join();
    final otherSeed = Uint8List.fromList(seed.reversed.toList());

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hivra-seed-test-');
      source = File('${root.path}/capsules/capsule_seeds.json');
      await source.parent.create(recursive: true);
      secureStorage = _FakeSecureStorage();
      store = CapsuleSeedStore(
        secureStorage: secureStorage,
        dirs: UserVisibleDataDirectoryService(
          runtimeRootOverride: root.path,
          homeOverride: root.path,
        ),
      );
    });

    tearDown(() => root.delete(recursive: true));

    final invalidSources = <String, String>{
      'empty file': '',
      'whitespace': ' \n\t ',
      'broken JSON': '{malformed',
      'non-object root': '[]',
      'null root': 'null',
      'invalid owner': jsonEncode({
        capsuleHex: base64.encode(seed),
        'invalid-owner': base64.encode(seed),
      }),
      'invalid seed': jsonEncode({
        capsuleHex: base64.encode(seed),
        otherCapsule: 'invalid-base64',
      }),
      'wrong seed length': jsonEncode({
        capsuleHex: base64.encode(seed),
        otherCapsule: base64.encode([1, 2, 3]),
      }),
      'non-string seed': jsonEncode({capsuleHex: null}),
      'duplicate normalized owner': jsonEncode({
        capsuleHex: base64.encode(seed),
        capsuleHex.toUpperCase(): base64.encode(otherSeed),
      }),
    };

    for (final entry in invalidSources.entries) {
      test(
        '${entry.key} retains source and blocks writes until retry',
        () async {
          await source.writeAsString(entry.value);
          for (final operation in <Future<Object?> Function()>[
            () => store.loadSeed(capsuleHex),
            () => store.hasStoredSeed(capsuleHex),
            () => store.loadValidatedSeed(
              capsuleHex,
              isValidSeed: (_) async => true,
              persistValidatedSeed: (_) async => fail('Unexpected persistence'),
            ),
            () => store.storeSeed(capsuleHex, seed),
          ]) {
            await expectLater(operation(), throwsA(isA<StateError>()));
            expect(await source.readAsString(), entry.value);
            expect(secureStorage.values, isEmpty);
            expect(secureStorage.writtenKeys, isEmpty);
          }

          await source.writeAsString(
            jsonEncode({capsuleHex: base64.encode(seed)}),
          );
          expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
          expect(await source.exists(), isFalse);
          expect(
            secureStorage.values['hivra.seed.$capsuleHex'],
            base64.encode(seed),
          );
        },
      );
    }

    test(
      'conflicting secure seed is never replaced by a legacy seed',
      () async {
        final original = jsonEncode({capsuleHex: base64.encode(seed)});
        await source.writeAsString(original);
        secureStorage.values['hivra.seed.$capsuleHex'] = base64.encode(
          otherSeed,
        );

        await expectLater(
          store.loadSeed(capsuleHex),
          throwsA(isA<StateError>()),
        );

        expect(await source.readAsString(), original);
        expect(
          secureStorage.values['hivra.seed.$capsuleHex'],
          base64.encode(otherSeed),
        );
        expect(secureStorage.writtenKeys, isEmpty);
      },
    );

    for (final failure in [
      'read failure',
      'write failure',
      'read-back mismatch',
    ]) {
      test('$failure retains all source entries for retry', () async {
        final original = jsonEncode({
          capsuleHex: base64.encode(seed),
          otherCapsule: base64.encode(otherSeed),
        });
        await source.writeAsString(original);
        if (failure == 'read failure') {
          secureStorage.failReadKey = 'hivra.seed.$otherCapsule';
        } else if (failure == 'write failure') {
          secureStorage.failWriteKey = 'hivra.seed.$otherCapsule';
        } else {
          secureStorage.ignoreWriteKey = 'hivra.seed.$otherCapsule';
        }

        await expectLater(
          store.loadSeed(capsuleHex),
          throwsA(isA<StateError>()),
        );
        expect(await source.readAsString(), original);
        expect(
          secureStorage.values['hivra.seed.$capsuleHex'],
          base64.encode(seed),
        );

        secureStorage.failReadKey = null;
        secureStorage.failWriteKey = null;
        secureStorage.ignoreWriteKey = null;
        store = CapsuleSeedStore(
          secureStorage: secureStorage,
          dirs: UserVisibleDataDirectoryService(
            runtimeRootOverride: root.path,
            homeOverride: root.path,
          ),
        );
        expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
        expect(await store.loadSeed(otherCapsule), orderedEquals(otherSeed));
        expect(await source.exists(), isFalse);
        // A verified earlier write is reused, rather than requesting another write.
        expect(
          secureStorage.writtenKeys.where(
            (key) => key == 'hivra.seed.$capsuleHex',
          ),
          hasLength(1),
        );
      });
    }

    test('migration reuses an identical stored seed without a write', () async {
      await source.writeAsString(jsonEncode({capsuleHex: base64.encode(seed)}));
      secureStorage.values['hivra.seed.$capsuleHex'] = base64.encode(seed);

      expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
      expect(await source.exists(), isFalse);
      expect(secureStorage.writtenKeys, isEmpty);
    });

    test('an empty legacy map has no seed to migrate', () async {
      await source.writeAsString('{}');

      expect(await store.loadSeed(capsuleHex), isNull);
      expect(await source.exists(), isFalse);
      expect(secureStorage.writtenKeys, isEmpty);
    });

    test('different visible legacy copy is retained with the source', () async {
      final original = jsonEncode({capsuleHex: base64.encode(seed)});
      final other = jsonEncode({otherCapsule: base64.encode(otherSeed)});
      final visibleSource = File(
        '${root.path}/Documents/Hivra/capsules/capsule_seeds.json',
      );
      await source.writeAsString(original);
      await visibleSource.parent.create(recursive: true);
      await visibleSource.writeAsString(other);

      await expectLater(store.loadSeed(capsuleHex), throwsA(isA<StateError>()));

      expect(await source.readAsString(), original);
      expect(await visibleSource.readAsString(), other);
      expect(
        secureStorage.values['hivra.seed.$capsuleHex'],
        base64.encode(seed),
      );
      // Resolving the conflicting fixture permits the same migration to retry.
      await visibleSource.writeAsString(original);
      expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
      expect(await source.exists(), isFalse);
      expect(await visibleSource.exists(), isFalse);
      expect(secureStorage.writtenKeys, hasLength(1));
    });
  });

  test('caches loaded seed for the current process', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    secureStorage.values['hivra.seed.$capsuleHex'] = base64.encode(seed);
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );

    final first = await store.loadSeed(capsuleHex);
    final second = await store.loadSeed(capsuleHex);

    expect(first, orderedEquals(seed));
    expect(second, orderedEquals(seed));
    expect(secureStorage.readCounts['hivra.seed.$capsuleHex'], equals(1));
  });

  test('failed secure deletion preserves the retained seed', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    await store.storeSeed(capsuleHex, seed);
    secureStorage.failDelete = true;

    await expectLater(
      store.deleteSeed(capsuleHex),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Secure seed cleanup failed'),
        ),
      ),
    );

    expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
    expect(secureStorage.values['hivra.seed.$capsuleHex'], base64.encode(seed));
  });

  test('successful secure deletion clears storage and process cache', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    await store.storeSeed(capsuleHex, seed);

    await store.deleteSeed(capsuleHex);

    expect(secureStorage.values['hivra.seed.$capsuleHex'], isNull);
    expect(await store.loadSeed(capsuleHex), isNull);
  });

  test('deletes legacy seed copies while preserving other Capsules', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    await store.storeSeed(capsuleHex, seed);
    final otherCapsule = List<String>.filled(64, 'b').join();
    final fallbackFiles = <File>[
      File(
        '${tempHome.path}/Library/Application Support/Hivra/capsules/capsule_seeds.json',
      ),
      File('${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json'),
      File(
        '${tempHome.path}/Library/Containers/com.hivra.hivraApp/Data/Documents/capsules/capsule_seeds.json',
      ),
      File(
        '${tempHome.path}/Library/Containers/com.hivra.hivraApp/Data/Documents/Hivra/capsules/capsule_seeds.json',
      ),
    ];
    for (final file in fallbackFiles) {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, String>{
          capsuleHex.toUpperCase(): base64.encode(seed),
          otherCapsule: base64.encode(seed.reversed.toList()),
        }),
      );
    }

    await store.deleteSeed(capsuleHex);

    for (final file in fallbackFiles) {
      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted.keys, equals(<Object?>[otherCapsule]));
    }
  });

  test('malformed legacy seed file blocks deletion fail closed', () async {
    final tempHome = await Directory.systemTemp.createTemp('hivra-seed-test-');
    addTearDown(() => tempHome.delete(recursive: true));
    final secureStorage = _FakeSecureStorage();
    final store = CapsuleSeedStore(
      secureStorage: secureStorage,
      dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
    );
    await store.storeSeed(capsuleHex, seed);
    final fallbackFile = File(
      '${tempHome.path}/Library/Application Support/Hivra/capsules/capsule_seeds.json',
    );
    await fallbackFile.writeAsString('{malformed');

    await expectLater(
      store.deleteSeed(capsuleHex),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Legacy seed cleanup failed'),
        ),
      ),
    );

    expect(await fallbackFile.readAsString(), equals('{malformed'));
    expect(await store.loadSeed(capsuleHex), orderedEquals(seed));
  });
}
