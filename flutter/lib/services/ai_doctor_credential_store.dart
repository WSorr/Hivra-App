import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hivra_secure_storage_options.dart';

class AiDoctorCredentialStore {
  static const String _openAiApiKeyKey = 'hivra.ai_doctor.openai.api_key.v1';

  final FlutterSecureStorage _secureStorage;
  String? _sessionApiKey;

  AiDoctorCredentialStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              mOptions: hivraMacOsSecureStorageOptions,
            );

  Future<void> saveOpenAiApiKey(String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('OpenAI API key is empty');
    }
    try {
      await _secureStorage.write(
        key: _openAiApiKeyKey,
        value: normalized,
      );
      final stored = await _secureStorage.read(key: _openAiApiKeyKey);
      if (stored != normalized) {
        throw StateError('Secure AI key read-back mismatch');
      }
      _sessionApiKey = normalized;
    } catch (error) {
      throw StateError('Secure AI credential storage is unavailable: $error');
    }
  }

  Future<String?> loadOpenAiApiKey() async {
    final cached = _sessionApiKey;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final stored = await _secureStorage.read(key: _openAiApiKeyKey);
      final normalized = stored?.trim();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      _sessionApiKey = normalized;
      return normalized;
    } catch (error) {
      throw StateError('Secure AI credential storage is unavailable: $error');
    }
  }

  Future<void> clearOpenAiApiKey() async {
    _sessionApiKey = null;
    try {
      await _secureStorage.delete(key: _openAiApiKeyKey);
    } catch (error) {
      throw StateError('Secure AI credential cleanup failed: $error');
    }
  }
}
