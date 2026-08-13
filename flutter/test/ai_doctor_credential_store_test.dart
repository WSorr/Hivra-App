import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';
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
