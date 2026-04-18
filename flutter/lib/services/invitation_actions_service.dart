import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/invitation_actions_runtime.dart';

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
  Future<void> _operationChain = Future<void>.value();
  static final Map<String, Future<void>> _pendingRetryPumpByCapsule =
      <String, Future<void>>{};

  InvitationActionsService({InvitationActionsRuntime? runtime})
      : _runtime = runtime ?? HivraInvitationActionsRuntime();

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
    if (ledgerJson == null || ledgerJson.isEmpty) {
      return;
    }
    final activeNow = await _runtime.resolveActiveCapsuleHex();
    if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
      await _persistWorkerLedgerForBootstrapCapsule(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
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
      ];
      for (final delay in retryDelays) {
        await Future<void>.delayed(delay);
        final workerResult =
            await compute<Map<String, Object?>, Map<String, Object?>>(
          receiveInvitationsInWorker,
          bootstrap,
        ).timeout(
          _receiveWorkerTimeout,
          onTimeout: () => <String, Object?>{'result': -1003},
        );

        final ledgerJson = workerResult['ledgerJson'] as String?;
        await _applyWorkerLedgerResult(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
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
      await _applyWorkerLedgerResult(
        bootstrapActiveHex: bootstrapActiveHex,
        ledgerJson: ledgerJson,
      );
      if (code != 0) {
        _schedulePendingOutgoingRetryPump(
          bootstrap: bootstrap,
          bootstrapActiveHex: bootstrapActiveHex,
        );
      }
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
      final workerFuture =
          compute<Map<String, Object?>, Map<String, Object?>>(
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
      if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
        final activeNow = await _runtime.resolveActiveCapsuleHex();
        if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
          await _persistWorkerLedgerForBootstrapCapsule(
            bootstrapActiveHex: bootstrapActiveHex,
            ledgerJson: ledgerJson,
          );
          return InvitationWorkerResult(
            code: code,
            ledgerJson: ledgerJson,
            lastError: lastError,
          );
        }
        await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
      }
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
      final workerFuture =
          compute<Map<String, Object?>, Map<String, Object?>>(
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
      if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
        final activeNow = await _runtime.resolveActiveCapsuleHex();
        if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
          await _persistWorkerLedgerForBootstrapCapsule(
            bootstrapActiveHex: bootstrapActiveHex,
            ledgerJson: ledgerJson,
          );
          return InvitationWorkerResult(
            code: code,
            ledgerJson: ledgerJson,
            lastError: lastError,
          );
        }
        await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
      }
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
      if (ledgerJson != null && ledgerJson.isNotEmpty) {
        final activeNow = await _runtime.resolveActiveCapsuleHex();
        if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
          await _persistWorkerLedgerForBootstrapCapsule(
            bootstrapActiveHex: bootstrapActiveHex,
            ledgerJson: ledgerJson,
          );
          return InvitationWorkerResult(
            code: code,
            ledgerJson: ledgerJson,
            lastError: lastError,
          );
        }
        await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
      }
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
