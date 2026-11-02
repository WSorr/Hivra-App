import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
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

class _ControlledPreferenceWrites extends AtomicFileWriteService {
  bool fail = false;
  @override
  Future<void> writeString(File target, String contents) async {
    if (fail) throw const FileSystemException('test write failure');
    await super.writeString(target, contents);
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

    test(
      'custom destination and model survive restart with independent secure keys',
      () async {
        final storage = _FakeSecureStorage();
        final store = buildStore(storage);
        await store.saveApiKey(InferenceConnection.gemini, 'existing-key');
        await store.savePreferredProvider(
          InferenceConnection.gemini,
          model: 'owner-existing-model',
        );
        final first = await store.addConnection(
          name: 'Owner endpoint',
          protocol: InferenceProtocol.chatCompletions,
          baseUrl: 'https://one.example/v1',
          model: 'owner-model',
          requiresApiKey: true,
        );
        final second = await store.addConnection(
          name: 'Owner endpoint',
          protocol: InferenceProtocol.responses,
          baseUrl: 'https://two.example/v1',
          model: 'next-model',
          requiresApiKey: true,
        );
        expect(first.id, isNot(second.id));
        expect(await store.hasApiKey(second), isFalse);
        await store.saveApiKey(first, 'first-key');
        await store.saveApiKey(second, 'second-key');
        await store.savePreferredProvider(first, model: 'updated-model');
        final restarted = buildStore(storage);
        storage.readCounts.clear();
        final saved = await restarted.loadConnections();
        final restored = saved.firstWhere((c) => c.id == first.id);
        expect(restored.protocol, InferenceProtocol.chatCompletions);
        expect(restored.baseUrl, 'https://one.example/v1');
        expect(await restarted.loadPreferredProvider(), restored);
        expect(await restarted.loadPreferredModel(restored), 'updated-model');
        expect(
          await restarted.loadPreferredModel(InferenceConnection.gemini),
          'owner-existing-model',
        );
        expect(
          storage.readCounts,
          isEmpty,
        ); // Configuration reads do not unlock keys.
        expect(restarted.isPreferredProviderUnlocked, isFalse);
        await restarted.unlockPreferredProviderSession();
        expect(restarted.sessionApiKey(restored), 'first-key');
        final root = await directories.rootDirectory();
        final json =
            await File(
              '${root.path}/ai_provider_preference.v1.json',
            ).readAsString();
        expect(json, contains('https://one.example/v1'));
        expect(json, isNot(contains('first-key')));
        await restarted.removeConnection(first.id);
        expect(restarted.isPreferredProviderUnlocked, isFalse);
        final finalStore = buildStore(storage);
        expect(
          (await finalStore.loadConnections()).any((c) => c.id == first.id),
          isFalse,
        );
        final other = finalStore.connections.firstWhere(
          (c) => c.id == second.id,
        );
        expect(await finalStore.loadApiKey(other), 'second-key');
        expect(
          await finalStore.loadApiKey(InferenceConnection.gemini),
          'existing-key',
        );
        expect(storage.values.values, isNot(contains('first-key')));
      },
    );

    test(
      'invalid custom configuration or failed write never installs a connection',
      () async {
        final storage = _FakeSecureStorage();
        final writes = _ControlledPreferenceWrites();
        final store = AiDoctorCredentialStore(
          secureStorage: storage,
          directories: directories,
          atomicWrites: writes,
        );
        for (final url in [
          'https://key:secret@example.com/v1',
          'file:///tmp/model',
          'https://example.com/v1?token=secret',
        ]) {
          await expectLater(
            store.addConnection(
              name: 'Bad',
              protocol: InferenceProtocol.responses,
              baseUrl: url,
              model: 'model',
              requiresApiKey: true,
            ),
            throwsArgumentError,
          );
        }
        writes.fail = true;
        await expectLater(
          store.addConnection(
            name: 'Failing',
            protocol: InferenceProtocol.responses,
            baseUrl: 'https://example.com/v1',
            model: 'model',
            requiresApiKey: true,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(store.connections, InferenceConnection.values);
        expect(storage.values, isEmpty);
      },
    );

    test('stores OpenAI key only in secure storage', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.saveApiKey(InferenceConnection.openAi, ' sk-test ');

      expect(await store.loadApiKey(InferenceConnection.openAi), 'sk-test');
      expect(await store.loadPreferredProvider(), InferenceConnection.openAi);
      expect(secureStorage.values, hasLength(1));
      expect(secureStorage.values.values.single, 'sk-test');
    });

    test('clears OpenAI key', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);
      await store.saveApiKey(InferenceConnection.openAi, 'sk-test');

      await store.clearApiKey(InferenceConnection.openAi);

      expect(await store.loadApiKey(InferenceConnection.openAi), isNull);
      expect(await store.loadPreferredProvider(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('stores provider keys independently', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.saveApiKey(InferenceConnection.openAi, 'sk-openai');
      await store.saveApiKey(InferenceConnection.gemini, 'gemini-key');
      await store.saveBaseUrl(
        InferenceConnection.localOpenAiCompatible,
        ' http://127.0.0.1:11434 ',
      );

      expect(await store.loadApiKey(InferenceConnection.openAi), 'sk-openai');
      expect(await store.loadApiKey(InferenceConnection.gemini), 'gemini-key');
      expect(
        await store.loadBaseUrl(InferenceConnection.localOpenAiCompatible),
        'http://127.0.0.1:11434',
      );
      expect(
        await store.loadPreferredProvider(),
        InferenceConnection.localOpenAiCompatible,
      );
      expect(secureStorage.values.length, 3);
    });

    test('stores explicit preferred provider outside secure storage', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);

      await store.savePreferredProvider(InferenceConnection.gemini);

      expect(await store.loadPreferredProvider(), InferenceConnection.gemini);
      expect(secureStorage.values, isEmpty);
    });

    test(
      'failed model save retains durable and in-memory selection, then retries',
      () async {
        final secrets = _FakeSecureStorage();
        final writes = _ControlledPreferenceWrites();
        final store = AiDoctorCredentialStore(
          secureStorage: secrets,
          directories: directories,
          atomicWrites: writes,
        );
        await store.savePreferredProvider(
          InferenceConnection.gemini,
          model: 'model-before',
        );
        writes.fail = true;
        await expectLater(
          store.savePreferredProvider(
            InferenceConnection.openAi,
            model: 'model-after',
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await store.loadPreferredProvider(), InferenceConnection.gemini);
        expect(
          await store.loadPreferredModel(InferenceConnection.gemini),
          'model-before',
        );
        final restarted = buildStore(secrets);
        expect(
          await restarted.loadPreferredProvider(),
          InferenceConnection.gemini,
        );
        expect(
          await restarted.loadPreferredModel(InferenceConnection.gemini),
          'model-before',
        );
        writes.fail = false;
        await store.savePreferredProvider(
          InferenceConnection.openAi,
          model: 'model-after',
        );
        expect(
          await store.loadPreferredModel(InferenceConnection.openAi),
          'model-after',
        );
      },
    );

    test(
      'rejects invalid model identifiers without changing existing preferences',
      () async {
        final store = buildStore(_FakeSecureStorage());
        await store.savePreferredProvider(
          InferenceConnection.gemini,
          model: 'retained-model',
        );
        for (final invalid in ['', 'a' * 257, 'bad\nmodel']) {
          expect(
            () => store.savePreferredProvider(
              InferenceConnection.openAi,
              model: invalid,
            ),
            throwsFormatException,
          );
        }
        expect(await store.loadPreferredProvider(), InferenceConnection.gemini);
        expect(
          await store.loadPreferredModel(InferenceConnection.gemini),
          'retained-model',
        );
      },
    );

    test(
      'per-provider models survive restart, switching and key replacement',
      () async {
        final secrets = _FakeSecureStorage();
        final store = buildStore(secrets);
        await store.saveApiKey(InferenceConnection.gemini, 'private-token');
        await store.savePreferredProvider(
          InferenceConnection.gemini,
          model: ' gemini-chosen ',
        );
        await store.savePreferredProvider(
          InferenceConnection.openAi,
          model: 'openai-chosen',
        );
        await store.saveApiKey(InferenceConnection.gemini, 'replacement-token');
        final restarted = buildStore(secrets);
        expect(
          await restarted.loadPreferredProvider(),
          InferenceConnection.gemini,
        );
        expect(
          await restarted.loadPreferredModel(InferenceConnection.gemini),
          'gemini-chosen',
        );
        expect(
          await restarted.loadPreferredModel(InferenceConnection.openAi),
          'openai-chosen',
        );
        expect(restarted.isPreferredProviderUnlocked, false);
        final root = await directories.rootDirectory();
        final content =
            await File(
              '${root.path}/ai_provider_preference.v1.json',
            ).readAsString();
        expect(content, isNot(contains('private-token')));
        expect(content, isNot(contains('replacement-token')));
        expect(secrets.values.keys.any((key) => key.contains('model')), false);
        await restarted.clearApiKey(InferenceConnection.gemini);
        final afterClear = buildStore(secrets);
        expect(await afterClear.loadPreferredProvider(), isNull);
        expect(
          await afterClear.loadPreferredModel(InferenceConnection.openAi),
          'openai-chosen',
        );
        expect(
          await afterClear.loadPreferredModel(InferenceConnection.gemini),
          InferenceConnection.gemini.defaultModel,
        );
      },
    );

    test('concurrent preference saves retain both model choices', () async {
      final store = buildStore(_FakeSecureStorage());
      await Future.wait([
        store.savePreferredProvider(
          InferenceConnection.gemini,
          model: 'model-a',
        ),
        store.savePreferredProvider(
          InferenceConnection.openAi,
          model: 'model-b',
        ),
      ]);
      final restarted = buildStore(_FakeSecureStorage());
      expect(
        await restarted.loadPreferredProvider(),
        InferenceConnection.openAi,
      );
      expect(
        await restarted.loadPreferredModel(InferenceConnection.gemini),
        'model-a',
      );
      expect(
        await restarted.loadPreferredModel(InferenceConnection.openAi),
        'model-b',
      );
    });

    test(
      'existing configuration without model remains readable without rewriting it',
      () async {
        final root = await directories.rootDirectory(create: true);
        final file = File('${root.path}/ai_provider_preference.v1.json');
        const original = '{"schema_version":1,"provider_id":"gemini"}';
        await file.writeAsString(original);
        final secrets = _FakeSecureStorage();
        final store = buildStore(secrets);
        expect(
          await store.loadPreferredModel(InferenceConnection.gemini),
          InferenceConnection.gemini.defaultModel,
        );
        expect(await file.readAsString(), original);
        expect(secrets.readCounts, isEmpty);
      },
    );

    test('invalid saved model fails closed before credential access', () async {
      final root = await directories.rootDirectory(create: true);
      final file = File('${root.path}/ai_provider_preference.v1.json');
      await file.writeAsString(
        jsonEncode({
          'schema_version': 1,
          'provider_id': 'gemini',
          'models': {'gemini': 'bad\nmodel'},
        }),
      );
      final secrets = _FakeSecureStorage();
      await expectLater(
        buildStore(secrets).unlockPreferredProviderSession(),
        throwsStateError,
      );
      expect(secrets.readCounts, isEmpty);
    });

    test(
      'Cloudflare account and token survive restart independently of Gemini',
      () async {
        const provider = InferenceConnection.cloudflareWorkersAi;
        const url =
            'https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/ai';
        final secureStorage = _FakeSecureStorage();
        final writer = buildStore(secureStorage);
        await writer.saveApiKey(InferenceConnection.gemini, 'gemini-key');
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
          await restarted.loadApiKey(InferenceConnection.gemini),
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
            InferenceConnection.cloudflareWorkersAi,
            'https://example.com',
          ),
          throwsArgumentError,
        );
        expect(secureStorage.values, isEmpty);
        expect(
          store.sessionBaseUrl(InferenceConnection.cloudflareWorkersAi),
          isNull,
        );
      },
    );

    test('unlocks provider once and reuses the in-memory session', () async {
      final secureStorage = _FakeSecureStorage();
      final writer = buildStore(secureStorage);
      await writer.saveApiKey(InferenceConnection.gemini, 'gemini-key');
      final restartedProcess = buildStore(secureStorage);
      secureStorage.readCounts.clear();

      final provider = await restartedProcess.unlockPreferredProviderSession();
      expect(provider, InferenceConnection.gemini);
      expect(restartedProcess.isPreferredProviderUnlocked, isTrue);
      expect(
        restartedProcess.sessionApiKey(InferenceConnection.gemini),
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
        await writer.saveApiKey(InferenceConnection.gemini, 'gemini-key');
        final restartedProcess = buildStore(secureStorage);
        secureStorage.readCounts.clear();

        expect(
          await restartedProcess.hasApiKey(InferenceConnection.gemini),
          isTrue,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);
        expect(
          restartedProcess.sessionApiKey(InferenceConnection.gemini),
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
        final first = store.hasApiKey(InferenceConnection.gemini);
        final second = store.hasApiKey(InferenceConnection.gemini);
        expect(storage.presenceChecks, 1);
        expect(storage.readCounts, isEmpty);
        pending.complete(true);
        expect(await first, true);
        expect(await second, true);
        expect(store.isPreferredProviderUnlocked, false);
        expect(store.sessionApiKey(InferenceConnection.gemini), isNull);
        storage.checkPresence = (_) async => false;
        expect(await store.hasApiKey(InferenceConnection.gemini), false);
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
          store.hasApiKey(InferenceConnection.gemini),
          throwsStateError,
        );
        storage.checkPresence = (_) async => true;
        expect(await store.hasApiKey(InferenceConnection.gemini), true);
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
        await store.saveApiKey(InferenceConnection.gemini, 'gemini-key');
        await store.saveApiKey(InferenceConnection.openAi, 'openai-key');
        await store.savePreferredProvider(InferenceConnection.gemini);

        await store.unlockProviderSession(InferenceConnection.openAi);

        expect(store.sessionPreferredProvider, InferenceConnection.openAi);
        expect(await store.loadPreferredProvider(), InferenceConnection.gemini);
        expect(secureStorage.values.values, contains('gemini-key'));
        expect(secureStorage.values.values, isNot(contains('gemini')));
      },
    );

    test('locking clears only the process session', () async {
      final secureStorage = _FakeSecureStorage();
      final store = buildStore(secureStorage);
      await store.saveApiKey(InferenceConnection.gemini, 'gemini-key');

      store.lockSession();

      expect(store.isPreferredProviderUnlocked, isFalse);
      expect(store.sessionPreferredProvider, isNull);
      expect(secureStorage.values.values, contains('gemini-key'));
      expect(
        await store.unlockPreferredProviderSession(),
        InferenceConnection.gemini,
      );
    });

    test(
      'restart keeps configuration locked until explicit unlock without key re-entry',
      () async {
        final secureStorage = _FakeSecureStorage();
        final firstProcess = buildStore(secureStorage);
        await firstProcess.saveApiKey(InferenceConnection.gemini, 'gemini-key');

        final restartedProcess = buildStore(secureStorage);

        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);
        expect(restartedProcess.sessionPreferredProvider, isNull);
        expect(
          await restartedProcess.loadPreferredProvider(),
          InferenceConnection.gemini,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isFalse);

        expect(
          await restartedProcess.unlockPreferredProviderSession(),
          InferenceConnection.gemini,
        );
        expect(restartedProcess.isPreferredProviderUnlocked, isTrue);
        expect(
          restartedProcess.sessionApiKey(InferenceConnection.gemini),
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
          InferenceConnection.gemini,
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
          InferenceConnection.gemini,
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
        store.saveApiKey(InferenceConnection.openAi, 'sk-test'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
