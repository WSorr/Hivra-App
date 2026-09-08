import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_credential_store.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> deleteKeys = <String>[];

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
    writeKeys.add(key);
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
    readKeys.add(key);
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
    deleteKeys.add(key);
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

    test('canonical load reads secure storage without rewriting it', () async {
      const scope =
          'abababababababababababababababababababababababababababababababab';
      final secureStorage = _FakeSecureStorage();
      final writer = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
      );
      await writer.save(
        const BingxFuturesApiCredentials(
          apiKey: 'canonical-key',
          apiSecret: 'canonical-secret',
        ),
      );
      secureStorage.readKeys.clear();
      secureStorage.writeKeys.clear();
      secureStorage.deleteKeys.clear();

      final reader = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
      );
      final loaded = await reader.load();

      expect(loaded?.apiKey, 'canonical-key');
      expect(loaded?.apiSecret, 'canonical-secret');
      expect(secureStorage.readKeys, <String>[
        'hivra.bingx.futures.$scope.credentials',
      ]);
      expect(secureStorage.writeKeys, isEmpty);
      expect(secureStorage.deleteKeys, isEmpty);
    });

    test('legacy split keys migrate once and are then sealed', () async {
      const scope =
          'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';
      final secureStorage = _FakeSecureStorage();
      secureStorage.values['hivra.bingx.futures.$scope.api_key'] = 'legacy-key';
      secureStorage.values['hivra.bingx.futures.$scope.api_secret'] =
          'legacy-secret';
      final migratingStore = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
      );

      final migrated = await migratingStore.load();

      expect(migrated?.apiKey, 'legacy-key');
      expect(migrated?.apiSecret, 'legacy-secret');
      expect(
        secureStorage.values['hivra.bingx.futures.$scope.credentials'],
        isNotNull,
      );
      expect(
        secureStorage.values.containsKey('hivra.bingx.futures.$scope.api_key'),
        isFalse,
      );
      expect(
        secureStorage.values.containsKey(
          'hivra.bingx.futures.$scope.api_secret',
        ),
        isFalse,
      );

      secureStorage.readKeys.clear();
      secureStorage.writeKeys.clear();
      secureStorage.deleteKeys.clear();
      final restartedStore = BingxFuturesCredentialStore(
        readActiveCapsuleRootHex: () => scope,
        secureStorage: secureStorage,
      );
      final restarted = await restartedStore.load();

      expect(restarted?.apiKey, 'legacy-key');
      expect(secureStorage.readKeys, <String>[
        'hivra.bingx.futures.$scope.credentials',
      ]);
      expect(secureStorage.writeKeys, isEmpty);
      expect(secureStorage.deleteKeys, isEmpty);
    });

    test(
      'malformed canonical record fails closed without legacy fallback',
      () async {
        const scope =
            'efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef';
        final secureStorage = _FakeSecureStorage();
        secureStorage.values['hivra.bingx.futures.$scope.credentials'] = '{}';
        secureStorage.values['hivra.bingx.futures.$scope.api_key'] =
            'stale-key';
        secureStorage.values['hivra.bingx.futures.$scope.api_secret'] =
            'stale-secret';
        final store = BingxFuturesCredentialStore(
          readActiveCapsuleRootHex: () => scope,
          secureStorage: secureStorage,
        );

        await expectLater(store.load(), throwsA(isA<StateError>()));
        expect(secureStorage.readKeys, <String>[
          'hivra.bingx.futures.$scope.credentials',
        ]);
        expect(secureStorage.writeKeys, isEmpty);
      },
    );

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
