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

typedef CapsuleDeliveryRetryRunner = Future<CapsuleDeliveryCycleResult>
    Function(String capsuleHex);
typedef CapsuleDeliveryNow = DateTime Function();

/// Owns persistent delivery recovery for one capsule.
///
/// The Ledger remains the source of domain truth. The outbox only records that
/// a locally committed transport side-effect still needs relay delivery. This
/// service is the sole owner of retry timing and receipt-to-outbox
/// reconciliation.
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
  })  : _retryRunner = retryRunner,
        _outbox = outbox,
        _now = now,
        _retryDelays = List<Duration>.unmodifiable(retryDelays);

  static DateTime _utcNow() => DateTime.now().toUtc();

  Future<void> enqueue({
    required String? capsuleHex,
    required String kind,
    required String reason,
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null) return;
    await _outbox.enqueue(
      capsuleHex: normalized,
      transport: DeliveryTransportId.nostr,
      kind: kind,
      reason: reason,
      now: _now(),
    );
    scheduleDuePump(capsuleHex: normalized);
  }

  Future<void> recordCycle({
    required String? capsuleHex,
    required CapsuleDeliveryCycleResult result,
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (normalized == null) return;
    final now = _now();
    final dueItems = await _outbox.due(capsuleHex: normalized, now: now);
    for (final item in dueItems) {
      if (_receiptsContainItem(result.deliveryReceiptsJson, item)) {
        await _outbox.markDelivered(capsuleHex: normalized, itemId: item.id);
        continue;
      }
      await _outbox.markAttempt(
        capsuleHex: normalized,
        itemId: item.id,
        nextAttemptAt: now.add(_backoffFor(item.attempts + 1)),
        lastError: result.code >= 0 ? null : result.lastError,
      );
    }
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
    final result = await _retryRunner(normalized);
    await recordCycle(capsuleHex: normalized, result: result);
    return result;
  }

  Future<void> _runPump(String capsuleHex) async {
    for (final delay in _retryDelays) {
      await Future<void>.delayed(delay);
      final result = await pumpDueNow(capsuleHex: capsuleHex);
      if (result == null) return;
    }
  }

  Duration _backoffFor(int attempts) {
    if (_retryDelays.isEmpty) return Duration.zero;
    final index = (attempts - 1).clamp(0, _retryDelays.length - 1);
    return _retryDelays[index];
  }

  bool _receiptsContainItem(
      String? deliveryReceiptsJson, DeliveryOutboxItem item) {
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
        if (_labelMatchesKind(raw['label']?.toString() ?? '', item.kind)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _labelMatchesKind(String label, String kind) {
    return switch (kind) {
      DeliveryOutboxKind.invitationSent =>
        label == 'InvitationSent' || label == 'InvitationSentRetry',
      DeliveryOutboxKind.invitationTerminal => label == 'InvitationAccepted' ||
          label == 'InvitationAcceptedRetry' ||
          label == 'InvitationRejected' ||
          label == 'InvitationRejectedRetry',
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
