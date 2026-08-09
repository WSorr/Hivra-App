import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/capsule_chat_delivery_service.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_passive_receive_coordinator.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/moltbook_ambassador_configuration_store.dart';
import 'package:hivra_app/services/moltbook_connection_service.dart';
import 'package:hivra_app/services/moltbook_cycle_trigger_service.dart';
import 'package:hivra_app/services/moltbook_draft_store.dart';
import 'package:hivra_app/services/moltbook_external_effect_adapter.dart';
import 'package:hivra_app/services/moltbook_feed_checkpoint_store.dart';
import 'package:hivra_app/services/moltbook_publication_service.dart';
import 'package:hivra_app/services/moltbook_public_bulletin_ai_service.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_runtime_module_service.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_source_catalog_service.dart';

void main() {
  late String activeRoot;
  late _CycleConnection connection;
  late _MemoryCheckpoint checkpoint;
  late _CyclePublications publications;
  late _EnabledConfiguration configuration;
  late _HeartbeatHost heartbeatHost;
  late _CycleAi ai;
  late _RecordingDraftStore drafts;
  late MoltbookCycleTriggerService triggers;
  late PluginRuntimeModule module;

  PluginRuntimeModule buildModule(MoltbookCycleTriggerService cycleTriggers) {
    return PluginRuntimeModule(
      registry: _UnusedRegistry(),
      sourceCatalog: _UnusedCatalog(),
      manualChecks: _UnusedManualChecks(),
      pluginHostApi: heartbeatHost,
      attestationExchange: _UnusedAttestationExchange(),
      chatDelivery: _UnusedChatDelivery(),
      passiveReceive: _UnusedPassiveReceive(),
      contactLabels: _UnusedContactLabels(),
      uiLog: _SilentLog(),
      externalEffects: _UnusedExternalEffects(),
      moltbookConnection: connection,
      moltbookDrafts: drafts,
      moltbookFeedCheckpoint: checkpoint,
      moltbookPublications: publications,
      moltbookPublicBulletinAi: ai,
      moltbookCycleTriggers: cycleTriggers,
      ambassadorConfiguration: configuration,
      fileStore: _UnusedFileStore(),
      secretVault: _UnusedSecretVault(),
      readActiveCapsuleRootHex: () => activeRoot,
    );
  }

  setUp(() {
    activeRoot = _rootA;
    connection = _CycleConnection();
    checkpoint = _MemoryCheckpoint();
    publications = _CyclePublications();
    configuration = _EnabledConfiguration();
    heartbeatHost = _HeartbeatHost();
    ai = _CycleAi();
    drafts = _RecordingDraftStore();
    triggers = MoltbookCycleTriggerService();
    module = buildModule(triggers);
  });

  test('successful verification archives its exact source draft', () async {
    publications.verificationResult = _succeededPostOperation();

    final result = await module.resolveMoltbookPublicationVerification(
      operationId: publications.verificationResult!.operationId,
      answer: '50',
    );

    expect(result.state, ExternalEffectState.succeeded);
    expect(drafts.deletedHashes, <String>{'f' * 64});
  });

  test('duplicate wake shares one in-flight Capsule account cycle', () async {
    final gate = Completer<void>();
    connection.observationGate = gate.future;

    final first = module.runMoltbookCycle();
    while (connection.observeCount == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = module.runMoltbookCycle();
    await Future<void>.delayed(Duration.zero);
    expect(connection.observeCount, 1);

    gate.complete();
    final summaries = await Future.wait(<Future<MoltbookCycleSummary>>[
      first,
      second,
    ]);

    expect(identical(summaries.first, summaries.last), isTrue);
    expect(checkpoint.commitCount, 1);
    expect(summaries.first.inspectedCount, 2);
  });

  test('later cycle resumes from durable checkpoint boundary', () async {
    final first = await module.runMoltbookCycle();
    expect(first.checkpoint.processedPostIds, <String>['post-2', 'post-1']);

    connection.feedIds = <String>['post-3', 'post-2'];
    final second = await module.runMoltbookCycle();

    expect(second.inspectedCount, 1);
    expect(second.checkpoint.processedPostIds, <String>[
      'post-3',
      'post-2',
      'post-1',
    ]);
    expect(connection.processedSnapshots.last, <String>{'post-2', 'post-1'});
  });

  test('Capsule switch rejects late observation before checkpoint', () async {
    connection.afterObserve = () => activeRoot = _rootB;

    await expectLater(module.runMoltbookCycle(), throwsA(isA<StateError>()));

    expect(checkpoint.commitCount, 0);
  });

  test(
    'stop rejects late observation before WASM planning or checkpoint',
    () async {
      final gate = Completer<void>();
      connection.observationGate = gate.future;

      final cycle = module.runMoltbookOnDemandCycle();
      while (connection.observeCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      module.stopMoltbookCycles();
      gate.complete();

      await expectLater(cycle, throwsA(isA<StateError>()));
      expect(checkpoint.commitCount, 0);
      expect(heartbeatHost.executeCount, 0);
    },
  );

  test('replacement cycle waits for stopped predecessor to quiesce', () async {
    final gate = Completer<void>();
    connection.observationGate = gate.future;

    final stopped = module.runMoltbookOnDemandCycle();
    while (connection.observeCount == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    module.stopMoltbookCycles();
    final replacement = module.runMoltbookOnDemandCycle();
    await Future<void>.delayed(Duration.zero);
    expect(connection.observeCount, 1);

    gate.complete();
    await expectLater(stopped, throwsA(isA<StateError>()));
    final summary = await replacement;

    expect(connection.observeCount, 2);
    expect(heartbeatHost.executeCount, 2);
    expect(summary.inspectedCount, 2);
  });

  test('recreated module stops an older shared in-flight cycle', () async {
    final gate = Completer<void>();
    connection.observationGate = gate.future;

    final cycle = module.runMoltbookOnDemandCycle();
    while (connection.observeCount == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final replacementModule = buildModule(MoltbookCycleTriggerService());
    replacementModule.stopMoltbookCycles();
    gate.complete();

    await expectLater(cycle, throwsA(isA<StateError>()));
    expect(checkpoint.commitCount, 0);
    expect(heartbeatHost.executeCount, 0);
  });

  test('account rotation rejects late observation before checkpoint', () async {
    connection.afterObserve = () => connection.accountId = 'agent-2';

    await expectLater(module.runMoltbookCycle(), throwsA(isA<StateError>()));

    expect(checkpoint.commitCount, 0);
  });

  test('reconciles unresolved effect and surfaces challenge first', () async {
    publications.operations = <ExternalEffectOperation>[_operation()];

    final summary = await module.runMoltbookCycle();

    expect(publications.processedIds, <String>['effect-1']);
    expect(summary.reconciledCount, 1);
    expect(summary.challengedCount, 1);
    expect(summary.blockedCount, 0);
    expect(checkpoint.commitCount, 1);
  });

  test('assisted cycle prepares one local reply without publishing', () async {
    heartbeatHost.engagementAction = 'reply_draft';

    final summary = await module.runMoltbookCycle();

    expect(ai.proposalCount, 1);
    expect(publications.preparedReplies, hasLength(1));
    expect(
      publications.preparedReplies.single.state,
      ExternalEffectState.prepared,
    );
    expect(publications.processedIds, isEmpty);
    expect(summary.blockedCount, 0);
    expect(summary.checkpoint.processedPostIds, <String>['post-2', 'post-1']);
  });

  test(
    'bounded cycle authorizes and processes one exact reply without review',
    () async {
      configuration.approvalMode =
          MoltbookAmbassadorConfiguration.approvalBounded;
      heartbeatHost.engagementAction = 'reply_draft';

      final summary = await module.runMoltbookCycle();

      expect(ai.proposalCount, 1);
      expect(heartbeatHost.authorizationCount, 1);
      expect(publications.delegatedApprovalCount, 1);
      expect(publications.processedIds, <String>['reply-effect-1']);
      expect(publications.verificationResolveCount, 0);
      expect(summary.challengedCount, 1);
      expect(summary.blockedCount, 0);
    },
  );

  test('bounded cycle fails closed after three durable writes today', () async {
    configuration.approvalMode =
        MoltbookAmbassadorConfiguration.approvalBounded;
    heartbeatHost.engagementAction = 'reply_draft';
    final now = DateTime.now().toUtc();
    publications.operations = <ExternalEffectOperation>[
      _committedReply('daily-1', now.subtract(const Duration(hours: 3))),
      _committedReply('daily-2', now.subtract(const Duration(hours: 2))),
      _committedReply('daily-3', now.subtract(const Duration(hours: 1))),
    ];

    final summary = await module.runMoltbookCycle();

    expect(heartbeatHost.authorizationCount, 1);
    expect(publications.preparedReplies, isEmpty);
    expect(publications.delegatedApprovalCount, 0);
    expect(publications.processedIds, isEmpty);
    expect(summary.blockedCount, 1);
  });

  test('bounded cycle cannot delegate a root comment', () async {
    configuration.approvalMode =
        MoltbookAmbassadorConfiguration.approvalBounded;
    heartbeatHost.engagementAction = 'comment_draft';

    final summary = await module.runMoltbookCycle();

    expect(heartbeatHost.authorizationCount, 0);
    expect(publications.preparedReplies, isEmpty);
    expect(publications.delegatedApprovalCount, 0);
    expect(publications.processedIds, isEmpty);
    expect(summary.blockedCount, 1);
  });

  test(
    'bounded cycle skips a closed comment and replies to the next',
    () async {
      configuration.approvalMode =
          MoltbookAmbassadorConfiguration.approvalBounded;
      heartbeatHost.engagementAction = 'reply_draft';
      connection.commentIds = <String>['comment-1', 'comment-2'];
      publications.unavailableCommentIds.add('comment-1');

      final summary = await module.runMoltbookCycle();

      expect(heartbeatHost.authorizedTargetCommentIds, <String>['comment-2']);
      expect(publications.delegatedApprovalCount, 1);
      expect(publications.processedIds, <String>['reply-effect-1']);
      expect(summary.blockedCount, 0);
    },
  );

  test(
    'recreated module enforces interval from durable reply history',
    () async {
      configuration.approvalMode =
          MoltbookAmbassadorConfiguration.approvalBounded;
      heartbeatHost.engagementAction = 'reply_draft';
      publications.operations = <ExternalEffectOperation>[
        _committedReply(
          'recent-1',
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        ),
      ];
      final restartedModule = buildModule(MoltbookCycleTriggerService());

      final summary = await restartedModule.runMoltbookCycle();

      expect(heartbeatHost.authorizationCount, 1);
      expect(publications.preparedReplies, isEmpty);
      expect(publications.delegatedApprovalCount, 0);
      expect(publications.processedIds, isEmpty);
      expect(summary.blockedCount, 1);
    },
  );

  test(
    'Capsule switch after bounded authorization creates no effect',
    () async {
      configuration.approvalMode =
          MoltbookAmbassadorConfiguration.approvalBounded;
      heartbeatHost.engagementAction = 'reply_draft';
      heartbeatHost.afterAuthorization = () => activeRoot = _rootB;

      await expectLater(module.runMoltbookCycle(), throwsA(isA<StateError>()));

      expect(publications.preparedReplies, isEmpty);
      expect(publications.delegatedApprovalCount, 0);
      expect(publications.processedIds, isEmpty);
      expect(checkpoint.commitCount, 0);
    },
  );

  test('Stop after bounded authorization creates no effect', () async {
    configuration.approvalMode =
        MoltbookAmbassadorConfiguration.approvalBounded;
    heartbeatHost.engagementAction = 'reply_draft';
    heartbeatHost.afterAuthorization = module.stopMoltbookCycles;

    await expectLater(module.runMoltbookCycle(), throwsA(isA<StateError>()));

    expect(publications.preparedReplies, isEmpty);
    expect(publications.delegatedApprovalCount, 0);
    expect(publications.processedIds, isEmpty);
    expect(checkpoint.commitCount, 0);
  });

  test('AI failure defers selected feed candidate from checkpoint', () async {
    heartbeatHost.engagementAction = 'reply_draft';
    ai.error = StateError('provider unavailable');

    final summary = await module.runMoltbookCycle();

    expect(summary.blockedCount, 1);
    expect(summary.inspectedCount, 1);
    expect(summary.checkpoint.processedPostIds, <String>['post-1']);
    expect(publications.preparedReplies, isEmpty);
  });

  test('unsupported remote write class stays deferred', () async {
    heartbeatHost.engagementAction = 'upvote_candidate';

    final summary = await module.runMoltbookCycle();

    expect(summary.blockedCount, 1);
    expect(summary.checkpoint.processedPostIds, <String>['post-1']);
    expect(ai.proposalCount, 0);
  });

  test(
    'Capsule switch during AI cannot prepare effect or checkpoint',
    () async {
      heartbeatHost.engagementAction = 'reply_draft';
      ai.afterProposal = () => activeRoot = _rootB;

      await expectLater(module.runMoltbookCycle(), throwsA(isA<StateError>()));

      expect(publications.preparedReplies, isEmpty);
      expect(checkpoint.commitCount, 0);
    },
  );

  test('configured on-demand policy never starts implicitly', () async {
    configuration.triggerPolicy =
        MoltbookAmbassadorConfiguration.triggerOnDemand;

    final summary = await module.startConfiguredMoltbookCycles();

    expect(summary, isNull);
    expect(connection.observeCount, 0);
  });

  test('configured session policy starts once for the runtime scope', () async {
    configuration.triggerPolicy =
        MoltbookAmbassadorConfiguration.triggerSession;

    final first = await module.startConfiguredMoltbookCycles();
    final duplicate = await module.startConfiguredMoltbookCycles();

    expect(first, isNotNull);
    expect(duplicate, isNull);
    expect(connection.observeCount, 1);
  });

  test('stopped session policy resumes exactly once when enabled', () async {
    configuration.triggerPolicy =
        MoltbookAmbassadorConfiguration.triggerSession;

    await module.startConfiguredMoltbookCycles();
    module.stopMoltbookCycles();
    final resumed = await module.startConfiguredMoltbookCycles();
    final duplicate = await module.startConfiguredMoltbookCycles();

    expect(resumed, isNotNull);
    expect(duplicate, isNull);
    expect(connection.observeCount, 2);
  });

  test('persistent stop disables future configured cycles', () async {
    configuration.triggerPolicy =
        MoltbookAmbassadorConfiguration.triggerSession;

    await module.stopMoltbookCyclesAndDisable();
    final summary = await module.startConfiguredMoltbookCycles();

    expect(configuration.enabled, isFalse);
    expect(summary, isNull);
    expect(connection.observeCount, 0);
  });
}

class _UnusedPassiveReceive implements CapsulePassiveReceivePort {
  @override
  Future<CapsulePassiveReceiveResult> trigger({
    required String capsuleHex,
    required CapsulePassiveReceiveReason reason,
    bool quick = true,
    bool manualRetry = false,
  }) => throw UnsupportedError('passive receive is unused');
}

class _CycleConnection implements MoltbookConnectionService {
  int observeCount = 0;
  String accountId = 'agent-1';
  List<String> feedIds = <String>['post-2', 'post-1'];
  List<String> commentIds = <String>['comment-1'];
  Future<void>? observationGate;
  void Function()? afterObserve;
  final List<Set<String>> processedSnapshots = <Set<String>>[];

  @override
  Future<MoltbookConnectionBinding?> loadBinding() async =>
      MoltbookConnectionBinding(
        accountId: accountId,
        accountName: 'Hivra Agent',
        isClaimed: true,
        isActive: true,
        verifiedAtUtc: '2026-08-01T00:00:00.000Z',
      );

  @override
  Future<MoltbookHeartbeatObservation> observeHeartbeat({
    Set<String> processedPostIds = const <String>{},
  }) async {
    observeCount++;
    processedSnapshots.add(Set<String>.from(processedPostIds));
    final gate = observationGate;
    if (gate != null) await gate;
    afterObserve?.call();
    return MoltbookHeartbeatObservation(
      home: const MoltbookHomeObservation(
        accountName: 'Hivra Agent',
        karma: 0,
        unreadNotificationCount: 0,
        activityOnOwnPosts: <MoltbookPostActivityObservation>[],
        suggestedActions: <String>[],
        rateLimit: _rateLimit,
      ),
      feed: MoltbookFeedObservation(
        posts: feedIds.map(_post).toList(growable: false),
        hasMore: false,
        nextCursor: null,
        rateLimit: _rateLimit,
      ),
    );
  }

  @override
  Future<MoltbookConversationObservation> observeConversation(
    String postId,
  ) async => MoltbookConversationObservation(
    post: MoltbookPostObservation(
      postId: postId,
      title: 'Post $postId',
      content: 'Public content',
      authorId: 'author-1',
      authorName: 'Agent',
      submoltName: 'hivra',
      score: 1,
      commentCount: 1,
      isVerified: true,
      isSpam: false,
      isLocked: false,
      createdAtUtc: '2026-08-01T00:00:00.000Z',
      updatedAtUtc: '2026-08-01T00:05:00.000Z',
    ),
    comments: commentIds
        .map(
          (commentId) => MoltbookCommentObservation(
            commentId: commentId,
            postId: postId,
            parentCommentId: null,
            content: 'What changed?',
            authorId: 'reader-$commentId',
            authorName: 'Reader',
            score: 0,
            createdAtUtc: '2026-08-01T00:04:00.000Z',
          ),
        )
        .toList(growable: false),
    hasMoreComments: false,
    rateLimit: _rateLimit,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCheckpoint implements MoltbookFeedCheckpointStore {
  MoltbookFeedCheckpoint value = const MoltbookFeedCheckpoint.empty();
  int commitCount = 0;

  @override
  Future<MoltbookFeedCheckpoint> load() async => value;

  @override
  Future<MoltbookFeedCheckpoint> commit(
    MoltbookFeedObservation observation, {
    required DateTime observedAt,
  }) async {
    commitCount++;
    value = value.advance(observation, observedAt: observedAt);
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeartbeatHost implements PluginHostApiService {
  int executeCount = 0;
  int authorizationCount = 0;
  final List<String> authorizedTargetCommentIds = <String>[];
  String engagementAction = 'no_action';
  void Function()? afterAuthorization;

  @override
  Future<PluginHostApiResponse> executeWithRuntimeHook(
    PluginHostApiRequest request,
  ) async {
    executeCount++;
    if (request.method == planMoltbookEngagementMethod) {
      return _engagementResponse(request);
    }
    if (request.method == prepareMoltbookReplyMethod) {
      return _replyDraftResponse(request);
    }
    if (request.method == authorizeMoltbookDelegatedReplyMethod) {
      authorizationCount++;
      authorizedTargetCommentIds.add(
        request.args['target_comment_id'] as String,
      );
      final writesToday = request.args['writes_today'] as int;
      final maxDailyWrites = request.args['max_daily_writes'] as int;
      final minutesSinceLastWrite =
          request.args['minutes_since_last_write'] as int?;
      final minIntervalMinutes = request.args['min_interval_minutes'] as int;
      if (writesToday >= maxDailyWrites ||
          (minutesSinceLastWrite != null &&
              minutesSinceLastWrite < minIntervalMinutes)) {
        throw StateError('Delegated reply policy denied authorization');
      }
      final response = _delegatedAuthorizationResponse(request);
      afterAuthorization?.call();
      return response;
    }
    final observedAt = request.args['observed_at_utc'] as String;
    final feed = request.args['feed'] as List<dynamic>;
    final candidates = feed
        .map((value) => (value as Map<String, dynamic>)['post_id'] as String)
        .take(5)
        .toList(growable: false);
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': moltbookAmbassadorPluginId,
      'contract_kind': 'moltbook_ambassador_heartbeat_plan',
      'observed_at_utc': observedAt,
      'priority': candidates.isEmpty ? 'idle' : 'inspect_feed',
      'reason': candidates.isEmpty ? 'No new feed items' : 'Review new items',
      'candidate_post_ids': candidates,
      'publish_allowed': false,
      'human_review_required': true,
      'safety_flags': <String>[
        'remote_content_untrusted',
        'no_external_effect',
      ],
    });
    final result = <String, dynamic>{
      'schema_version': 1,
      'plugin_id': moltbookAmbassadorPluginId,
      'contract_kind': 'moltbook_ambassador_heartbeat_plan',
      'observed_at_utc': observedAt,
      'priority': candidates.isEmpty ? 'idle' : 'inspect_feed',
      'reason': candidates.isEmpty ? 'No new feed items' : 'Review new items',
      'candidate_post_ids': candidates,
      'publish_allowed': false,
      'human_review_required': true,
      'safety_flags': <String>[
        'remote_content_untrusted',
        'no_external_effect',
      ],
      'canonical_plan_json': canonical,
      'plan_hash_hex': sha256.convert(utf8.encode(canonical)).toString(),
    };
    return PluginHostApiResponse(
      status: PluginHostApiStatus.executed,
      pluginId: moltbookAmbassadorPluginId,
      method: request.method,
      executionSource: 'test',
      executionPackageId: null,
      executionPackageVersion: null,
      executionPackageKind: null,
      executionPackageDigestHex: null,
      executionContractKind: null,
      executionRuntimeMode: null,
      executionRuntimeAbi: null,
      executionRuntimeEntryExport: null,
      executionRuntimeModulePath: null,
      executionRuntimeModuleSelection: null,
      executionRuntimeModuleDigestHex: null,
      executionRuntimeInvokeDigestHex: null,
      executionCapabilities: const <String>[],
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
      canonicalJson: canonical,
      responseHashHex: sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  PluginHostApiResponse _engagementResponse(PluginHostApiRequest request) {
    final observedAt = request.args['observed_at_utc'] as String;
    final post = request.args['post'] as Map<String, dynamic>;
    final comments = request.args['comments'] as List<dynamic>;
    final targetCommentId =
        engagementAction == 'reply_draft' && comments.isNotEmpty
            ? (comments.first as Map<String, dynamic>)['comment_id'] as String
            : null;
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': moltbookAmbassadorPluginId,
      'contract_kind': 'moltbook_ambassador_engagement_plan',
      'observed_at_utc': observedAt,
      'action_class': engagementAction,
      'target_post_id': post['post_id'],
      'target_comment_id': targetCommentId,
      'reason':
          engagementAction == 'no_action'
              ? 'No useful reply is required.'
              : 'A factual reply may be useful.',
      'publish_allowed': false,
      'human_review_required': true,
      'safety_flags': <String>[
        'remote_content_untrusted',
        'no_external_effect',
        'ai_text_not_generated',
      ],
    });
    return _response(request, <String, dynamic>{
      ...jsonDecode(canonical) as Map<String, dynamic>,
      'canonical_plan_json': canonical,
      'plan_hash_hex': sha256.convert(utf8.encode(canonical)).toString(),
    }, canonical);
  }

  PluginHostApiResponse _replyDraftResponse(PluginHostApiRequest request) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': moltbookAmbassadorPluginId,
      'contract_kind': 'moltbook_ambassador_reply_draft',
      'target_post_id': request.args['target_post_id'],
      'target_comment_id': request.args['target_comment_id'],
      'engagement_plan_hash_hex': request.args['engagement_plan_hash_hex'],
      'body': request.args['reviewed_body'],
      'approval_required': true,
      'safety_flags': <String>[
        'exact_reply_draft_bound',
        'engagement_plan_bound',
      ],
    });
    return _response(request, <String, dynamic>{
      ...jsonDecode(canonical) as Map<String, dynamic>,
      'canonical_draft_json': canonical,
      'draft_hash_hex': sha256.convert(utf8.encode(canonical)).toString(),
    }, canonical);
  }

  PluginHostApiResponse _delegatedAuthorizationResponse(
    PluginHostApiRequest request,
  ) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': moltbookAmbassadorPluginId,
      'contract_kind': 'moltbook_ambassador_delegated_reply_authorization',
      'target_post_id': request.args['target_post_id'],
      'target_comment_id': request.args['target_comment_id'],
      'engagement_plan_hash_hex': request.args['engagement_plan_hash_hex'],
      'reply_draft_hash_hex': request.args['reply_draft_hash_hex'],
      'policy_version': request.args['policy_version'],
      'max_daily_writes': request.args['max_daily_writes'],
      'writes_today': request.args['writes_today'],
      'min_interval_minutes': request.args['min_interval_minutes'],
      'observed_at_utc': request.args['observed_at_utc'],
      'publish_allowed': true,
      'human_review_required': false,
      'safety_flags': <String>[
        'exact_reply_draft_bound',
        'engagement_plan_bound',
      ],
    });
    return _response(request, <String, dynamic>{
      ...jsonDecode(canonical) as Map<String, dynamic>,
      'canonical_authorization_json': canonical,
      'authorization_hash_hex':
          sha256.convert(utf8.encode(canonical)).toString(),
    }, canonical);
  }

  PluginHostApiResponse _response(
    PluginHostApiRequest request,
    Map<String, dynamic> result,
    String canonical,
  ) => PluginHostApiResponse(
    status: PluginHostApiStatus.executed,
    pluginId: moltbookAmbassadorPluginId,
    method: request.method,
    executionSource: 'test',
    executionPackageId: null,
    executionPackageVersion: null,
    executionPackageKind: null,
    executionPackageDigestHex: null,
    executionContractKind: null,
    executionRuntimeMode: null,
    executionRuntimeAbi: null,
    executionRuntimeEntryExport: null,
    executionRuntimeModulePath: null,
    executionRuntimeModuleSelection: null,
    executionRuntimeModuleDigestHex: null,
    executionRuntimeInvokeDigestHex: null,
    executionCapabilities: const <String>[],
    errorCode: null,
    errorMessage: null,
    blockingFacts: const <ConsensusBlockingFact>[],
    result: result,
    canonicalJson: canonical,
    responseHashHex: sha256.convert(utf8.encode(canonical)).toString(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EnabledConfiguration implements MoltbookAmbassadorConfigurationStore {
  String approvalMode = MoltbookAmbassadorConfiguration.approvalAssisted;
  String triggerPolicy = MoltbookAmbassadorConfiguration.triggerOnDemand;
  bool enabled = true;

  @override
  Future<MoltbookAmbassadorConfiguration> load() async =>
      MoltbookAmbassadorConfiguration(
        agentName: 'Hivra Agent',
        agentDescription: 'Capsule ambassador',
        personaSummary: 'Technical Hivra updates',
        allowedTopics: const <String>['hivra'],
        approvalMode: approvalMode,
        triggerPolicy: triggerPolicy,
        enabled: enabled,
      );

  @override
  Future<void> save(MoltbookAmbassadorConfiguration configuration) async {
    approvalMode = configuration.approvalMode;
    triggerPolicy = configuration.triggerPolicy;
    enabled = configuration.enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CyclePublications implements MoltbookPublicationService {
  List<ExternalEffectOperation> operations = <ExternalEffectOperation>[];
  final List<String> processedIds = <String>[];
  final List<ExternalEffectOperation> preparedReplies =
      <ExternalEffectOperation>[];
  ExternalEffectOperation? verificationResult;
  int delegatedApprovalCount = 0;
  int verificationResolveCount = 0;
  final Set<String> unavailableCommentIds = <String>{};

  @override
  Future<List<ExternalEffectOperation>> list() async => operations;

  @override
  Future<ExternalEffectOperation> process(String operationId) async {
    processedIds.add(operationId);
    return _operation(challenged: true);
  }

  @override
  Future<ExternalEffectOperation> approveDelegatedReplyAndQueue({
    required ExternalEffectOperation operation,
    required MoltbookDelegatedReplyAuthorization authorization,
  }) async {
    delegatedApprovalCount++;
    return operation;
  }

  @override
  Future<ExternalEffectOperation> resolveVerification({
    required String operationId,
    required String answer,
  }) async {
    verificationResolveCount++;
    return verificationResult!;
  }

  @override
  Future<List<ExternalEffectOperation>> findReplyOperations({
    required String accountBindingId,
    required String postId,
    required String? parentCommentId,
  }) async => preparedReplies;

  @override
  Future<bool> isReplyTargetUnavailable({
    required String accountBindingId,
    required String postId,
    required String parentCommentId,
  }) async => unavailableCommentIds.contains(parentCommentId);

  @override
  Future<ExternalEffectOperation> prepareReply({
    required MoltbookReplyDraftPreview draft,
  }) async {
    if (preparedReplies.isNotEmpty) return preparedReplies.single;
    final operation = ExternalEffectOperation(
      ownerCapsuleHex: _rootA,
      operationId: 'reply-effect-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'agent-1',
      effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
      canonicalPayloadJson: jsonEncode(<String, dynamic>{
        'schema_version': 2,
        'account_name': 'Hivra Agent',
        'post_id': draft.targetPostId,
        'parent_comment_id': draft.targetCommentId,
        'content': draft.body,
      }),
      payloadHashHex:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      state: ExternalEffectState.prepared,
      approvalEvidenceHashHex: null,
      attemptCount: 0,
      revision: 0,
      createdAtUtc: '2026-08-01T00:00:00.000Z',
      updatedAtUtc: '2026-08-01T00:00:00.000Z',
      lastErrorCode: null,
      lastErrorMessage: null,
      requiredAction: null,
      receipt: null,
    );
    preparedReplies.add(operation);
    operations.add(operation);
    return operation;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentLog implements UiEventLogService {
  @override
  Future<void> log(String source, String message) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const MoltbookRateLimitSnapshot _rateLimit = MoltbookRateLimitSnapshot(
  limit: 100,
  remaining: 99,
  resetEpochSeconds: null,
  retryAfterSeconds: null,
);

MoltbookFeedPost _post(String id) => MoltbookFeedPost(
  postId: id,
  title: 'Post $id',
  content: 'Public content',
  authorId: 'author-1',
  authorName: 'Agent',
  submoltName: 'hivra',
  score: 1,
  commentCount: 0,
  isVerified: true,
  isSpam: false,
  createdAtUtc: '2026-08-01T00:00:00.000Z',
);

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ExternalEffectOperation _operation({bool challenged = false}) =>
    ExternalEffectOperation(
      ownerCapsuleHex: _rootA,
      operationId: 'effect-1',
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'agent-1',
      effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
      canonicalPayloadJson: '{}',
      payloadHashHex:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      state: ExternalEffectState.unresolved,
      approvalEvidenceHashHex: null,
      attemptCount: 1,
      revision: 1,
      createdAtUtc: '2026-08-01T00:00:00.000Z',
      updatedAtUtc: '2026-08-01T00:00:00.000Z',
      lastErrorCode: challenged ? 'verification_required' : 'network_timeout',
      lastErrorMessage: challenged ? 'Complete challenge' : 'Timed out',
      requiredAction:
          challenged
              ? const ExternalEffectRequiredAction(
                kind: 'numeric_challenge',
                providerReferenceId: 'challenge-1',
                actionToken: 'token',
                prompt: '2 + 2',
                expiresAtUtc: '2026-08-01T01:00:00.000Z',
              )
              : null,
      receipt: null,
    );

ExternalEffectOperation _committedReply(String operationId, DateTime updated) =>
    ExternalEffectOperation(
      ownerCapsuleHex: _rootA,
      operationId: operationId,
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountBindingId: 'agent-1',
      effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
      canonicalPayloadJson: '{}',
      payloadHashHex:
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      state: ExternalEffectState.succeeded,
      approvalEvidenceHashHex:
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      attemptCount: 1,
      revision: 2,
      createdAtUtc:
          updated.subtract(const Duration(minutes: 1)).toIso8601String(),
      updatedAtUtc: updated.toIso8601String(),
      lastErrorCode: null,
      lastErrorMessage: null,
      requiredAction: null,
      receipt: null,
    );

class _UnusedRegistry implements WasmPluginRegistryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCatalog implements WasmPluginSourceCatalogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedManualChecks implements ManualConsensusCheckService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAttestationExchange
    implements ConsensusAttestationExchangeService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedChatDelivery implements CapsuleChatDeliveryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedContactLabels implements CapsuleContactLabelStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedExternalEffects implements ExternalEffectService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingDraftStore implements MoltbookDraftStore {
  final Set<String> deletedHashes = <String>{};

  @override
  Future<void> deleteAll(Set<String> draftHashHexes) async {
    deletedHashes.addAll(draftHashHexes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExternalEffectOperation _succeededPostOperation() {
  const operationId = 'moltbook-post-verified';
  return ExternalEffectOperation(
    ownerCapsuleHex: _rootA,
    operationId: operationId,
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'agent-1',
    effectKind: 'moltbook.post.create',
    canonicalPayloadJson: '{"source_draft_hash_hex":"${'f' * 64}"}',
    payloadHashHex: 'c' * 64,
    state: ExternalEffectState.succeeded,
    approvalEvidenceHashHex: 'd' * 64,
    attemptCount: 1,
    revision: 3,
    createdAtUtc: '2026-08-01T00:00:00.000Z',
    updatedAtUtc: '2026-08-01T00:01:00.000Z',
    lastErrorCode: null,
    lastErrorMessage: null,
    requiredAction: null,
    receipt: const ExternalEffectReceipt(
      operationId: operationId,
      providerId: 'moltbook',
      providerReceiptId: 'post-1',
      evidenceHashHex:
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      receivedAtUtc: '2026-08-01T00:01:00.000Z',
    ),
  );
}

class _CycleAi implements MoltbookPublicBulletinAiService {
  int proposalCount = 0;
  Object? error;
  void Function()? afterProposal;

  @override
  Future<MoltbookReplyProposal> proposeReply({
    required MoltbookConversationObservation conversation,
    required MoltbookEngagementPlan engagementPlan,
    required String personaSummary,
  }) async {
    proposalCount++;
    final failure = error;
    if (failure != null) throw failure;
    afterProposal?.call();
    return const MoltbookReplyProposal(
      body: 'This is a bounded factual reply.',
      groundingPoints: <String>['Public post and recent comment'],
      providerLabel: 'Gemini',
      model: 'test-model',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedFileStore implements CapsuleFileStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSecretVault implements CapsuleScopedSecretVault {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
