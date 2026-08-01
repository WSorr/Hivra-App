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
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/consensus_attestation_exchange_service.dart';
import 'package:hivra_app/services/external_effect_service.dart';
import 'package:hivra_app/services/manual_consensus_check_service.dart';
import 'package:hivra_app/services/moltbook_ambassador_configuration_store.dart';
import 'package:hivra_app/services/moltbook_connection_service.dart';
import 'package:hivra_app/services/moltbook_cycle_trigger_service.dart';
import 'package:hivra_app/services/moltbook_draft_store.dart';
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
      contactLabels: _UnusedContactLabels(),
      uiLog: _SilentLog(),
      externalEffects: _UnusedExternalEffects(),
      moltbookConnection: connection,
      moltbookDrafts: _UnusedDraftStore(),
      moltbookFeedCheckpoint: checkpoint,
      moltbookPublications: publications,
      moltbookPublicBulletinAi: _UnusedAi(),
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
    triggers = MoltbookCycleTriggerService();
    module = buildModule(triggers);
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
    expect(heartbeatHost.executeCount, 1);
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

class _CycleConnection implements MoltbookConnectionService {
  int observeCount = 0;
  String accountId = 'agent-1';
  List<String> feedIds = <String>['post-2', 'post-1'];
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

  @override
  Future<PluginHostApiResponse> executeWithRuntimeHook(
    PluginHostApiRequest request,
  ) async {
    executeCount++;
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EnabledConfiguration implements MoltbookAmbassadorConfigurationStore {
  String triggerPolicy = MoltbookAmbassadorConfiguration.triggerOnDemand;
  bool enabled = true;

  @override
  Future<MoltbookAmbassadorConfiguration> load() async =>
      MoltbookAmbassadorConfiguration(
        agentName: 'Hivra Agent',
        agentDescription: 'Capsule ambassador',
        personaSummary: 'Technical Hivra updates',
        allowedTopics: const <String>['hivra'],
        approvalMode: MoltbookAmbassadorConfiguration.approvalAssisted,
        triggerPolicy: triggerPolicy,
        enabled: enabled,
      );

  @override
  Future<void> save(MoltbookAmbassadorConfiguration configuration) async {
    triggerPolicy = configuration.triggerPolicy;
    enabled = configuration.enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CyclePublications implements MoltbookPublicationService {
  List<ExternalEffectOperation> operations = <ExternalEffectOperation>[];
  final List<String> processedIds = <String>[];

  @override
  Future<List<ExternalEffectOperation>> list() async => operations;

  @override
  Future<ExternalEffectOperation> process(String operationId) async {
    processedIds.add(operationId);
    return _operation(challenged: true);
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
      effectKind: 'comment.create',
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

class _UnusedDraftStore implements MoltbookDraftStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAi implements MoltbookPublicBulletinAiService {
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
