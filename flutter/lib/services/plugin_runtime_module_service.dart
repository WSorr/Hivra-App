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
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';
import 'capsule_chat_delivery_service.dart';
import 'capsule_contact_label_store.dart';
import 'consensus_attestation_exchange_service.dart';
import 'external_effect_service.dart';
import 'manual_consensus_check_service.dart';
import 'moltbook_ambassador_configuration_store.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_draft_store.dart';
import 'moltbook_external_effect_adapter.dart';
import 'moltbook_feed_checkpoint_store.dart';
import 'moltbook_publication_service.dart';
import 'moltbook_public_bulletin_ai_service.dart';
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
  final WasmPluginRegistryService registry;
  final WasmPluginSourceCatalogService sourceCatalog;
  final ManualConsensusCheckService manualChecks;
  final PluginHostApiService pluginHostApi;
  final ConsensusAttestationExchangeService attestationExchange;
  final CapsuleChatDeliveryService chatDelivery;
  final CapsuleContactLabelStore contactLabels;
  final UiEventLogService uiLog;
  final ExternalEffectService externalEffects;
  final MoltbookConnectionService moltbookConnection;
  final MoltbookDraftStore moltbookDrafts;
  final MoltbookFeedCheckpointStore moltbookFeedCheckpoint;
  final MoltbookPublicationService moltbookPublications;
  final MoltbookPublicBulletinAiService moltbookPublicBulletinAi;
  final MoltbookAmbassadorConfigurationStore _ambassadorConfiguration;
  final CapsuleFileStore _fileStore;
  final CapsuleScopedSecretVault _secretVault;
  final String? Function() _readActiveCapsuleRootHex;

  const PluginRuntimeModule({
    required this.registry,
    required this.sourceCatalog,
    required this.manualChecks,
    required this.pluginHostApi,
    required this.attestationExchange,
    required this.chatDelivery,
    required this.contactLabels,
    required this.uiLog,
    required this.externalEffects,
    required this.moltbookConnection,
    required this.moltbookDrafts,
    required this.moltbookFeedCheckpoint,
    required this.moltbookPublications,
    required this.moltbookPublicBulletinAi,
    required MoltbookAmbassadorConfigurationStore ambassadorConfiguration,
    required CapsuleFileStore fileStore,
    required CapsuleScopedSecretVault secretVault,
    required String? Function() readActiveCapsuleRootHex,
  }) : _ambassadorConfiguration = ambassadorConfiguration,
       _fileStore = fileStore,
       _secretVault = secretVault,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex;

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

  Future<MoltbookHeartbeatPlan> planMoltbookHeartbeat() async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled) {
      throw StateError('Moltbook Ambassador is disabled');
    }
    final ownerHex = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (ownerHex == null || ownerHex.length != 64) {
      throw StateError('Active capsule identity is unavailable');
    }
    await uiLog.log('moltbook.heartbeat.plan', 'start owner=$ownerHex');
    final checkpoint = await moltbookFeedCheckpoint.load();
    final observation = await moltbookConnection.observeHeartbeat(
      processedPostIds: checkpoint.processedPostIdSet,
    );
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Heartbeat discarded because the active capsule changed',
      );
    }
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
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Heartbeat discarded because the active capsule changed',
      );
    }
    final result = response.result;
    if (response.status != PluginHostApiStatus.executed || result == null) {
      throw StateError(
        response.errorMessage ?? 'Moltbook heartbeat planning was rejected',
      );
    }
    final plan = MoltbookHeartbeatPlan.fromHostResult(result);
    await moltbookFeedCheckpoint.commit(
      observation.feed,
      observedAt: DateTime.parse(observedAtUtc),
    );
    if (!_isStillOwnedBy(ownerHex)) {
      throw StateError(
        'Heartbeat checkpoint discarded because the active capsule changed',
      );
    }
    await uiLog.log(
      'moltbook.heartbeat.plan',
      'success priority=${plan.priority} '
          'candidates=${plan.candidatePostIds.length} '
          'hash=${plan.planHashHex.substring(0, 12)}..',
    );
    return plan;
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

  Future<List<MoltbookStoredDraft>> loadMoltbookDrafts() =>
      moltbookDrafts.load();

  Future<List<ExternalEffectOperation>> loadMoltbookPublications() =>
      moltbookPublications.list();

  Future<ExternalEffectOperation> prepareMoltbookPublication({
    required MoltbookDraftPreview draft,
    required String submoltName,
  }) async {
    final configuration = await _ambassadorConfiguration.load();
    if (!configuration.enabled ||
        configuration.approvalMode !=
            MoltbookAmbassadorConfiguration.approvalAssisted) {
      throw StateError('Assisted Moltbook publication is not enabled');
    }
    final operation = await moltbookPublications.prepare(
      draft: draft,
      submoltName: submoltName,
    );
    await uiLog.log(
      'moltbook.publication.prepare',
      'operation=${operation.operationId} '
          'payload=${operation.payloadHashHex.substring(0, 12)}..',
    );
    return operation;
  }

  Future<ExternalEffectOperation> approveMoltbookPublication(
    ExternalEffectOperation operation,
  ) async {
    final queued = await moltbookPublications.approveAndQueue(operation);
    await uiLog.log(
      'moltbook.publication.approve',
      'operation=${queued.operationId} state=${queued.state.wireName}',
    );
    return queued;
  }

  Future<ExternalEffectOperation> processMoltbookPublication(
    String operationId,
  ) async {
    final result = await moltbookPublications.process(operationId);
    await uiLog.log(
      'moltbook.publication.process',
      'operation=$operationId state=${result.state.wireName} '
          'error=${result.lastErrorCode ?? "none"}',
    );
    return result;
  }

  Future<ExternalEffectOperation> resolveMoltbookPublicationVerification({
    required String operationId,
    required String answer,
  }) async {
    final result = await moltbookPublications.resolveVerification(
      operationId: operationId,
      answer: answer,
    );
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
    await moltbookDrafts.save(preview);
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
        final delivery = await chatDelivery.sendCanonicalEnvelope(
          peerHex: normalizedPeer,
          canonicalEnvelopeJson: canonicalEnvelopeJson,
          expectedCapsuleRootHex: operationCapsuleHex,
        );
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
        final envelopeHash =
            response.result?['envelope_hash_hex']?.toString() ?? '';
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
    return PluginRuntimeModule(
      registry: const WasmPluginRegistryService(),
      sourceCatalog: const WasmPluginSourceCatalogService(),
      manualChecks: runtime.buildManualConsensusCheckService(),
      pluginHostApi: runtime.buildPluginHostApiService(),
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
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
        credentialStore: AiDoctorCredentialStore(),
      ),
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
