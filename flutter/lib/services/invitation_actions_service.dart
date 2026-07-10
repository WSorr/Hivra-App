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

class CapsuleWorkerQueue {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  Future<T> run<T>(String capsuleHex, Future<T> Function() operation) {
    final key = capsuleHex.trim().toLowerCase();
    if (key.isEmpty) {
      return Future<T>.error(
        ArgumentError.value(capsuleHex, 'capsuleHex', 'must not be empty'),
      );
    }

    final result = Completer<T>();
    final previous = _tails[key] ?? Future<void>.value();
    late final Future<void> tail;
    tail = previous.catchError((_) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _tails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[key], tail)) {
          _tails.remove(key);
        }
      }),
    );
    return result.future;
  }
}

class InvitationActionsService {
  static final CapsuleWorkerQueue _sharedWorkerQueue = CapsuleWorkerQueue();

  final InvitationActionsRuntime _runtime;
  final DeliveryOutboxStore _outboxStore;
  final CapsuleWorkerQueue _workerQueue;
  Future<void> _operationChain = Future<void>.value();
  static final Map<String, Future<void>> _pendingRetryPumpByCapsule =
      <String, Future<void>>{};

  InvitationActionsService({
    InvitationActionsRuntime? runtime,
    DeliveryOutboxStore outboxStore = const DeliveryOutboxStore(),
    CapsuleWorkerQueue? workerQueue,
  })  : _runtime = runtime ?? HivraInvitationActionsRuntime(),
        _outboxStore = outboxStore,
        _workerQueue = workerQueue ?? _sharedWorkerQueue;

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

  Future<Map<String, Object?>> _runCapsuleWorker({
    required Map<String, Object?> initialBootstrap,
    required Future<Map<String, Object?>> Function(
      Map<String, Object?> bootstrap,
    ) startWorker,
    bool Function(Map<String, Object?> result)? shouldApplyLedger,
  }) {
    final initialCapsuleHex = (initialBootstrap['activeCapsuleHex'] as String?)
            ?.trim()
            .toLowerCase() ??
        '';
    if (initialCapsuleHex.isEmpty) {
      return Future<Map<String, Object?>>.value(
        <String, Object?>{'result': -1004},
      );
    }

    return _workerQueue.run(initialCapsuleHex, () async {
      final refreshed = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: initialCapsuleHex,
      );
      final bootstrap = refreshed ?? initialBootstrap;
      final actualCapsuleHex =
          (bootstrap['activeCapsuleHex'] as String?)?.trim().toLowerCase() ??
              '';
      if (actualCapsuleHex != initialCapsuleHex) {
        return <String, Object?>{'result': -1004};
      }

      final result = await startWorker(bootstrap);
      final applyLedger = shouldApplyLedger?.call(result) ?? true;
      if (applyLedger) {
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: actualCapsuleHex,
          ledgerJson: result['ledgerJson'] as String?,
        );
      }
      return result;
    });
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
      DeliveryOutboxKind.invitationTerminal => label == 'InvitationAccepted' ||
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
        final workerResult = await _runCapsuleWorker(
          initialBootstrap: attemptBootstrap,
          startWorker: (currentBootstrap) =>
              compute<Map<String, Object?>, Map<String, Object?>>(
            retryPendingOutgoingInvitationsInWorker,
            currentBootstrap,
          ),
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
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          sendInvitationInWorker,
          <String, Object?>{
            ...currentBootstrap,
            'toPubkey': toPubkey,
            'starterSlot': starterSlot,
          },
        ),
      );
      final workerResult = await workerFuture.timeout(
        _sendWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] send worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_sendWorkerTimeout.inMilliseconds}',
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
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
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          receiveInvitationsInWorker,
          currentBootstrap,
        ),
        shouldApplyLedger: (result) =>
            ((result['result'] as int?) ?? -1003) >= 0,
      );
      final workerResult = await workerFuture.timeout(
        _receiveWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] receive worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_receiveWorkerTimeout.inMilliseconds}',
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
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
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          receiveInvitationsQuickInWorker,
          currentBootstrap,
        ),
        shouldApplyLedger: (result) =>
            ((result['result'] as int?) ?? -1003) >= 0,
      );
      final workerResult = await workerFuture.timeout(
        _receiveQuickWorkerTimeout,
        onTimeout: () {
          debugPrint(
            '[InvitationActions] quick receive worker timeout capsule=${bootstrapActiveHex ?? 'unknown'} timeoutMs=${_receiveQuickWorkerTimeout.inMilliseconds}',
          );
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final deliveryReceiptsJson =
          workerResult['deliveryReceiptsJson'] as String?;
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
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          acceptInvitationInWorker,
          <String, Object?>{
            ...currentBootstrap,
            'invitationId': invitationId,
            'fromPubkey': fromPubkey,
          },
        ),
      );
      final workerResult = await workerFuture.timeout(
        _acceptWorkerTimeout,
        onTimeout: () {
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
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
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          rejectInvitationInWorker,
          <String, Object?>{
            ...currentBootstrap,
            'invitationId': invitationId,
            'reason': reason,
          },
        ),
      );
      final workerResult = await workerFuture.timeout(
        _rejectWorkerTimeout,
        onTimeout: () {
          return <String, Object?>{'result': -1003};
        },
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
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

      final workerResult = await _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker: (currentBootstrap) =>
            compute<Map<String, Object?>, Map<String, Object?>>(
          cancelInvitationInWorker,
          <String, Object?>{
            ...currentBootstrap,
            'invitationId': invitationId,
          },
        ),
        shouldApplyLedger: (result) => ((result['result'] as int?) ?? -1) == 0,
      );

      final code = (workerResult['result'] as int?) ?? -1;
      if (code != 0) return false;

      return true;
    });
  }
}
