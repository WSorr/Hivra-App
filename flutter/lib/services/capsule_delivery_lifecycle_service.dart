import 'dart:async';
import 'dart:convert';

import 'delivery_outbox_store.dart';
import 'delivery_transport_contract.dart';

/// Result of one transport cycle. It intentionally contains no UI state and
/// no ledger data: the owning use-case persists ledger facts before reporting.
class CapsuleDeliveryCycleResult {
  final int code;
  final String? lastError;
  final String? deliveryReceiptsJson;

  const CapsuleDeliveryCycleResult({
    required this.code,
    this.lastError,
    this.deliveryReceiptsJson,
  });
}

typedef CapsuleDeliveryRetryRunner =
    Future<CapsuleDeliveryCycleResult> Function(
      String capsuleHex,
      DeliveryOutboxItem item,
    );
typedef CapsuleDeliveryNow = DateTime Function();

/// Owns persistent delivery recovery for one capsule.
///
/// The Ledger remains the source of domain truth. The outbox only records that
/// a locally committed transport side-effect still needs relay delivery. This
/// service is the sole owner of relay propagation. A relay receipt is
/// publication evidence, not evidence that another capsule received a fact;
/// it owns relay receipt-to-outbox reconciliation. A temporary network
/// failure never makes a locally committed core fact terminal.
class CapsuleDeliveryLifecycleService {
  final DeliveryOutboxStore _outbox;
  final CapsuleDeliveryRetryRunner _retryRunner;
  final CapsuleDeliveryNow _now;
  final List<Duration> _retryDelays;
  final Map<String, Future<void>> _pumpsByCapsule = <String, Future<void>>{};

  CapsuleDeliveryLifecycleService({
    required CapsuleDeliveryRetryRunner retryRunner,
    DeliveryOutboxStore outbox = const DeliveryOutboxStore(),
    CapsuleDeliveryNow now = _utcNow,
    List<Duration> retryDelays = const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 20),
      Duration(seconds: 45),
      Duration(seconds: 90),
      Duration(minutes: 3),
    ],
  }) : _retryRunner = retryRunner,
       _outbox = outbox,
       _now = now,
       _retryDelays = List<Duration>.unmodifiable(retryDelays);

  static DateTime _utcNow() => DateTime.now().toUtc();

  Future<void> enqueue({
    required String? capsuleHex,
    required String kind,
    required String reason,
    String? deliveryReference,
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null) return;
    await _outbox.enqueue(
      capsuleHex: normalized,
      transport: DeliveryTransportId.nostr,
      kind: kind,
      reason: reason,
      deliveryReference: deliveryReference,
      now: _now(),
    );
    scheduleDuePump(capsuleHex: normalized);
  }

  Future<bool> ensureEnqueued({
    required String? capsuleHex,
    required String kind,
    required String reason,
    String? deliveryReference,
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null) return false;
    final inserted = await _outbox.enqueueIfAbsent(
      capsuleHex: normalized,
      transport: DeliveryTransportId.nostr,
      kind: kind,
      reason: reason,
      deliveryReference: deliveryReference,
      now: _now(),
    );
    if (inserted) scheduleDuePump(capsuleHex: normalized);
    return inserted;
  }

  Future<void> _recordItemCycle({
    required String capsuleHex,
    required DeliveryOutboxItem item,
    required CapsuleDeliveryCycleResult result,
  }) async {
    final now = _now();
    if (_receiptsContainItem(result.deliveryReceiptsJson, item)) {
      await _outbox.markPublished(
        capsuleHex: capsuleHex,
        itemId: item.id,
        nextAttemptAt: now.add(_backoffFor(item.attempts + 1)),
      );
      return;
    }
    // Exact retry endpoints return success with no receipt only when their
    // referenced fact is no longer deliverable (for example, an invitation
    // was resolved before its offer was published). Preserve that audit fact
    // without allowing a later pump to resurrect it.
    if (result.code >= 0 && !_hasAnyReceipt(result.deliveryReceiptsJson)) {
      await _outbox.markSuperseded(capsuleHex: capsuleHex, itemId: item.id);
      return;
    }
    if (result.code >= 0) return;
    await _outbox.markAttempt(
      capsuleHex: capsuleHex,
      itemId: item.id,
      nextAttemptAt: now.add(_backoffFor(item.attempts + 1)),
      lastError: result.lastError,
    );
  }

  void scheduleDuePump({required String? capsuleHex}) {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null || _pumpsByCapsule.containsKey(normalized)) return;

    final task = _runPump(normalized);
    _pumpsByCapsule[normalized] = task.catchError((_) {});
    unawaited(task.whenComplete(() => _pumpsByCapsule.remove(normalized)));
  }

  Future<CapsuleDeliveryCycleResult?> pumpDueNow({
    required String? capsuleHex,
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null) return null;
    final dueItems = await _outbox.due(capsuleHex: normalized, now: _now());
    if (dueItems.isEmpty) return null;
    CapsuleDeliveryCycleResult? lastResult;
    for (final item in dueItems) {
      final result = await _retryRunner(normalized, item);
      await _recordItemCycle(
        capsuleHex: normalized,
        item: item,
        result: result,
      );
      lastResult = result;
    }
    return lastResult;
  }

  Future<void> _runPump(String capsuleHex) async {
    // Enqueue callers commonly perform an immediate foreground send. Give it
    // the first backoff window before this background recovery pump starts,
    // so the same immutable fact is never sent concurrently twice.
    if (_retryDelays.isEmpty) return;
    await Future<void>.delayed(_retryDelays.first);
    while (true) {
      final result = await pumpDueNow(capsuleHex: capsuleHex);
      if (result == null) {
        final pending = await _outbox.due(
          capsuleHex: capsuleHex,
          now: DateTime.utc(9999),
        );
        if (pending.isEmpty) return;
        final nextAttempt = pending
            .map((item) => item.nextAttemptAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final wait = nextAttempt.difference(_now());
        await Future<void>.delayed(wait.isNegative ? Duration.zero : wait);
      }
    }
  }

  Duration _backoffFor(int attempts) {
    if (_retryDelays.isEmpty) return Duration.zero;
    final index = (attempts - 1).clamp(0, _retryDelays.length - 1);
    return _retryDelays[index];
  }

  bool _receiptsContainItem(
    String? deliveryReceiptsJson,
    DeliveryOutboxItem item,
  ) {
    if (deliveryReceiptsJson == null || deliveryReceiptsJson.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(deliveryReceiptsJson);
      if (decoded is! Map || decoded['receipts'] is! List) return false;
      for (final raw in decoded['receipts'] as List) {
        if (raw is! Map) continue;
        final receipt = raw['receipt'];
        if (receipt is! Map ||
            receipt['transport']?.toString() != item.transport) {
          continue;
        }
        if (_labelMatchesKind(raw['label']?.toString() ?? '', item.kind) &&
            _referenceMatches(raw['correlation_id_hex']?.toString(), item)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _hasAnyReceipt(String? deliveryReceiptsJson) {
    if (deliveryReceiptsJson == null || deliveryReceiptsJson.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(deliveryReceiptsJson);
      return decoded is Map &&
          decoded['receipts'] is List &&
          (decoded['receipts'] as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _referenceMatches(String? receiptReference, DeliveryOutboxItem item) {
    final expected = item.deliveryReference;
    // Legacy v1 entries did not retain an event reference. Keep them
    // recoverable, while v2 entries require an exact immutable match.
    if (expected == null) return true;
    return receiptReference?.trim().toLowerCase() == expected;
  }

  bool _labelMatchesKind(String label, String kind) {
    return switch (kind) {
      DeliveryOutboxKind.invitationSent =>
        label == 'InvitationSent' || label == 'InvitationSentRetry',
      DeliveryOutboxKind.invitationTerminal =>
        label == 'InvitationAccepted' ||
            label == 'InvitationAcceptedRetry' ||
            label == 'InvitationRejected' ||
            label == 'InvitationRejectedRetry' ||
            label == 'InvitationExpired' ||
            label == 'InvitationExpiredRetry',
      DeliveryOutboxKind.relationshipBroken =>
        label == 'RelationshipBroken' || label == 'RelationshipBrokenRetry',
      _ => false,
    };
  }

  String? _normalizeCapsuleHex(String? capsuleHex) {
    final normalized = capsuleHex?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
