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
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }
    final map = Map<String, dynamic>.from(decoded);
    final active = map['active']?.toString();
    final capsulesMap = <String, CapsuleIndexEntry>{};
    final list = map['capsules'];
    if (list is Map) {
      final items = Map<String, dynamic>.from(list);
      for (final entry in items.entries) {
        if (entry.value is Map) {
          capsulesMap[entry.key] =
              CapsuleIndexEntry.fromMap(Map<String, dynamic>.from(entry.value));
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
}
