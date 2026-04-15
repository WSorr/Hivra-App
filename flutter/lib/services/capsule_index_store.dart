import 'dart:convert';
import 'dart:io';

import 'capsule_persistence_models.dart';
import 'user_visible_data_directory_service.dart';

class CapsulesIndex {
  String? activePubKeyHex;
  final Map<String, CapsuleIndexEntry> capsules;

  CapsulesIndex({
    required this.activePubKeyHex,
    required this.capsules,
  });
}

class CapsuleIndexStore {
  static const String _indexFileName = 'capsules_index.json';
  final UserVisibleDataDirectoryService _dirs;

  const CapsuleIndexStore({UserVisibleDataDirectoryService? dirs})
      : _dirs = dirs ?? const UserVisibleDataDirectoryService();

  Future<CapsulesIndex> read() async {
    final capsulesRoot = await _dirs.capsulesDirectory(create: false);
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    CapsulesIndex index;
    if (!await indexFile.exists()) {
      index = CapsulesIndex(activePubKeyHex: null, capsules: {});
    } else {
      try {
        final raw = await indexFile.readAsString();
        index = _fromJson(raw);
      } catch (_) {
        index = CapsulesIndex(activePubKeyHex: null, capsules: {});
      }
    }

    final repaired = await _repairFromCapsuleDirectories(index, capsulesRoot);
    if (!_sameIndexState(index, repaired)) {
      await write(repaired);
    }
    return repaired;
  }

  Future<void> write(CapsulesIndex index) async {
    final capsulesRoot = await _dirs.capsulesDirectory(create: true);
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    await indexFile.writeAsString(_toJson(index), flush: true);
  }

  Future<void> setActive(String pubKeyHex) async {
    final index = await read();
    index.activePubKeyHex = pubKeyHex;
    await write(index);
  }

  Future<void> upsert(
    String pubKeyHex, {
    bool? isGenesis,
    bool? isNeste,
    String? identityMode,
  }) async {
    final index = await read();
    final now = DateTime.now().toUtc();
    final existing = index.capsules[pubKeyHex];
    index.capsules[pubKeyHex] = CapsuleIndexEntry(
      pubKeyHex: pubKeyHex,
      createdAt: existing?.createdAt ?? now,
      lastActive: now,
      isGenesis: isGenesis ?? existing?.isGenesis ?? false,
      isNeste: isNeste ?? existing?.isNeste ?? true,
      identityMode: identityMode ?? existing?.identityMode ?? 'root_owner',
    );
    await write(index);
  }

  CapsulesIndex _fromJson(String raw) {
    final map = _parseJsonMap(raw);
    if (map == null) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }
    final active = map['active']?.toString();
    final capsulesMap = <String, CapsuleIndexEntry>{};
    final items = _coerceJsonMap(map['capsules']);
    if (items != null) {
      for (final entry in items.entries) {
        final entryMap = _coerceJsonMap(entry.value);
        if (entryMap != null) {
          capsulesMap[entry.key] = CapsuleIndexEntry.fromMap(entryMap);
        }
      }
    }
    final normalizedActive =
        active != null && capsulesMap.containsKey(active) ? active : null;
    return CapsulesIndex(
      activePubKeyHex: normalizedActive,
      capsules: capsulesMap,
    );
  }

  String _toJson(CapsulesIndex index) {
    final capsulesJson = <String, dynamic>{};
    for (final entry in index.capsules.entries) {
      capsulesJson[entry.key] = entry.value.toMap();
    }
    return jsonEncode({
      'active': index.activePubKeyHex,
      'capsules': capsulesJson,
    });
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      return _coerceJsonMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _coerceJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<CapsulesIndex> _repairFromCapsuleDirectories(
    CapsulesIndex index,
    Directory capsulesRoot,
  ) async {
    if (!await capsulesRoot.exists()) return index;

    final capsules = Map<String, CapsuleIndexEntry>.from(index.capsules);
    await for (final entity in capsulesRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final segments = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.isEmpty) continue;
      final pubKeyHex = segments.last;
      if (!_isPubKeyHex(pubKeyHex)) continue;
      if (capsules.containsKey(pubKeyHex)) continue;
      capsules[pubKeyHex] = await _synthesizeEntry(pubKeyHex, entity);
    }

    var active = index.activePubKeyHex;
    if (active != null && !capsules.containsKey(active)) {
      active = null;
    }

    return CapsulesIndex(activePubKeyHex: active, capsules: capsules);
  }

  Future<CapsuleIndexEntry> _synthesizeEntry(
    String pubKeyHex,
    Directory capsuleDir,
  ) async {
    final now = DateTime.now().toUtc();
    var timestamp = now;
    try {
      final stat = await capsuleDir.stat();
      timestamp = stat.modified.toUtc();
    } catch (_) {}

    var isGenesis = false;
    var isNeste = true;
    var identityMode = 'root_owner';
    final stateFile = File('${capsuleDir.path}/capsule_state.json');
    if (await stateFile.exists()) {
      try {
        final raw = await stateFile.readAsString();
        final state = _parseJsonMap(raw);
        if (state != null) {
          isGenesis = state['isGenesis'] == true;
          isNeste = state['isNeste'] != false;
          identityMode = state['identityMode']?.toString() ?? identityMode;
        }
      } catch (_) {}
    }

    return CapsuleIndexEntry(
      pubKeyHex: pubKeyHex,
      createdAt: timestamp,
      lastActive: timestamp,
      isGenesis: isGenesis,
      isNeste: isNeste,
      identityMode: identityMode,
    );
  }

  bool _isPubKeyHex(String value) {
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  }

  bool _sameIndexState(CapsulesIndex a, CapsulesIndex b) {
    if (a.activePubKeyHex != b.activePubKeyHex) return false;
    if (a.capsules.length != b.capsules.length) return false;
    for (final entry in a.capsules.entries) {
      final other = b.capsules[entry.key];
      if (other == null) return false;
      if (entry.value.pubKeyHex != other.pubKeyHex) return false;
      if (entry.value.createdAt != other.createdAt) return false;
      if (entry.value.lastActive != other.lastActive) return false;
      if (entry.value.isGenesis != other.isGenesis) return false;
      if (entry.value.isNeste != other.isNeste) return false;
      if (entry.value.identityMode != other.identityMode) return false;
    }
    return true;
  }
}
