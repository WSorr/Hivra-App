import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/plugin_contract_ids.dart';
import 'capsule_file_store.dart';

class MoltbookPublicChange {
  final String sourceId;
  final String category;
  final List<String> facts;
  final String commitmentHashHex;
  final DateTime recordedAtUtc;
  final String? draftHashHex;

  const MoltbookPublicChange({
    required this.sourceId,
    required this.category,
    required this.facts,
    required this.commitmentHashHex,
    required this.recordedAtUtc,
    this.draftHashHex,
  });

  bool get isPending => draftHashHex == null;

  String get sourceNotes => facts.join('\n');

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': 1,
    'source_id': sourceId,
    'category': category,
    'facts': facts,
    'commitment_hash_hex': commitmentHashHex,
    'recorded_at_utc': recordedAtUtc.toIso8601String(),
    'draft_hash_hex': draftHashHex,
  };

  factory MoltbookPublicChange.fromJson(Map<String, dynamic> json) {
    final facts = json['facts'];
    final recordedAt = DateTime.tryParse(
      json['recorded_at_utc']?.toString() ?? '',
    );
    final draftHash = json['draft_hash_hex'];
    if (json['schema_version'] != 1 ||
        json['source_id'] is! String ||
        json['category'] is! String ||
        facts is! List ||
        facts.any((value) => value is! String) ||
        json['commitment_hash_hex'] is! String ||
        recordedAt == null ||
        !recordedAt.isUtc ||
        (draftHash != null && draftHash is! String)) {
      throw const FormatException('Invalid Moltbook public change');
    }
    final change = MoltbookPublicChange(
      sourceId: json['source_id'] as String,
      category: json['category'] as String,
      facts: List<String>.unmodifiable(facts.cast<String>()),
      commitmentHashHex: json['commitment_hash_hex'] as String,
      recordedAtUtc: recordedAt,
      draftHashHex: draftHash as String?,
    );
    MoltbookPublicChangeFeedStore.validate(change);
    return change;
  }
}

class MoltbookPublicChangeFeedStore {
  static const String _fileName = 'public_change_feed.v1.json';
  static const int maxChanges = 100;
  static const int maxManifestChanges = 32;
  static const int maxManifestCharacters = 32768;
  static const int maxFacts = 8;
  static const int maxFactCharacters = 280;

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;
  Future<void> _writeTail = Future<void>.value();

  MoltbookPublicChangeFeedStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<List<MoltbookPublicChange>> load() async {
    final ownerHex = _requireOwnerHex();
    return _loadForOwner(ownerHex);
  }

  Future<MoltbookPublicChange?> nextPending() async {
    final changes = await load();
    for (final change in changes) {
      if (change.isPending) return change;
    }
    return null;
  }

  Future<MoltbookPublicChange> record({
    required String sourceId,
    required String category,
    required List<String> facts,
  }) {
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      final normalizedSourceId = sourceId.trim();
      final normalizedCategory = category.trim();
      final normalizedFacts = facts.map((fact) => fact.trim()).toList();
      final commitment = commitmentFor(
        sourceId: normalizedSourceId,
        category: normalizedCategory,
        facts: normalizedFacts,
      );
      final changes = await _loadForOwner(ownerHex);
      final sameSource = changes.where(
        (change) => change.sourceId == normalizedSourceId,
      );
      for (final existing in sameSource) {
        if (existing.commitmentHashHex == commitment) return existing;
        throw StateError(
          'Public change source id is already bound to different facts',
        );
      }
      final change = MoltbookPublicChange(
        sourceId: normalizedSourceId,
        category: normalizedCategory,
        facts: List<String>.unmodifiable(normalizedFacts),
        commitmentHashHex: commitment,
        recordedAtUtc: DateTime.now().toUtc(),
      );
      validate(change);
      final updated = <MoltbookPublicChange>[...changes, change];
      if (updated.length > maxChanges) {
        updated.removeRange(0, updated.length - maxChanges);
      }
      await _writeForOwner(ownerHex, updated);
      return change;
    });
  }

  Future<List<MoltbookPublicChange>> ingestManifest(
    String raw, {
    required Set<String> allowedTopics,
  }) {
    return _serialized(() async {
      final ownerHex = _requireOwnerHex();
      if (raw.length > maxManifestCharacters) {
        throw const FormatException(
          'Moltbook public change manifest exceeds its character limit',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded.length != 3 ||
          decoded['schema_version'] != 1 ||
          decoded['producer_id'] != 'hivra.bundled_public_changes' ||
          decoded['changes'] is! List) {
        throw const FormatException('Invalid Moltbook public change manifest');
      }
      final rawChanges = decoded['changes'] as List;
      if (rawChanges.isEmpty || rawChanges.length > maxManifestChanges) {
        throw const FormatException(
          'Moltbook public change manifest exceeds its limit',
        );
      }

      final manifestChanges =
          <
            ({
              String sourceId,
              String category,
              List<String> facts,
              String commitment,
            })
          >[];
      final sourceIds = <String>{};
      for (final value in rawChanges) {
        if (value is! Map ||
            value.length != 3 ||
            value['source_id'] is! String ||
            value['category'] is! String ||
            value['facts'] is! List ||
            (value['facts'] as List).any((fact) => fact is! String)) {
          throw const FormatException(
            'Invalid Moltbook public change manifest entry',
          );
        }
        final sourceId = (value['source_id'] as String).trim();
        final category = (value['category'] as String).trim();
        final facts = (value['facts'] as List)
            .cast<String>()
            .map((fact) => fact.trim())
            .toList(growable: false);
        final commitment = commitmentFor(
          sourceId: sourceId,
          category: category,
          facts: facts,
        );
        validate(
          MoltbookPublicChange(
            sourceId: sourceId,
            category: category,
            facts: facts,
            commitmentHashHex: commitment,
            recordedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
        if (!sourceIds.add(sourceId)) {
          throw const FormatException(
            'Moltbook public change manifest repeats a source id',
          );
        }
        manifestChanges.add((
          sourceId: sourceId,
          category: category,
          facts: facts,
          commitment: commitment,
        ));
      }

      final changes = await _loadForOwner(ownerHex);
      final bySource = <String, MoltbookPublicChange>{
        for (final change in changes) change.sourceId: change,
      };
      final inserted = <MoltbookPublicChange>[];
      for (final manifestChange in manifestChanges) {
        if (!allowedTopics.contains(manifestChange.category)) continue;
        final existing = bySource[manifestChange.sourceId];
        if (existing != null) {
          if (existing.commitmentHashHex != manifestChange.commitment) {
            throw StateError(
              'Public change source id is already bound to different facts',
            );
          }
          continue;
        }
        final change = MoltbookPublicChange(
          sourceId: manifestChange.sourceId,
          category: manifestChange.category,
          facts: List<String>.unmodifiable(manifestChange.facts),
          commitmentHashHex: manifestChange.commitment,
          recordedAtUtc: DateTime.now().toUtc(),
        );
        changes.add(change);
        bySource[change.sourceId] = change;
        inserted.add(change);
      }
      if (inserted.isEmpty) return const <MoltbookPublicChange>[];
      if (changes.length > maxChanges) {
        changes.removeRange(0, changes.length - maxChanges);
      }
      await _writeForOwner(ownerHex, changes);
      return List<MoltbookPublicChange>.unmodifiable(inserted);
    });
  }

  Future<void> markDrafted(String commitmentHashHex, String draftHashHex) {
    return _serialized(() async {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(draftHashHex)) {
        throw ArgumentError('Draft hash is invalid');
      }
      final ownerHex = _requireOwnerHex();
      final changes = await _loadForOwner(ownerHex);
      final index = changes.indexWhere(
        (change) => change.commitmentHashHex == commitmentHashHex,
      );
      if (index < 0) throw StateError('Public change is unavailable');
      final current = changes[index];
      if (current.draftHashHex != null &&
          current.draftHashHex != draftHashHex) {
        throw StateError('Public change is already bound to another draft');
      }
      changes[index] = MoltbookPublicChange(
        sourceId: current.sourceId,
        category: current.category,
        facts: current.facts,
        commitmentHashHex: current.commitmentHashHex,
        recordedAtUtc: current.recordedAtUtc,
        draftHashHex: draftHashHex,
      );
      await _writeForOwner(ownerHex, changes);
    });
  }

  static String commitmentFor({
    required String sourceId,
    required String category,
    required List<String> facts,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'contract': 'hivra.moltbook.public_change.v1',
      'source_id': sourceId,
      'category': category,
      'facts': facts,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static void validate(MoltbookPublicChange change) {
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,128}$').hasMatch(change.sourceId) ||
        !RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(change.category) ||
        change.facts.isEmpty ||
        change.facts.length > maxFacts ||
        change.facts.toSet().length != change.facts.length ||
        change.facts.any(
          (fact) =>
              fact.isEmpty ||
              fact.length > maxFactCharacters ||
              fact.trim() != fact ||
              _containsSensitivePublicMaterial(fact),
        ) ||
        commitmentFor(
              sourceId: change.sourceId,
              category: change.category,
              facts: change.facts,
            ) !=
            change.commitmentHashHex ||
        (change.draftHashHex != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(change.draftHashHex!))) {
      throw const FormatException('Malformed Moltbook public change');
    }
  }

  static bool _containsSensitivePublicMaterial(String value) {
    return RegExp(
          r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
          caseSensitive: false,
        ).hasMatch(value) ||
        RegExp(
          r'\b(?:api[_ -]?(?:key|secret)|password|seed(?: phrase)?|private[_ -]?key)\s*[:=]\s*\S+',
          caseSensitive: false,
        ).hasMatch(value) ||
        RegExp(
          r'\b(?:sk-[A-Za-z0-9_-]{16,}|AIza[A-Za-z0-9_-]{20,})\b',
        ).hasMatch(value) ||
        RegExp(r'\b[0-9a-fA-F]{64,}\b').hasMatch(value) ||
        RegExp(r'\bh1[a-z0-9]{20,}\b', caseSensitive: false).hasMatch(value);
  }

  Future<List<MoltbookPublicChange>> _loadForOwner(String ownerHex) async {
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
    if (raw == null) return <MoltbookPublicChange>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schema_version'] != 1 ||
        decoded['plugin_id'] != moltbookAmbassadorPluginId ||
        decoded['changes'] is! List) {
      throw const FormatException('Invalid Moltbook public change feed');
    }
    final changes =
        (decoded['changes'] as List).map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid public change entry');
          }
          return MoltbookPublicChange.fromJson(
            Map<String, dynamic>.from(value),
          );
        }).toList();
    if (changes.length > maxChanges) {
      throw const FormatException(
        'Moltbook public change feed exceeds its limit',
      );
    }
    return changes;
  }

  Future<void> _writeForOwner(
    String ownerHex,
    List<MoltbookPublicChange> changes,
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
        'changes': changes.map((change) => change.toJson()).toList(),
      }),
    );
    _ensureOwner(ownerHex);
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
        'Active capsule changed during public change persistence',
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
