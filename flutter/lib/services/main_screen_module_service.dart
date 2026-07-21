import 'app_runtime_service.dart';
import 'ai_tooling_module_service.dart';
import 'capsule_history_ai_advisor_service.dart';
import 'capsule_history_projection_service.dart';
import 'consensus_attestation_exchange_service.dart';
import 'consensus_attestation_sync_service.dart';
import 'relationship_service.dart';
import 'settings_service.dart';

class MainScreenModule {
  final RelationshipService Function({String? activeCapsuleHex})
  relationshipService;
  final SettingsService Function() settingsService;
  final ConsensusAttestationSyncService consensusAttestations;
  final ConsensusAttestationExchangeService attestationExchange;
  final CapsuleHistoryProjectionService capsuleHistory;
  final CapsuleHistoryAiAdvisorService capsuleHistoryAi;

  const MainScreenModule({
    required this.relationshipService,
    required this.settingsService,
    required this.consensusAttestations,
    required this.attestationExchange,
    required this.capsuleHistory,
    required this.capsuleHistoryAi,
  });
}

class MainScreenModuleService {
  final AppRuntimeService runtime;

  const MainScreenModuleService({required this.runtime});

  MainScreenModule build() {
    final aiTooling = AiToolingModuleService(runtime: runtime);
    return MainScreenModule(
      relationshipService: runtime.buildRelationshipService,
      settingsService: runtime.buildSettingsService,
      consensusAttestations: runtime.buildConsensusAttestationSyncService(),
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      capsuleHistory: CapsuleHistoryProjectionService(
        exportLedger: runtime.exportLedger,
      ),
      capsuleHistoryAi: aiTooling.buildCapsuleHistoryAiAdvisorService(),
    );
  }
}
