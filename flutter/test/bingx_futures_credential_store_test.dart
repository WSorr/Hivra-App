import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_credential_store.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
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

void main() {
  group('BingxFuturesCredentialStore', () {
    test(
      'does not fallback to global credentials for non-global scope',
      () async {
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

        expect(loaded, isNull);
        expect(
          secureStorage.values.containsKey(
            'hivra.bingx.futures.$activeScope.credentials',
          ),
          isFalse,
        );
        expect(
          secureStorage.values.containsKey(
            'hivra.bingx.futures.global.credentials',
          ),
          isTrue,
        );
      },
    );

    test(
      'loads global credentials when no active capsule is selected',
      () async {
        String? activeScope;
        final secureStorage = _FakeSecureStorage();
        final store = BingxFuturesCredentialStore(
          readActiveCapsuleRootHex: () => activeScope,
          secureStorage: secureStorage,
        );
        await store.save(
          const BingxFuturesApiCredentials(
            apiKey: 'global-only-key',
            apiSecret: 'global-only-secret',
          ),
        );

        activeScope = null;
        final loaded = await store.load();

        expect(loaded, isNotNull);
        expect(loaded!.apiKey, 'global-only-key');
        expect(loaded.apiSecret, 'global-only-secret');
      },
    );

    test('does not mirror capsule save to global fallback scope', () async {
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
      expect(loaded, isNull);
      expect(
        secureStorage.values.containsKey(
          'hivra.bingx.futures.global.credentials',
        ),
        isFalse,
      );
    });

    test('fails closed when secure storage is unavailable', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-cred-store-test-',
      );
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

      await expectLater(
        store.save(
          const BingxFuturesApiCredentials(
            apiKey: 'fallback-key',
            apiSecret: 'fallback-secret',
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        File(
          '${tempHome.path}/Documents/Hivra/bingx_futures_credentials.json',
        ).existsSync(),
        isFalse,
      );
    });

    test('migrates legacy plaintext credentials into secure storage', () async {
      final tempHome = await Directory.systemTemp.createTemp(
        'hivra-cred-store-test-',
      );
      addTearDown(() async {
        if (await tempHome.exists()) {
          await tempHome.delete(recursive: true);
        }
      });

      final scope =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final fallbackFile = File(
        '${tempHome.path}/Documents/Hivra/bingx_futures_credentials.json',
      );
      await fallbackFile.parent.create(recursive: true);
      await fallbackFile.writeAsString(
        '{"$scope":{"api_key":"durable-key","api_secret":"durable-secret"}}',
      );
      final secureStorage = _FakeSecureStorage();
      final store = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
        dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
      );

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'durable-key');
      expect(loaded.apiSecret, 'durable-secret');
      final secureCredentials =
          jsonDecode(
                secureStorage.values['hivra.bingx.futures.$scope.credentials']!,
              )
              as Map<String, dynamic>;
      expect(secureCredentials['api_key'], 'durable-key');
      expect(secureCredentials['api_secret'], 'durable-secret');
      expect(await fallbackFile.exists(), isFalse);
    });
  });
}
