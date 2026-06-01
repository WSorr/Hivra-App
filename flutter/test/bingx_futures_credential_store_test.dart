import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_credential_store.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  _FakeSecureStorage();

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
      return;
    }
    values[key] = value;
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
    throw Exception('secure storage unavailable');
  }
}

class _FailingReadSecureStorage extends _FakeSecureStorage {
  bool failRead = false;

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
    if (failRead) {
      throw Exception('secure storage read unavailable');
    }
    return super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

void main() {
  group('BingxFuturesCredentialStore', () {
    test('loads global credentials and promotes to capsule scope', () async {
      String? activeScope;
      final secureStorage = _FakeSecureStorage();
      final store = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => activeScope,
        secureStorage: secureStorage,
      );
      await store.save(
        const BingxFuturesApiCredentials(
          apiKey: 'global-key',
          apiSecret: 'global-secret',
        ),
      );

      activeScope =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'global-key');
      expect(loaded.apiSecret, 'global-secret');
      expect(
        secureStorage.values
            .containsKey('hivra.bingx.futures.$activeScope.api_key'),
        isTrue,
      );
      expect(
        secureStorage.values
            .containsKey('hivra.bingx.futures.$activeScope.api_secret'),
        isTrue,
      );
    });

    test('mirrors capsule save to global fallback scope', () async {
      String? activeScope =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final secureStorage = _FakeSecureStorage();
      final store = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => activeScope,
        secureStorage: secureStorage,
      );
      await store.save(
        const BingxFuturesApiCredentials(
          apiKey: 'capsule-key',
          apiSecret: 'capsule-secret',
        ),
      );

      activeScope = null;
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'capsule-key');
      expect(loaded.apiSecret, 'capsule-secret');
      expect(
        secureStorage.values.containsKey('hivra.bingx.futures.global.api_key'),
        isTrue,
      );
      expect(
        secureStorage.values
            .containsKey('hivra.bingx.futures.global.api_secret'),
        isTrue,
      );
    });

    test('falls back to file storage when secure storage is unavailable',
        () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-cred-store-test-');
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      final scope =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final store = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: _ThrowingSecureStorage(),
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );

      await store.save(
        const BingxFuturesApiCredentials(
          apiKey: 'fallback-key',
          apiSecret: 'fallback-secret',
        ),
      );
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'fallback-key');
      expect(loaded.apiSecret, 'fallback-secret');
    });

    test('loads from fallback when secure read fails after prior save', () async {
      final tempHome =
          await Directory.systemTemp.createTemp('hivra-cred-store-test-');
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      final scope =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final secureStorage = _FailingReadSecureStorage();
      final store = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );

      await store.save(
        const BingxFuturesApiCredentials(
          apiKey: 'durable-key',
          apiSecret: 'durable-secret',
        ),
      );
      secureStorage.failRead = true;

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'durable-key');
      expect(loaded.apiSecret, 'durable-secret');
    });
  });
}
