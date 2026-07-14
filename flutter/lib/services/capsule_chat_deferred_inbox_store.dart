import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capsule_file_store.dart';

const int capsuleChatDeferredInboxSchemaVersion = 1;
const int capsuleChatDeferredInboxMaxItems = 200;
const Duration capsuleChatDeferredInboxTtl = Duration(hours: 48);

class CapsuleChatDeferredInboxItem {
  final String id;
  final String capsuleHex;
  final String fromHex;
  final String payloadJson;
  final int timestampMs;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int attempts;

  const CapsuleChatDeferredInboxItem({
    required this.id,
    required this.capsuleHex,
    required this.fromHex,
    required this.payloadJson,
    required this.timestampMs,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.attempts,
  });

  CapsuleChatDeferredInboxItem copyWith({
    DateTime? lastSeenAt,
    int? attempts,
  }) {
    return CapsuleChatDeferredInboxItem(
      id: id,
      capsuleHex: capsuleHex,
      fromHex: fromHex,
      payloadJson: payloadJson,
      timestampMs: timestampMs,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'capsule_hex': capsuleHex,
      'from_hex': fromHex,
      'payload_json': payloadJson,
      'timestamp_ms': timestampMs,
      'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
      'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
      'attempts': attempts,
    };
  }

  static CapsuleChatDeferredInboxItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString().trim().toLowerCase() ?? '';
    final capsuleHex =
        map['capsule_hex']?.toString().trim().toLowerCase() ?? '';
    final fromHex = map['from_hex']?.toString().trim().toLowerCase() ?? '';
    final payloadJson = map['payload_json']?.toString() ?? '';
    final timestampMs = map['timestamp_ms'];
    final firstSeenAt =
        DateTime.tryParse(map['first_seen_at']?.toString() ?? '');
    final lastSeenAt = DateTime.tryParse(map['last_seen_at']?.toString() ?? '');
    final attempts = map['attempts'];
    if (!_isHex64(id) ||
        !_isHex64(capsuleHex) ||
        !_isHex64(fromHex) ||
        payloadJson.isEmpty ||
        timestampMs is! int ||
        firstSeenAt == null ||
        lastSeenAt == null ||
        attempts is! int ||
        attempts < 0) {
      return null;
    }
    return CapsuleChatDeferredInboxItem(
      id: id,
      capsuleHex: capsuleHex,
      fromHex: fromHex,
      payloadJson: payloadJson,
      timestampMs: timestampMs,
      firstSeenAt: firstSeenAt.toUtc(),
      lastSeenAt: lastSeenAt.toUtc(),
      attempts: attempts,
    );
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

class CapsuleChatDeferredInboxStore {
  final CapsuleFileStore _fileStore;

  const CapsuleChatDeferredInboxStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
  }) : _fileStore = fileStore;

  Future<List<CapsuleChatDeferredInboxItem>> load(String capsuleHex) async {
    final normalized = capsuleHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return const <CapsuleChatDeferredInboxItem>[];
    final dir = await _fileStore.capsuleDirForHex(normalized, create: true);
    final raw = await _fileStore.readChatDeferredInbox(dir);
    if (raw == null) return const <CapsuleChatDeferredInboxItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <CapsuleChatDeferredInboxItem>[];
      final items = decoded['items'];
      if (items is! List) return const <CapsuleChatDeferredInboxItem>[];
      return items
          .map(CapsuleChatDeferredInboxItem.fromJson)
          .whereType<CapsuleChatDeferredInboxItem>()
          .where((item) => item.capsuleHex == normalized)
          .toList(growable: false);
    } catch (_) {
      return const <CapsuleChatDeferredInboxItem>[];
    }
  }

  Future<void> upsertMany({
    required String capsuleHex,
    required Iterable<CapsuleChatDeferredInboxItem> items,
    required DateTime now,
  }) async {
    final normalized = capsuleHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    final existing = <String, CapsuleChatDeferredInboxItem>{
      for (final item in await load(normalized)) item.id: item,
    };
    final nowUtc = now.toUtc();
    for (final item in items) {
      if (item.capsuleHex != normalized) continue;
      final previous = existing[item.id];
      existing[item.id] = previous == null
          ? item
          : previous.copyWith(
              lastSeenAt: nowUtc,
              attempts: previous.attempts + 1,
            );
    }
    await _write(normalized, _pruned(existing.values, nowUtc));
  }

  Future<void> replaceAll({
    required String capsuleHex,
    required Iterable<CapsuleChatDeferredInboxItem> items,
    required DateTime now,
  }) async {
    final normalized = capsuleHex.trim().toLowerCase();
    if (!_isHex64(normalized)) return;
    await _write(normalized, _pruned(items, now.toUtc()));
  }

  CapsuleChatDeferredInboxItem create({
    required String capsuleHex,
    required String fromHex,
    required String payloadJson,
    required int timestampMs,
    required DateTime now,
  }) {
    final normalizedCapsule = capsuleHex.trim().toLowerCase();
    final normalizedFrom = fromHex.trim().toLowerCase();
    final id = stableId(
      capsuleHex: normalizedCapsule,
      fromHex: normalizedFrom,
      payloadJson: payloadJson,
      timestampMs: timestampMs,
    );
    final nowUtc = now.toUtc();
    return CapsuleChatDeferredInboxItem(
      id: id,
      capsuleHex: normalizedCapsule,
      fromHex: normalizedFrom,
      payloadJson: payloadJson,
      timestampMs: timestampMs,
      firstSeenAt: nowUtc,
      lastSeenAt: nowUtc,
      attempts: 0,
    );
  }

  static String stableId({
    required String capsuleHex,
    required String fromHex,
    required String payloadJson,
    required int timestampMs,
  }) {
    final canonical = [
      capsuleHex.trim().toLowerCase(),
      fromHex.trim().toLowerCase(),
      timestampMs,
      payloadJson,
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<void> _write(
    String capsuleHex,
    Iterable<CapsuleChatDeferredInboxItem> items,
  ) async {
    final dir = await _fileStore.capsuleDirForHex(capsuleHex, create: true);
    final sorted = items.toList()..sort((a, b) => a.id.compareTo(b.id));
    final payload = <String, dynamic>{
      'schema_version': capsuleChatDeferredInboxSchemaVersion,
      'items': sorted.map((item) => item.toJson()).toList(growable: false),
    };
    await _fileStore.writeChatDeferredInbox(dir, jsonEncode(payload));
  }

  List<CapsuleChatDeferredInboxItem> _pruned(
    Iterable<CapsuleChatDeferredInboxItem> items,
    DateTime now,
  ) {
    final cutoff = now.toUtc().subtract(capsuleChatDeferredInboxTtl);
    final fresh = items
        .where((item) => !item.firstSeenAt.isBefore(cutoff))
        .toList(growable: false)
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return fresh.take(capsuleChatDeferredInboxMaxItems).toList(growable: false);
  }

  static bool _isHex64(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
