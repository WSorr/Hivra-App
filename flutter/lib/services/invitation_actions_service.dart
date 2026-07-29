import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/invitation_actions_runtime.dart';
import 'capsule_delivery_lifecycle_service.dart';
import 'capsule_ffi_worker_queue.dart';
import 'delivery_outbox_store.dart';
import 'delivery_transport_contract.dart';
import 'ledger_view_support.dart';
import 'ui_event_log_service.dart';

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

typedef CapsuleWorkerQueue = CapsuleFfiWorkerQueue;
typedef InvitationWorkerResultObserver =
    FutureOr<void> Function(Map<String, Object?> result, String capsuleHex);

class InvitationActionsService {
  static final CapsuleFfiWorkerQueue _sharedWorkerQueue =
      CapsuleFfiWorkerQueue.shared;
  static const UiEventLogService _uiLog = UiEventLogService();

  final InvitationActionsRuntime _runtime;
  final CapsuleDeliveryLifecycleService _deliveryLifecycle;
  final CapsuleFfiWorkerQueue _workerQueue;
  final Future<Uint8List?> Function()? _readOwnCardSignature;
  Future<void> _operationChain = Future<void>.value();

  InvitationActionsService({
    InvitationActionsRuntime? runtime,
    CapsuleDeliveryLifecycleService? deliveryLifecycle,
    CapsuleFfiWorkerQueue? workerQueue,
    Future<Uint8List?> Function()? readOwnCardSignature,
  }) : _runtime = runtime ?? HivraInvitationActionsRuntime(),
       _deliveryLifecycle =
           deliveryLifecycle ??
           CapsuleDeliveryLifecycleService(
             retryRunner: _unconfiguredRetryRunner,
           ),
       _workerQueue = workerQueue ?? _sharedWorkerQueue,
       _readOwnCardSignature = readOwnCardSignature;

  static Future<CapsuleDeliveryCycleResult> _unconfiguredRetryRunner(
    String capsuleHex,
    DeliveryOutboxItem item,
  ) async => const CapsuleDeliveryCycleResult(
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
    required String? capsuleStateJson,
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
      capsuleStateJson: capsuleStateJson,
    );
  }

  Future<void> _applyWorkerLedgerResult({
    required String? bootstrapActiveHex,
    required String? ledgerJson,
    required String? capsuleStateJson,
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
          capsuleStateJson: capsuleStateJson,
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
    String? capsuleStateJson,
  }) {
    return _applyWorkerLedgerResult(
      bootstrapActiveHex: bootstrapActiveHex,
      ledgerJson: ledgerJson,
      capsuleStateJson: capsuleStateJson,
    );
  }

  Future<Map<String, Object?>> _runCapsuleWorker({
    required Map<String, Object?> initialBootstrap,
    required Future<Map<String, Object?>> Function(
      Map<String, Object?> bootstrap,
    )
    startWorker,
    bool Function(Map<String, Object?> result)? shouldApplyLedger,
    InvitationWorkerResultObserver? afterWorkerResult,
  }) {
    final initialCapsuleHex =
        (initialBootstrap['activeCapsuleHex'] as String?)
            ?.trim()
            .toLowerCase() ??
        '';
    if (initialCapsuleHex.isEmpty) {
      return Future<Map<String, Object?>>.value(<String, Object?>{
        'result': -1004,
      });
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
          capsuleStateJson: result['capsuleStateJson'] as String?,
        );
      }
      // A Dart timeout does not cancel a compute worker. Record the durable
      // relay obligation here so a late local ledger append cannot be left
      // without its outbox item.
      await afterWorkerResult?.call(result, actualCapsuleHex);
      return result;
    });
  }

  Future<void> _enqueueInvitationTerminalRetry({
    required String? bootstrapActiveHex,
    required Uint8List invitationId,
  }) async {
    await _deliveryLifecycle.enqueue(
      capsuleHex: bootstrapActiveHex,
      kind: DeliveryOutboxKind.invitationTerminal,
      reason: DeliveryOutboxReason.invitationTerminalRetry,
      deliveryReference: _hex32(invitationId),
    );
  }

  Future<void> _enqueueInvitationOfferRetry({
    required String capsuleHex,
    required int resultCode,
    required String? ledgerJson,
  }) async {
    if (resultCode != 0 || ledgerJson == null || ledgerJson.isEmpty) return;
    await _deliveryLifecycle.enqueue(
      capsuleHex: capsuleHex,
      kind: DeliveryOutboxKind.invitationSent,
      reason: DeliveryOutboxReason.sendInvitationRetry,
      deliveryReference: _latestInvitationSentReference(ledgerJson),
    );
  }

  Future<void> _reconcileTerminalOutbox(Map<String, Object?> bootstrap) async {
    final capsuleHex =
        (bootstrap['activeCapsuleHex'] as String?)?.trim().toLowerCase();
    final ledgerJson = bootstrap['ledgerJson'] as String?;
    if (capsuleHex == null ||
        capsuleHex.length != 64 ||
        ledgerJson == null ||
        ledgerJson.isEmpty) {
      return;
    }

    final root = const LedgerViewSupport().exportLedgerRoot(ledgerJson);
    if (root == null) return;
    for (final raw in const LedgerViewSupport().events(root)) {
      if (raw is! Map) continue;
      final event = Map<String, dynamic>.from(raw);
      final kind = const LedgerViewSupport().kindCode(event['kind']);
      if (kind != 2 && kind != 3 && kind != 4) continue;

      final signer = const LedgerViewSupport().payloadBytes(event['signer']);
      if (signer.length != 32 || _hex32(signer) != capsuleHex) continue;
      final payload = const LedgerViewSupport().payloadBytes(event['payload']);
      if (payload.length < 32) continue;

      await _deliveryLifecycle.ensureEnqueued(
        capsuleHex: capsuleHex,
        kind: DeliveryOutboxKind.invitationTerminal,
        reason: DeliveryOutboxReason.invitationTerminalRetry,
        deliveryReference: _hex32(Uint8List.sublistView(payload, 0, 32)),
      );
    }
  }

  @visibleForTesting
  Future<void> reconcileTerminalOutboxForTest(Map<String, Object?> bootstrap) {
    return _reconcileTerminalOutbox(bootstrap);
  }

  String? _hex32(Uint8List bytes) {
    if (bytes.length != 32) return null;
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<CapsuleDeliveryCycleResult> retryPendingDelivery({
    required String capsuleHex,
    required DeliveryOutboxItem item,
  }) async {
    final normalizedCapsuleHex = capsuleHex.trim().toLowerCase();
    final bootstrap = await _runtime.loadWorkerBootstrapArgs(
      capsuleHex: normalizedCapsuleHex,
    );
    final bootstrapCapsuleHex =
        (bootstrap?['activeCapsuleHex'] as String?)?.trim().toLowerCase();
    if (bootstrap == null || bootstrapCapsuleHex != normalizedCapsuleHex) {
      unawaited(
        _uiLog.log(
          'delivery.retry.binding_rejected',
          'requested=$normalizedCapsuleHex bootstrap=${bootstrapCapsuleHex ?? 'none'}',
        ),
      );
      return const CapsuleDeliveryCycleResult(code: -1004);
    }
    final deliveryReference = _decodeHex32(item.deliveryReference);
    final worker =
        deliveryReference != null &&
                item.kind == DeliveryOutboxKind.invitationSent
            ? retryOutgoingInvitationOfferByIdInWorker
            : deliveryReference != null &&
                item.kind == DeliveryOutboxKind.invitationTerminal
            ? retryOutgoingInvitationTerminalByIdInWorker
            : deliveryReference != null &&
                item.kind == DeliveryOutboxKind.relationshipBroken
            ? retryOutgoingRelationshipBreakByEventIdInWorker
            : null;
    if (worker == null) {
      unawaited(
        _uiLog.log(
          'delivery.retry.binding_rejected',
          'requested=$normalizedCapsuleHex item=${item.kind}:${item.deliveryReference ?? 'missing-reference'}',
        ),
      );
      return const CapsuleDeliveryCycleResult(code: -1004);
    }
    final workerResult = await _runCapsuleWorker(
      initialBootstrap: bootstrap,
      startWorker:
          (currentBootstrap) =>
              compute<Map<String, Object?>, Map<String, Object?>>(
                worker,
                <String, Object?>{
                  ...currentBootstrap,
                  if (deliveryReference != null &&
                      item.kind != DeliveryOutboxKind.relationshipBroken)
                    'invitationId': deliveryReference,
                  if (deliveryReference != null &&
                      item.kind == DeliveryOutboxKind.relationshipBroken)
                    'eventId': deliveryReference,
                },
              ),
    ).timeout(
      _sendWorkerTimeout,
      onTimeout: () => <String, Object?>{'result': -1003},
    );
    final resultCode = (workerResult['result'] as int?) ?? -1003;
    final receiptsJson = workerResult['deliveryReceiptsJson'] as String?;
    _uiLog.log(
      'delivery.retry',
      'capsule=$normalizedCapsuleHex item=${item.kind}:${item.deliveryReference ?? 'legacy'} code=$resultCode receipts=${_receiptCount(receiptsJson)}',
    );
    return CapsuleDeliveryCycleResult(
      code: resultCode,
      lastError: workerResult['lastError'] as String?,
      deliveryReceiptsJson: receiptsJson,
    );
  }

  Uint8List? _decodeHex32(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      return null;
    }
    return Uint8List.fromList(<int>[
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ]);
  }

  static int _receiptCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['receipts'] is List
          ? (decoded['receipts'] as List).length
          : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<InvitationWorkerResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot, {
    String? capsuleHex,
  }) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      final senderCardSignature = await _readOwnCardSignature?.call();
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  sendInvitationInWorker,
                  <String, Object?>{
                    ...currentBootstrap,
                    'toPubkey': toPubkey,
                    'starterSlot': starterSlot,
                    if (senderCardSignature != null)
                      'senderCardSignature': senderCardSignature,
                  },
                ),
        afterWorkerResult: (result, workerCapsuleHex) {
          return _enqueueInvitationOfferRetry(
            capsuleHex: workerCapsuleHex,
            resultCode: (result['result'] as int?) ?? -1,
            ledgerJson: result['ledgerJson'] as String?,
          );
        },
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
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  String? _latestInvitationSentReference(String ledgerJson) {
    try {
      final root = const LedgerViewSupport().exportLedgerRoot(ledgerJson);
      if (root == null) return null;
      final events = const LedgerViewSupport().events(root);
      for (final raw in events.reversed) {
        if (raw is! Map) continue;
        final event = Map<String, dynamic>.from(raw);
        if (const LedgerViewSupport().kindCode(event['kind']) != 1) continue;
        final payload = const LedgerViewSupport().payloadBytes(
          event['payload'],
        );
        if (payload.length < 32) return null;
        return payload
            .take(32)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<InvitationWorkerResult> fetchInvitations({String? capsuleHex}) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      await _reconcileTerminalOutbox(bootstrap);
      _deliveryLifecycle.scheduleDuePump(capsuleHex: bootstrapActiveHex);
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  receiveInvitationsInWorker,
                  currentBootstrap,
                ),
        shouldApplyLedger:
            (result) => ((result['result'] as int?) ?? -1003) >= 0,
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
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> fetchInvitationsQuick({
    String? capsuleHex,
  }) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
      await _reconcileTerminalOutbox(bootstrap);
      _deliveryLifecycle.scheduleDuePump(capsuleHex: bootstrapActiveHex);
      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  receiveInvitationsQuickInWorker,
                  currentBootstrap,
                ),
        shouldApplyLedger:
            (result) => ((result['result'] as int?) ?? -1003) >= 0,
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
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> acceptInvitation(
    Uint8List invitationId,
    Uint8List fromPubkey, {
    String? capsuleHex,
  }) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  acceptInvitationInWorker,
                  <String, Object?>{
                    ...currentBootstrap,
                    'invitationId': invitationId,
                    'fromPubkey': fromPubkey,
                  },
                ),
        afterWorkerResult: (result, workerCapsuleHex) async {
          if ((result['result'] as int?) != 0 ||
              result['ledgerJson'] is! String) {
            return;
          }
          await _enqueueInvitationTerminalRetry(
            bootstrapActiveHex: workerCapsuleHex,
            invitationId: invitationId,
          );
        },
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
      return InvitationWorkerResult(
        code: code,
        ledgerJson: ledgerJson,
        lastError: lastError,
      );
    });
  }

  Future<InvitationWorkerResult> rejectInvitation(
    Uint8List invitationId,
    int reason, {
    String? capsuleHex,
  }) async {
    return _serialize(() async {
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) {
        return const InvitationWorkerResult(code: -1004);
      }

      final workerFuture = _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  rejectInvitationInWorker,
                  <String, Object?>{
                    ...currentBootstrap,
                    'invitationId': invitationId,
                    'reason': reason,
                  },
                ),
        afterWorkerResult: (result, workerCapsuleHex) async {
          if ((result['result'] as int?) != 0 ||
              result['ledgerJson'] is! String) {
            return;
          }
          await _enqueueInvitationTerminalRetry(
            bootstrapActiveHex: workerCapsuleHex,
            invitationId: invitationId,
          );
        },
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
      final bootstrap = await _runtime.loadWorkerBootstrapArgs(
        capsuleHex: capsuleHex,
      );
      if (bootstrap == null) return false;

      final workerResult = await _runCapsuleWorker(
        initialBootstrap: bootstrap,
        startWorker:
            (currentBootstrap) =>
                compute<Map<String, Object?>, Map<String, Object?>>(
                  cancelInvitationInWorker,
                  <String, Object?>{
                    ...currentBootstrap,
                    'invitationId': invitationId,
                  },
                ),
        shouldApplyLedger: (result) => result['ledgerJson'] is String,
        afterWorkerResult: (result, workerCapsuleHex) async {
          if ((result['result'] as int?) != 0 ||
              result['ledgerJson'] is! String) {
            return;
          }
          await _enqueueInvitationTerminalRetry(
            bootstrapActiveHex: workerCapsuleHex,
            invitationId: invitationId,
          );
        },
      );

      final code = (workerResult['result'] as int?) ?? -1;
      final ledgerJson = workerResult['ledgerJson'] as String?;
      return code == 0 || ledgerJson != null;
    });
  }
}
