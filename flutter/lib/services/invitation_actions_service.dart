import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';

const Duration _sendWorkerTimeout = Duration(seconds: 35);
const Duration _receiveWorkerTimeout = Duration(seconds: 20);
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

bool _bootstrapWorkerRuntime(HivraBindings hivra, Map<String, Object?> args) {
  final seed = args['seed'] as Uint8List;
  final isGenesis = args['isGenesis'] as bool;
  final isNeste = args['isNeste'] as bool;
  final identityMode = args['identityMode'] as String? ?? 'root_owner';
  final ledgerJson = args['ledgerJson'] as String?;

  if (!hivra.saveSeed(seed)) return false;
  if (!hivra.createCapsule(
    seed,
    isGenesis: isGenesis,
    isNeste: isNeste,
    ownerMode: identityMode == 'legacy_nostr_owner'
        ? HivraBindings.legacyNostrOwnerMode
        : HivraBindings.rootOwnerMode,
  )) {
    return false;
  }
  if (ledgerJson != null &&
      ledgerJson.isNotEmpty &&
      !hivra.importLedger(ledgerJson)) {
    return false;
  }
  return true;
}

Map<String, Object?> _sendInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }

  final toPubkey = args['toPubkey'] as Uint8List;
  final starterSlot = args['starterSlot'] as int;
  final result = hivra.deliverInvitationCode(toPubkey, starterSlot);
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': result,
    'ledgerJson': result == 0 ? hivra.exportLedger() : null,
    'lastError': lastError,
  };
}

Map<String, Object?> _receiveInvitationsInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.fetchInvitationDeliveries();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
  };
}

Map<String, Object?> _receiveInvitationsQuickInWorker(
  Map<String, Object?> args,
) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.fetchInvitationDeliveriesQuick();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
  };
}

Map<String, Object?> _acceptInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }

  final invitationId = args['invitationId'] as Uint8List;
  final fromPubkey = args['fromPubkey'] as Uint8List;
  final placeholderStarterId = Uint8List(32);
  final result = hivra.acceptInvitationCode(
      invitationId, fromPubkey, placeholderStarterId);
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': result,
    'ledgerJson': result == 0 ? hivra.exportLedger() : null,
    'lastError': lastError,
  };
}

Map<String, Object?> _rejectInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }

  final invitationId = args['invitationId'] as Uint8List;
  final reason = args['reason'] as int;
  final ok = hivra.rejectInvitation(invitationId, reason);
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': ok ? 0 : -1,
    'ledgerJson': ok ? hivra.exportLedger() : null,
    'lastError': lastError,
  };
}

class InvitationActionsService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  InvitationActionsService(
    this._hivra, {
    CapsulePersistenceService? persistence,
  }) : _persistence = persistence ?? CapsulePersistenceService();

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
    await _persistence.persistLedgerSnapshotForCapsuleHex(
      bootstrapActiveHex,
      ledgerJson,
    );
  }

  Future<InvitationWorkerResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _sendInvitationInWorker,
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
    if (code == 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      final activeNow = await _persistence.resolveActiveCapsuleHex(_hivra);
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
      await _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
    }
    return InvitationWorkerResult(
      code: code,
      ledgerJson: ledgerJson,
      lastError: lastError,
    );
  }

  Future<InvitationWorkerResult> fetchInvitations() async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _receiveInvitationsInWorker,
      bootstrap,
    ).timeout(
      _receiveWorkerTimeout,
      onTimeout: () => <String, Object?>{'result': -1003},
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final ledgerJson = workerResult['ledgerJson'] as String?;
    if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      final activeNow = await _persistence.resolveActiveCapsuleHex(_hivra);
      if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
        await _persistWorkerLedgerForBootstrapCapsule(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
        );
        return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
      }
      await _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
    }
    return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
  }

  Future<InvitationWorkerResult> fetchInvitationsQuick() async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _receiveInvitationsQuickInWorker,
      bootstrap,
    ).timeout(
      _receiveWorkerTimeout,
      onTimeout: () => <String, Object?>{'result': -1003},
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final ledgerJson = workerResult['ledgerJson'] as String?;
    if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      final activeNow = await _persistence.resolveActiveCapsuleHex(_hivra);
      if (bootstrapActiveHex != null && bootstrapActiveHex != activeNow) {
        await _persistWorkerLedgerForBootstrapCapsule(
          bootstrapActiveHex: bootstrapActiveHex,
          ledgerJson: ledgerJson,
        );
        return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
      }
      await _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
    }
    return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
  }

  Future<InvitationWorkerResult> acceptInvitation(
    Uint8List invitationId,
    Uint8List fromPubkey,
  ) async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _acceptInvitationInWorker,
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
    if (code == 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      final activeNow = await _persistence.resolveActiveCapsuleHex(_hivra);
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
      await _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
    }
    return InvitationWorkerResult(
      code: code,
      ledgerJson: ledgerJson,
      lastError: lastError,
    );
  }

  Future<InvitationWorkerResult> rejectInvitation(
    Uint8List invitationId,
    int reason,
  ) async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final bootstrapActiveHex = bootstrap['activeCapsuleHex'] as String?;
    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _rejectInvitationInWorker,
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
    if (code == 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      final activeNow = await _persistence.resolveActiveCapsuleHex(_hivra);
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
      await _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
    }
    return InvitationWorkerResult(
      code: code,
      ledgerJson: ledgerJson,
      lastError: lastError,
    );
  }

  Future<bool> cancelInvitation(Uint8List invitationId) async {
    final ok = _hivra.expireInvitation(invitationId);
    if (!ok) return false;
    await _persistence.persistLedgerSnapshot(_hivra);
    return true;
  }
}
