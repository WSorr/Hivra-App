import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hivra_secure_storage_options.dart';
import 'inference_provider_adapter.dart';

class AiDoctorCredentialStore {
  static const String _openAiApiKeyKey = 'hivra.ai_doctor.openai.api_key.v1';
  static const String _geminiApiKeyKey = 'hivra.ai_doctor.gemini.api_key.v1';

  final FlutterSecureStorage _secureStorage;
  final Map<InferenceProviderKind, String> _sessionApiKeys =
      <InferenceProviderKind, String>{};

  AiDoctorCredentialStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              mOptions: hivraMacOsSecureStorageOptions,
            );

  Future<void> saveApiKey(
    InferenceProviderKind provider,
    String apiKey,
  ) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('${provider.label} API key is empty');
    }
    final key = _keyForProvider(provider);
    try {
      final existing = await _secureStorage.read(key: key);
      if (existing == normalized) {
        _sessionApiKeys[provider] = normalized;
        return;
      }
      await _secureStorage.write(
        key: key,
        value: normalized,
      );
      final stored = await _secureStorage.read(key: key);
      if (stored != normalized) {
        throw StateError('Secure ${provider.label} key read-back mismatch');
      }
      _sessionApiKeys[provider] = normalized;
    } catch (error) {
      throw StateError('Secure AI credential storage is unavailable: $error');
    }
  }

  Future<String?> loadApiKey(InferenceProviderKind provider) async {
    final cached = _sessionApiKeys[provider];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final key = _keyForProvider(provider);
    try {
      final stored = await _secureStorage.read(key: key);
      final normalized = stored?.trim();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      _sessionApiKeys[provider] = normalized;
      return normalized;
    } catch (error) {
      throw StateError('Secure AI credential storage is unavailable: $error');
    }
  }

  Future<void> clearApiKey(InferenceProviderKind provider) async {
    _sessionApiKeys.remove(provider);
    final key = _keyForProvider(provider);
    try {
      await _secureStorage.delete(key: key);
    } catch (error) {
      throw StateError('Secure AI credential cleanup failed: $error');
    }
  }

  Future<void> saveOpenAiApiKey(String apiKey) {
    return saveApiKey(InferenceProviderKind.openAi, apiKey);
  }

  Future<String?> loadOpenAiApiKey() {
    return loadApiKey(InferenceProviderKind.openAi);
  }

  Future<void> clearOpenAiApiKey() {
    return clearApiKey(InferenceProviderKind.openAi);
  }

  static String _keyForProvider(InferenceProviderKind provider) {
    return switch (provider) {
      InferenceProviderKind.openAi => _openAiApiKeyKey,
      InferenceProviderKind.gemini => _geminiApiKeyKey,
    };
  }
}
