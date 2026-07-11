import 'app_runtime_service.dart';
import 'consensus_attestation_sync_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';

class MainScreenModule {
  final RelationshipService Function({String? activeCapsuleHex})
      relationshipService;
  final SettingsService Function() settingsService;
  final ConsensusAttestationSyncService consensusAttestations;

  const MainScreenModule({
    required this.relationshipService,
    required this.settingsService,
    required this.consensusAttestations,
  });
}

class MainScreenModuleService {
  final AppRuntimeService runtime;

  const MainScreenModuleService({
    required this.runtime,
  });

  MainScreenModule build() {
    return MainScreenModule(
      relationshipService: runtime.buildRelationshipService,
      settingsService: runtime.buildSettingsService,
      consensusAttestations: runtime.buildConsensusAttestationSyncService(),
    );
  }
}
