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

    expect(
      secureStorage.values['hivra.seed.$capsuleHex'],
      base64.encode(seed),
    );
    expect(
      File('${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json')
          .existsSync(),
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
      File('${tempHome.path}/Documents/Hivra/capsules/capsule_seeds.json')
          .existsSync(),
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
    expect(
      secureStorage.values['hivra.seed.$capsuleHex'],
      base64.encode(seed),
    );
    expect(await fallbackFile.exists(), isFalse);
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
}
