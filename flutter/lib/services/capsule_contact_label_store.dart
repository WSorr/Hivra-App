import 'dart:convert';

import 'capsule_file_store.dart';

/// User-owned display names. They are local metadata, never contact-card,
/// ledger, consensus, or transport data.
class CapsuleContactLabelStore {
  static const int _schemaVersion = 1;

  final CapsuleFileStore _fileStore;
  final String? Function() _readActiveCapsuleRootHex;

  const CapsuleContactLabelStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    required String? Function() readActiveCapsuleRootHex,
  }) : _fileStore = fileStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  Future<Map<String, String>> load() async {
    final ownerHex = _activeOwnerHex();
    if (ownerHex == null) return const <String, String>{};
    final dir = await _fileStore.capsuleDirForHex(ownerHex, create: true);
    final raw = await _fileStore.readContactLabels(dir);
    if (raw == null) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        return const <String, String>{};
      }
      final labels = decoded['labels'];
      if (labels is! Map) return const <String, String>{};
      final result = <String, String>{};
      for (final entry in labels.entries) {
        final peerKey = entry.key.toString().trim().toLowerCase();
        final label = entry.value.toString().trim();
        if (_isCapsuleKey(peerKey) && label.isNotEmpty) {
          result[peerKey] = label;
        }
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> save({
    required String peerRootKey,
    required String label,
  }) async {
    final ownerHex = _activeOwnerHex();
    final peerKey = peerRootKey.trim().toLowerCase();
    if (ownerHex == null || !_isCapsuleKey(peerKey)) return;
    final normalizedLabel = label.trim();
    if (normalizedLabel.length > 64) {
      throw ArgumentError('Contact name must be at most 64 characters');
    }
    final labels = Map<String, String>.from(await load());
    if (normalizedLabel.isEmpty) {
      labels.remove(peerKey);
    } else {
      labels[peerKey] = normalizedLabel;
    }
    final dir = await _fileStore.capsuleDirForHex(ownerHex, create: true);
    final ordered = Map<String, String>.fromEntries(
      labels.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
    await _fileStore.writeContactLabels(
      dir,
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'version': _schemaVersion,
        'labels': ordered,
      }),
    );
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }

  bool _isCapsuleKey(String value) => RegExp(r'^h1[0-9a-z]+$').hasMatch(value);
}
