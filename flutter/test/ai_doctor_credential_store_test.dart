import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_credential_store.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

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
}

void main() {
  group('AiDoctorCredentialStore', () {
    test('stores OpenAI key only in secure storage', () async {
      final secureStorage = _FakeSecureStorage();
      final store = AiDoctorCredentialStore(secureStorage: secureStorage);

      await store.saveOpenAiApiKey(' sk-test ');

      expect(await store.loadOpenAiApiKey(), 'sk-test');
      expect(secureStorage.values.length, 1);
      expect(secureStorage.values.values.single, 'sk-test');
    });

    test('clears OpenAI key', () async {
      final secureStorage = _FakeSecureStorage();
      final store = AiDoctorCredentialStore(secureStorage: secureStorage);
      await store.saveOpenAiApiKey('sk-test');

      await store.clearOpenAiApiKey();

      expect(await store.loadOpenAiApiKey(), isNull);
      expect(secureStorage.values, isEmpty);
    });

    test('stores provider keys independently', () async {
      final secureStorage = _FakeSecureStorage();
      final store = AiDoctorCredentialStore(secureStorage: secureStorage);

      await store.saveApiKey(InferenceProviderKind.openAi, 'sk-openai');
      await store.saveApiKey(InferenceProviderKind.gemini, 'gemini-key');
      await store.saveBaseUrl(
        InferenceProviderKind.localOpenAiCompatible,
        ' http://127.0.0.1:11434 ',
      );

      expect(
        await store.loadApiKey(InferenceProviderKind.openAi),
        'sk-openai',
      );
      expect(
        await store.loadApiKey(InferenceProviderKind.gemini),
        'gemini-key',
      );
      expect(
        await store.loadBaseUrl(InferenceProviderKind.localOpenAiCompatible),
        'http://127.0.0.1:11434',
      );
      expect(secureStorage.values.length, 3);
    });

    test('fails closed when secure storage is unavailable', () async {
      final store = AiDoctorCredentialStore(
        secureStorage: _ThrowingSecureStorage(),
      );

      await expectLater(
        store.saveOpenAiApiKey('sk-test'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
