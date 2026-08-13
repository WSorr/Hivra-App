import 'dart:async';

import '../models/capsule_chat_models.dart';
import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/moltbook_provider_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../models/wasm_plugin_models.dart';
import 'app_runtime_service.dart';
import 'ai_doctor_credential_store.dart';
import 'capsule_ai_runtime_service.dart';
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';
import 'capsule_chat_delivery_service.dart';
import 'capsule_contact_label_store.dart';
import 'capsule_passive_receive_coordinator.dart';
import 'consensus_attestation_exchange_service.dart';
import 'external_effect_service.dart';
import 'manual_consensus_check_service.dart';
import 'moltbook_ambassador_configuration_store.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_cycle_trigger_service.dart';
import 'moltbook_draft_store.dart';
import 'moltbook_external_effect_adapter.dart';
import 'moltbook_feed_checkpoint_store.dart';
import 'moltbook_publication_service.dart';
import 'moltbook_public_bulletin_ai_service.dart';
import 'moltbook_public_change_feed_store.dart';
import 'moltbook_provider_adapter.dart';
import 'plugin_host_api_service.dart';
import 'ui_event_log_service.dart';
import 'wasm_plugin_registry_service.dart';
import 'wasm_plugin_source_catalog_service.dart';

enum PluginChatSendStatus {
  sent,
  syncing,
  blocked,
  rejected,
  failed,
  capsuleChanged,
}

class PluginChatSendResult {
  final PluginChatSendStatus status;
  final String message;
  final PluginHostApiResponse? hostResponse;
  final CapsuleChatDeliverySendResult? delivery;

  const PluginChatSendResult({
    required this.status,
    required this.message,
    this.hostResponse,
    this.delivery,
  });

  bool get isSuccess => status == PluginChatSendStatus.sent;
}

class PluginRuntimeModule {
  static final Map<String, Future<MoltbookCycleSummary>> _moltbookCycles =
      <String, Future<MoltbookCycleSummary>>{};
  static final Map<String, int> _moltbookCycleEpochs = <String, int>{};
  static int _moltbookCycleEpoch = 0;

  final WasmPluginRegistryService registry;
  final WasmPluginSourceCatalogService sourceCatalog;
  final ManualConsensusCheckService manualChecks;
  final PluginHostApiService pluginHostApi;
  final ConsensusAttestationExchangeService attestationExchange;
  final CapsuleChatDeliveryService chatDelivery;
  final CapsulePassiveReceivePort passiveReceive;
  final CapsuleContactLabelStore contactLabels;
  final UiEventLogService uiLog;
  final ExternalEffectService externalEffects;
  final MoltbookConnectionService moltbookConnection;
  final MoltbookDraftStore moltbookDrafts;
  final MoltbookFeedCheckpointStore moltbookFeedCheckpoint;
  final MoltbookPublicationService moltbookPublications;
  final MoltbookPublicBulletinAiService moltbookPublicBulletinAi;
  final MoltbookPublicChangeFeedStore moltbookPublicChanges;
  final MoltbookCycleTriggerService moltbookCycleTriggers;
  final MoltbookAmbassadorConfigurationStore _ambassadorConfiguration;
  final CapsuleFileStore _fileStore;
  final CapsuleScopedSecretVault _secretVault;
  final String? Function() _readActiveCapsuleRootHex;
  PluginRuntimeModule({
    required this.registry,
    required this.sourceCatalog,
    required this.manualChecks,
    required this.pluginHostApi,
    required this.attestationExchange,
    required this.chatDelivery,
    required this.passiveReceive,
    required this.contactLabels,
    required this.uiLog,
    required this.externalEffects,
    required this.moltbookConnection,
    required this.moltbookDrafts,
    required this.moltbookFeedCheckpoint,
    required this.moltbookPublications,
    required this.moltbookPublicBulletinAi,
    required this.moltbookPublicChanges,
    required this.moltbookCycleTriggers,
    required MoltbookAmbassadorConfigurationStore ambassadorConfiguration,
    required CapsuleFileStore fileStore,
    required CapsuleScopedSecretVault secretVault,
    required String? Function() readActiveCapsuleRootHex,
  }) : _ambassadorConfiguration = ambassadorConfiguration,
       _fileStore = fileStore,
       _secretVault = secretVault,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

  bool get isMoltbookAiSessionUnlocked =>
      moltbookPublicBulletinAi.isSessionUnlocked;

  String? activeCapsuleRootHex() => _readActiveCapsuleRootHex();

  String? get moltbookAiSessionProviderLabel =>
      moltbookPublicBulletinAi.sessionProviderLabel;

  Future<String> unlockMoltbookAiSession() async {
    return moltbookPublicBulletinAi.unlockSession();
  }

  void lockMoltbookAiSession() {
    moltbookPublicBulletinAi.lockSession();
  }

  Future<MoltbookAmbassadorConfiguration> loadAmbassadorConfiguration() =>
      _ambassadorConfiguration.load();

  Future<void> saveAmbassadorConfiguration(
    MoltbookAmbassadorConfiguration configuration,
  ) => _ambassadorConfiguration.save(configuration);

  Future<MoltbookPublicBulletinProposal> proposeMoltbookPublicBulletin(
    String sourceNotes, {
    required String category,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final normalizedCategory = category.trim();
    if (!configuration.allowedTopics.contains(normalizedCategory)) {
      throw StateError(
        'Public bulletin category must match one of the allowed topics',
      );
    }
    final operationCapsuleHex =
        _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (operationCapsuleHex == null || operationCapsuleHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    await uiLog.log(
      'moltbook.public_bulletin.propose',
      'start owner=$operationCapsuleHex category=$normalizedCategory',
    );
    try {
      final proposal = await moltbookPublicBulletinAi.propose(
        sourceNotes: sourceNotes,
        category: normalizedCategory,
        personaSummary: configuration.personaSummary,
      );
      if (!_isStillOwnedBy(operationCapsuleHex)) {
        throw StateError(
          'Public bulletin discarded because the active capsule changed',
        );
      }
      await uiLog.log(
        'moltbook.public_bulletin.propose',
        'success provider=${proposal.providerLabel} '
            'model=${_safeLogValue(proposal.model)} facts=${proposal.facts.length}',
      );
      return proposal;
    } catch (error) {
      await uiLog.log(
        'moltbook.public_bulletin.propose',
        'error ${_safeError(error)}',
      );
      rethrow;
    }
  }

  Future<List<MoltbookPublicChange>> loadMoltbookPublicChanges() =>
      moltbookPublicChanges.load();

  Future<MoltbookPublicChange> recordMoltbookPublicChange({
    required String sourceId,
    required String category,
    required List<String> facts,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    final normalizedCategory = category.trim();
    if (!configuration.allowedTopics.contains(normalizedCategory)) {
      throw StateError('Public change category must match an allowed topic');
    }
    return moltbookPublicChanges.record(
      sourceId: sourceId,
      category: normalizedCategory,
      facts: facts,
    );
  }

  Future<MoltbookPublicBulletinProposal?>
  proposeNextMoltbookPublicChange() async {
    final change = await moltbookPublicChanges.nextPending();
    if (change == null) return null;
    return proposeMoltbookPublicBulletin(
      change.sourceNotes,
      category: change.category,
    );
  }

  Future<MoltbookConnectionBinding?> loadMoltbookBinding() =>
      moltbookConnection.loadBinding();

  Future<MoltbookFeedCheckpoint> loadMoltbookFeedCheckpoint() =>
      moltbookFeedCheckpoint.load();

  Future<MoltbookConnectionBinding> connectMoltbook(String apiKey) async {
    await uiLog.log('moltbook.connect', 'start');
    try {
      final binding = await moltbookConnection.connect(apiKey);
      await uiLog.log(
        'moltbook.connect',
        'success account=${binding.accountId} claimed=${binding.isClaimed} '
            'active=${binding.isActive}',
      );
      return binding;
    } catch (error) {
      await uiLog.log('moltbook.connect', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<MoltbookConnectionBinding> refreshMoltbookBinding() async {
    await uiLog.log('moltbook.account.refresh', 'start');
    try {
      final binding = await moltbookConnection.refresh();
      await uiLog.log(
        'moltbook.account.refresh',
        'success account=${binding.accountId} claimed=${binding.isClaimed} '
            'active=${binding.isActive}',
      );
      return binding;
    } catch (error) {
      await uiLog.log('moltbook.account.refresh', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<MoltbookHomeObservation> observeMoltbookHome() async {
    await uiLog.log('moltbook.home.observe', 'start');
    try {
      final observation = await moltbookConnection.observeHome();
      await uiLog.log(
        'moltbook.home.observe',
        'success karma=${observation.karma} '
            'unread=${observation.unreadNotificationCount} '
            'actions=${observation.suggestedActions.length} '
            'rateRemaining=${observation.rateLimit.remaining ?? "unknown"}',
      );
      return observation;
    } catch (error) {
      await uiLog.log('moltbook.home.observe', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<MoltbookFeedObservation> observeMoltbookFeed() async {
    await uiLog.log('moltbook.feed.observe', 'start sort=new limit=15');
    try {
      final observation = await moltbookConnection.observeFeed();
      await uiLog.log(
        'moltbook.feed.observe',
        'success posts=${observation.posts.length} '
            'has_more=${observation.hasMore}',
      );
      return observation;
    } catch (error) {
      await uiLog.log('moltbook.feed.observe', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<MoltbookConversationObservation> observeMoltbookConversation(
    String postId,
  ) async {
    final normalizedPostId = postId.trim();
    await uiLog.log(
      'moltbook.conversation.observe',
      'start post=$normalizedPostId',
    );
    try {
      final observation = await moltbookConnection.observeConversation(
        normalizedPostId,
      );
      await uiLog.log(
        'moltbook.conversation.observe',
        'success post=${observation.post.postId} '
            'comments=${observation.comments.length} '
            'hasMore=${observation.hasMoreComments}',
      );
      return observation;
    } catch (error) {
      await uiLog.log(
        'moltbook.conversation.observe',
        'error post=$normalizedPostId ${_safeError(error)}',
      );
      rethrow;
    }
  }

  Future<MoltbookEngagementPlan> planMoltbookEngagement({
    required MoltbookConversationObservation conversation,
    required String selectionKind,
  }) async {
    if (!const <String>{
      'own_activity',
      'feed_candidate',
    }.contains(selectionKind)) {
      throw ArgumentError.value(
        selectionKind,
        'selectionKind',
        'Unsupported Moltbook engagement selection',
      );
    }
    conversation.validate();
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final binding = await moltbookConnection.loadBinding();
    if (binding == null || !binding.isClaimed || !binding.isActive) {
      throw StateError('Active Moltbook account binding is unavailable');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    final observedAtUtc = DateTime.now().toUtc().toIso8601String();
    await uiLog.log(
      'moltbook.engagement.plan',
      'start post=${conversation.post.postId} selection=$selectionKind',
    );
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: moltbookAmbassadorPluginId,
        method: planMoltbookEngagementMethod,
        args: <String, dynamic>{
          'observed_at_utc': observedAtUtc,
          'selection_kind': selectionKind,
          'actor_name': binding.accountName,
          'allowed_topics': configuration.allowedTopics,
          'post': <String, dynamic>{
            'post_id': conversation.post.postId,
            'title': conversation.post.title,
            'content': conversation.post.content,
            'author_name': conversation.post.authorName,
            'submolt_name': conversation.post.submoltName,
            'score': conversation.post.score,
            'is_verified': conversation.post.isVerified,
            'is_spam': conversation.post.isSpam,
            'is_locked': conversation.post.isLocked,
          },
          'comments': conversation.comments
              .map(
                (comment) => <String, dynamic>{
                  'comment_id': comment.commentId,
                  'parent_comment_id': comment.parentCommentId,
                  'content': comment.content,
                  'author_name': comment.authorName,
                  'score': comment.score,
                  'created_at_utc': comment.createdAtUtc,
                },
              )
              .toList(growable: false),
        },
      ),
    );
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Engagement plan discarded because the active capsule changed',
      );
    }
    final result = response.result;
    if (response.status != PluginHostApiStatus.executed || result == null) {
      throw StateError(
        response.errorMessage ?? 'Moltbook engagement planning was rejected',
      );
    }
    final plan = MoltbookEngagementPlan.fromHostResult(result);
    await uiLog.log(
      'moltbook.engagement.plan',
      'success action=${plan.actionClass} '
          'post=${plan.targetPostId} hash=${plan.planHashHex.substring(0, 12)}..',
    );
    return plan;
  }

  Future<MoltbookReplyProposal> proposeMoltbookReply({
    required MoltbookConversationObservation conversation,
    required MoltbookEngagementPlan engagementPlan,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    await uiLog.log(
      'moltbook.reply.propose',
      'start post=${engagementPlan.targetPostId} '
          'comment=${engagementPlan.targetCommentId ?? "root"}',
    );
    try {
      final proposal = await moltbookPublicBulletinAi.proposeReply(
        conversation: conversation,
        engagementPlan: engagementPlan,
        personaSummary: configuration.personaSummary,
      );
      if (!_isStillOwnedBy(ownerHex)) {
        throw StateError(
          'Reply proposal discarded because the active capsule changed',
        );
      }
      await uiLog.log(
        'moltbook.reply.propose',
        'success provider=${proposal.providerLabel} '
            'model=${_safeLogValue(proposal.model)} '
            'points=${proposal.groundingPoints.length}',
      );
      return proposal;
    } catch (error) {
      await uiLog.log('moltbook.reply.propose', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<MoltbookReplyDraftPreview> prepareMoltbookReply({
    required MoltbookEngagementPlan engagementPlan,
    required String reviewedBody,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    if (!const <String>{
      'reply_draft',
      'comment_draft',
    }.contains(engagementPlan.actionClass)) {
      throw StateError('Engagement plan does not allow a reply draft');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    await uiLog.log(
      'moltbook.reply.prepare',
      'start post=${engagementPlan.targetPostId} '
          'plan=${engagementPlan.planHashHex.substring(0, 12)}..',
    );
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: moltbookAmbassadorPluginId,
        method: prepareMoltbookReplyMethod,
        args: <String, dynamic>{
          'schema_version': 1,
          'plugin_id': moltbookAmbassadorPluginId,
          'host_method': prepareMoltbookReplyMethod,
          'target_post_id': engagementPlan.targetPostId,
          'target_comment_id': engagementPlan.targetCommentId,
          'engagement_plan_hash_hex': engagementPlan.planHashHex,
          'reviewed_body': reviewedBody.trim(),
        },
      ),
    );
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Reply draft discarded because the active capsule changed',
      );
    }
    final result = response.result;
    if (response.status != PluginHostApiStatus.executed || result == null) {
      throw StateError(
        response.errorMessage ?? 'Moltbook reply preparation was rejected',
      );
    }
    final preview = MoltbookReplyDraftPreview.fromHostResult(result);
    await uiLog.log(
      'moltbook.reply.prepare',
      'success hash=${preview.draftHashHex.substring(0, 12)}..',
    );
    return preview;
  }

  Future<MoltbookDelegatedReplyAuthorization> _authorizeDelegatedMoltbookReply({
    required MoltbookEngagementPlan engagementPlan,
    required MoltbookReplyDraftPreview draft,
    DateTime? nowUtc,
  }) async {
    if (engagementPlan.actionClass != 'reply_draft' ||
        draft.targetCommentId == null) {
      throw StateError(
        'Bounded delegation permits replies to an exact comment only',
      );
    }
    if (draft.engagementPlanHashHex != engagementPlan.planHashHex ||
        draft.targetPostId != engagementPlan.targetPostId ||
        draft.targetCommentId != engagementPlan.targetCommentId) {
      throw const FormatException(
        'Reply draft does not bind the selected engagement plan',
      );
    }
    if (!const <String>{
      'reply_draft',
      'comment_draft',
    }.contains(engagementPlan.actionClass)) {
      throw StateError('Engagement plan does not authorize a written reply');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final usage = await _moltbookDelegationUsage(now);
    final writesToday = usage.writesToday;
    final minutesSinceLastWrite = usage.minutesSinceLastWrite;
    const maxDailyWrites = 3;
    const minIntervalMinutes = 30;
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: moltbookAmbassadorPluginId,
        method: authorizeMoltbookDelegatedReplyMethod,
        args: <String, dynamic>{
          'schema_version': 1,
          'plugin_id': moltbookAmbassadorPluginId,
          'host_method': authorizeMoltbookDelegatedReplyMethod,
          'target_post_id': draft.targetPostId,
          'target_comment_id': draft.targetCommentId,
          'engagement_plan_hash_hex': draft.engagementPlanHashHex,
          'reply_draft_hash_hex': draft.draftHashHex,
          'policy_version': 1,
          'max_daily_writes': maxDailyWrites,
          'writes_today': writesToday,
          'min_interval_minutes': minIntervalMinutes,
          'minutes_since_last_write': minutesSinceLastWrite,
          'observed_at_utc': now.toIso8601String(),
        },
      ),
    );
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Delegated authorization discarded because the active capsule changed',
      );
    }
    final result = response.result;
    if (response.status != PluginHostApiStatus.executed || result == null) {
      throw StateError(
        response.errorMessage ?? 'Delegated reply authorization was rejected',
      );
    }
    final authorization = MoltbookDelegatedReplyAuthorization.fromHostResult(
      result,
    );
    if (authorization.replyDraftHashHex != draft.draftHashHex ||
        authorization.engagementPlanHashHex != engagementPlan.planHashHex) {
      throw const FormatException(
        'Delegated authorization changed the bound reply evidence',
      );
    }
    await uiLog.log(
      'moltbook.reply.delegate',
      'authorized draft=${draft.draftHashHex.substring(0, 12)}.. '
          'budget=$writesToday/$maxDailyWrites',
    );
    return authorization;
  }

  Future<MoltbookHeartbeatPlan> planMoltbookHeartbeat() =>
      _planMoltbookHeartbeat(cycleEpoch: _moltbookCycleEpoch);

  Future<MoltbookHeartbeatPlan> _planMoltbookHeartbeat({
    required int cycleEpoch,
  }) async {
    final result = await _observeAndPlanMoltbookHeartbeat(
      cycleEpoch: cycleEpoch,
    );
    await moltbookFeedCheckpoint.commit(
      result.observation.feed,
      observedAt: result.observedAt,
    );
    await _ensureMoltbookCycleScope(
      result.ownerHex,
      result.accountBindingId,
      cycleEpoch: cycleEpoch,
    );
    return result.plan;
  }

  Future<
    ({
      String ownerHex,
      String accountBindingId,
      MoltbookHeartbeatObservation observation,
      MoltbookHeartbeatPlan plan,
      DateTime observedAt,
    })
  >
  _observeAndPlanMoltbookHeartbeat({required int cycleEpoch}) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    final binding = await moltbookConnection.loadBinding();
    if (binding == null || !binding.isClaimed || !binding.isActive) {
      throw StateError('Active Moltbook account binding is unavailable');
    }
    await uiLog.log('moltbook.heartbeat.plan', 'start owner=$ownerHex');
    final checkpoint = await moltbookFeedCheckpoint.load();
    final observation = await moltbookConnection.observeHeartbeat(
      processedPostIds: checkpoint.processedPostIdSet,
    );
    await _ensureMoltbookCycleScope(
      ownerHex,
      binding.accountId,
      cycleEpoch: cycleEpoch,
    );
    final observedAtUtc = DateTime.now().toUtc().toIso8601String();
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: moltbookAmbassadorPluginId,
        method: planMoltbookHeartbeatMethod,
        args: <String, dynamic>{
          'observed_at_utc': observedAtUtc,
          'allowed_topics': configuration.allowedTopics,
          'home': <String, dynamic>{
            'unread_notification_count':
                observation.home.unreadNotificationCount,
            'activity_on_own_posts': observation.home.activityOnOwnPosts
                .map(
                  (activity) => <String, dynamic>{
                    'post_id': activity.postId,
                    'post_title': activity.postTitle,
                    'submolt_name': activity.submoltName,
                    'new_notification_count': activity.newNotificationCount,
                    'latest_at_utc': activity.latestAtUtc,
                    'latest_commenters': activity.latestCommenters,
                    'preview': activity.preview,
                  },
                )
                .toList(growable: false),
            'suggested_actions': observation.home.suggestedActions,
          },
          'feed': observation.feed.posts
              .where(
                (post) => !checkpoint.processedPostIdSet.contains(post.postId),
              )
              .map(
                (post) => <String, dynamic>{
                  'post_id': post.postId,
                  'title': post.title,
                  'author_name': post.authorName,
                  'submolt_name': post.submoltName,
                  'score': post.score,
                  'comment_count': post.commentCount,
                  'is_verified': post.isVerified,
                  'is_spam': post.isSpam,
                  'created_at_utc': post.createdAtUtc,
                },
              )
              .toList(growable: false),
        },
      ),
    );
    await _ensureMoltbookCycleScope(
      ownerHex,
      binding.accountId,
      cycleEpoch: cycleEpoch,
    );
    final result = response.result;
    if (response.status != PluginHostApiStatus.executed || result == null) {
      throw StateError(
        response.errorMessage ?? 'Moltbook heartbeat planning was rejected',
      );
    }
    final plan = MoltbookHeartbeatPlan.fromHostResult(result);
    await _ensureMoltbookCycleScope(
      ownerHex,
      binding.accountId,
      cycleEpoch: cycleEpoch,
    );
    await uiLog.log(
      'moltbook.heartbeat.plan',
      'success priority=${plan.priority} '
          'candidates=${plan.candidatePostIds.length} '
          'hash=${plan.planHashHex.substring(0, 12)}..',
    );
    return (
      ownerHex: ownerHex,
      accountBindingId: binding.accountId,
      observation: observation,
      plan: plan,
      observedAt: DateTime.parse(observedAtUtc),
    );
  }

  Future<MoltbookCycleSummary> runMoltbookCycle() async {
    final cycleEpoch = _moltbookCycleEpoch;
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(ownerHex)) {
      throw StateError('Active capsule identity is unavailable');
    }
    final binding = await moltbookConnection.loadBinding();
    if (binding == null || !binding.isClaimed || !binding.isActive) {
      throw StateError('Active Moltbook account binding is unavailable');
    }
    final scope =
        '$ownerHex::$moltbookAmbassadorPluginId::${binding.accountId}';
    final existing = _moltbookCycles[scope];
    if (existing != null) {
      if (_moltbookCycleEpochs[scope] == cycleEpoch) return existing;
      try {
        await existing;
      } catch (_) {
        // A stopped predecessor must quiesce before a replacement can start.
      }
      if (cycleEpoch != _moltbookCycleEpoch) {
        throw StateError('Moltbook cycle was stopped');
      }
      return runMoltbookCycle();
    }

    final cycle = _runMoltbookCycle(
      ownerHex: ownerHex,
      accountBindingId: binding.accountId,
      startedAtUtc: DateTime.now().toUtc(),
      cycleEpoch: cycleEpoch,
    );
    _moltbookCycles[scope] = cycle;
    _moltbookCycleEpochs[scope] = cycleEpoch;
    void releaseCycle() {
      if (identical(_moltbookCycles[scope], cycle)) {
        _moltbookCycles.remove(scope);
        _moltbookCycleEpochs.remove(scope);
      }
    }

    cycle.then<void>(
      (_) => releaseCycle(),
      onError: (Object _, StackTrace _) => releaseCycle(),
    );
    return cycle;
  }

  Future<MoltbookCycleSummary> runMoltbookOnDemandCycle() async {
    final scope = await _moltbookCycleScope();
    return moltbookCycleTriggers.runOnDemand(
      scope: scope,
      runCycle: runMoltbookCycle,
    );
  }

  Future<MoltbookCycleSummary?> startConfiguredMoltbookCycles() async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      moltbookCycleTriggers.stopAll();
      return null;
    }
    final scope = await _moltbookCycleScope();
    switch (configuration.triggerPolicy) {
      case MoltbookAmbassadorConfiguration.triggerOnDemand:
        return null;
      case MoltbookAmbassadorConfiguration.triggerSession:
        return moltbookCycleTriggers.startSession(
          scope: scope,
          runCycle: runMoltbookCycle,
        );
      case MoltbookAmbassadorConfiguration.triggerContinuous:
        return moltbookCycleTriggers.startContinuous(
          scope: scope,
          runCycle: runMoltbookCycle,
        );
      default:
        throw StateError('Unsupported Moltbook trigger policy');
    }
  }

  void stopMoltbookCycles() {
    _moltbookCycleEpoch++;
    moltbookCycleTriggers.stopAll();
  }

  Future<void> stopMoltbookCyclesAndDisable() async {
    stopMoltbookCycles();
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) return;
    await _ambassadorConfiguration.save(
      MoltbookAmbassadorConfiguration(
        agentName: configuration.agentName,
        agentDescription: configuration.agentDescription,
        personaSummary: configuration.personaSummary,
        allowedTopics: configuration.allowedTopics,
        approvalMode: configuration.approvalMode,
        triggerPolicy: configuration.triggerPolicy,
        enabled: false,
      ),
    );
  }

  Future<MoltbookCycleTriggerSnapshot?>
  loadMoltbookCycleTriggerSnapshot() async {
    final scope = await _moltbookCycleScope();
    return moltbookCycleTriggers.snapshot(scope);
  }

  Future<MoltbookCycleSummary> _runMoltbookCycle({
    required String ownerHex,
    required String accountBindingId,
    required DateTime startedAtUtc,
    required int cycleEpoch,
  }) async {
    await uiLog.log(
      'moltbook.cycle',
      'wake owner=$ownerHex account=$accountBindingId',
    );
    await _ensureMoltbookCycleScope(
      ownerHex,
      accountBindingId,
      cycleEpoch: cycleEpoch,
    );
    final before = await moltbookFeedCheckpoint.load();
    var reconciledCount = 0;
    var challengedCount = 0;
    var blockedCount = 0;
    final unresolved = (await moltbookPublications.list())
        .where((operation) => operation.state == ExternalEffectState.unresolved)
        .toList(growable: false);
    for (final operation in unresolved) {
      await _ensureMoltbookCycleScope(
        ownerHex,
        accountBindingId,
        cycleEpoch: cycleEpoch,
      );
      try {
        final resolved = await moltbookPublications.process(
          operation.operationId,
        );
        reconciledCount++;
        if (resolved.requiredAction != null ||
            resolved.lastErrorCode == 'verification_required') {
          challengedCount++;
        }
      } catch (error) {
        blockedCount++;
        await uiLog.log(
          'moltbook.cycle.reconcile',
          'blocked operation=${operation.operationId} ${_safeError(error)}',
        );
      }
    }
    await _ensureMoltbookCycleScope(
      ownerHex,
      accountBindingId,
      cycleEpoch: cycleEpoch,
    );
    final heartbeat = await _observeAndPlanMoltbookHeartbeat(
      cycleEpoch: cycleEpoch,
    );
    final heartbeatPlan = heartbeat.plan;
    String? deferredFeedPostId;
    for (final candidatePostId in heartbeatPlan.candidatePostIds) {
      try {
        final selectionKind =
            heartbeatPlan.priority == 'review_activity'
                ? 'own_activity'
                : 'feed_candidate';
        final observedConversation = await observeMoltbookConversation(
          candidatePostId,
        );
        await _ensureMoltbookCycleScope(
          ownerHex,
          accountBindingId,
          cycleEpoch: cycleEpoch,
        );
        final publiclyAnsweredCommentIds =
            observedConversation.comments
                .where(
                  (comment) =>
                      comment.authorId == accountBindingId &&
                      comment.parentCommentId != null,
                )
                .map((comment) => comment.parentCommentId!)
                .toSet();
        final availableComments = <MoltbookCommentObservation>[];
        for (final comment in observedConversation.comments) {
          final unavailable =
              comment.authorId == accountBindingId ||
              publiclyAnsweredCommentIds.contains(comment.commentId) ||
              await moltbookPublications.isReplyTargetUnavailable(
                accountBindingId: accountBindingId,
                postId: observedConversation.post.postId,
                parentCommentId: comment.commentId,
              );
          await _ensureMoltbookCycleScope(
            ownerHex,
            accountBindingId,
            cycleEpoch: cycleEpoch,
          );
          if (!unavailable) availableComments.add(comment);
        }
        if (availableComments.length != observedConversation.comments.length) {
          await uiLog.log(
            'moltbook.cycle.targets',
            'post=${observedConversation.post.postId} '
                'available=${availableComments.length} '
                'excluded=${observedConversation.comments.length - availableComments.length}',
          );
        }
        final conversation = MoltbookConversationObservation(
          post: observedConversation.post,
          comments: availableComments,
          hasMoreComments: observedConversation.hasMoreComments,
          rateLimit: observedConversation.rateLimit,
        );
        final engagementPlan = await planMoltbookEngagement(
          conversation: conversation,
          selectionKind: selectionKind,
        );
        await _ensureMoltbookCycleScope(
          ownerHex,
          accountBindingId,
          cycleEpoch: cycleEpoch,
        );
        if (const <String>{
          'reply_draft',
          'comment_draft',
        }.contains(engagementPlan.actionClass)) {
          final existing = await moltbookPublications.findReplyOperations(
            accountBindingId: accountBindingId,
            postId: engagementPlan.targetPostId,
            parentCommentId: engagementPlan.targetCommentId,
          );
          await _ensureMoltbookCycleScope(
            ownerHex,
            accountBindingId,
            cycleEpoch: cycleEpoch,
          );
          if (existing.isEmpty) {
            final configuration = await _ambassadorConfiguration.load();
            if (const <String>{
              MoltbookAmbassadorConfiguration.approvalAssisted,
              MoltbookAmbassadorConfiguration.approvalBounded,
            }.contains(configuration.approvalMode)) {
              final proposal = await proposeMoltbookReply(
                conversation: conversation,
                engagementPlan: engagementPlan,
              );
              await _ensureMoltbookCycleScope(
                ownerHex,
                accountBindingId,
                cycleEpoch: cycleEpoch,
              );
              final draft = await prepareMoltbookReply(
                engagementPlan: engagementPlan,
                reviewedBody: proposal.body,
              );
              await _ensureMoltbookCycleScope(
                ownerHex,
                accountBindingId,
                cycleEpoch: cycleEpoch,
              );
              final bounded =
                  configuration.approvalMode ==
                  MoltbookAmbassadorConfiguration.approvalBounded;
              final operation = await _advanceMoltbookEngagement(
                engagementPlan: engagementPlan,
                draft: draft,
                policy:
                    bounded
                        ? MoltbookEngagementWritePolicy.bounded
                        : MoltbookEngagementWritePolicy.assisted,
                exactApproval: bounded,
                processAuthorizedEffect: bounded,
                cycleOwnerHex: ownerHex,
                cycleAccountBindingId: accountBindingId,
                cycleEpoch: cycleEpoch,
              );
              await _ensureMoltbookCycleScope(
                ownerHex,
                accountBindingId,
                cycleEpoch: cycleEpoch,
              );
              await uiLog.log(
                bounded ? 'moltbook.cycle.delegate' : 'moltbook.cycle.propose',
                '${bounded ? "processed" : "prepared"} '
                'operation=${operation.operationId} '
                'post=${engagementPlan.targetPostId} '
                'state=${operation.state.wireName}',
              );
              if (bounded &&
                  (operation.requiredAction != null ||
                      operation.lastErrorCode == 'verification_required')) {
                challengedCount++;
              }
              if (bounded &&
                  operation.state == ExternalEffectState.terminalFailure) {
                blockedCount++;
              }
            }
          }
          break;
        } else if (engagementPlan.actionClass != 'no_action') {
          throw StateError(
            'Cycle action ${engagementPlan.actionClass} is not mounted',
          );
        }
      } catch (error) {
        blockedCount++;
        if (heartbeatPlan.priority != 'review_activity') {
          deferredFeedPostId = candidatePostId;
        }
        await uiLog.log(
          'moltbook.cycle.propose',
          'deferred post=$candidatePostId ${_safeError(error)}',
        );
        break;
      }
    }
    await _ensureMoltbookCycleScope(
      ownerHex,
      accountBindingId,
      cycleEpoch: cycleEpoch,
    );
    final committedFeed =
        deferredFeedPostId == null
            ? heartbeat.observation.feed
            : MoltbookFeedObservation(
              posts: heartbeat.observation.feed.posts
                  .where((post) => post.postId != deferredFeedPostId)
                  .toList(growable: false),
              hasMore: heartbeat.observation.feed.hasMore,
              nextCursor: heartbeat.observation.feed.nextCursor,
              rateLimit: heartbeat.observation.feed.rateLimit,
            );
    await moltbookFeedCheckpoint.commit(
      committedFeed,
      observedAt: heartbeat.observedAt,
    );
    final checkpoint = await moltbookFeedCheckpoint.load();
    await _ensureMoltbookCycleScope(
      ownerHex,
      accountBindingId,
      cycleEpoch: cycleEpoch,
    );
    final inspectedCount = checkpoint.processedPostIdSet
        .difference(before.processedPostIdSet)
        .length
        .clamp(0, 100);
    final completedAtUtc = DateTime.now().toUtc();
    final summary = MoltbookCycleSummary(
      ownerCapsuleHex: ownerHex,
      accountBindingId: accountBindingId,
      startedAtUtc: startedAtUtc.toIso8601String(),
      completedAtUtc:
          completedAtUtc.isBefore(startedAtUtc)
              ? startedAtUtc.toIso8601String()
              : completedAtUtc.toIso8601String(),
      inspectedCount: inspectedCount,
      candidateCount: heartbeatPlan.candidatePostIds.length,
      reconciledCount: reconciledCount,
      challengedCount: challengedCount,
      blockedCount: blockedCount,
      heartbeatPlan: heartbeatPlan,
      checkpoint: checkpoint,
    );
    summary.validate();
    await uiLog.log(
      'moltbook.cycle',
      'sleep inspected=${summary.inspectedCount} '
          'candidates=${summary.candidateCount} '
          'reconciled=${summary.reconciledCount} '
          'challenged=${summary.challengedCount} '
          'blocked=${summary.blockedCount}',
    );
    return summary;
  }

  Future<void> _ensureMoltbookCycleScope(
    String ownerHex,
    String accountBindingId, {
    required int cycleEpoch,
  }) async {
    if (cycleEpoch != _moltbookCycleEpoch) {
      throw StateError('Moltbook cycle was stopped');
    }
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError('Moltbook cycle stopped because the Capsule changed');
    }
    final binding = await moltbookConnection.loadBinding();
    if (binding == null ||
        !binding.isClaimed ||
        !binding.isActive ||
        binding.accountId != accountBindingId) {
      throw StateError(
        'Moltbook cycle stopped because the account binding changed',
      );
    }
  }

  Future<String> _moltbookCycleScope() async {
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(ownerHex)) {
      throw StateError('Active capsule identity is unavailable');
    }
    final binding = await moltbookConnection.loadBinding();
    if (binding == null || !binding.isClaimed || !binding.isActive) {
      throw StateError('Active Moltbook account binding is unavailable');
    }
    return '$ownerHex::$moltbookAmbassadorPluginId::${binding.accountId}';
  }

  Future<void> disconnectMoltbook() async {
    await uiLog.log('moltbook.disconnect', 'start');
    try {
      await moltbookConnection.disconnect();
      await uiLog.log('moltbook.disconnect', 'success');
    } catch (error) {
      await uiLog.log('moltbook.disconnect', 'error ${_safeError(error)}');
      rethrow;
    }
  }

  Future<List<MoltbookStoredDraft>> loadMoltbookDrafts() async {
    await _archiveSucceededMoltbookDrafts(await moltbookPublications.list());
    return moltbookDrafts.load();
  }

  Future<List<ExternalEffectOperation>> loadMoltbookPublications() =>
      moltbookPublications.list();

  Future<ExternalEffectOperation> prepareMoltbookPublication({
    required MoltbookDraftPreview draft,
    required String submoltName,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled ||
        !const <String>{
          MoltbookAmbassadorConfiguration.approvalAssisted,
          MoltbookAmbassadorConfiguration.approvalBounded,
        }.contains(configuration.approvalMode)) {
      throw StateError('Assisted Moltbook publication is not enabled');
    }
    final operation = await moltbookPublications.prepare(
      draft: draft,
      submoltName: submoltName,
    );
    if (operation.state == ExternalEffectState.succeeded) {
      await moltbookDrafts.delete(draft.draftHashHex);
    } else {
      await _archiveSucceededMoltbookDrafts(<ExternalEffectOperation>[
        operation,
      ]);
    }
    await uiLog.log(
      'moltbook.publication.prepare',
      'operation=${operation.operationId} '
          'payload=${operation.payloadHashHex.substring(0, 12)}..',
    );
    return operation;
  }

  Future<ExternalEffectOperation> advanceMoltbookEngagement({
    required MoltbookEngagementPlan engagementPlan,
    required MoltbookReplyDraftPreview draft,
    required MoltbookEngagementWritePolicy policy,
    required bool exactApproval,
    bool processAuthorizedEffect = false,
    DateTime? nowUtc,
  }) => _advanceMoltbookEngagement(
    engagementPlan: engagementPlan,
    draft: draft,
    policy: policy,
    exactApproval: exactApproval,
    processAuthorizedEffect: processAuthorizedEffect,
    nowUtc: nowUtc,
  );

  Future<ExternalEffectOperation> _advanceMoltbookEngagement({
    required MoltbookEngagementPlan engagementPlan,
    required MoltbookReplyDraftPreview draft,
    required MoltbookEngagementWritePolicy policy,
    required bool exactApproval,
    required bool processAuthorizedEffect,
    DateTime? nowUtc,
    String? cycleOwnerHex,
    String? cycleAccountBindingId,
    int? cycleEpoch,
  }) async {
    Future<void> ensureCycleScope() async {
      if (cycleOwnerHex == null ||
          cycleAccountBindingId == null ||
          cycleEpoch == null) {
        return;
      }
      await _ensureMoltbookCycleScope(
        cycleOwnerHex,
        cycleAccountBindingId,
        cycleEpoch: cycleEpoch,
      );
    }

    final configuration = await _ambassadorConfiguration.load();
    final policyAllowed = switch (policy) {
      MoltbookEngagementWritePolicy.assisted => const <String>{
        MoltbookAmbassadorConfiguration.approvalAssisted,
        MoltbookAmbassadorConfiguration.approvalBounded,
      }.contains(configuration.approvalMode),
      MoltbookEngagementWritePolicy.bounded =>
        configuration.approvalMode ==
            MoltbookAmbassadorConfiguration.approvalBounded,
    };
    if (!configuration.enabled || !policyAllowed) {
      throw StateError('Moltbook engagement publication is not enabled');
    }
    if (draft.engagementPlanHashHex != engagementPlan.planHashHex ||
        draft.targetPostId != engagementPlan.targetPostId ||
        draft.targetCommentId != engagementPlan.targetCommentId) {
      throw const FormatException(
        'Reply draft does not bind the selected engagement plan',
      );
    }
    if (processAuthorizedEffect && !exactApproval) {
      throw StateError('An unapproved engagement cannot be processed');
    }

    MoltbookDelegatedReplyAuthorization? delegatedAuthorization;
    if (policy == MoltbookEngagementWritePolicy.bounded) {
      if (!exactApproval) {
        throw StateError('Bounded engagement requires explicit enablement');
      }
      delegatedAuthorization = await _authorizeDelegatedMoltbookReply(
        engagementPlan: engagementPlan,
        draft: draft,
        nowUtc: nowUtc,
      );
      await ensureCycleScope();
    }

    final operation = await moltbookPublications.prepareReply(draft: draft);
    await ensureCycleScope();
    await uiLog.log(
      'moltbook.engagement.advance',
      'policy=${policy.name} approval=$exactApproval '
          'operation=${operation.operationId} '
          'payload=${operation.payloadHashHex.substring(0, 12)}..',
    );
    if (!exactApproval) return operation;

    final queued =
        policy == MoltbookEngagementWritePolicy.assisted
            ? await moltbookPublications.approveAndQueue(operation)
            : await _approveDelegatedMoltbookReply(
              operation: operation,
              authorization: delegatedAuthorization!,
              nowUtc: nowUtc,
            );
    await ensureCycleScope();
    if (!processAuthorizedEffect) return queued;
    return moltbookPublications.process(queued.operationId);
  }

  Future<ExternalEffectOperation> approveMoltbookPublication(
    ExternalEffectOperation operation,
  ) async {
    final queued = await moltbookPublications.approveAndQueue(operation);
    await _archiveSucceededMoltbookDrafts(<ExternalEffectOperation>[queued]);
    await uiLog.log(
      'moltbook.publication.approve',
      'operation=${queued.operationId} state=${queued.state.wireName}',
    );
    return queued;
  }

  Future<ExternalEffectOperation> _approveDelegatedMoltbookReply({
    required ExternalEffectOperation operation,
    required MoltbookDelegatedReplyAuthorization authorization,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final observedAt = DateTime.parse(authorization.observedAtUtc).toUtc();
    final authorizationAge = now.difference(observedAt);
    if (authorizationAge.isNegative ||
        authorizationAge > const Duration(minutes: 10)) {
      throw StateError('Delegated reply authorization is stale');
    }
    final usage = await _moltbookDelegationUsage(now);
    if (usage.writesToday != authorization.writesToday ||
        usage.writesToday >= authorization.maxDailyWrites ||
        (usage.minutesSinceLastWrite != null &&
            usage.minutesSinceLastWrite! < authorization.minIntervalMinutes)) {
      throw StateError(
        'Delegated reply policy changed after authorization; authorize again',
      );
    }
    final queued = await moltbookPublications.approveDelegatedReplyAndQueue(
      operation: operation,
      authorization: authorization,
    );
    await uiLog.log(
      'moltbook.reply.delegate.queue',
      'operation=${queued.operationId} state=${queued.state.wireName}',
    );
    return queued;
  }

  Future<({int writesToday, int? minutesSinceLastWrite})>
  _moltbookDelegationUsage(DateTime nowUtc) async {
    final now = nowUtc.toUtc();
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    final committedReplies =
        (await moltbookPublications.list())
            .where(
              (operation) =>
                  operation.effectKind ==
                      MoltbookExternalEffectAdapter.commentEffectKind &&
                  const <ExternalEffectState>{
                    ExternalEffectState.approved,
                    ExternalEffectState.queued,
                    ExternalEffectState.delivering,
                    ExternalEffectState.unresolved,
                    ExternalEffectState.succeeded,
                  }.contains(operation.state),
            )
            .toList()
          ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    final writesToday =
        committedReplies.where((operation) {
          final updated = DateTime.tryParse(operation.updatedAtUtc)?.toUtc();
          return updated != null && !updated.isBefore(dayStart);
        }).length;
    final lastWriteAt =
        committedReplies.isEmpty
            ? null
            : DateTime.tryParse(committedReplies.first.updatedAtUtc)?.toUtc();
    final minutesSinceLastWrite =
        lastWriteAt == null
            ? null
            : now.difference(lastWriteAt).inMinutes.clamp(0, 1000000);
    return (
      writesToday: writesToday,
      minutesSinceLastWrite: minutesSinceLastWrite,
    );
  }

  Future<ExternalEffectOperation> processMoltbookPublication(
    String operationId,
  ) async {
    final result = await moltbookPublications.process(operationId);
    await _archiveSucceededMoltbookDrafts(<ExternalEffectOperation>[result]);
    await uiLog.log(
      'moltbook.publication.process',
      'operation=$operationId state=${result.state.wireName} '
          'error=${result.lastErrorCode ?? "none"}',
    );
    return result;
  }

  Future<ExternalEffectOperation> reconcileMoltbookPublication(
    String operationId, {
    String? providerReferenceId,
  }) async {
    final result = await moltbookPublications.reconcileOnly(
      operationId,
      providerReferenceId: providerReferenceId,
    );
    await _archiveSucceededMoltbookDrafts(<ExternalEffectOperation>[result]);
    await uiLog.log(
      'moltbook.publication.reconcile',
      'operation=$operationId state=${result.state.wireName} '
          'error=${result.lastErrorCode ?? "none"}',
    );
    return result;
  }

  Future<void> _archiveSucceededMoltbookDrafts(
    Iterable<ExternalEffectOperation> operations,
  ) async {
    final hashes = <String>{};
    for (final operation in operations) {
      final hash = MoltbookPublicationService.succeededPostDraftHash(operation);
      if (hash != null) hashes.add(hash);
    }
    if (hashes.isEmpty) return;
    await moltbookDrafts.deleteAll(hashes);
    await uiLog.log('moltbook.draft.archive', 'success count=${hashes.length}');
  }

  Future<ExternalEffectOperation> resolveMoltbookPublicationVerification({
    required String operationId,
    required String answer,
  }) async {
    final result = await moltbookPublications.resolveVerification(
      operationId: operationId,
      answer: answer,
    );
    await _archiveSucceededMoltbookDrafts(<ExternalEffectOperation>[result]);
    await uiLog.log(
      'moltbook.publication.verify',
      'operation=$operationId state=${result.state.wireName} '
          'error=${result.lastErrorCode ?? "none"}',
    );
    return result;
  }

  Future<ExternalEffectOperation> cancelMoltbookPublication(
    String operationId,
  ) => moltbookPublications.cancel(operationId);

  Future<void> deleteMoltbookDraft(String draftHashHex) async {
    final normalizedHash = draftHashHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw ArgumentError('Invalid Moltbook draft hash');
    }
    await moltbookDrafts.delete(normalizedHash);
    await uiLog.log(
      'moltbook.draft.delete',
      'success hash=${normalizedHash.substring(0, 12)}..',
    );
  }

  Future<MoltbookDraftPreview> prepareMoltbookDraft({
    required String bulletinId,
    required String releaseTag,
    required String category,
    required List<String> facts,
    required String titleHint,
    required String reviewedBody,
    required String audience,
    String? publicChangeCommitmentHashHex,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final normalizedCategory = category.trim();
    if (!configuration.allowedTopics.contains(normalizedCategory)) {
      throw StateError('Draft category must match one of the allowed topics');
    }
    final operationCapsuleHex =
        _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (operationCapsuleHex == null || operationCapsuleHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    await uiLog.log(
      'moltbook.draft.prepare',
      'start owner=$operationCapsuleHex bulletin=${_safeLogValue(bulletinId)}',
    );
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: moltbookAmbassadorPluginId,
        method: prepareMoltbookDraftMethod,
        args: <String, dynamic>{
          'schema_version': 1,
          'plugin_id': moltbookAmbassadorPluginId,
          'bulletin_id': bulletinId.trim(),
          'release_tag': releaseTag.trim(),
          'category': normalizedCategory,
          'facts': facts.map((fact) => fact.trim()).toList(),
          'title_hint': titleHint.trim(),
          'reviewed_body': reviewedBody.trim(),
          'audience': audience.trim(),
        },
      ),
    );
    if (!_isStillOwnedBy(operationCapsuleHex)) {
      await uiLog.log(
        'moltbook.draft.prepare',
        'aborted reason=capsule_changed owner=$operationCapsuleHex',
      );
      throw StateError('Draft discarded because the active capsule changed');
    }
    if (response.status != PluginHostApiStatus.executed) {
      final message =
          response.errorMessage ??
          (response.blockingFacts.isEmpty
              ? 'Moltbook draft preparation was rejected'
              : response.blockingFacts.first.label);
      await uiLog.log(
        'moltbook.draft.prepare',
        'rejected code=${response.errorCode ?? response.status.name} '
            'message=${_safeError(message)}',
      );
      throw StateError(message);
    }
    final result = response.result;
    if (result == null) {
      throw StateError('Moltbook draft result is missing');
    }
    final preview = MoltbookDraftPreview.fromHostResult(result);
    if (preview.title != titleHint.trim() ||
        preview.body != reviewedBody.trim()) {
      throw StateError(
        'Installed Moltbook plugin does not preserve the reviewed title/body. Upgrade the plugin before publishing.',
      );
    }
    if (publicChangeCommitmentHashHex != null) {
      final change =
          (await moltbookPublicChanges.load())
              .where(
                (candidate) =>
                    candidate.commitmentHashHex ==
                    publicChangeCommitmentHashHex,
              )
              .singleOrNull;
      if (change == null || !change.isPending) {
        throw StateError('Pending public change is unavailable');
      }
      if (preview.bulletinId != change.sourceId ||
          preview.category != change.category) {
        throw StateError('WASM draft does not match the queued public change');
      }
    }
    await moltbookDrafts.save(preview);
    if (publicChangeCommitmentHashHex != null) {
      await moltbookPublicChanges.markDrafted(
        publicChangeCommitmentHashHex,
        preview.draftHashHex,
      );
    }
    await uiLog.log(
      'moltbook.draft.prepare',
      'success bulletin=${_safeLogValue(preview.bulletinId)} '
          'hash=${preview.draftHashHex.substring(0, 12)}.. '
          'source=${response.executionSource}',
    );
    return preview;
  }

  Future<void> removePlugin(WasmPluginRecord record) async {
    final pluginId = record.pluginId?.trim();
    if (pluginId != null && pluginId.isNotEmpty) {
      await _secretVault.deletePlugin(pluginId);
      await _fileStore.deletePluginStateFromAllCapsules(pluginId);
    }
    await registry.removePlugin(record.id);
  }

  Future<PluginChatSendResult> sendChatMessage({
    required String peerHex,
    required String messageText,
  }) async {
    final normalizedPeer = peerHex.trim().toLowerCase();
    final normalizedMessage = messageText.trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedPeer)) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.rejected,
        message: 'Choose a valid consensus peer before sending',
      );
    }
    if (normalizedMessage.isEmpty) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.rejected,
        message: 'Message text cannot be empty',
      );
    }

    final operationCapsuleHex =
        _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (operationCapsuleHex == null || operationCapsuleHex.length != 64) {
      return const PluginChatSendResult(
        status: PluginChatSendStatus.failed,
        message: 'Active capsule identity is unavailable',
      );
    }

    await uiLog.log(
      'chat.send.request',
      'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
          'fullPeer=$normalizedPeer textBytes=${normalizedMessage.length}',
    );
    final attestation = await attestationExchange.ensureForPeer(normalizedPeer);
    await uiLog.log(
      'chat.attestation.ensure',
      'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
          'status=${attestation.status.name} '
          'receive=${attestation.receiveCode}/${attestation.receivedCount}/${attestation.storedCount} '
          'mismatch=${attestation.mismatchedEvidenceCount} '
          'sent=${attestation.localEvidenceSent} send=${attestation.sendCode ?? "-"}',
    );
    if (!_isStillOwnedBy(operationCapsuleHex)) {
      return _capsuleChanged(operationCapsuleHex);
    }
    if (!attestation.isReady) {
      return PluginChatSendResult(
        status:
            attestation.status == ConsensusAttestationExchangeStatus.syncing
                ? PluginChatSendStatus.syncing
                : PluginChatSendStatus.blocked,
        message:
            attestation.message ?? 'Pair consensus attestation is not ready',
      );
    }

    final createdAtUtc = DateTime.now().toUtc().toIso8601String();
    final response = await pluginHostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: pluginHostApiSchemaVersion,
        pluginId: capsuleChatPluginId,
        method: postCapsuleChatMethod,
        args: <String, dynamic>{
          'peer_hex': normalizedPeer,
          'client_message_id': 'ui-${DateTime.now().microsecondsSinceEpoch}',
          'message_text': normalizedMessage,
          'created_at_utc': createdAtUtc,
        },
      ),
    );
    if (!_isStillOwnedBy(operationCapsuleHex)) {
      return _capsuleChanged(operationCapsuleHex, hostResponse: response);
    }

    switch (response.status) {
      case PluginHostApiStatus.executed:
        final canonicalEnvelopeJson =
            response.result?['canonical_envelope_json']?.toString() ?? '';
        final envelopeHash =
            response.result?['envelope_hash_hex']?.toString().toLowerCase() ??
            '';
        final canonicalMessageText =
            response.result?['message_text']?.toString() ?? normalizedMessage;
        final canonicalCreatedAtUtc =
            response.result?['created_at_utc']?.toString() ?? createdAtUtc;
        final CapsuleChatDeliverySendResult delivery;
        try {
          delivery = await chatDelivery.sendCanonicalEnvelopeWithTimeline(
            capsuleRootHex: operationCapsuleHex,
            peerHex: normalizedPeer,
            canonicalEnvelopeJson: canonicalEnvelopeJson,
            envelopeHashHex: envelopeHash,
            messageText: canonicalMessageText,
            createdAtUtc: canonicalCreatedAtUtc,
          );
        } catch (error) {
          await uiLog.log(
            'chat.send.timeline.error',
            'owner=$operationCapsuleHex phase=prepare error=${_safeError(error)}',
          );
          return const PluginChatSendResult(
            status: PluginChatSendStatus.failed,
            message:
                'Message was not sent because Chat history could not be saved',
          );
        }
        if (!delivery.isSuccess) {
          await uiLog.log(
            'chat.send.transport.error',
            'owner=$operationCapsuleHex code=${delivery.code} '
                'blocked=${delivery.blockedByConsensus} '
                'deliveryPeer=${delivery.deliveryPeerHex ?? "none"} '
                'message=${delivery.errorMessage ?? "unknown"}',
          );
          return PluginChatSendResult(
            status: PluginChatSendStatus.failed,
            message:
                delivery.errorMessage ??
                'Chat transport failed (code ${delivery.code})',
            hostResponse: response,
            delivery: delivery,
          );
        }
        final shortHash =
            envelopeHash.length >= 12
                ? '${envelopeHash.substring(0, 12)}..'
                : envelopeHash;
        await uiLog.log(
          'chat.send.success',
          'owner=$operationCapsuleHex peer=${normalizedPeer.substring(0, 8)}.. '
              'deliveryPeer=${delivery.deliveryPeerHex ?? "none"} '
              'receipts=${delivery.deliveryReceiptCount} '
              'hash=${shortHash.isEmpty ? "none" : shortHash} '
              'source=${response.executionSource}',
        );
        return PluginChatSendResult(
          status: PluginChatSendStatus.sent,
          message: 'Message sent${shortHash.isEmpty ? "" : " · $shortHash"}',
          hostResponse: response,
          delivery: delivery,
        );
      case PluginHostApiStatus.blocked:
        final message =
            response.blockingFacts.isEmpty
                ? 'Consensus guard blocked execution'
                : response.blockingFacts.first.label;
        await uiLog.log('chat.send.blocked', message);
        return PluginChatSendResult(
          status: PluginChatSendStatus.blocked,
          message: message,
          hostResponse: response,
        );
      case PluginHostApiStatus.rejected:
        final message = response.errorMessage ?? 'Chat request rejected';
        await uiLog.log(
          'chat.send.rejected',
          '$message code=${response.errorCode ?? "none"}',
        );
        return PluginChatSendResult(
          status: PluginChatSendStatus.rejected,
          message: message,
          hostResponse: response,
        );
    }
  }

  bool _isStillOwnedBy(String operationCapsuleHex) =>
      _readActiveCapsuleRootHex()?.trim().toLowerCase() == operationCapsuleHex;

  String _safeError(Object error) {
    final compact = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 240 ? compact : compact.substring(0, 240);
  }

  String _safeLogValue(String value) {
    final compact = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return compact.length <= 80 ? compact : compact.substring(0, 80);
  }

  PluginChatSendResult _capsuleChanged(
    String operationCapsuleHex, {
    PluginHostApiResponse? hostResponse,
  }) {
    final activeCapsuleHex = _readActiveCapsuleRootHex() ?? 'none';
    unawaited(
      uiLog.log(
        'chat.send.aborted',
        'reason=capsule_changed owner=$operationCapsuleHex active=$activeCapsuleHex',
      ),
    );
    return PluginChatSendResult(
      status: PluginChatSendStatus.capsuleChanged,
      message: 'Message not sent because the active capsule changed',
      hostResponse: hostResponse,
    );
  }
}

class PluginRuntimeModuleService {
  static final MoltbookCycleTriggerService _moltbookCycleTriggers =
      MoltbookCycleTriggerService();

  final AppRuntimeService runtime;
  final ExternalEffectAdapterResolver? externalEffectAdapterResolver;
  final CapsuleFileStore fileStore;

  const PluginRuntimeModuleService({
    required this.runtime,
    this.externalEffectAdapterResolver,
    this.fileStore = const CapsuleFileStore(),
  });

  PluginRuntimeModule build() {
    final activeCapsuleRootHex = runtime.activeCapsuleRootHex;
    final secretVault = CapsuleScopedSecretVault();
    final provider = MoltbookProviderAdapter();
    final connection = MoltbookConnectionService(
      fileStore: fileStore,
      secretVault: secretVault,
      observer: provider,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    final moltbookAdapter = MoltbookExternalEffectAdapter(
      secretVault: secretVault,
      provider: provider,
    );
    final effects = ExternalEffectService(
      readActiveCapsuleRootHex: activeCapsuleRootHex,
      resolveAdapter:
          externalEffectAdapterResolver ??
          (providerId) =>
              providerId == MoltbookConnectionService.providerId
                  ? moltbookAdapter
                  : null,
      fileStore: fileStore,
    );
    final aiRuntime = CapsuleAiRuntimeService(
      credentialStore: AiDoctorCredentialStore.shared,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
    return PluginRuntimeModule(
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      manualChecks: runtime.buildManualConsensusCheckService(),
      pluginHostApi: runtime.buildPluginHostApiService(),
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      passiveReceive: runtime.passiveReceive,
      contactLabels: runtime.buildCapsuleContactLabelStore(),
      uiLog: const UiEventLogService(),
      externalEffects: effects,
      moltbookConnection: connection,
      moltbookDrafts: MoltbookDraftStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookFeedCheckpoint: MoltbookFeedCheckpointStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookPublications: MoltbookPublicationService(
        connection: connection,
        effects: effects,
      ),
      moltbookPublicBulletinAi: MoltbookPublicBulletinAiService(
        runtime: aiRuntime,
      ),
      moltbookPublicChanges: MoltbookPublicChangeFeedStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      moltbookCycleTriggers: _moltbookCycleTriggers,
      ambassadorConfiguration: MoltbookAmbassadorConfigurationStore(
        fileStore: fileStore,
        readActiveCapsuleRootHex: activeCapsuleRootHex,
      ),
      secretVault: secretVault,
      fileStore: fileStore,
      readActiveCapsuleRootHex: activeCapsuleRootHex,
    );
  }
}
