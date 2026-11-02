import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'atomic_file_write_service.dart';
import 'hivra_secure_storage_options.dart';
import 'inference_provider_adapter.dart';
import 'user_visible_data_directory_service.dart';

class AiDoctorCredentialStore {
  static final AiDoctorCredentialStore shared = AiDoctorCredentialStore();

  static const String _openAiApiKeyKey = 'hivra.ai_doctor.openai.api_key.v1';
  static const String _geminiApiKeyKey = 'hivra.ai_doctor.gemini.api_key.v1';
  static const String _cloudflareApiKeyKey =
      'hivra.ai_doctor.cloudflare.api_key.v1';
  static const String _cloudflareBaseUrlKey =
      'hivra.ai_doctor.cloudflare.base_url.v1';
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
  final Map<InferenceConnection, String> _sessionApiKeys =
      <InferenceConnection, String>{};
  final Map<InferenceConnection, String> _sessionBaseUrls =
      <InferenceConnection, String>{};
  final Map<InferenceConnection, Future<bool>> _presenceChecks = {};
  InferenceConnection? _cachedPreferredProvider;
  InferenceConnection? _sessionPreferredProvider;
  final Map<InferenceConnection, String> _preferredModels = {};
  final Map<String, InferenceConnection> _connections = {};
  bool _preferencesLoaded = false;
  Future<void> _preferenceWrites = Future<void>.value();

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

  List<InferenceConnection> get connections => [
    ...InferenceConnection.values,
    ..._connections.values,
  ];

  Future<List<InferenceConnection>> loadConnections() async {
    await loadPreferredProvider();
    return connections;
  }

  Future<InferenceConnection> addConnection({
    required String name,
    required InferenceProtocol protocol,
    required String baseUrl,
    required String model,
    required bool requiresApiKey,
  }) async {
    final label = name.trim();
    if (label.isEmpty ||
        label.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label)) {
      throw ArgumentError('Connection name must contain 1..80 characters');
    }
    final endpoint = InferenceConnection.validateBaseUrl(baseUrl).toString();
    final normalizedModel = _validateModel(model);
    final random = Random.secure();
    final suffix =
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    final id = 'connection_$suffix';
    final connection = InferenceConnection(
      id: id,
      label: label,
      protocol: protocol,
      baseUrl: endpoint,
      defaultModel: normalizedModel,
      requiresApiKey: requiresApiKey,
    );
    await _serializePreferences(() async {
      await _loadPreferences();
      _connections[id] = connection;
      try {
        await _writePreferences(connection, _preferredModels);
      } catch (_) {
        _connections.remove(id);
        rethrow;
      }
    });
    return connection;
  }

  Future<void> removeConnection(String id) async {
    await loadPreferredProvider();
    final connection = _connections[id];
    if (connection == null) {
      throw ArgumentError('Custom AI connection is not saved');
    }
    // Invalidate a queued/unlocked lease before any awaited storage operation.
    if (_sessionPreferredProvider == connection) lockSession();
    await clearApiKey(connection);
    await _serializePreferences(() async {
      _connections.remove(id);
      try {
        await _writePreferences(_cachedPreferredProvider, _preferredModels);
      } catch (_) {
        _connections[id] = connection;
        rethrow;
      }
    });
  }

  Future<void> saveApiKey(InferenceConnection provider, String apiKey) async {
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
      throw _secureCredentialStorageError(error);
    }
  }

  Future<String?> loadApiKey(InferenceConnection provider) async {
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
      throw _secureCredentialStorageError(error);
    }
  }

  Future<bool> hasApiKey(InferenceConnection provider) {
    final cached = _sessionApiKeys[provider];
    if (cached != null && cached.isNotEmpty) return Future.value(true);
    return _presenceChecks.putIfAbsent(provider, () async {
      try {
        // Metadata lookup only. The native Darwin implementation explicitly
        // disables kSecReturnData; status must not read or unlock the secret.
        return await _secureStorage.containsKey(key: _keyForProvider(provider));
      } catch (error) {
        throw _secureCredentialStorageError(error);
      } finally {
        _presenceChecks.remove(provider);
      }
    });
  }

  Future<void> clearApiKey(InferenceConnection provider) async {
    _sessionApiKeys.remove(provider);
    final key = _keyForProvider(provider);
    try {
      await _secureStorage.delete(key: key);
      await _clearProviderPreferences(provider);
    } catch (error) {
      throw StateError('Secure AI credential cleanup failed: $error');
    }
  }

  Future<void> saveBaseUrl(InferenceConnection provider, String baseUrl) async {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('${provider.label} base URL is empty');
    }
    final key = _baseUrlKeyForProvider(provider);
    if (key == null) {
      throw ArgumentError('${provider.label} does not support base URL');
    }
    if (provider == InferenceConnection.cloudflareWorkersAi) {
      InferenceProtocolAdapter.chatCompletionsEndpoint(provider, normalized);
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

  Future<void> savePreferredProvider(
    InferenceConnection provider, {
    String? model,
  }) {
    final normalizedModel = model == null ? null : _validateModel(model);
    return _serializePreferences(() async {
      await _loadPreferences();
      final models = Map<InferenceConnection, String>.of(_preferredModels);
      if (normalizedModel != null) models[provider] = normalizedModel;
      await _writePreferences(provider, models);
      _sessionPreferredProvider = provider;
    });
  }

  Future<InferenceConnection?> loadPreferredProvider() async {
    InferenceConnection? provider;
    await _serializePreferences(() async {
      provider = await _loadPreferences();
    });
    return provider;
  }

  Future<String> loadPreferredModel(InferenceConnection provider) async {
    await loadPreferredProvider();
    return preferredModel(provider);
  }

  String preferredModel(InferenceConnection provider) =>
      _preferredModels[provider] ?? provider.defaultModel;

  Future<InferenceConnection?> _loadPreferences() async {
    if (_preferencesLoaded) return _cachedPreferredProvider;
    try {
      final file = await _preferredProviderFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map || decoded['schema_version'] != 1) {
          throw const FormatException('Invalid AI provider preference');
        }
        final rawConnections = decoded['connections'] ?? const [];
        if (rawConnections is! List) {
          throw const FormatException('Invalid AI connections');
        }
        final loaded = <String, InferenceConnection>{};
        for (final raw in rawConnections) {
          if (raw is! Map ||
              raw['id'] is! String ||
              !RegExp(
                r'^connection_[0-9a-f]{32}$',
              ).hasMatch(raw['id'] as String) ||
              raw['name'] is! String ||
              (raw['name'] as String).trim().isEmpty ||
              (raw['name'] as String).length > 80 ||
              raw['base_url'] is! String ||
              raw['model'] is! String ||
              raw['requires_api_key'] is! bool ||
              loaded.containsKey(raw['id'])) {
            throw const FormatException('Invalid AI connection');
          }
          final protocol =
              InferenceProtocol.values
                  .where((p) => p.name == raw['protocol'])
                  .firstOrNull;
          if (protocol == null) {
            throw const FormatException('Unsupported inference protocol');
          }
          final connection = InferenceConnection(
            id: raw['id'] as String,
            label: raw['name'] as String,
            protocol: protocol,
            baseUrl:
                InferenceConnection.validateBaseUrl(
                  raw['base_url'] as String,
                ).toString(),
            defaultModel: _validateModel(raw['model'] as String),
            requiresApiKey: raw['requires_api_key'] as bool,
          );
          loaded[connection.id] = connection;
        }
        _connections.addAll(loaded);
        final provider = _providerForId(decoded['provider_id']);
        if (decoded['provider_id'] != null && provider == null) {
          throw const FormatException('Unknown AI provider preference');
        }
        final rawModels =
            decoded.containsKey('models')
                ? decoded['models']
                : const <String, String>{};
        if (rawModels is! Map) {
          throw const FormatException('Invalid AI model preferences');
        }
        final models = <InferenceConnection, String>{};
        for (final entry in rawModels.entries) {
          final modelProvider = _providerForId(entry.key);
          if (modelProvider == null || entry.value is! String) {
            throw const FormatException('Invalid AI model preference');
          }
          models[modelProvider] = _validateModel(entry.value as String);
        }
        _preferredModels.addAll(models);
        _cachedPreferredProvider = provider;
        _preferencesLoaded = true;
        return provider;
      }
      final provider = await _migrateLegacyPreferredProvider();
      _preferencesLoaded = true;
      return provider;
    } catch (error) {
      _connections.clear();
      _preferredModels.clear();
      _cachedPreferredProvider = null;
      throw StateError('AI provider preference load failed: $error');
    }
  }

  Future<String?> loadBaseUrl(InferenceConnection provider) async {
    if (provider.isCustom) return provider.baseUrl;
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

  Future<void> clearBaseUrl(InferenceConnection provider) async {
    _sessionBaseUrls.remove(provider);
    final key = _baseUrlKeyForProvider(provider);
    if (key == null) return;
    try {
      await _secureStorage.delete(key: key);
      await _clearProviderPreferences(provider);
    } catch (error) {
      throw StateError('Secure AI endpoint cleanup failed: $error');
    }
  }

  Future<void> _clearProviderPreferences(InferenceConnection provider) async {
    await _serializePreferences(() async {
      final preferred = await _loadPreferences();
      final models = Map<InferenceConnection, String>.of(_preferredModels)
        ..remove(provider);
      await _writePreferences(preferred == provider ? null : preferred, models);
      await _secureStorage.delete(key: _preferredProviderKey);
      if (_sessionPreferredProvider == provider) {
        _sessionPreferredProvider = null;
      }
    });
  }

  InferenceConnection? get sessionPreferredProvider =>
      _sessionPreferredProvider;

  String? sessionApiKey(InferenceConnection provider) =>
      _sessionApiKeys[provider];

  String? sessionBaseUrl(InferenceConnection provider) =>
      provider.baseUrl ?? _sessionBaseUrls[provider];

  bool get isPreferredProviderUnlocked {
    final provider = _sessionPreferredProvider;
    if (provider == null) return false;
    if (provider.requiresApiKey &&
        (_sessionApiKeys[provider]?.isNotEmpty != true)) {
      return false;
    }
    if (provider.requiresBaseUrl &&
        (sessionBaseUrl(provider)?.isNotEmpty != true)) {
      return false;
    }
    return true;
  }

  Future<InferenceConnection> unlockPreferredProviderSession() async {
    final provider =
        await loadPreferredProvider() ?? InferenceConnection.gemini;
    return unlockProviderSession(provider);
  }

  Future<InferenceConnection> unlockProviderSession(
    InferenceConnection provider,
  ) async {
    await loadPreferredProvider();
    final apiKey = await loadApiKey(provider);
    if (provider.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        '${provider.label} API key is not saved. Configure it in Capsule Analyst.',
      );
    }
    final baseUrl = await loadBaseUrl(provider);
    if (provider.requiresBaseUrl && (baseUrl == null || baseUrl.isEmpty)) {
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

  Future<InferenceConnection?> _migrateLegacyPreferredProvider() async {
    final legacy = await _secureStorage.read(key: _preferredProviderKey);
    final provider = _providerForId(legacy);
    if (provider == null) return null;
    await _writePreferences(provider, const {});
    await _secureStorage.delete(key: _preferredProviderKey);
    return provider;
  }

  Future<void> _serializePreferences(Future<void> Function() action) {
    final pending = _preferenceWrites.then((_) => action());
    _preferenceWrites = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<void> _writePreferences(
    InferenceConnection? provider,
    Map<InferenceConnection, String> models,
  ) async {
    final savedModels = Map<InferenceConnection, String>.of(models);
    final file = await _preferredProviderFile(createRoot: true);
    if (provider == null && models.isEmpty && _connections.isEmpty) {
      if (await file.exists()) await file.delete();
    } else {
      await _atomicWrites.writeString(
        file,
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'provider_id': provider?.id,
          if (_connections.isNotEmpty)
            'connections': [
              for (final c in _connections.values)
                {
                  'id': c.id,
                  'name': c.label,
                  'protocol': c.protocol.name,
                  'base_url': c.baseUrl,
                  'model': c.defaultModel,
                  'requires_api_key': c.requiresApiKey,
                },
            ],
          if (models.isNotEmpty)
            'models': {
              for (final entry in models.entries) entry.key.id: entry.value,
            },
        }),
      );
    }
    _cachedPreferredProvider = provider;
    _preferredModels
      ..clear()
      ..addAll(savedModels);
    _preferencesLoaded = true;
  }

  static String _validateModel(String model) {
    final normalized = model.trim();
    if (normalized.isEmpty ||
        utf8.encode(normalized).length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(normalized)) {
      throw const FormatException(
        'Model must contain 1..256 UTF-8 bytes without control characters',
      );
    }
    return normalized;
  }

  InferenceConnection? _providerForId(Object? providerId) {
    final normalized = providerId is String ? providerId.trim() : '';
    for (final provider in connections) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  Future<File> _preferredProviderFile({bool createRoot = false}) async {
    final root = await _directories.rootDirectory(create: createRoot);
    return File('${root.path}/$_preferredProviderFileName');
  }

  static String _keyForProvider(InferenceConnection provider) {
    return switch (provider) {
      InferenceConnection.openAi => _openAiApiKeyKey,
      InferenceConnection.gemini => _geminiApiKeyKey,
      InferenceConnection.cloudflareWorkersAi => _cloudflareApiKeyKey,
      InferenceConnection.localOpenAiCompatible => _localOpenAiApiKeyKey,
      _ => 'hivra.ai.connection.${provider.id}.api_key.v1',
    };
  }

  static StateError _secureCredentialStorageError(Object error) {
    final message = error.toString();
    if (message.contains('-67068') ||
        message.contains('cannot find code object on disk') ||
        message.contains('100002')) {
      return StateError(
        'macOS Keychain cannot verify this app bundle. Open the signed app '
        'from a stable location and do not move or run it from a temporary '
        'extracted folder, then try again.',
      );
    }
    return StateError('Secure AI credential storage is unavailable: $error');
  }

  static String? _baseUrlKeyForProvider(InferenceConnection provider) {
    return switch (provider) {
      InferenceConnection.openAi => null,
      InferenceConnection.gemini => null,
      InferenceConnection.cloudflareWorkersAi => _cloudflareBaseUrlKey,
      InferenceConnection.localOpenAiCompatible => _localOpenAiBaseUrlKey,
      _ => null,
    };
  }
}
