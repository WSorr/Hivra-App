import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/invitation_actions_runtime.dart';
import 'capsule_delivery_lifecycle_service.dart';
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
  final CapsuleDeliveryLifecycleService _deliveryLifecycle;
  final CapsuleWorkerQueue _workerQueue;
  Future<void> _operationChain = Future<void>.value();

  InvitationActionsService({
    InvitationActionsRuntime? runtime,
    CapsuleDeliveryLifecycleService? deliveryLifecycle,
    CapsuleWorkerQueue? workerQueue,
  })  : _runtime = runtime ?? HivraInvitationActionsRuntime(),
        _deliveryLifecycle = deliveryLifecycle ??
            CapsuleDeliveryLifecycleService(
              retryRunner: _unconfiguredRetryRunner,
            ),
        _workerQueue = workerQueue ?? _sharedWorkerQueue;

  static Future<CapsuleDeliveryCycleResult> _unconfiguredRetryRunner(
    String _,
  ) async =>
      const CapsuleDeliveryCycleResult(
        code: -1004,
        lastError: 'Delivery lifecycle retry runner is not configured',
      );

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
    final workerCapsuleHex = bootstrapActiveHex?.trim().toLowerCase();
    final activeNow =
        (await _runtime.resolveActiveCapsuleHex())?.trim().toLowerCase();
    if (workerCapsuleHex != null &&
        workerCapsuleHex.isNotEmpty &&
        workerCapsuleHex != activeNow) {
      if (ledgerJson != null && ledgerJson.isNotEmpty) {
        await _persistWorkerLedgerForBootstrapCapsule(
          bootstrapActiveHex: workerCapsuleHex,
          ledgerJson: ledgerJson,
        );
      }
      final restored = await _runtime.bootstrapActiveCapsuleRuntime();
      debugPrint(
        '[InvitationActions] restored selected runtime after worker completion '
        'workerCapsule=$workerCapsuleHex activeCapsule=${activeNow ?? 'none'} '
        'restored=$restored',
      );
      return;
    }
    if (ledgerJson == null || ledgerJson.isEmpty) {
      return;
    }
    await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
  }

  @visibleForTesting
  Future<void> applyWorkerLedgerResultForTest({
    required String? bootstrapActiveHex,
    required String? ledgerJson,
  }) {
    return _applyWorkerLedgerResult(
      bootstrapActiveHex: bootstrapActiveHex,
      ledgerJson: ledgerJson,
    );
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

  Future<void> _enqueueInvitationTerminalRetry({
    required String? bootstrapActiveHex,
  }) async {
    await _deliveryLifecycle.enqueue(
      capsuleHex: bootstrapActiveHex,
      kind: DeliveryOutboxKind.invitationTerminal,
      reason: DeliveryOutboxReason.invitationTerminalRetry,
    );
  }

  Future<CapsuleDeliveryCycleResult> retryPendingDelivery({
    required String capsuleHex,
  }) async {
    final bootstrap = await _runtime.loadWorkerBootstrapArgs(
      capsuleHex: capsuleHex,
    );
    if (bootstrap == null) {
      return const CapsuleDeliveryCycleResult(code: -1004);
    }
    final workerResult = await _runCapsuleWorker(
      initialBootstrap: bootstrap,
      startWorker: (currentBootstrap) =>
          compute<Map<String, Object?>, Map<String, Object?>>(
        retryPendingOutgoingInvitationsInWorker,
        currentBootstrap,
      ),
    ).timeout(
      _sendWorkerTimeout,
      onTimeout: () => <String, Object?>{'result': -1003},
    );
    return CapsuleDeliveryCycleResult(
      code: (workerResult['result'] as int?) ?? -1003,
      lastError: workerResult['lastError'] as String?,
      deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
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
      if (ledgerJson != null) {
        await _deliveryLifecycle.enqueue(
          capsuleHex: bootstrapActiveHex,
          kind: DeliveryOutboxKind.invitationSent,
          reason: DeliveryOutboxReason.sendInvitationRetry,
        );
      }
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: deliveryReceiptsJson,
        ),
      );
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> fetchInvitations({String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap =
          await _runtime.loadWorkerBootstrapArgs(capsuleHex: capsuleHex);
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      _deliveryLifecycle.scheduleDuePump(capsuleHex: bootstrapActiveHex);
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
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: deliveryReceiptsJson,
        ),
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
      _deliveryLifecycle.scheduleDuePump(capsuleHex: bootstrapActiveHex);
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
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: deliveryReceiptsJson,
        ),
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
      }
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
        ),
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
      if (ledgerJson != null) {
        await _enqueueInvitationTerminalRetry(
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
        ),
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
        shouldApplyLedger: (result) => result['ledgerJson'] is String,
      );

      final code = (workerResult['result'] as int?) ?? -1;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      final lastError = workerResult['lastError'] as String?;
      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      if (ledgerJson != null) {
        await _enqueueInvitationTerminalRetry(
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
      await _deliveryLifecycle.recordCycle(
        capsuleHex: bootstrapActiveHex,
        result: CapsuleDeliveryCycleResult(
          code: code,
          lastError: lastError,
          deliveryReceiptsJson: workerResult['deliveryReceiptsJson'] as String?,
        ),
      );

      return code == 0 || ledgerJson != null;
    });
  }
}
