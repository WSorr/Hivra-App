import 'dart:typed_data';

import '../services/capsule_persistence_service.dart';
import '../services/capsule_persistence_models.dart';
import 'capsule_address_runtime.dart';
import 'hivra_bindings.dart';
import 'invitation_actions_runtime.dart';
import 'ledger_view_runtime.dart';

abstract class AppRuntimeRuntime {
  LedgerViewRuntime get ledgerViewRuntime;

  InvitationActionsRuntime get invitationActionsRuntime;

  CapsuleAddressRuntime get capsuleAddressRuntime;

  Future<bool> bootstrapActiveCapsuleRuntime();

  Future<void> persistLedgerSnapshot();

  Uint8List? capsuleRootPublicKey();

  Uint8List? capsuleNostrPublicKey();

  Uint8List? loadSeed();

  String? exportLedger();

  Future<Map<String, Object?>?> loadWorkerBootstrapArgs();

  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  );

  Future<CapsuleTraceReport> diagnoseCapsuleTraces();

  Future<CapsuleBootstrapReport> diagnoseBootstrapReport();
}

class HivraAppRuntimeRuntime implements AppRuntimeRuntime {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;

  @override
  late final LedgerViewRuntime ledgerViewRuntime =
      HivraLedgerViewRuntime(_hivra);

  @override
  late final InvitationActionsRuntime invitationActionsRuntime =
      HivraInvitationActionsRuntime(
    hivra: _hivra,
    persistence: _persistence,
  );

  @override
  late final CapsuleAddressRuntime capsuleAddressRuntime =
      HivraCapsuleAddressRuntime(_hivra);

  HivraAppRuntimeRuntime({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService();

  @override
  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _persistence.bootstrapActiveCapsuleRuntime(_hivra);
  }

  @override
  Future<void> persistLedgerSnapshot() async {
    await _persistence.persistLedgerSnapshot(_hivra);
  }

  @override
  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();

  @override
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();

  @override
  Uint8List? loadSeed() => _hivra.loadSeed();

  @override
  String? exportLedger() => _hivra.exportLedger();

  @override
  Future<Map<String, Object?>?> loadWorkerBootstrapArgs() {
    return _persistence.loadWorkerBootstrapArgs(_hivra);
  }

  @override
  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) {
    return _hivra.breakRelationship(peerPubkey, ownStarterId, peerStarterId);
  }

  @override
  Future<CapsuleTraceReport> diagnoseCapsuleTraces() {
    return _persistence.diagnoseCapsuleTraces(_hivra);
  }

  @override
  Future<CapsuleBootstrapReport> diagnoseBootstrapReport() {
    return _persistence.diagnoseBootstrapReport(_hivra);
  }
}
