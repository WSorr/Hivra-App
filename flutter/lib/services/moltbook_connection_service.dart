import 'dart:convert';

import '../models/moltbook_provider_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';
import 'moltbook_provider_adapter.dart';

class MoltbookConnectionService {
  static const String providerId = 'moltbook';
  static const String secretName = 'api_key';
  static const String _bindingFileName = 'connection.v1.json';

  final CapsuleFileStore _fileStore;
  final CapsuleScopedSecretVault _secretVault;
  final MoltbookObservePort _observer;
  final String? Function() _readActiveCapsuleRootHex;
  final DateTime Function() _now;

  const MoltbookConnectionService({
    required CapsuleFileStore fileStore,
    required CapsuleScopedSecretVault secretVault,
    required MoltbookObservePort observer,
    required String? Function() readActiveCapsuleRootHex,
    DateTime Function() now = DateTime.now,
  }) : _fileStore = fileStore,
       _secretVault = secretVault,
       _observer = observer,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _now = now;

  Future<MoltbookConnectionBinding?> loadBinding() async {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) return null;
    final capsuleDir = await _fileStore.capsuleDirForHex(ownerHex);
    final raw = await _fileStore.readPluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _bindingFileName,
    );
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Moltbook binding must be a JSON object');
    }
    return MoltbookConnectionBinding.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<MoltbookConnectionBinding> connect(String apiKey) async {
    final ownerHex = _requireActiveOwnerHex();
    final normalizedKey = apiKey.trim();
    final observation = await _observer.observeAccount(normalizedKey);
    _requireSameOwner(ownerHex);

    final next = MoltbookConnectionBinding.fromObservation(
      observation,
      verifiedAt: _now(),
    );
    final previous = await loadBinding();
    _requireSameOwner(ownerHex);
    final previousSecret =
        previous == null
            ? null
            : await _secretVault.loadSecret(
              capsuleHex: ownerHex,
              pluginId: moltbookAmbassadorPluginId,
              providerId: providerId,
              accountId: previous.accountId,
              secretName: secretName,
            );
    _requireSameOwner(ownerHex);

    await _secretVault.replaceAccountSecret(
      capsuleHex: ownerHex,
      pluginId: moltbookAmbassadorPluginId,
      providerId: providerId,
      previousAccountId: previous?.accountId,
      accountId: next.accountId,
      secretName: secretName,
      secretValue: normalizedKey,
    );
    try {
      await _writeBinding(ownerHex, next);
      _requireSameOwner(ownerHex);
      return next;
    } catch (error, stackTrace) {
      Object? rollbackError;
      StackTrace? rollbackStackTrace;
      try {
        await _restoreBinding(ownerHex, previous);
      } catch (restoreError, restoreStackTrace) {
        rollbackError = restoreError;
        rollbackStackTrace = restoreStackTrace;
      }
      try {
        await _restoreSecret(
          ownerHex: ownerHex,
          failedAccountId: next.accountId,
          previous: previous,
          previousSecret: previousSecret,
        );
      } catch (restoreError, restoreStackTrace) {
        rollbackError ??= restoreError;
        rollbackStackTrace ??= restoreStackTrace;
      }
      if (rollbackError != null) {
        Error.throwWithStackTrace(
          StateError(
            'Moltbook connection failed and rollback was incomplete: '
            '$rollbackError',
          ),
          rollbackStackTrace!,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<MoltbookConnectionBinding> refresh() async {
    final ownerHex = _requireActiveOwnerHex();
    final current = await loadBinding();
    if (current == null) {
      throw StateError('Moltbook account is not connected');
    }
    final apiKey = await _secretVault.loadSecret(
      capsuleHex: ownerHex,
      pluginId: moltbookAmbassadorPluginId,
      providerId: providerId,
      accountId: current.accountId,
      secretName: secretName,
    );
    if (apiKey == null) {
      throw StateError('Moltbook credential is unavailable');
    }
    final observation = await _observer.observeAccount(apiKey);
    _requireSameOwner(ownerHex);
    if (observation.accountId.trim() != current.accountId) {
      throw StateError('Moltbook credential resolved to another account');
    }
    final refreshed = MoltbookConnectionBinding.fromObservation(
      observation,
      verifiedAt: _now(),
    );
    await _writeBinding(ownerHex, refreshed);
    _requireSameOwner(ownerHex);
    return refreshed;
  }

  Future<MoltbookHomeObservation> observeHome() async {
    return _withBoundCredential(_observer.observeHome);
  }

  Future<MoltbookFeedObservation> observeFeed({
    String sort = 'new',
    int limit = 15,
    String? cursor,
  }) {
    return _withBoundCredential(
      (apiKey) => _observer.observeFeed(
        apiKey,
        sort: sort,
        limit: limit,
        cursor: cursor,
      ),
    );
  }

  Future<T> _withBoundCredential<T>(
    Future<T> Function(String apiKey) operation,
  ) async {
    final ownerHex = _requireActiveOwnerHex();
    final current = await loadBinding();
    if (current == null) {
      throw StateError('Moltbook account is not connected');
    }
    final apiKey = await _secretVault.loadSecret(
      capsuleHex: ownerHex,
      pluginId: moltbookAmbassadorPluginId,
      providerId: providerId,
      accountId: current.accountId,
      secretName: secretName,
    );
    if (apiKey == null) {
      throw StateError('Moltbook credential is unavailable');
    }
    final observation = await operation(apiKey);
    _requireSameOwner(ownerHex);
    return observation;
  }

  Future<void> disconnect() async {
    final ownerHex = _requireActiveOwnerHex();
    final binding = await loadBinding();
    if (binding == null) return;
    await _secretVault.deleteAccount(
      capsuleHex: ownerHex,
      pluginId: moltbookAmbassadorPluginId,
      providerId: providerId,
      accountId: binding.accountId,
    );
    await _deleteBinding(ownerHex);
    _requireSameOwner(ownerHex);
  }

  Future<void> _writeBinding(
    String ownerHex,
    MoltbookConnectionBinding binding,
  ) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    await _fileStore.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _bindingFileName,
      const JsonEncoder.withIndent('  ').convert(binding.toJson()),
    );
  }

  Future<void> _restoreBinding(
    String ownerHex,
    MoltbookConnectionBinding? previous,
  ) {
    return previous == null
        ? _deleteBinding(ownerHex)
        : _writeBinding(ownerHex, previous);
  }

  Future<void> _deleteBinding(String ownerHex) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(ownerHex);
    await _fileStore.deletePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _bindingFileName,
    );
  }

  Future<void> _restoreSecret({
    required String ownerHex,
    required String failedAccountId,
    required MoltbookConnectionBinding? previous,
    required String? previousSecret,
  }) async {
    if (previous != null && previousSecret != null) {
      await _secretVault.replaceAccountSecret(
        capsuleHex: ownerHex,
        pluginId: moltbookAmbassadorPluginId,
        providerId: providerId,
        previousAccountId: failedAccountId,
        accountId: previous.accountId,
        secretName: secretName,
        secretValue: previousSecret,
      );
      return;
    }
    await _secretVault.deleteAccount(
      capsuleHex: ownerHex,
      pluginId: moltbookAmbassadorPluginId,
      providerId: providerId,
      accountId: failedAccountId,
    );
  }

  String _requireActiveOwnerHex() {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) {
      throw StateError('Active capsule identity is unavailable');
    }
    return ownerHex;
  }

  void _requireSameOwner(String expectedOwnerHex) {
    if (_activeOwnerHex() != expectedOwnerHex) {
      throw StateError('Active capsule changed during Moltbook operation');
    }
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }
}
