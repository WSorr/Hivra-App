import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hivra_secure_storage_options.dart';

class CapsuleScopedSecretVault {
  static const String _storageKey = 'hivra.capsule_scoped_secrets.v1';
  static const int _schemaVersion = 1;
  static const int _maxEntries = 512;
  static final _VaultCoordinator _productionCoordinator = _VaultCoordinator();

  final FlutterSecureStorage _secureStorage;
  final _VaultCoordinator _coordinator;

  CapsuleScopedSecretVault({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(mOptions: hivraMacOsSecureStorageOptions),
      _coordinator =
          secureStorage == null ? _productionCoordinator : _VaultCoordinator();

  Future<void> saveSecret({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
    required String secretName,
    required String secretValue,
  }) {
    final entry = _VaultEntry(
      capsuleHex: capsuleHex.trim().toLowerCase(),
      pluginId: pluginId.trim(),
      providerId: providerId.trim(),
      accountId: accountId.trim(),
      secretName: secretName.trim(),
      secretValue: secretValue.trim(),
    )..validate();
    return _locked(() async {
      final entries = await _loadEntries();
      entries[entry.scopeKey] = entry;
      if (entries.length > _maxEntries) {
        throw StateError('Capsule-scoped secret vault is full');
      }
      await _writeEntries(entries);
    });
  }

  Future<String?> loadSecret({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
    required String secretName,
  }) {
    final scope = _scopeKey(
      capsuleHex: capsuleHex,
      pluginId: pluginId,
      providerId: providerId,
      accountId: accountId,
      secretName: secretName,
    );
    return _locked(() async {
      final entries = await _loadEntries();
      return entries[scope]?.secretValue;
    });
  }

  Future<void> deleteAccount({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
  }) {
    final normalizedCapsule = _capsuleHex(capsuleHex);
    final normalizedPlugin = _identifier('plugin_id', pluginId);
    final normalizedProvider = _identifier('provider_id', providerId);
    final normalizedAccount = _identifier('account_id', accountId);
    return _removeWhere(
      (entry) =>
          entry.capsuleHex == normalizedCapsule &&
          entry.pluginId == normalizedPlugin &&
          entry.providerId == normalizedProvider &&
          entry.accountId == normalizedAccount,
    );
  }

  Future<void> replaceAccountSecret({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    String? previousAccountId,
    required String accountId,
    required String secretName,
    required String secretValue,
  }) {
    final entry = _VaultEntry(
      capsuleHex: capsuleHex.trim().toLowerCase(),
      pluginId: pluginId.trim(),
      providerId: providerId.trim(),
      accountId: accountId.trim(),
      secretName: secretName.trim(),
      secretValue: secretValue.trim(),
    )..validate();
    final normalizedPrevious =
        previousAccountId == null
            ? null
            : _identifier('previous_account_id', previousAccountId);
    return _locked(() async {
      final entries = await _loadEntries();
      if (normalizedPrevious != null && normalizedPrevious != entry.accountId) {
        entries.removeWhere(
          (_, candidate) =>
              candidate.capsuleHex == entry.capsuleHex &&
              candidate.pluginId == entry.pluginId &&
              candidate.providerId == entry.providerId &&
              candidate.accountId == normalizedPrevious &&
              candidate.secretName == entry.secretName,
        );
      }
      entries[entry.scopeKey] = entry;
      if (entries.length > _maxEntries) {
        throw StateError('Capsule-scoped secret vault is full');
      }
      await _writeEntries(entries);
    });
  }

  Future<void> deletePlugin(String pluginId) {
    final normalized = _identifier('plugin_id', pluginId);
    return _removeWhere((entry) => entry.pluginId == normalized);
  }

  Future<void> deleteCapsule(String capsuleHex) {
    return deleteCapsules(<String>{capsuleHex});
  }

  Future<void> deleteCapsules(Set<String> capsuleHexes) {
    final normalized = capsuleHexes.map(_capsuleHex).toSet();
    return _removeWhere((entry) => normalized.contains(entry.capsuleHex));
  }

  Future<void> _removeWhere(bool Function(_VaultEntry entry) predicate) {
    return _locked(() async {
      final entries = await _loadEntries();
      final before = entries.length;
      entries.removeWhere((_, entry) => predicate(entry));
      if (entries.length == before) return;
      await _writeEntries(entries);
    });
  }

  Future<Map<String, _VaultEntry>> _loadEntries() async {
    final cached = _coordinator.cache;
    if (cached != null) return Map<String, _VaultEntry>.from(cached);
    final String? raw;
    try {
      raw = await _secureStorage.read(key: _storageKey);
    } catch (error) {
      throw StateError('Secure plugin credential storage is unavailable');
    }
    if (raw == null || raw.trim().isEmpty) {
      _coordinator.cache = <String, _VaultEntry>{};
      return <String, _VaultEntry>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schema_version'] != _schemaVersion) {
        throw const FormatException('Unsupported secret vault schema');
      }
      final rawEntries = decoded['entries'];
      if (rawEntries is! List || rawEntries.length > _maxEntries) {
        throw const FormatException('Invalid secret vault entries');
      }
      final entries = <String, _VaultEntry>{};
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) {
          throw const FormatException('Invalid secret vault entry');
        }
        final entry = _VaultEntry.fromJson(Map<String, dynamic>.from(rawEntry))
          ..validate();
        if (entries.containsKey(entry.scopeKey)) {
          throw const FormatException('Duplicate secret vault scope');
        }
        entries[entry.scopeKey] = entry;
      }
      _coordinator.cache = Map<String, _VaultEntry>.from(entries);
      return entries;
    } catch (_) {
      throw StateError('Secure plugin credential vault is malformed');
    }
  }

  Future<void> _writeEntries(Map<String, _VaultEntry> entries) async {
    try {
      if (entries.isEmpty) {
        await _secureStorage.delete(key: _storageKey);
      } else {
        final ordered =
            entries.values.toList()
              ..sort((left, right) => left.scopeKey.compareTo(right.scopeKey));
        await _secureStorage.write(
          key: _storageKey,
          value: jsonEncode(<String, dynamic>{
            'schema_version': _schemaVersion,
            'entries': ordered.map((entry) => entry.toJson()).toList(),
          }),
        );
      }
      _coordinator.cache = Map<String, _VaultEntry>.from(entries);
    } catch (_) {
      throw StateError('Secure plugin credential storage is unavailable');
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _coordinator.tail = _coordinator.tail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String _scopeKey({
    required String capsuleHex,
    required String pluginId,
    required String providerId,
    required String accountId,
    required String secretName,
  }) {
    return <String>[
      _capsuleHex(capsuleHex),
      _identifier('plugin_id', pluginId),
      _identifier('provider_id', providerId),
      _identifier('account_id', accountId),
      _identifier('secret_name', secretName),
    ].join('::');
  }

  static String _capsuleHex(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('capsule_hex must be 64 lowercase hex');
    }
    return normalized;
  }

  static String _identifier(String field, String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:@-]{0,255}$').hasMatch(normalized)) {
      throw FormatException('$field is invalid');
    }
    return normalized;
  }
}

class _VaultCoordinator {
  Future<void> tail = Future<void>.value();
  Map<String, _VaultEntry>? cache;
}

class _VaultEntry {
  final String capsuleHex;
  final String pluginId;
  final String providerId;
  final String accountId;
  final String secretName;
  final String secretValue;

  const _VaultEntry({
    required this.capsuleHex,
    required this.pluginId,
    required this.providerId,
    required this.accountId,
    required this.secretName,
    required this.secretValue,
  });

  factory _VaultEntry.fromJson(Map<String, dynamic> json) {
    return _VaultEntry(
      capsuleHex: json['capsule_hex']?.toString() ?? '',
      pluginId: json['plugin_id']?.toString() ?? '',
      providerId: json['provider_id']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      secretName: json['secret_name']?.toString() ?? '',
      secretValue: json['secret_value']?.toString() ?? '',
    );
  }

  String get scopeKey => <String>[
    capsuleHex,
    pluginId,
    providerId,
    accountId,
    secretName,
  ].join('::');

  Map<String, dynamic> toJson() => <String, dynamic>{
    'capsule_hex': capsuleHex,
    'plugin_id': pluginId,
    'provider_id': providerId,
    'account_id': accountId,
    'secret_name': secretName,
    'secret_value': secretValue,
  };

  void validate() {
    CapsuleScopedSecretVault._capsuleHex(capsuleHex);
    CapsuleScopedSecretVault._identifier('plugin_id', pluginId);
    CapsuleScopedSecretVault._identifier('provider_id', providerId);
    CapsuleScopedSecretVault._identifier('account_id', accountId);
    CapsuleScopedSecretVault._identifier('secret_name', secretName);
    if (secretValue.isEmpty || secretValue.length > 4096) {
      throw const FormatException('secret_value must contain 1..4096 chars');
    }
  }
}
