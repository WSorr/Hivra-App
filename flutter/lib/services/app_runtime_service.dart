import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';
import 'capsule_state_manager.dart';
import 'invitation_actions_service.dart';
import 'ledger_view_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';

class AppRuntimeService {
  final HivraBindings _hivra;
  final CapsulePersistenceService _persistence;
  late final CapsuleStateManager _stateManager;
  late final InvitationActionsService _invitationActions;
  late final LedgerViewService _ledgerView;

  AppRuntimeService({
    HivraBindings? hivra,
    CapsulePersistenceService? persistence,
  })  : _hivra = hivra ?? HivraBindings(),
        _persistence = persistence ?? CapsulePersistenceService() {
    _stateManager = CapsuleStateManager(_hivra);
    _invitationActions = InvitationActionsService(_hivra, persistence: _persistence);
    _ledgerView = LedgerViewService(_hivra);
  }

  CapsuleStateManager get stateManager => _stateManager;
  InvitationActionsService get invitationActions => _invitationActions;
  LedgerViewService get ledgerView => _ledgerView;

  Future<bool> bootstrapActiveCapsuleRuntime() {
    return _persistence.bootstrapActiveCapsuleRuntime(_hivra);
  }

  Future<void> persistLedgerSnapshot() {
    return _persistence.persistLedgerSnapshot(_hivra);
  }

  Uint8List? capsuleRootPublicKey() => _hivra.capsuleRootPublicKey();
  Uint8List? capsuleNostrPublicKey() => _hivra.capsuleNostrPublicKey();
  String? exportLedger() => _hivra.exportLedger();

  RelationshipService buildRelationshipService() {
    return RelationshipService(_hivra);
  }

  SettingsService buildSettingsService() {
    return SettingsService(_hivra);
  }
}
