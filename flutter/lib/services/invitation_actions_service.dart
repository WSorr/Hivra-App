import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/invitation_actions_runtime.dart';

const Duration _sendWorkerTimeout = Duration(seconds: 35);
const Duration _receiveWorkerTimeout = Duration(seconds: 20);
const Duration _receiveQuickWorkerTimeout = Duration(seconds: 8);
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

  Future<InvitationWorkerResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs();
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        sendInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'toPubkey': toPubkey,
          'starterSlot': starterSlot,
        },
      ).timeout(
        _sendWorkerTimeout,
        onTimeout: () => <String, Object?>{'result': -1003},
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

  Future<InvitationWorkerResult> fetchInvitations() async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs();
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        receiveInvitationsInWorker,
        bootstrap,
      ).timeout(
        _receiveWorkerTimeout,
        onTimeout: () => <String, Object?>{'result': -1003},
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
        final activeNow = await _runtime.resolveActiveCapsuleHex();
        if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
          await _persistWorkerLedgerForBootstrapCapsule(
            bootstrapActiveHex: bootstrapActiveHex,
            ledgerJson: ledgerJson,
          );
          return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
        }
        await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
      }
      return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
    });
  }

  Future<InvitationWorkerResult> fetchInvitationsQuick() async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs();
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        receiveInvitationsQuickInWorker,
        bootstrap,
      ).timeout(
        _receiveQuickWorkerTimeout,
        onTimeout: () => <String, Object?>{'result': -1003},
      );

      final code = (workerResult['result'] as int?) ?? -1003;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
        final activeNow = await _runtime.resolveActiveCapsuleHex();
        if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
          await _persistWorkerLedgerForBootstrapCapsule(
            bootstrapActiveHex: bootstrapActiveHex,
            ledgerJson: ledgerJson,
          );
          return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
        }
        await _runtime.applyLedgerSnapshotIfNotStale(ledgerJson);
      }
      return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
    });
  }

  Future<InvitationWorkerResult> acceptInvitation(
    Uint8List invitationId,
    Uint8List fromPubkey,
  ) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs();
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        acceptInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'invitationId': invitationId,
          'fromPubkey': fromPubkey,
        },
      ).timeout(
        _acceptWorkerTimeout,
        onTimeout: () => <String, Object?>{'result': -1003},
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

  Future<InvitationWorkerResult> rejectInvitation(
    Uint8List invitationId,
    int reason,
  ) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs();
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final workerResult =
          await compute<Map<String, Object?>, Map<String, Object?>>(
        rejectInvitationInWorker,
        <String, Object?>{
          ...bootstrap,
          'invitationId': invitationId,
          'reason': reason,
        },
      ).timeout(
        _rejectWorkerTimeout,
        onTimeout: () => <String, Object?>{'result': -1003},
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

  Future<bool> cancelInvitation(Uint8List invitationId) async {
    return _serialize(() async {
      final ok = _runtime.expireInvitation(invitationId);
      if (!ok) return false;
      await _runtime.persistLedgerSnapshot();
      return true;
    });
  }
}
