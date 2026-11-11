import 'dart:convert';
import 'dart:io';

import 'capsule_file_store.dart';

/// User-owned display names. They are local metadata, never contact-card,
/// ledger, consensus, or transport data.
class CapsuleContactLabelStore {
  static const int _schemaVersion = 1;
  static final Map<String, Future<void>> _writes = {};

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
    return _load(dir);
  }

  Future<Map<String, String>> _load(
    Directory dir, {
    bool forWrite = false,
  }) async {
    final raw = await _fileStore.readContactLabels(dir);
    if (raw == null) {
      if (forWrite && await _fileStore.contactLabelsFile(dir).exists()) {
        throw const FormatException('Saved contact names are unreadable');
      }
      return const <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        throw const FormatException('Saved contact names are unreadable');
      }
      final labels = decoded['labels'];
      if (labels is! Map) {
        throw const FormatException('Saved contact names are unreadable');
      }
      final result = <String, String>{};
      for (final entry in labels.entries) {
        if (forWrite && entry.value is! String) {
          throw const FormatException('Saved contact names are unreadable');
        }
        final peerKey = entry.key.toString().trim().toLowerCase();
        final label = entry.value.toString().trim();
        if (_isCapsuleKey(peerKey) && label.isNotEmpty) {
          result[peerKey] = label;
        }
      }
      if (forWrite && result.length != labels.length) {
        throw const FormatException('Saved contact names are unreadable');
      }
      return result;
    } catch (_) {
      if (forWrite) rethrow;
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
    final dir = await _fileStore.capsuleDirForHex(ownerHex, create: true);
    // Serialize the whole read/modify/write, including across store instances.
    final path = _fileStore.contactLabelsFile(dir).absolute.path;
    final operation = (_writes[path] ?? Future<void>.value()).then((_) async {
      final labels = Map<String, String>.from(await _load(dir, forWrite: true));
      if (normalizedLabel.isEmpty) {
        labels.remove(peerKey);
      } else {
        labels[peerKey] = normalizedLabel;
      }
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
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _writes[path] = tail;
    return operation.whenComplete(() {
      if (identical(_writes[path], tail)) _writes.remove(path);
    });
  }

  String? _activeOwnerHex() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }

  bool _isCapsuleKey(String value) => RegExp(r'^h1[0-9a-z]+$').hasMatch(value);
}
