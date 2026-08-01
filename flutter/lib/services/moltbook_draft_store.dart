import 'dart:async';
import 'dart:convert';

import '../models/moltbook_ambassador_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';

class MoltbookDraftStore {
  static const String _fileName = 'drafts.v1.json';
  static const int _maxDrafts = 100;

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  Future<void> _writeTail = Future<void>.value();

  MoltbookDraftStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<List<MoltbookStoredDraft>> load() async {
    final ownerHex = _requireOwnerHex();
    return _loadForOwner(ownerHex);
  }

  Future<MoltbookStoredDraft> save(MoltbookDraftPreview preview) {
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      final drafts = await _loadForOwner(ownerHex);
      final stored = MoltbookStoredDraft(
        preview: preview,
        createdAtUtc: DateTime.now().toUtc(),
      );
      final updated =
          <MoltbookStoredDraft>[
            stored,
            ...drafts.where(
              (draft) => draft.preview.draftHashHex != preview.draftHashHex,
            ),
          ].take(_maxDrafts).toList();
      await _writeForOwner(ownerHex, updated);
      return stored;
    });
  }

  Future<void> delete(String draftHashHex) {
    return deleteAll(<String>{draftHashHex});
  }

  Future<void> deleteAll(Set<String> draftHashHexes) {
    if (draftHashHexes.isEmpty) return Future<void>.value();
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      final drafts = await _loadForOwner(ownerHex);
      final updated =
          drafts
              .where(
                (draft) => !draftHashHexes.contains(draft.preview.draftHashHex),
              )
              .toList();
      if (updated.length != drafts.length) {
        await _writeForOwner(ownerHex, updated);
      }
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

  Future<List<MoltbookStoredDraft>> _loadForOwner(String ownerHex) async {
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
    if (raw == null) return const <MoltbookStoredDraft>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schema_version'] != 1 ||
        decoded['plugin_id'] != moltbookAmbassadorPluginId ||
        decoded['drafts'] is! List) {
      throw const FormatException('Invalid Moltbook draft store');
    }
    final drafts =
        (decoded['drafts'] as List).map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid Moltbook draft entry');
          }
          return MoltbookStoredDraft.fromJson(Map<String, dynamic>.from(value));
        }).toList();
    if (drafts.length > _maxDrafts) {
      throw const FormatException('Moltbook draft store exceeds its limit');
    }
    return drafts;
  }

  Future<void> _writeForOwner(
    String ownerHex,
    List<MoltbookStoredDraft> drafts,
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
        'schema_version': 1,
        'plugin_id': moltbookAmbassadorPluginId,
        'drafts': drafts.map((draft) => draft.toJson()).toList(),
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
      throw StateError('Active capsule changed during draft persistence');
    }
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }
}
