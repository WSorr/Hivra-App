import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bingx_futures_exchange_service.dart';
import 'user_visible_data_directory_service.dart';

class BingxFuturesCredentialStore {
  static const String _keyPrefix = 'hivra.bingx.futures.';
  static const String _apiKeySuffix = 'api_key';
  static const String _apiSecretSuffix = 'api_secret';
  static const String _globalScope = 'global';
  static const String _fallbackFileName = 'bingx_futures_credentials.json';
  static final Map<String, BingxFuturesApiCredentials> _sessionCache =
      <String, BingxFuturesApiCredentials>{};

  final FlutterSecureStorage _secureStorage;
  final String? Function() _readActiveCapsuleRootHex;
  final UserVisibleDataDirectoryService _dirs;

  const BingxFuturesCredentialStore({
    required String? Function() readActiveCapsuleRootHex,
    FlutterSecureStorage? secureStorage,
    UserVisibleDataDirectoryService? dirs,
  })  : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _dirs = dirs ?? const UserVisibleDataDirectoryService();

  Future<void> save(BingxFuturesApiCredentials credentials) async {
    final normalized = credentials.normalized();
    final primaryScope = _scopeKey();
    await _writeScope(primaryScope, normalized);
    _sessionCache[primaryScope] = normalized;

    // Keep a global fallback so users do not need to re-enter credentials
    // when scope is temporarily unavailable during bootstrap/switch.
    if (primaryScope != _globalScope) {
      await _writeScope(_globalScope, normalized);
      _sessionCache[_globalScope] = normalized;
    }
  }

  Future<BingxFuturesApiCredentials?> load() async {
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
    final scopes = <String>{
      primaryScope,
      _globalScope,
    };
    for (final scope in scopes) {
      _sessionCache.remove(scope);
      try {
        await _secureStorage.delete(
          key: _apiKeyForScope(scope),
        );
      } catch (_) {
        // Ignore secure storage cleanup errors.
      }
      try {
        await _secureStorage.delete(
          key: _apiSecretForScope(scope),
        );
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

  Future<void> _writeScope(
    String scope,
    BingxFuturesApiCredentials credentials,
  ) async {
    try {
      await _secureStorage.write(
        key: _apiKeyForScope(scope),
        value: credentials.apiKey,
      );
      await _secureStorage.write(
        key: _apiSecretForScope(scope),
        value: credentials.apiSecret,
      );
    } catch (_) {
      // Secure storage may be unavailable in some release/signing contexts.
    }
    // Keep file fallback as durability layer across keychain availability
    // changes between app launches/builds.
    await _writeScopeFallback(scope, credentials);
  }

  Future<BingxFuturesApiCredentials?> _readScope(String scope) async {
    try {
      final apiKey = await _secureStorage.read(
        key: _apiKeyForScope(scope),
      );
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
        );
      }
    } catch (_) {
      // Secure storage unavailable for current build/signing.
    }

    final fallback = await _readScopeFallback(scope);
    if (fallback == null) return null;
    return BingxFuturesApiCredentials(
      apiKey: fallback.$1,
      apiSecret: fallback.$2,
    );
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
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(map), flush: true);
  }

  Future<void> _writeScopeFallback(
    String scope,
    BingxFuturesApiCredentials credentials,
  ) async {
    final map = await _readFallbackMap();
    map[scope] = <String, String>{
      _apiKeySuffix: credentials.apiKey,
      _apiSecretSuffix: credentials.apiSecret,
    };
    await _writeFallbackMap(map);
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
    try {
      await _secureStorage.write(
        key: _apiKeyForScope(scope),
        value: credentials.apiKey,
      );
      await _secureStorage.write(
        key: _apiSecretForScope(scope),
        value: credentials.apiSecret,
      );
    } catch (_) {
      // Keep fallback as source of truth when keychain is unavailable.
    }
    // Never delete fallback automatically: keychain availability may change
    // across launches and signatures, and fallback keeps credentials durable.
    await _writeScopeFallback(scope, credentials);
  }

  Future<BingxFuturesApiCredentials?> _readScopeAndPromote(String scope) async {
    final loaded = await _readScope(scope);
    if (loaded == null) return null;
    await _promoteToSecureIfNeeded(scope, loaded);
    return loaded;
  }
}
