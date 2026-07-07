import 'ai_capsule_inspection_service.dart';
import 'ai_developer_engineer_service.dart';
import 'ai_developer_remote_repository_cache_service.dart';
import 'ai_developer_workspace_service.dart';
import 'ai_doctor_chat_service.dart';
import 'ai_doctor_credential_store.dart';
import 'ai_patch_proposal_service.dart';
import 'ai_plugin_audit_service.dart';
import 'ai_plugin_scaffold_draft_service.dart';
import 'ai_review_gate_integration_service.dart';
import 'app_runtime_service.dart';

class AiToolingModuleService {
  final AppRuntimeService _runtime;

  const AiToolingModuleService({
    required AppRuntimeService runtime,
  }) : _runtime = runtime;

  AiToolingModule buildModule() {
    return AiToolingModule(
      capsuleInspection: buildCapsuleInspectionService(),
      capsuleAnalystChat: buildCapsuleAnalystChatService(),
      pluginAudit: buildPluginAuditService(),
      developerWorkspace: buildDeveloperWorkspaceService(),
      developerEngineer: buildDeveloperEngineerService(),
      remoteRepositoryCache: buildDeveloperRemoteRepositoryCacheService(),
      pluginScaffoldDraft: buildPluginScaffoldDraftService(),
      patchProposal: buildPatchProposalService(),
      reviewGateIntegration: buildReviewGateIntegrationService(),
    );
  }

  AiCapsuleInspectionService buildCapsuleInspectionService() {
    return AiCapsuleInspectionService(
      ledgerView: _runtime.ledgerView,
      consensus: _runtime.buildConsensusRuntimeService(),
      diagnostics: _runtime.buildCapsuleDiagnosticsService(),
      readActiveCapsuleHex: _runtime.activeCapsuleRootHex,
    );
  }

  AiDoctorChatService buildCapsuleAnalystChatService() {
    return AiDoctorChatService(
      credentialStore: AiDoctorCredentialStore(),
    );
  }

  AiPluginAuditService buildPluginAuditService() {
    return const AiPluginAuditService();
  }

  AiDeveloperWorkspaceService buildDeveloperWorkspaceService() {
    return const AiDeveloperWorkspaceService();
  }

  AiDeveloperEngineerService buildDeveloperEngineerService() {
    return AiDeveloperEngineerService(
      credentialStore: AiDoctorCredentialStore(),
    );
  }

  AiDeveloperRemoteRepositoryCacheService
      buildDeveloperRemoteRepositoryCacheService() {
    return const AiDeveloperRemoteRepositoryCacheService();
  }

  AiPluginScaffoldDraftService buildPluginScaffoldDraftService() {
    return const AiPluginScaffoldDraftService();
  }

  AiPatchProposalService buildPatchProposalService() {
    return const AiPatchProposalService();
  }

  AiReviewGateIntegrationService buildReviewGateIntegrationService() {
    return const AiReviewGateIntegrationService();
  }
}

class AiToolingModule {
  final AiCapsuleInspectionService capsuleInspection;
  final AiDoctorChatService capsuleAnalystChat;
  final AiPluginAuditService pluginAudit;
  final AiDeveloperWorkspaceService developerWorkspace;
  final AiDeveloperEngineerService developerEngineer;
  final AiDeveloperRemoteRepositoryCacheService remoteRepositoryCache;
  final AiPluginScaffoldDraftService pluginScaffoldDraft;
  final AiPatchProposalService patchProposal;
  final AiReviewGateIntegrationService reviewGateIntegration;

  const AiToolingModule({
    required this.capsuleInspection,
    required this.capsuleAnalystChat,
    required this.pluginAudit,
    required this.developerWorkspace,
    required this.developerEngineer,
    required this.remoteRepositoryCache,
    required this.pluginScaffoldDraft,
    required this.patchProposal,
    required this.reviewGateIntegration,
  });
}
