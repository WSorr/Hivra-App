import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'atomic_file_write_service.dart';
import 'hivra_secure_storage_options.dart';
import 'inference_provider_adapter.dart';
import 'user_visible_data_directory_service.dart';

class AiDoctorCredentialStore {
  static final AiDoctorCredentialStore shared = AiDoctorCredentialStore();

  static const String _openAiApiKeyKey = 'hivra.ai_doctor.openai.api_key.v1';
  static const String _geminiApiKeyKey = 'hivra.ai_doctor.gemini.api_key.v1';
  static const String _localOpenAiApiKeyKey =
      'hivra.ai_doctor.local_openai.api_key.v1';
  static const String _localOpenAiBaseUrlKey =
      'hivra.ai_doctor.local_openai.base_url.v1';
  static const String _preferredProviderKey =
      'hivra.ai_doctor.preferred_provider.v1';
  static const String _preferredProviderFileName =
      'ai_provider_preference.v1.json';

  final FlutterSecureStorage _secureStorage;
  final UserVisibleDataDirectoryService _directories;
  final AtomicFileWriteService _atomicWrites;
  final Map<InferenceProviderKind, String> _sessionApiKeys =
      <InferenceProviderKind, String>{};
  final Map<InferenceProviderKind, String> _sessionBaseUrls =
      <InferenceProviderKind, String>{};
  InferenceProviderKind? _cachedPreferredProvider;
  InferenceProviderKind? _sessionPreferredProvider;

  AiDoctorCredentialStore({
    FlutterSecureStorage? secureStorage,
    UserVisibleDataDirectoryService directories =
        const UserVisibleDataDirectoryService(),
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(mOptions: hivraMacOsSecureStorageOptions),
       _directories = directories,
       _atomicWrites = atomicWrites;

  Future<void> saveApiKey(InferenceProviderKind provider, String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('${provider.label} API key is empty');
    }
    final key = _keyForProvider(provider);
    try {
      final existing = await _secureStorage.read(key: key);
      if (existing == normalized) {
        _sessionApiKeys[provider] = normalized;
        await savePreferredProvider(provider);
        return;
      }
      await _secureStorage.write(key: key, value: normalized);
      final stored = await _secureStorage.read(key: key);
      if (stored != normalized) {
        throw StateError('Secure ${provider.label} key read-back mismatch');
      }
      _sessionApiKeys[provider] = normalized;
      await savePreferredProvider(provider);
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
      await _clearPreferredProviderIf(provider);
    } catch (error) {
      throw StateError('Secure AI credential cleanup failed: $error');
    }
  }

  Future<void> saveBaseUrl(
    InferenceProviderKind provider,
    String baseUrl,
  ) async {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('${provider.label} base URL is empty');
    }
    final key = _baseUrlKeyForProvider(provider);
    if (key == null) {
      throw ArgumentError('${provider.label} does not support base URL');
    }
    try {
      await _secureStorage.write(key: key, value: normalized);
      final stored = await _secureStorage.read(key: key);
      if (stored != normalized) {
        throw StateError('${provider.label} base URL read-back mismatch');
      }
      _sessionBaseUrls[provider] = normalized;
      await savePreferredProvider(provider);
    } catch (error) {
      throw StateError('Secure AI endpoint storage is unavailable: $error');
    }
  }

  Future<void> savePreferredProvider(InferenceProviderKind provider) async {
    try {
      final file = await _preferredProviderFile(createRoot: true);
      await _atomicWrites.writeString(
        file,
        jsonEncode(<String, Object>{
          'schema_version': 1,
          'provider_id': provider.id,
        }),
      );
      _cachedPreferredProvider = provider;
      _sessionPreferredProvider = provider;
    } catch (error) {
      throw StateError('AI provider preference storage failed: $error');
    }
  }

  Future<InferenceProviderKind?> loadPreferredProvider() async {
    final cached = _cachedPreferredProvider;
    if (cached != null) return cached;
    try {
      final file = await _preferredProviderFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map || decoded['schema_version'] != 1) {
          throw const FormatException('Invalid AI provider preference');
        }
        return _cachePreferredProvider(decoded['provider_id']);
      }
      return _migrateLegacyPreferredProvider();
    } catch (error) {
      throw StateError('AI provider preference load failed: $error');
    }
  }

  Future<String?> loadBaseUrl(InferenceProviderKind provider) async {
    final cached = _sessionBaseUrls[provider];
    if (cached != null && cached.isNotEmpty) return cached;
    final key = _baseUrlKeyForProvider(provider);
    if (key == null) return null;
    try {
      final stored = await _secureStorage.read(key: key);
      final normalized = stored?.trim();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      _sessionBaseUrls[provider] = normalized;
      return normalized;
    } catch (error) {
      throw StateError('Secure AI endpoint storage is unavailable: $error');
    }
  }

  Future<void> clearBaseUrl(InferenceProviderKind provider) async {
    _sessionBaseUrls.remove(provider);
    final key = _baseUrlKeyForProvider(provider);
    if (key == null) return;
    try {
      await _secureStorage.delete(key: key);
      await _clearPreferredProviderIf(provider);
    } catch (error) {
      throw StateError('Secure AI endpoint cleanup failed: $error');
    }
  }

  Future<void> _clearPreferredProviderIf(InferenceProviderKind provider) async {
    final preferred = await loadPreferredProvider();
    if (preferred != provider) return;
    final file = await _preferredProviderFile();
    if (await file.exists()) await file.delete();
    await _secureStorage.delete(key: _preferredProviderKey);
    _cachedPreferredProvider = null;
    if (_sessionPreferredProvider == provider) {
      _sessionPreferredProvider = null;
    }
  }

  InferenceProviderKind? get sessionPreferredProvider =>
      _sessionPreferredProvider;

  String? sessionApiKey(InferenceProviderKind provider) =>
      _sessionApiKeys[provider];

  String? sessionBaseUrl(InferenceProviderKind provider) =>
      _sessionBaseUrls[provider];

  bool get isPreferredProviderUnlocked {
    final provider = _sessionPreferredProvider;
    if (provider == null) return false;
    if (provider.requiresApiKey &&
        (_sessionApiKeys[provider]?.isNotEmpty != true)) {
      return false;
    }
    if (provider == InferenceProviderKind.localOpenAiCompatible &&
        (_sessionBaseUrls[provider]?.isNotEmpty != true)) {
      return false;
    }
    return true;
  }

  Future<InferenceProviderKind> unlockPreferredProviderSession() async {
    final provider =
        await loadPreferredProvider() ?? InferenceProviderKind.gemini;
    return unlockProviderSession(provider);
  }

  Future<InferenceProviderKind> unlockProviderSession(
    InferenceProviderKind provider,
  ) async {
    final apiKey = await loadApiKey(provider);
    if (provider.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        '${provider.label} API key is not saved. Configure it in Capsule Analyst.',
      );
    }
    final baseUrl = await loadBaseUrl(provider);
    if (provider == InferenceProviderKind.localOpenAiCompatible &&
        (baseUrl == null || baseUrl.isEmpty)) {
      throw StateError(
        '${provider.label} base URL is not saved. Configure it in Capsule Analyst.',
      );
    }
    _sessionPreferredProvider = provider;
    return provider;
  }

  void lockSession() {
    _sessionApiKeys.clear();
    _sessionBaseUrls.clear();
    _sessionPreferredProvider = null;
  }

  Future<InferenceProviderKind?> _migrateLegacyPreferredProvider() async {
    final legacy = await _secureStorage.read(key: _preferredProviderKey);
    final provider = _providerForId(legacy);
    if (provider == null) return null;
    await savePreferredProvider(provider);
    await _secureStorage.delete(key: _preferredProviderKey);
    return provider;
  }

  InferenceProviderKind? _cachePreferredProvider(Object? providerId) {
    final provider = _providerForId(providerId);
    if (provider == null) {
      throw const FormatException('Unknown AI provider preference');
    }
    _cachedPreferredProvider = provider;
    return provider;
  }

  static InferenceProviderKind? _providerForId(Object? providerId) {
    final normalized = providerId is String ? providerId.trim() : '';
    for (final provider in InferenceProviderKind.values) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  Future<File> _preferredProviderFile({bool createRoot = false}) async {
    final root = await _directories.rootDirectory(create: createRoot);
    return File('${root.path}/$_preferredProviderFileName');
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
      InferenceProviderKind.localOpenAiCompatible => _localOpenAiApiKeyKey,
    };
  }

  static String? _baseUrlKeyForProvider(InferenceProviderKind provider) {
    return switch (provider) {
      InferenceProviderKind.openAi => null,
      InferenceProviderKind.gemini => null,
      InferenceProviderKind.localOpenAiCompatible => _localOpenAiBaseUrlKey,
    };
  }
}
