import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bingx_futures_exchange_service.dart';

class BingxFuturesCredentialStore {
  static const String _keyPrefix = 'hivra.bingx.futures.';
  static const String _apiKeySuffix = 'api_key';
  static const String _apiSecretSuffix = 'api_secret';
  static const String _globalScope = 'global';

  final FlutterSecureStorage _secureStorage;
  final String? Function() _readActiveCapsuleRootHex;

  const BingxFuturesCredentialStore({
    required String? Function() readActiveCapsuleRootHex,
    FlutterSecureStorage? secureStorage,
  })  : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> save(BingxFuturesApiCredentials credentials) async {
    final normalized = credentials.normalized();
    final scope = _scopeKey();
    await _secureStorage.write(
      key: '$_keyPrefix$scope.$_apiKeySuffix',
      value: normalized.apiKey,
    );
    await _secureStorage.write(
      key: '$_keyPrefix$scope.$_apiSecretSuffix',
      value: normalized.apiSecret,
    );
  }

  Future<BingxFuturesApiCredentials?> load() async {
    final scope = _scopeKey();
    final apiKey = await _secureStorage.read(
      key: '$_keyPrefix$scope.$_apiKeySuffix',
    );
    final apiSecret = await _secureStorage.read(
      key: '$_keyPrefix$scope.$_apiSecretSuffix',
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

  Future<void> clear() async {
    final scope = _scopeKey();
    await _secureStorage.delete(
      key: '$_keyPrefix$scope.$_apiKeySuffix',
    );
    await _secureStorage.delete(
      key: '$_keyPrefix$scope.$_apiSecretSuffix',
    );
  }

  String _scopeKey() {
    final raw = _readActiveCapsuleRootHex()?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(raw)) {
      return raw;
    }
    return _globalScope;
  }
}
