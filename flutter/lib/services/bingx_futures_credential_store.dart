import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bingx_futures_exchange_service.dart';

class BingxFuturesCredentialStore {
  static const String _keyPrefix = 'hivra.bingx.futures.';
  static const String _apiKeySuffix = 'api_key';
  static const String _apiSecretSuffix = 'api_secret';
  static const String _globalScope = 'global';
  static final Map<String, BingxFuturesApiCredentials> _sessionCache =
      <String, BingxFuturesApiCredentials>{};

  final FlutterSecureStorage _secureStorage;
  final String? Function() _readActiveCapsuleRootHex;

  const BingxFuturesCredentialStore({
    required String? Function() readActiveCapsuleRootHex,
    FlutterSecureStorage? secureStorage,
  })  : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

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
      final loaded = await _readScope(scope);
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
      await _secureStorage.delete(
        key: _apiKeyForScope(scope),
      );
      await _secureStorage.delete(
        key: _apiSecretForScope(scope),
      );
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
    await _secureStorage.write(
      key: _apiKeyForScope(scope),
      value: credentials.apiKey,
    );
    await _secureStorage.write(
      key: _apiSecretForScope(scope),
      value: credentials.apiSecret,
    );
  }

  Future<BingxFuturesApiCredentials?> _readScope(String scope) async {
    final apiKey = await _secureStorage.read(
      key: _apiKeyForScope(scope),
    );
    final apiSecret = await _secureStorage.read(
      key: _apiSecretForScope(scope),
    );
    if (apiKey == null ||
        apiSecret == null ||
        apiKey.trim().isEmpty ||
        apiSecret.trim().isEmpty) {
      return null;
    }
    return BingxFuturesApiCredentials(
      apiKey: apiKey.trim(),
      apiSecret: apiSecret.trim(),
    );
  }
}
