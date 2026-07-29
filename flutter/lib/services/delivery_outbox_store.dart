import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capsule_file_store.dart';

const int deliveryOutboxSchemaVersion = 3;

enum DeliveryOutboxStatus {
  pending,

  /// At least one relay accepted the envelope. This is not confirmation that
  /// the receiving capsule has fetched or acted on it. A published Nostr
  /// event is durable at the relay layer, so it is not retransmitted here.
  published,

  /// The referenced domain effect was resolved or superseded before it was
  /// published. Keeping the audit record prevents a legacy retry from
  /// resurrecting it.
  superseded,

  /// Legacy retry-exhausted state. New builds never write this state: core
  /// facts must remain recoverable across temporary transport failures.
  dead,
}

class DeliveryOutboxItem {
  final String id;
  final String capsuleHex;
  final String transport;
  final String kind;
  final String reason;

  /// Immutable ledger fact identity, when the transport envelope has one.
  /// Invitation delivery uses its invitation_id; it prevents unrelated
  /// pending facts from sharing a retry record.
  final String? deliveryReference;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final int attempts;
  final DeliveryOutboxStatus status;
  final String? lastError;

  const DeliveryOutboxItem({
    required this.id,
    required this.capsuleHex,
    required this.transport,
    required this.kind,
    required this.reason,
    this.deliveryReference,
    required this.createdAt,
    required this.nextAttemptAt,
    required this.attempts,
    required this.status,
    this.lastError,
  });

  DeliveryOutboxItem copyWith({
    DateTime? nextAttemptAt,
    int? attempts,
    DeliveryOutboxStatus? status,
    String? lastError,
    bool clearLastError = false,
  }) {
    return DeliveryOutboxItem(
      id: id,
      capsuleHex: capsuleHex,
      transport: transport,
      kind: kind,
      reason: reason,
      deliveryReference: deliveryReference,
      createdAt: createdAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'capsule_hex': capsuleHex,
      'transport': transport,
      'kind': kind,
      'reason': reason,
      'delivery_reference': deliveryReference,
      'created_at': createdAt.toUtc().toIso8601String(),
      'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
      'attempts': attempts,
      'status': status.name,
      'last_error': lastError,
    };
  }

  static DeliveryOutboxItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString().trim() ?? '';
    final capsuleHex =
        map['capsule_hex']?.toString().trim().toLowerCase() ?? '';
    final transport = map['transport']?.toString().trim() ?? '';
    final kind = map['kind']?.toString().trim() ?? '';
    final reason = map['reason']?.toString().trim() ?? '';
    final deliveryReference = DeliveryOutboxStore._normalizeDeliveryReference(
      map['delivery_reference']?.toString(),
    );
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    final nextAttemptAt = DateTime.tryParse(
      map['next_attempt_at']?.toString() ?? '',
    );
    final attempts = map['attempts'];
    final persistedStatus = map['status']?.toString();
    // Schema v1 used `delivered` for a single relay acknowledgement. Keep
    // those records recoverable, but do not misrepresent them as receiver
    // delivery in newer builds.
    final status =
        persistedStatus == 'delivered'
            ? DeliveryOutboxStatus.published
            // v2 incorrectly made a locally committed core fact terminal
            // after a fixed number of relay retries. Recover it on the next
            // delivery pump instead of losing the fact forever.
            : persistedStatus == 'dead'
            ? DeliveryOutboxStatus.pending
            : DeliveryOutboxStatus.values
                .where((value) => value.name == persistedStatus)
                .firstOrNull;
    if (id.isEmpty ||
        capsuleHex.isEmpty ||
        transport.isEmpty ||
        kind.isEmpty ||
        reason.isEmpty ||
        createdAt == null ||
        nextAttemptAt == null ||
        attempts is! int ||
        attempts < 0 ||
        status == null) {
      return null;
    }
    return DeliveryOutboxItem(
      id: id,
      capsuleHex: capsuleHex,
      transport: transport,
      kind: kind,
      reason: reason,
      deliveryReference: deliveryReference,
      createdAt: createdAt.toUtc(),
      nextAttemptAt: nextAttemptAt.toUtc(),
      attempts: attempts,
      status: status,
      lastError: map['last_error']?.toString(),
    );
  }
}

class DeliveryOutboxStore {
  final CapsuleFileStore _fileStore;

  const DeliveryOutboxStore({
    CapsuleFileStore fileStore = const CapsuleFileStore(),
  }) : _fileStore = fileStore;

  Future<List<DeliveryOutboxItem>> load(String capsuleHex) async {
    final dir = await _fileStore.capsuleDirForHex(capsuleHex, create: true);
    final raw = await _fileStore.readDeliveryOutbox(dir);
    if (raw == null) return const <DeliveryOutboxItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <DeliveryOutboxItem>[];
      final items = decoded['items'];
      if (items is! List) return const <DeliveryOutboxItem>[];
      return items
          .map(DeliveryOutboxItem.fromJson)
          .whereType<DeliveryOutboxItem>()
          .toList(growable: false);
    } catch (_) {
      return const <DeliveryOutboxItem>[];
    }
  }

  Future<void> enqueue({
    required String capsuleHex,
    required String transport,
    required String kind,
    required String reason,
    String? deliveryReference,
    required DateTime now,
  }) async {
    final normalizedCapsuleHex = capsuleHex.trim().toLowerCase();
    if (normalizedCapsuleHex.isEmpty) return;
    final id = _stableId(
      capsuleHex: normalizedCapsuleHex,
      transport: transport,
      kind: kind,
      reason: reason,
      deliveryReference: deliveryReference,
    );
    final items = await load(normalizedCapsuleHex);
    final next = <DeliveryOutboxItem>[];
    var inserted = false;
    for (final item in items) {
      if (item.id == id) {
        next.add(
          item.copyWith(
            status: DeliveryOutboxStatus.pending,
            nextAttemptAt: now.toUtc(),
            attempts: 0,
            clearLastError: true,
          ),
        );
        inserted = true;
      } else {
        next.add(item);
      }
    }
    if (!inserted) {
      next.add(
        DeliveryOutboxItem(
          id: id,
          capsuleHex: normalizedCapsuleHex,
          transport: transport,
          kind: kind,
          reason: reason,
          deliveryReference: _normalizeDeliveryReference(deliveryReference),
          createdAt: now.toUtc(),
          nextAttemptAt: now.toUtc(),
          attempts: 0,
          status: DeliveryOutboxStatus.pending,
        ),
      );
    }
    await _write(normalizedCapsuleHex, next);
  }

  /// Restores a missing delivery obligation without reviving an existing
  /// published or superseded record.
  Future<bool> enqueueIfAbsent({
    required String capsuleHex,
    required String transport,
    required String kind,
    required String reason,
    String? deliveryReference,
    required DateTime now,
  }) async {
    final normalizedCapsuleHex = capsuleHex.trim().toLowerCase();
    if (normalizedCapsuleHex.isEmpty) return false;
    final normalizedReference = _normalizeDeliveryReference(deliveryReference);
    final id = _stableId(
      capsuleHex: normalizedCapsuleHex,
      transport: transport,
      kind: kind,
      reason: reason,
      deliveryReference: normalizedReference,
    );
    final items = await load(normalizedCapsuleHex);
    if (items.any((item) => item.id == id)) return false;

    final next = <DeliveryOutboxItem>[
      ...items,
      DeliveryOutboxItem(
        id: id,
        capsuleHex: normalizedCapsuleHex,
        transport: transport,
        kind: kind,
        reason: reason,
        deliveryReference: normalizedReference,
        createdAt: now.toUtc(),
        nextAttemptAt: now.toUtc(),
        attempts: 0,
        status: DeliveryOutboxStatus.pending,
      ),
    ];
    await _write(normalizedCapsuleHex, next);
    return true;
  }

  Future<List<DeliveryOutboxItem>> due({
    required String capsuleHex,
    required DateTime now,
  }) async {
    final items = await load(capsuleHex);
    return items
        .where((item) {
          return item.status == DeliveryOutboxStatus.pending &&
              !item.nextAttemptAt.isAfter(now.toUtc());
        })
        .toList(growable: false);
  }

  Future<void> markAttempt({
    required String capsuleHex,
    required String itemId,
    required DateTime nextAttemptAt,
    String? lastError,
  }) async {
    final items = await load(capsuleHex);
    final next = items
        .map((item) {
          if (item.id != itemId) return item;
          return item.copyWith(
            attempts: item.attempts + 1,
            nextAttemptAt: nextAttemptAt.toUtc(),
            lastError: lastError,
            clearLastError: lastError == null,
          );
        })
        .toList(growable: false);
    await _write(capsuleHex, next);
  }

  Future<void> markPublished({
    required String capsuleHex,
    required String itemId,
    required DateTime nextAttemptAt,
  }) async {
    final items = await load(capsuleHex);
    final next = items
        .map((item) {
          if (item.id != itemId) return item;
          return item.copyWith(
            status: DeliveryOutboxStatus.published,
            attempts: item.attempts + 1,
            nextAttemptAt: nextAttemptAt.toUtc(),
            clearLastError: true,
          );
        })
        .toList(growable: false);
    await _write(capsuleHex, next);
  }

  Future<void> markSuperseded({
    required String capsuleHex,
    required String itemId,
  }) async {
    final items = await load(capsuleHex);
    final next = items
        .map((item) {
          if (item.id != itemId) return item;
          return item.copyWith(
            status: DeliveryOutboxStatus.superseded,
            clearLastError: true,
          );
        })
        .toList(growable: false);
    await _write(capsuleHex, next);
  }

  Future<void> _write(String capsuleHex, List<DeliveryOutboxItem> items) async {
    final dir = await _fileStore.capsuleDirForHex(capsuleHex, create: true);
    final sorted = items.toList()..sort((a, b) => a.id.compareTo(b.id));
    final payload = <String, dynamic>{
      'schema_version': deliveryOutboxSchemaVersion,
      'items': sorted.map((item) => item.toJson()).toList(growable: false),
    };
    await _fileStore.writeDeliveryOutbox(dir, jsonEncode(payload));
  }

  String _stableId({
    required String capsuleHex,
    required String transport,
    required String kind,
    required String reason,
    String? deliveryReference,
  }) {
    final canonical = [
      capsuleHex.trim().toLowerCase(),
      transport.trim(),
      kind.trim(),
      reason.trim(),
      _normalizeDeliveryReference(deliveryReference) ?? '',
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String? _normalizeDeliveryReference(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }
}
