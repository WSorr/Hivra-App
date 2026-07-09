import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/invitation_actions_runtime.dart';
import 'delivery_outbox_store.dart';
import 'delivery_transport_contract.dart';

// Keep invitation actions responsive under unstable transport.
// Local truth is still protected by ledger projection + retry pumps.
const Duration _sendWorkerTimeout = Duration(seconds: 20);
// Full receive path can spend up to:
// - relay reconnect wait (up to transport timeout)
// - fetch_events timeout (up to transport timeout)
// so worker budget must exceed roughly 2x transport timeout.
const Duration _receiveWorkerTimeout = Duration(seconds: 30);
// Quick receive is a best-effort fast path. Keep timeout short so it does not
// block user-initiated invitation actions behind long background polls.
// In practice quick transport can still take reconnect + fetch cycle (~16s),
// so keep this below full receive but above that combined budget.
const Duration _receiveQuickWorkerTimeout = Duration(seconds: 20);
const Duration _acceptWorkerTimeout = Duration(seconds: 35);
const Duration _rejectWorkerTimeout = Duration(seconds: 35);

class InvitationWorkerResult {
  final int code;
  final String? ledgerJson;
  final String? lastError;

  const InvitationWorkerResult({
    required this.code,
    this.ledgerJson,
    this.lastError,
  });

  bool get isSuccess => code == 0;
}

class InvitationActionsService {
  final InvitationActionsRuntime _runtime;
  final DeliveryOutboxStore _outboxStore;
  Future<void> _operationChain = Future<void>.value();
  static final Map<String, Future<void>> _pendingRetryPumpByCapsule =
      <String, Future<void>>{};

  InvitationActionsService({
    InvitationActionsRuntime? runtime,
    DeliveryOutboxStore outboxStore = const DeliveryOutboxStore(),
  })  : _runtime = runtime ?? HivraInvitationActionsRuntime(),
        _outboxStore = outboxStore;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationChain = _operationChain.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _persistWorkerLedgerForBootstrapCapsule({
    required String? bootstrapActiveHex,
    required String? ledgerJson,
  }) async {
    if (bootstrapActiveHex == null ||
        bootstrapActiveHex.isEmpty ||
        ledgerJson == null ||
        ledgerJson.isEmpty) {
      return;
    }
    await _runtime.persistLedgerSnapshotForCapsuleHex(
      bootstrapActiveHex,
      ledgerJson,
    );
  }

  Future<void> _applyWorkerLedgerResult({
    required String? bootstrapActiveHex,
    required String? ledgerJson,
  }) async {
    final activeNow = await _runtime.resolveActiveCapsuleHex();
    if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
      if (ledgerJson != null && ledgerJson.isNotEmpty) {
        await _persistWorkerLedgerForBootstrapCapsule(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
        );
      }
      // Do not re-bootstrap active runtime for non-active worker completions.
      // Persist worker ledger to its capsule storage and keep currently active
      // capsule runtime untouched to prevent cross-capsule UI drift.
      if (activeNow == null || activeNow.isEmpty) {
        final restored = await _runtime.bootstrapActiveCapsuleRuntime();
        debugPrint(
          '[InvitationActions] restored active runtime capsule after worker drift '
          'workerCapsule=${bootstrapActiveHex.isEmpty ? 'unknown' : bootstrapActiveHex} '
          'activeCapsule=${activeNow ?? 'none'} restored=$restored',
        );
      } else {
        debugPrint(
          '[InvitationActions] persisted worker ledger for non-active capsule '
          'workerCapsule=${bootstrapActiveHex.isEmpty ? 'unknown' : bootstrapActiveHex} '
          'activeCapsule=$activeNow',
        );
      }
      return;
    }
    if (ledgerJson == null || ledgerJson.isEmpty) {
      return;
    }
    await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
  }

  void _scheduleLateWorkerLedgerApply({
    required Future<Map<String, Object?>> workerFuture,
    required String? bootstrapActiveHex,
  }) {
    unawaited(
      workerFuture.then((lateResult) async {
        final lateCode = (lateResult['result'] as int?) ?? -1003;
        final lateLastError = (lateResult['lastError'] as String?)?.trim();
        final lateLedgerJson = lateResult['ledgerJson'] as String?;
        debugPrint(
          '[InvitationActions] late worker completion capsule=${bootstrapActiveHex ?? 'unknown'} code=$lateCode lastError=${lateLastError ?? '-'} ledger=${lateLedgerJson?.isNotEmpty == true ? 'yes' : 'no'}',
        );
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: lateLedgerJson,
        );
      }).catchError((error, stackTrace) {
        debugPrint(
          '[InvitationActions] late worker completion failed capsule=${bootstrapActiveHex ?? 'unknown'} error=$error',
        );
      }),
    );
  }

  Future<void> _recordOutboxTransportCycle({
    required String? capsuleHex,
    required int code,
    required String? lastError,
    required String? deliveryReceiptsJson,
  }) async {
    final normalizedCapsuleHex = capsuleHex?.trim().toLowerCase();
    if (normalizedCapsuleHex == null || normalizedCapsuleHex.isEmpty) return;
    final now = DateTime.now().toUtc();
    final dueItems = await _outboxStore.due(
      capsuleHex: normalizedCapsuleHex,
      now: now,
    );
    if (dueItems.isEmpty) return;
    for (final item in dueItems) {
      if (_deliveryReceiptsContainItem(
        deliveryReceiptsJson: deliveryReceiptsJson,
        item: item,
      )) {
        await _outboxStore.markDelivered(
          capsuleHex: normalizedCapsuleHex,
          itemId: item.id,
        );
        continue;
      }
      await _outboxStore.markAttempt(
        capsuleHex: normalizedCapsuleHex,
        itemId: item.id,
        nextAttemptAt: now.add(_retryBackoffForAttempt(item.attempts + 1)),
        lastError: code >= 0 ? null : lastError,
      );
    }
  }

  bool _deliveryReceiptsContainItem({
    required String? deliveryReceiptsJson,
    required DeliveryOutboxItem item,
  }) {
    if (deliveryReceiptsJson == null || deliveryReceiptsJson.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(deliveryReceiptsJson);
      if (decoded is! Map) return false;
      final receipts = decoded['receipts'];
      if (receipts is! List) return false;
      for (final raw in receipts) {
        if (raw is! Map) continue;
        final label = raw['label']?.toString() ?? '';
        final receipt = raw['receipt'];
        if (receipt is! Map) continue;
        final transport = receipt['transport']?.toString() ?? '';
        if (transport != item.transport) continue;
        if (_receiptLabelMatchesOutboxKind(label, item.kind)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _receiptLabelMatchesOutboxKind(String label, String kind) {
    return switch (kind) {
      DeliveryOutboxKind.invitationSent =>
        label == 'InvitationSent' || label == 'InvitationSentRetry',
      DeliveryOutboxKind.invitationTerminal =>
        label == 'InvitationAccepted' ||
            label == 'InvitationAcceptedRetry' ||
            label == 'InvitationRejected' ||
            label == 'InvitationRejectedRetry',
      DeliveryOutboxKind.relationshipBroken =>
        label == 'RelationshipBroken' || label == 'RelationshipBrokenRetry',
      _ => false,
    };
  }

  Future<void> _enqueueInvitationTerminalRetry({
    required String? bootstrapActiveHex,
  }) async {
    final capsuleHex = bootstrapActiveHex?.trim().toLowerCase();
    if (capsuleHex == null || capsuleHex.isEmpty) return;
    await _outboxStore.enqueue(
      capsuleHex: capsuleHex,
      transport: DeliveryTransportId.nostr,
      kind: DeliveryOutboxKind.invitationTerminal,
      reason: DeliveryOutboxReason.invitationTerminalRetry,
      now: DateTime.now().toUtc(),
    );
  }

  Future<void> _schedulePendingOutgoingRetryPumpIfDue({
    required Map<String, Object?> bootstrap,
    required String? bootstrapActiveHex,
  }) async {
    final capsuleHex = bootstrapActiveHex?.trim().toLowerCase();
    if (capsuleHex == null || capsuleHex.isEmpty) return;
    final dueItems = await _outboxStore.due(
      capsuleHex: capsuleHex,
      now: DateTime.now().toUtc(),
    );
    if (dueItems.isEmpty) return;
    _schedulePendingOutgoingRetryPump(
      bootstrap: bootstrap,
      bootstrapActiveHex: bootstrapActiveHex,
    );
  }

  void _schedulePendingOutgoingRetryPump({
    required Map<String, Object?> bootstrap,
    required String? bootstrapActiveHex,
  }) {
    final capsuleHex = bootstrapActiveHex?.trim();
    if (capsuleHex == null || capsuleHex.isEmpty) return;
    if (_pendingRetryPumpByCapsule.containsKey(capsuleHex)) return;

    final task = () async {
      // Retry delivery for locally recorded pending invitations of this capsule
      // even if UI switches to another capsule right after send timeout.
      const retryDelays = <Duration>[
        Duration(seconds: 2),
        Duration(seconds: 8),
        Duration(seconds: 20),
        Duration(seconds: 45),
        Duration(seconds: 90),
        Duration(seconds: 180),
      ];
      for (var attempt = 0; attempt < retryDelays.length; attempt += 1) {
        final delay = retryDelays[attempt];
        await Future<void>.delayed(delay);
        final refreshedBootstrap = await _runtime.loadWorkerBootstrapArgs(
          capsuleHex: capsuleHex,
        );
        final attemptBootstrap = refreshedBootstrap ?? bootstrap;
        final attemptCapsuleHex =
            attemptBootstrap['activeCapsuleHex'] as String? ??
                bootstrapActiveHex;
        final bootstrapSource =
            refreshedBootstrap == null ? 'initial' : 'refreshed';
        debugPrint(
          '[InvitationActions] pending outgoing retry attempt=${attempt + 1}/${retryDelays.length} '
          'capsule=$capsuleHex delayMs=${delay.inMilliseconds} bootstrap=$bootstrapSource',
        );
        final workerResult =
            await compute<Map<String, Object?>, Map<String, Object?>>(
          retryPendingOutgoingInvitationsInWorker,
          attemptBootstrap,
        ).timeout(
          _sendWorkerTimeout,
          onTimeout: () => <String, Object?>{'result': -1003},
        );
        final code = (workerResult['result'] as int?) ?? -1003;
        final lastError = (workerResult['lastError'] as String?)?.trim();
        final deliveryReceiptsJson =
            workerResult['deliveryReceiptsJson'] as String?;
        debugPrint(
          '[InvitationActions] pending outgoing retry result attempt=${attempt + 1}/${retryDelays.length} '
          'capsule=$capsuleHex code=$code error=${lastError ?? '-'}',
        );

        final ledgerJson = workerResult['ledgerJson'] as String?;
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: attemptCapsuleHex,
          ledgerJson: ledgerJson,
        );
        await _recordOutboxTransportCycle(
          capsuleHex: attemptCapsuleHex,
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: deliveryReceiptsJson,
        );
      }
    }();

    _pendingRetryPumpByCapsule[capsuleHex] = task.catchError((_) {});
    unawaited(
      task.whenComplete(() {
        _pendingRetryPumpByCapsule.remove(capsuleHex);
      }),
    );
  }

  Future<InvitationWorkerResult> sendInvitation(
      Uint8List toPubkey, int starterSlot,
      {String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerFuture = compute<Map<String, Object?>, Map<String, Object?>>(
        sendInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'toPubkey': toPubkey,
          'starterSlot': starterSlot,
        },
      );
      final workerResult = await workerFuture.timeout(
        _sendWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] send worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_sendWorkerTimeout.inMilliseconds}',
          );
          _scheduleLateWorkerLedgerApply(
            workerFuture: workerFuture,
            bootstrapActiveHex: bootstrapActiveHex,
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
      await _applyWorkerLedgerResult(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
      if (code != 0) {
        final capsuleHex = bootstrapActiveHex?.trim().toLowerCase();
        if (capsuleHex != null && capsuleHex.isNotEmpty) {
          await _outboxStore.enqueue(
            capsuleHex: capsuleHex,
            transport: DeliveryTransportId.nostr,
            kind: DeliveryOutboxKind.invitationSent,
            reason: DeliveryOutboxReason.sendInvitationRetry,
            now: DateTime.now().toUtc(),
          );
        }
        _schedulePendingOutgoingRetryPump(
          bootstrap: bootstrap,
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
      await _recordOutboxTransportCycle(
        capsuleHex: bootstrapActiveHex,
        code: code,
        lastError: lastError,
        deliveryReceiptsJson: deliveryReceiptsJson,
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Duration _retryBackoffForAttempt(int attempt) {
    return switch (attempt) {
      <= 1 => const Duration(seconds: 2),
      2 => const Duration(seconds: 8),
      3 => const Duration(seconds: 20),
      4 => const Duration(seconds: 45),
      5 => const Duration(seconds: 90),
      _ => const Duration(minutes: 3),
    };
  }

  Future<InvitationWorkerResult> fetchInvitations({String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      await _schedulePendingOutgoingRetryPumpIfDue(
        bootstrap: bootstrap,
        bootstrapActiveHex: bootstrapActiveHex,
      );
      final workerFuture = compute<Map<String, Object?>, Map<String, Object?>>(
        receiveInvitationsInWorker,
        bootstrap,
      );
      final workerResult = await workerFuture.timeout(
        _receiveWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] receive worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_receiveWorkerTimeout.inMilliseconds}',
          );
          _scheduleLateWorkerLedgerApply(
            workerFuture: workerFuture,
            bootstrapActiveHex: bootstrapActiveHex,
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
      if (code >= 0) {
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
        );
      }
      await _recordOutboxTransportCycle(
        capsuleHex: bootstrapActiveHex,
        code: code,
        lastError: lastError,
        deliveryReceiptsJson: deliveryReceiptsJson,
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> fetchInvitationsQuick(
      {String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      await _schedulePendingOutgoingRetryPumpIfDue(
        bootstrap: bootstrap,
        bootstrapActiveHex: bootstrapActiveHex,
      );
      final workerFuture = compute<Map<String, Object?>, Map<String, Object?>>(
        receiveInvitationsQuickInWorker,
        bootstrap,
      );
      final workerResult = await workerFuture.timeout(
        _receiveQuickWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] quick receive worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_receiveQuickWorkerTimeout.inMilliseconds}',
          );
          _scheduleLateWorkerLedgerApply(
            workerFuture: workerFuture,
            bootstrapActiveHex: bootstrapActiveHex,
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
      if (code >= 0) {
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
        );
      }
      await _recordOutboxTransportCycle(
        capsuleHex: bootstrapActiveHex,
        code: code,
        lastError: lastError,
        deliveryReceiptsJson: deliveryReceiptsJson,
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> acceptInvitation(
      Uint8List invitationId, Uint8List fromPubkey,
      {String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerFuture = compute<Map<String, Object?>, Map<String, Object?>>(
        acceptInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'invitationId': invitationId,
          'fromPubkey': fromPubkey,
        },
      );
      final workerResult = await workerFuture.timeout(
        _acceptWorkerTimeout,
        onTimeout: () {
          _scheduleLateWorkerLedgerApply(
            workerFuture: workerFuture,
            bootstrapActiveHex: bootstrapActiveHex,
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      await _applyWorkerLedgerResult(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
      if (code != 0) {
        await _enqueueInvitationTerminalRetry(
          bootstrapActiveHex: bootstrapActiveHex,
        );
        _schedulePendingOutgoingRetryPump(
          bootstrap: bootstrap,
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
      await _recordOutboxTransportCycle(
        capsuleHex: bootstrapActiveHex,
        code: code,
        lastError: lastError,
        deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> rejectInvitation(
      Uint8List invitationId, int reason,
      {String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerFuture = compute<Map<String, Object?>, Map<String, Object?>>(
        rejectInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'invitationId': invitationId,
          'reason': reason,
        },
      );
      final workerResult = await workerFuture.timeout(
        _rejectWorkerTimeout,
        onTimeout: () {
          _scheduleLateWorkerLedgerApply(
            workerFuture: workerFuture,
            bootstrapActiveHex: bootstrapActiveHex,
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      await _applyWorkerLedgerResult(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
      if (code != 0) {
        await _enqueueInvitationTerminalRetry(
          bootstrapActiveHex: bootstrapActiveHex,
        );
        _schedulePendingOutgoingRetryPump(
          bootstrap: bootstrap,
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
      await _recordOutboxTransportCycle(
        capsuleHex: bootstrapActiveHex,
        code: code,
        lastError: lastError,
        deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<bool> cancelInvitation(
    Uint8List invitationId, {
    String? capsuleHex,
  }) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) return false;

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        cancelInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'invitationId': invitationId,
        },
      );

      final code = (workerResult['result'] as int?) ?? -1;
      if (code != 0) return false;

      final ledgerJson = workerResult['ledgerJson'] as String?;
      await _applyWorkerLedgerResult(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
      return true;
    });
  }
}
