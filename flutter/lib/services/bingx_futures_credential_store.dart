import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/bingx_futures_exchange_models.dart';
import 'atomic_file_write_service.dart';
import 'hivra_secure_storage_options.dart';
import 'user_visible_data_directory_service.dart';

class BingxFuturesCredentialStore {
  static const String _keyPrefix = 'hivra.bingx.futures.';
  static const String _apiKeySuffix = 'api_key';
  static const String _apiSecretSuffix = 'api_secret';
  static const String _credentialsSuffix = 'credentials';
  static const String _globalScope = 'global';
  static const String _fallbackFileName = 'bingx_futures_credentials.json';
  final Map<String, BingxFuturesApiCredentials> _sessionCache =
      <String, BingxFuturesApiCredentials>{};

  final FlutterSecureStorage _secureStorage;
  final String? Function() _readActiveCapsuleRootHex;
  final UserVisibleDataDirectoryService _dirs;
  final AtomicFileWriteService _atomicWrites;

  BingxFuturesCredentialStore({
    required String? Function() readActiveCapsuleRootHex,
    FlutterSecureStorage? secureStorage,
    UserVisibleDataDirectoryService? dirs,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(mOptions: hivraMacOsSecureStorageOptions),
       _dirs = dirs ?? const UserVisibleDataDirectoryService(),
       _atomicWrites = atomicWrites;

  Future<void> save(BingxFuturesApiCredentials credentials) async {
    await _migrateLegacyFallbackFile();
    final normalized = credentials.normalized();
    final primaryScope = _scopeKey();
    await _writeScope(primaryScope, normalized);
    _sessionCache[primaryScope] = normalized;
  }

  Future<BingxFuturesApiCredentials?> load() async {
    await _migrateLegacyFallbackFile();
    final primaryScope = _scopeKey();
    final scopes = <String>[
      primaryScope,
      if (primaryScope != _globalScope) _globalScope,
    ];

    for (final scope in scopes) {
      final cached = _sessionCache[scope];
      if (cached != null) {
        if (scope != primaryScope) {
          await _writeScope(primaryScope, cached);
          _sessionCache[primaryScope] = cached;
        }
        return cached;
      }
    }

    for (final scope in scopes) {
      final loaded = await _readScopeAndPromote(scope);
      if (loaded == null) continue;
      _sessionCache[scope] = loaded;
      if (scope != primaryScope) {
        await _writeScope(primaryScope, loaded);
        _sessionCache[primaryScope] = loaded;
      }
      return loaded;
    }
    return null;
  }

  Future<void> clear() async {
    final primaryScope = _scopeKey();
    final scopes = <String>{primaryScope, _globalScope};
    for (final scope in scopes) {
      _sessionCache.remove(scope);
      try {
        await _secureStorage.delete(key: _credentialsForScope(scope));
      } catch (_) {
        // Ignore secure storage cleanup errors.
      }
      try {
        await _secureStorage.delete(key: _apiKeyForScope(scope));
      } catch (_) {
        // Ignore secure storage cleanup errors.
      }
      try {
        await _secureStorage.delete(key: _apiSecretForScope(scope));
      } catch (_) {
        // Ignore secure storage cleanup errors.
      }
      await _deleteScopeFallback(scope);
    }
  }

  String _scopeKey() {
    final raw = _readActiveCapsuleRootHex()?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(raw)) {
      return raw;
    }
    return _globalScope;
  }

  String _apiKeyForScope(String scope) => '$_keyPrefix$scope.$_apiKeySuffix';
  String _apiSecretForScope(String scope) =>
      '$_keyPrefix$scope.$_apiSecretSuffix';
  String _credentialsForScope(String scope) =>
      '$_keyPrefix$scope.$_credentialsSuffix';

  Future<void> _writeScope(
    String scope,
    BingxFuturesApiCredentials credentials,
  ) async {
    await _writeSecureScope(scope, credentials);
    await _deleteScopeFallback(scope);
  }

  Future<void> _writeSecureScope(
    String scope,
    BingxFuturesApiCredentials credentials,
  ) async {
    try {
      await _secureStorage.write(
        key: _credentialsForScope(scope),
        value: jsonEncode(<String, String>{
          _apiKeySuffix: credentials.apiKey,
          _apiSecretSuffix: credentials.apiSecret,
        }),
      );
    } catch (error) {
      throw StateError('Secure credential storage is unavailable: $error');
    }
  }

  Future<BingxFuturesApiCredentials?> _readScope(String scope) async {
    try {
      final raw = await _secureStorage.read(key: _credentialsForScope(scope));
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final apiKey = map[_apiKeySuffix]?.toString().trim() ?? '';
          final apiSecret = map[_apiSecretSuffix]?.toString().trim() ?? '';
          if (apiKey.isNotEmpty && apiSecret.isNotEmpty) {
            return BingxFuturesApiCredentials(
              apiKey: apiKey,
              apiSecret: apiSecret,
            ).normalized();
          }
        }
      }
    } catch (_) {
      // Continue into legacy secure storage/fallback migration.
    }

    try {
      final apiKey = await _secureStorage.read(key: _apiKeyForScope(scope));
      final apiSecret = await _secureStorage.read(
        key: _apiSecretForScope(scope),
      );
      if (apiKey != null &&
          apiSecret != null &&
          apiKey.trim().isNotEmpty &&
          apiSecret.trim().isNotEmpty) {
        return BingxFuturesApiCredentials(
          apiKey: apiKey.trim(),
          apiSecret: apiSecret.trim(),
        ).normalized();
      }
    } catch (_) {
      // Continue into one-time migration of legacy plaintext storage.
    }

    final fallback = await _readScopeFallback(scope);
    if (fallback == null) return null;
    return BingxFuturesApiCredentials(
      apiKey: fallback.$1,
      apiSecret: fallback.$2,
    ).normalized();
  }

  Future<File> _fallbackFile() async {
    final root = await _dirs.rootDirectory(create: true);
    return File('${root.path}/$_fallbackFileName');
  }

  Future<Map<String, dynamic>> _readFallbackMap() async {
    final file = await _fallbackFile();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeFallbackMap(Map<String, dynamic> map) async {
    final file = await _fallbackFile();
    if (map.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await _atomicWrites.writeString(file, jsonEncode(map));
  }

  Future<(String, String)?> _readScopeFallback(String scope) async {
    final map = await _readFallbackMap();
    final entry = map[scope];
    if (entry is! Map) return null;
    final scoped = Map<String, dynamic>.from(entry);
    final apiKey = scoped[_apiKeySuffix]?.toString().trim() ?? '';
    final apiSecret = scoped[_apiSecretSuffix]?.toString().trim() ?? '';
    if (apiKey.isEmpty || apiSecret.isEmpty) return null;
    return (apiKey, apiSecret);
  }

  Future<void> _deleteScopeFallback(String scope) async {
    final map = await _readFallbackMap();
    if (!map.containsKey(scope)) return;
    map.remove(scope);
    await _writeFallbackMap(map);
  }

  Future<void> _promoteToSecureIfNeeded(
    String scope,
    BingxFuturesApiCredentials credentials,
  ) async {
    await _writeScope(scope, credentials);
  }

  Future<void> _migrateLegacyFallbackFile() async {
    final file = await _fallbackFile();
    if (!await file.exists()) return;
    final map = await _readFallbackMap();
    final credentialsByScope = <String, BingxFuturesApiCredentials>{};
    for (final entry in map.entries) {
      final scope = entry.key.trim().toLowerCase();
      final value = entry.value;
      if (value is! Map ||
          (scope != _globalScope &&
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(scope))) {
        continue;
      }
      final scoped = Map<String, dynamic>.from(value);
      final apiKey = scoped[_apiKeySuffix]?.toString().trim() ?? '';
      final apiSecret = scoped[_apiSecretSuffix]?.toString().trim() ?? '';
      if (apiKey.isEmpty || apiSecret.isEmpty) continue;
      try {
        credentialsByScope[scope] =
            BingxFuturesApiCredentials(
              apiKey: apiKey,
              apiSecret: apiSecret,
            ).normalized();
      } on FormatException {
        continue;
      }
    }

    try {
      for (final entry in credentialsByScope.entries) {
        await _writeSecureScope(entry.key, entry.value);
      }
    } catch (error) {
      throw StateError('Secure credential migration failed: $error');
    }
    await file.delete();
  }

  Future<BingxFuturesApiCredentials?> _readScopeAndPromote(String scope) async {
    final loaded = await _readScope(scope);
    if (loaded == null) return null;
    await _promoteToSecureIfNeeded(scope, loaded);
    return loaded;
  }
}
