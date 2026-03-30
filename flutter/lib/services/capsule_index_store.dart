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
    if (!await indexFile.exists()) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }

    try {
      final raw = await indexFile.readAsString();
      return _fromJson(raw);
    } catch (_) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }
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
}
