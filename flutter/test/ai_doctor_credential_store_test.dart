import 'dart:io';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final Map<String, int> readCounts = <String, int>{};
  int presenceChecks = 0;
  Future<bool> Function(String)? checkPresence;

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    presenceChecks++;
    return checkPresence?.call(key) ?? Future.value(values.containsKey(key));
  }

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
    readCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
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
}

void main() {
  group('AiDoctorCredentialStore', () {
    late Directory tempHome;
    late UserVisibleDataDirectoryService directories;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-ai-credentials-');
      directories = UserVisibleDataDirectoryService(
        homeOverride: tempHome.path,
      );
    });

    tearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    AiDoctorCredentialStore buildStore(FlutterSecureStorage secureStorage) {
      return AiDoctorCredentialStore(
        secureStorage: secureStorage,
        directories: directories,
      );
    }

    test('stores OpenAI key only in secure storage', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.saveOpenAiApiKey(' sk-test ');

      expect(await store.loadOpenAiApiKey(), 'sk-test');
      expect(await store.loadPreferredProvider(), InferenceProviderKind.openAi);
      expect(secureStorage.values, hasLength(1));
      expect(secureStorage.values.values.single, 'sk-test');
    });

    test('clears OpenAI key', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);
      await store.saveOpenAiApiKey('sk-test');

      await store.clearOpenAiApiKey();

      expect(await store.loadOpenAiApiKey(), isNull);
      expect(await store.loadPreferredProvider(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('stores provider keys independently', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.saveApiKey(InferenceProviderKind.openAi, 'sk-openai');
      await store.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
      await store.saveBaseUrl(
        InferenceProviderKind.localOpenAiCompatible,
        ' http://127.0.0.1:11434 ',
      );

      expect(await store.loadApiKey(InferenceProviderKind.openAi), 'sk-openai');
      expect(
        await store.loadApiKey(InferenceProviderKind.gemini),
        'gemini-key',
      );
      expect(
        await store.loadBaseUrl(InferenceProviderKind.localOpenAiCompatible),
        'http://127.0.0.1:11434',
      );
      expect(
        await store.loadPreferredProvider(),
        InferenceProviderKind.localOpenAiCompatible,
      );
      expect(secureStorage.values.length, 3);
    });

    test('stores explicit preferred provider outside secure storage', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.savePreferredProvider(InferenceProviderKind.gemini);

      expect(await store.loadPreferredProvider(), InferenceProviderKind.gemini);
      expect(secureStorage.values, isEmpty);
    });

    test(
      'Cloudflare account and token survive restart independently of Gemini',
      () async {
        const provider = InferenceProviderKind.cloudflareWorkersAi;
        const url =
            'https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/ai';
        final secureStorage = _FakeSecureStorage();
        final writer = buildStore(secureStorage);
        await writer.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
        await writer.saveApiKey(provider, 'cloudflare-test-token');
        expect(writer.isPreferredProviderUnlocked, isFalse);
        await expectLater(
          writer.unlockPreferredProviderSession(),
          throwsStateError,
        );
        await writer.saveBaseUrl(provider, url);
        writer.lockSession();

        final restarted = buildStore(secureStorage);
        expect(await restarted.loadPreferredProvider(), provider);
        expect(restarted.isPreferredProviderUnlocked, isFalse);
        await restarted.unlockPreferredProviderSession();
        expect(restarted.sessionApiKey(provider), 'cloudflare-test-token');
        expect(restarted.sessionBaseUrl(provider), url);
        expect(restarted.isPreferredProviderUnlocked, isTrue);
        final preferenceRoot = await directories.rootDirectory();
        final preference =
            await File(
              '${preferenceRoot.path}/ai_provider_preference.v1.json',
            ).readAsString();
        expect(preference, contains('cloudflare_workers_ai'));
        expect(preference, isNot(contains('cloudflare-test-token')));
        expect(preference, isNot(contains(url)));
        restarted.lockSession();
        expect(restarted.sessionApiKey(provider), isNull);
        expect(restarted.sessionBaseUrl(provider), isNull);

        await restarted.clearApiKey(provider);
        await restarted.clearBaseUrl(provider);
        expect(await restarted.loadApiKey(provider), isNull);
        expect(await restarted.loadBaseUrl(provider), isNull);
        expect(
          await restarted.loadApiKey(InferenceProviderKind.gemini),
          'gemini-key',
        );
        final root = await directories.rootDirectory();
        final config =
            await File('${root.path}/ai_provider_preference.v1.json').exists();
        expect(config, isFalse);
      },
    );

    test(
      'Cloudflare rejects credential destinations outside its pinned account endpoint',
      () async {
        final secureStorage = _FakeSecureStorage();
        final store = buildStore(secureStorage);
        await expectLater(
          store.saveBaseUrl(
            InferenceProviderKind.cloudflareWorkersAi,
            'https://example.com',
          ),
          throwsArgumentError,
        );
        expect(secureStorage.values, isEmpty);
        expect(
          store.sessionBaseUrl(InferenceProviderKind.cloudflareWorkersAi),
          isNull,
        );
      },
    );

    test('unlocks provider once and reuses the in-memory session', () async {
      final secureStorage = _FakeSecureStorage();
      final writer = buildStore(secureStorage);
      await writer.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
      final restartedProcess = buildStore(secureStorage);
      secureStorage.readCounts.clear();

      final provider = await restartedProcess.unlockPreferredProviderSession();
      expect(provider, InferenceProviderKind.gemini);
      expect(restartedProcess.isPreferredProviderUnlocked, isTrue);
      expect(
        restartedProcess.sessionApiKey(InferenceProviderKind.gemini),
        'gemini-key',
      );
      expect(secureStorage.readCounts.values.fold(0, (a, b) => a + b), 1);

      await restartedProcess.unlockPreferredProviderSession();
      expect(secureStorage.readCounts.values.fold(0, (a, b) => a + b), 1);
    });

    test(
      'reports key presence without unlocking the provider session',
      () async {
        final secureStorage = _FakeSecureStorage();
        final writer = buildStore(secureStorage);
        await writer.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
        final restartedProcess = buildStore(secureStorage);
        secureStorage.readCounts.clear();

        expect(
          await restartedProcess.hasApiKey(InferenceProviderKind.gemini),
          isTrue,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);
        expect(
          restartedProcess.sessionApiKey(InferenceProviderKind.gemini),
          isNull,
        );
        expect(secureStorage.readCounts.values.fold(0, (a, b) => a + b), 0);
        expect(secureStorage.presenceChecks, 1);
      },
    );

    test(
      'presence checks share only pending metadata lookups and remain locked',
      () async {
        final storage = _FakeSecureStorage();
        final store = buildStore(storage);
        final pending = Completer<bool>();
        storage.checkPresence = (_) => pending.future;
        final first = store.hasApiKey(InferenceProviderKind.gemini);
        final second = store.hasApiKey(InferenceProviderKind.gemini);
        expect(storage.presenceChecks, 1);
        expect(storage.readCounts, isEmpty);
        pending.complete(true);
        expect(await first, true);
        expect(await second, true);
        expect(store.isPreferredProviderUnlocked, false);
        expect(store.sessionApiKey(InferenceProviderKind.gemini), isNull);
        storage.checkPresence = (_) async => false;
        expect(await store.hasApiKey(InferenceProviderKind.gemini), false);
        expect(storage.presenceChecks, 2);
        expect(storage.readCounts, isEmpty);
      },
    );

    test(
      'failed metadata lookup can retry without reading a credential',
      () async {
        final storage = _FakeSecureStorage();
        final store = buildStore(storage);
        storage.checkPresence = (_) async => throw StateError('denied');
        await expectLater(
          store.hasApiKey(InferenceProviderKind.gemini),
          throwsStateError,
        );
        storage.checkPresence = (_) async => true;
        expect(await store.hasApiKey(InferenceProviderKind.gemini), true);
        expect(storage.presenceChecks, 2);
        expect(storage.readCounts, isEmpty);
        expect(store.isPreferredProviderUnlocked, false);
      },
    );

    test(
      'explicit session unlock does not rewrite preferred provider',
      () async {
        final secureStorage = _FakeSecureStorage();
        final store = buildStore(secureStorage);
        await store.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
        await store.saveApiKey(InferenceProviderKind.openAi, 'openai-key');
        await store.savePreferredProvider(InferenceProviderKind.gemini);

        await store.unlockProviderSession(InferenceProviderKind.openAi);

        expect(store.sessionPreferredProvider, InferenceProviderKind.openAi);
        expect(
          await store.loadPreferredProvider(),
          InferenceProviderKind.gemini,
        );
        expect(secureStorage.values.values, contains('gemini-key'));
        expect(secureStorage.values.values, isNot(contains('gemini')));
      },
    );

    test('locking clears only the process session', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);
      await store.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');

      store.lockSession();

      expect(store.isPreferredProviderUnlocked, isFalse);
      expect(store.sessionPreferredProvider, isNull);
      expect(secureStorage.values.values, contains('gemini-key'));
      expect(
        await store.unlockPreferredProviderSession(),
        InferenceProviderKind.gemini,
      );
    });

    test(
      'restart keeps configuration locked until explicit unlock without key re-entry',
      () async {
        final secureStorage = _FakeSecureStorage();
        final firstProcess = buildStore(secureStorage);
        await firstProcess.saveApiKey(
          InferenceProviderKind.gemini,
          'gemini-key',
        );

        final restartedProcess = buildStore(secureStorage);

        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);
        expect(restartedProcess.sessionPreferredProvider, isNull);
        expect(
          await restartedProcess.loadPreferredProvider(),
          InferenceProviderKind.gemini,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);

        expect(
          await restartedProcess.unlockPreferredProviderSession(),
          InferenceProviderKind.gemini,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isTrue);
        expect(
          restartedProcess.sessionApiKey(InferenceProviderKind.gemini),
          'gemini-key',
        );
      },
    );

    test(
      'migrates legacy secure preference without moving key material',
      () async {
        final secureStorage = _FakeSecureStorage();
        secureStorage.values['hivra.ai_doctor.preferred_provider.v1'] =
            'gemini';
        secureStorage.values['hivra.ai_doctor.gemini.api_key.v1'] =
            'gemini-key';

        final migratingProcess = buildStore(secureStorage);
        expect(
          await migratingProcess.unlockPreferredProviderSession(),
          InferenceProviderKind.gemini,
        );
        expect(secureStorage.readCounts.values.fold(0, (a, b) => a + b), 2);
        expect(
          secureStorage.values['hivra.ai_doctor.gemini.api_key.v1'],
          'gemini-key',
        );
        expect(
          secureStorage.values,
          isNot(contains('hivra.ai_doctor.preferred_provider.v1')),
        );

        final restartedProcess = buildStore(secureStorage);
        secureStorage.readCounts.clear();
        expect(
          await restartedProcess.unlockPreferredProviderSession(),
          InferenceProviderKind.gemini,
        );
        expect(secureStorage.readCounts.values.fold(0, (a, b) => a + b), 1);
      },
    );

    test('malformed local provider preference fails closed', () async {
      final root = await directories.rootDirectory(create: true);
      await File(
        '${root.path}/ai_provider_preference.v1.json',
      ).writeAsString('{"schema_version":1,"provider_id":"unknown"}');
      final secureStorage = _FakeSecureStorage();
      secureStorage.values['hivra.ai_doctor.gemini.api_key.v1'] = 'gemini-key';

      await expectLater(
        buildStore(secureStorage).unlockPreferredProviderSession(),
        throwsA(isA<StateError>()),
      );
      expect(secureStorage.readCounts, isEmpty);
    });

    test('fails closed when secure storage is unavailable', () async {
      final store = buildStore(_ThrowingSecureStorage());

      await expectLater(
        store.saveOpenAiApiKey('sk-test'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
