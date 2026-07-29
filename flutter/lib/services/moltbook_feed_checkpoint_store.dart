import 'dart:async';
import 'dart:convert';

import '../models/moltbook_provider_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';

class MoltbookFeedCheckpointStore {
  static const String _fileName = 'feed_checkpoint.v1.json';

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  Future<void> _writeTail = Future<void>.value();

  MoltbookFeedCheckpointStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<MoltbookFeedCheckpoint> load() async {
    final ownerHex = _requireOwnerHex();
    return _loadForOwner(ownerHex);
  }

  Future<MoltbookFeedCheckpoint> commit(
    MoltbookFeedObservation observation, {
    required DateTime observedAt,
  }) {
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      final current = await _loadForOwner(ownerHex);
      final updated = current.advance(observation, observedAt: observedAt);
      await _writeForOwner(ownerHex, updated);
      return updated;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<MoltbookFeedCheckpoint> _loadForOwner(String ownerHex) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    final raw = await _fileStore.readPluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
    );
    _ensureOwner(ownerHex);
    if (raw == null) return const MoltbookFeedCheckpoint.empty();
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['plugin_id'] != moltbookAmbassadorPluginId) {
      throw const FormatException('Invalid Moltbook feed checkpoint store');
    }
    return MoltbookFeedCheckpoint.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> _writeForOwner(
    String ownerHex,
    MoltbookFeedCheckpoint checkpoint,
  ) async {
    _ensureOwner(ownerHex);
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    await _fileStore.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      _fileName,
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        ...checkpoint.toJson(),
        'plugin_id': moltbookAmbassadorPluginId,
      }),
    );
    _ensureOwner(ownerHex);
  }

  String _requireOwnerHex() {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) {
      throw StateError('Active capsule identity is unavailable');
    }
    return ownerHex;
  }

  void _ensureOwner(String expectedOwnerHex) {
    if (_activeOwnerHex() != expectedOwnerHex) {
      throw StateError(
        'Active capsule changed during Moltbook checkpoint persistence',
      );
    }
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }
}
