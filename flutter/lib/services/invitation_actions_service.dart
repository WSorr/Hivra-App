import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';

class InvitationWorkerResult {
  final int code;
  final String? ledgerJson;

  const InvitationWorkerResult({
    required this.code,
    this.ledgerJson,
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
    ownerMode: identityMode == 'root_owner'
        ? HivraBindings.rootOwnerMode
        : HivraBindings.legacyNostrOwnerMode,
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
  return <String, Object?>{
    'result': result,
    'ledgerJson': result == 0 ? hivra.exportLedger() : null,
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

Map<String, Object?> _acceptInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }

  final invitationId = args['invitationId'] as Uint8List;
  final fromPubkey = args['fromPubkey'] as Uint8List;
  final placeholderStarterId = Uint8List(32);
  final result =
      hivra.acceptInvitationCode(invitationId, fromPubkey, placeholderStarterId);
  return <String, Object?>{
    'result': result,
    'ledgerJson': result == 0 ? hivra.exportLedger() : null,
  };
}

class InvitationActionsService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  InvitationActionsService(
    this._hivra, {
    CapsulePersistenceService? persistence,
  }) : _persistence = persistence ?? CapsulePersistenceService();

  Future<InvitationWorkerResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _sendInvitationInWorker,
      <String, Object?>{
        ...bootstrap,
        'toPubkey': toPubkey,
        'starterSlot': starterSlot,
      },
    ).timeout(
      const Duration(seconds: 8),
      onTimeout: () => <String, Object?>{'result': -1003},
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final ledgerJson = workerResult['ledgerJson'] as String?;
    if (code == 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      _hivra.importLedger(ledgerJson);
      await _persistence.persistLedgerSnapshot(_hivra);
    }
    return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
  }

  Future<InvitationWorkerResult> fetchInvitations() async {
    final bootstrap = await _persistence.loadWorkerBootstrapArgs(_hivra);
    if (bootstrap == null) {
      return const InvitationWorkerResult(code: -1004);
    }

    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _receiveInvitationsInWorker,
      bootstrap,
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () => <String, Object?>{'result': -1003},
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final ledgerJson = workerResult['ledgerJson'] as String?;
    if (code >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      _hivra.importLedger(ledgerJson);
      await _persistence.persistLedgerSnapshot(_hivra);
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

    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _acceptInvitationInWorker,
      <String, Object?>{
        ...bootstrap,
        'invitationId': invitationId,
        'fromPubkey': fromPubkey,
      },
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () => <String, Object?>{'result': -1003},
    );

    final code = (workerResult['result'] as int?) ?? -1003;
    final ledgerJson = workerResult['ledgerJson'] as String?;
    if (code == 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
      _hivra.importLedger(ledgerJson);
      await _persistence.persistLedgerSnapshot(_hivra);
    }
    return InvitationWorkerResult(code: code, ledgerJson: ledgerJson);
  }

  Future<bool> rejectInvitation(Uint8List invitationId, int reason) async {
    final ok = _hivra.rejectInvitation(invitationId, reason);
    if (!ok) return false;
    await _persistence.persistLedgerSnapshot(_hivra);
    return true;
  }

  Future<bool> cancelInvitation(Uint8List invitationId) async {
    final ok = _hivra.expireInvitation(invitationId);
    if (!ok) return false;
    await _persistence.persistLedgerSnapshot(_hivra);
    return true;
  }
}
