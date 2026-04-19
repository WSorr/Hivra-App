import 'dart:typed_data';

import '../services/capsule_persistence_service.dart';
import 'hivra_bindings.dart';

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

Map<String, Object?> sendInvitationInWorker(Map<String, Object?> args) {
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
    'ledgerJson': hivra.exportLedger(),
    'lastError': lastError,
  };
}

Map<String, Object?> receiveInvitationsInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.fetchInvitationDeliveries();
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
    'lastError': lastError,
  };
}

Map<String, Object?> receiveInvitationsQuickInWorker(
    Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.fetchInvitationDeliveriesQuick();
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
    'lastError': lastError,
  };
}

Map<String, Object?> acceptInvitationInWorker(Map<String, Object?> args) {
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
    'ledgerJson': hivra.exportLedger(),
    'lastError': lastError,
  };
}

Map<String, Object?> rejectInvitationInWorker(Map<String, Object?> args) {
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

Map<String, Object?> cancelInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }

  final invitationId = args['invitationId'] as Uint8List;
  final ok = hivra.expireInvitation(invitationId);
  final lastError = hivra.lastErrorMessage();
  return <String, Object?>{
    'result': ok ? 0 : -1,
    'ledgerJson': ok ? hivra.exportLedger() : null,
    'lastError': lastError,
  };
}

abstract class InvitationActionsRuntime {
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs({
    String? capsuleHex,
  });

  Future<bool> bootstrapActiveCapsuleRuntime();

  Future<String?> resolveActiveCapsuleHex();

  Future<bool> applyLedgerSnapshotIfNotStale(String ledgerJson);

  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  );

  bool expireInvitation(Uint8List invitationId);

  Future<bool> persistLedgerSnapshot();
}

class HivraInvitationActionsRuntime implements InvitationActionsRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  HivraInvitationActionsRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs({
    String? capsuleHex,
  }) {
    return _persistence.loadWorkerBootstrapArgs(
      _hivra,
      capsuleHex: capsuleHex,
    );
  }

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _persistence.bootstrapActiveCapsuleRuntime(_hivra);
  }

  @override
  Future<String?> resolveActiveCapsuleHex() {
    return _persistence.resolveActiveCapsuleHex(_hivra);
  }

  @override
  Future<bool> applyLedgerSnapshotIfNotStale(String ledgerJson) {
    return _persistence.applyLedgerSnapshotIfNotStale(_hivra, ledgerJson);
  }

  @override
  Future<void> persistLedgerSnapshotForCapsuleHex(
    String pubKeyHex,
    String ledgerJson,
  ) {
    return _persistence.persistLedgerSnapshotForCapsuleHex(
        pubKeyHex, ledgerJson);
  }

  @override
  bool expireInvitation(Uint8List invitationId) {
    return _hivra.expireInvitation(invitationId);
  }

  @override
  Future<bool> persistLedgerSnapshot() {
    return _persistence.persistLedgerSnapshot(_hivra);
  }
}
