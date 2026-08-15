import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'moltbook_provider_models.dart';
import 'plugin_contract_ids.dart';

final RegExp _unsafePublicTextControls = RegExp(
  r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);

const String moltbookPersonFirstRuntimeSubmoltName = 'person-first-runtime';
const String moltbookPersonFirstRuntimeSubmoltDisplayName =
    'Person-First Runtime';
const String moltbookPersonFirstRuntimeSubmoltDescription =
    'Architecture where the person—not an application or AI agent—is the '
    'primary execution context. Identity, relationships, rules, history, '
    'capabilities, and continuity remain person-owned, while apps and agents '
    'stay replaceable.';

bool _containsUnsafePublicTextControls(String value) =>
    _unsafePublicTextControls.hasMatch(value);

class MoltbookPublicBulletinProposal {
  static final RegExp _forbiddenPositioning = RegExp(
    r'\b(?:relationship-first|concept system)\b',
    caseSensitive: false,
  );

  final String title;
  final String body;
  final List<String> facts;
  final String providerLabel;
  final String model;

  const MoltbookPublicBulletinProposal({
    required this.title,
    required this.body,
    required this.facts,
    required this.providerLabel,
    required this.model,
  });

  void validate() {
    if (title.trim() != title || title.isEmpty || title.length > 120) {
      throw const FormatException(
        'AI public bulletin title is outside safe bounds',
      );
    }
    if (body.trim() != body || body.isEmpty || body.length > 1200) {
      throw const FormatException(
        'AI public bulletin body is outside safe bounds',
      );
    }
    if (_containsUnsafePublicTextControls('$title\n$body')) {
      throw const FormatException(
        'AI public bulletin contains hidden text controls',
      );
    }
    if (body.contains(
      RegExp(r'https?://|#\w|\[hivra-effect:', caseSensitive: false),
    )) {
      throw const FormatException(
        'AI public bulletin body contains unsupported formatting',
      );
    }
    if (_forbiddenPositioning.hasMatch('$title\n$body')) {
      throw const FormatException(
        'AI public bulletin contradicts the Capsule-first product axis',
      );
    }
    if (facts.isEmpty ||
        facts.length > 8 ||
        facts.toSet().length != facts.length) {
      throw const FormatException(
        'AI public bulletin must contain 1..8 unique supporting facts',
      );
    }
    for (final fact in facts) {
      if (fact.trim() != fact ||
          fact.isEmpty ||
          fact.length > 280 ||
          _containsUnsafePublicTextControls(fact)) {
        throw const FormatException('AI public fact is outside safe bounds');
      }
    }
    if (providerLabel.isEmpty ||
        providerLabel.length > 64 ||
        model.isEmpty ||
        model.length > 128) {
      throw const FormatException('AI public facts model is invalid');
    }
  }
}

class MoltbookReplyProposal {
  final String body;
  final List<String> groundingPoints;
  final String providerLabel;
  final String model;

  const MoltbookReplyProposal({
    required this.body,
    required this.groundingPoints,
    required this.providerLabel,
    required this.model,
  });

  void validate() {
    if (body.trim() != body || body.isEmpty || body.length > 2000) {
      throw const FormatException('AI reply body is outside safe bounds');
    }
    if (_containsUnsafePublicTextControls(body)) {
      throw const FormatException('AI reply contains hidden text controls');
    }
    if (body.contains(
      RegExp(
        r'https?://|\[hivra-effect:|api[_ -]?key|seed phrase',
        caseSensitive: false,
      ),
    )) {
      throw const FormatException('AI reply contains unsupported content');
    }
    if (groundingPoints.isEmpty ||
        groundingPoints.length > 6 ||
        groundingPoints.toSet().length != groundingPoints.length) {
      throw const FormatException(
        'AI reply must contain 1..6 unique grounding points',
      );
    }
    for (final point in groundingPoints) {
      if (point.trim() != point ||
          point.isEmpty ||
          point.length > 280 ||
          _containsUnsafePublicTextControls(point)) {
        throw const FormatException(
          'AI reply grounding point is outside safe bounds',
        );
      }
    }
    if (providerLabel.isEmpty ||
        providerLabel.length > 64 ||
        model.isEmpty ||
        model.length > 128) {
      throw const FormatException('AI reply model is invalid');
    }
  }
}

class MoltbookDraftPreview {
  final String bulletinId;
  final String releaseTag;
  final String category;
  final String title;
  final String body;
  final String audience;
  final bool approvalRequired;
  final List<String> safetyFlags;
  final String draftHashHex;
  final String canonicalDraftJson;

  const MoltbookDraftPreview({
    required this.bulletinId,
    required this.releaseTag,
    required this.category,
    required this.title,
    required this.body,
    required this.audience,
    required this.approvalRequired,
    required this.safetyFlags,
    required this.draftHashHex,
    required this.canonicalDraftJson,
  });

  factory MoltbookDraftPreview.fromHostResult(Map<String, dynamic> result) {
    if (result['schema_version'] != 1 ||
        result['plugin_id'] != moltbookAmbassadorPluginId ||
        result['contract_kind'] != 'moltbook_ambassador_draft' ||
        result['approval_required'] != true) {
      throw const FormatException('Invalid Moltbook draft contract result');
    }
    final rawFlags = result['safety_flags'];
    if (rawFlags is! List || rawFlags.any((value) => value is! String)) {
      throw const FormatException('Invalid Moltbook draft safety flags');
    }
    final preview = MoltbookDraftPreview(
      bulletinId: _requiredString(result, 'bulletin_id'),
      releaseTag: _requiredString(result, 'release_tag'),
      category: _requiredString(result, 'category'),
      title: _requiredString(result, 'title'),
      body: _requiredString(result, 'body'),
      audience: _requiredString(result, 'audience'),
      approvalRequired: true,
      safetyFlags: rawFlags.cast<String>(),
      draftHashHex: _requiredString(result, 'draft_hash_hex'),
      canonicalDraftJson: _requiredString(result, 'canonical_draft_json'),
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(preview.draftHashHex)) {
      throw const FormatException('Invalid Moltbook draft hash');
    }
    if (sha256.convert(utf8.encode(preview.canonicalDraftJson)).toString() !=
        preview.draftHashHex) {
      throw const FormatException('Moltbook canonical draft hash mismatch');
    }
    final canonical = jsonDecode(preview.canonicalDraftJson);
    if (canonical is! Map ||
        canonical['bulletin_id'] != preview.bulletinId ||
        canonical['release_tag'] != preview.releaseTag ||
        canonical['category'] != preview.category ||
        canonical['title'] != preview.title ||
        canonical['body'] != preview.body ||
        canonical['audience'] != preview.audience ||
        canonical['approval_required'] != true ||
        jsonEncode(canonical['safety_flags']) !=
            jsonEncode(preview.safetyFlags)) {
      throw const FormatException(
        'Moltbook canonical draft projection mismatch',
      );
    }
    return preview;
  }

  Map<String, dynamic> toHostResult() => <String, dynamic>{
    'schema_version': 1,
    'plugin_id': moltbookAmbassadorPluginId,
    'contract_kind': 'moltbook_ambassador_draft',
    'bulletin_id': bulletinId,
    'release_tag': releaseTag,
    'category': category,
    'title': title,
    'body': body,
    'audience': audience,
    'approval_required': approvalRequired,
    'safety_flags': safetyFlags,
    'draft_hash_hex': draftHashHex,
    'canonical_draft_json': canonicalDraftJson,
  };

  static String _requiredString(Map<String, dynamic> value, String field) {
    final result = value[field];
    if (result is! String || result.trim().isEmpty) {
      throw FormatException('Invalid Moltbook draft field: $field');
    }
    return result;
  }
}

class MoltbookReplyDraftPreview {
  final String targetPostId;
  final String? targetCommentId;
  final String engagementPlanHashHex;
  final String body;
  final bool approvalRequired;
  final List<String> safetyFlags;
  final String draftHashHex;
  final String canonicalDraftJson;

  const MoltbookReplyDraftPreview({
    required this.targetPostId,
    required this.targetCommentId,
    required this.engagementPlanHashHex,
    required this.body,
    required this.approvalRequired,
    required this.safetyFlags,
    required this.draftHashHex,
    required this.canonicalDraftJson,
  });

  factory MoltbookReplyDraftPreview.fromHostResult(
    Map<String, dynamic> result,
  ) {
    if (result['schema_version'] != 1 ||
        result['plugin_id'] != moltbookAmbassadorPluginId ||
        result['contract_kind'] != 'moltbook_ambassador_reply_draft' ||
        result['approval_required'] != true) {
      throw const FormatException('Invalid Moltbook reply draft result');
    }
    final rawFlags = result['safety_flags'];
    final rawCommentId = result['target_comment_id'];
    if (rawFlags is! List ||
        rawFlags.any((value) => value is! String) ||
        (rawCommentId != null && rawCommentId is! String)) {
      throw const FormatException('Invalid Moltbook reply draft fields');
    }
    final preview = MoltbookReplyDraftPreview(
      targetPostId: _replyRequiredString(result, 'target_post_id'),
      targetCommentId: rawCommentId as String?,
      engagementPlanHashHex: _replyRequiredString(
        result,
        'engagement_plan_hash_hex',
      ),
      body: _replyRequiredString(result, 'body'),
      approvalRequired: true,
      safetyFlags: rawFlags.cast<String>(),
      draftHashHex: _replyRequiredString(result, 'draft_hash_hex'),
      canonicalDraftJson: _replyRequiredString(result, 'canonical_draft_json'),
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(preview.draftHashHex) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(preview.engagementPlanHashHex) ||
        sha256.convert(utf8.encode(preview.canonicalDraftJson)).toString() !=
            preview.draftHashHex) {
      throw const FormatException('Moltbook reply draft hash mismatch');
    }
    final canonical = jsonDecode(preview.canonicalDraftJson);
    if (canonical is! Map ||
        canonical['target_post_id'] != preview.targetPostId ||
        canonical['target_comment_id'] != preview.targetCommentId ||
        canonical['engagement_plan_hash_hex'] !=
            preview.engagementPlanHashHex ||
        canonical['body'] != preview.body ||
        canonical['approval_required'] != true ||
        jsonEncode(canonical['safety_flags']) !=
            jsonEncode(preview.safetyFlags)) {
      throw const FormatException(
        'Moltbook canonical reply projection mismatch',
      );
    }
    return preview;
  }

  static String _replyRequiredString(Map<String, dynamic> value, String field) {
    final result = value[field];
    if (result is! String || result.trim().isEmpty) {
      throw FormatException('Invalid Moltbook reply field: $field');
    }
    return result;
  }
}

class MoltbookDelegatedReplyAuthorization {
  final String targetPostId;
  final String? targetCommentId;
  final String engagementPlanHashHex;
  final String replyDraftHashHex;
  final int policyVersion;
  final int maxDailyWrites;
  final int writesToday;
  final int minIntervalMinutes;
  final String observedAtUtc;
  final List<String> safetyFlags;
  final String authorizationHashHex;
  final String canonicalAuthorizationJson;

  const MoltbookDelegatedReplyAuthorization({
    required this.targetPostId,
    required this.targetCommentId,
    required this.engagementPlanHashHex,
    required this.replyDraftHashHex,
    required this.policyVersion,
    required this.maxDailyWrites,
    required this.writesToday,
    required this.minIntervalMinutes,
    required this.observedAtUtc,
    required this.safetyFlags,
    required this.authorizationHashHex,
    required this.canonicalAuthorizationJson,
  });

  factory MoltbookDelegatedReplyAuthorization.fromHostResult(
    Map<String, dynamic> result,
  ) {
    if (result['schema_version'] != 1 ||
        result['plugin_id'] != moltbookAmbassadorPluginId ||
        result['contract_kind'] !=
            'moltbook_ambassador_delegated_reply_authorization' ||
        result['publish_allowed'] != true ||
        result['human_review_required'] != false ||
        result['safety_flags'] is! List) {
      throw const FormatException('Invalid delegated reply authorization');
    }
    final authorization = MoltbookDelegatedReplyAuthorization(
      targetPostId: result['target_post_id']?.toString() ?? '',
      targetCommentId: result['target_comment_id'] as String?,
      engagementPlanHashHex:
          result['engagement_plan_hash_hex']?.toString() ?? '',
      replyDraftHashHex: result['reply_draft_hash_hex']?.toString() ?? '',
      policyVersion:
          result['policy_version'] is int
              ? result['policy_version'] as int
              : -1,
      maxDailyWrites:
          result['max_daily_writes'] is int
              ? result['max_daily_writes'] as int
              : -1,
      writesToday:
          result['writes_today'] is int ? result['writes_today'] as int : -1,
      minIntervalMinutes:
          result['min_interval_minutes'] is int
              ? result['min_interval_minutes'] as int
              : -1,
      observedAtUtc: result['observed_at_utc']?.toString() ?? '',
      safetyFlags: (result['safety_flags'] as List).cast<String>(),
      authorizationHashHex: result['authorization_hash_hex']?.toString() ?? '',
      canonicalAuthorizationJson:
          result['canonical_authorization_json']?.toString() ?? '',
    );
    final observedAt = DateTime.tryParse(authorization.observedAtUtc);
    if (authorization.targetPostId.isEmpty ||
        authorization.targetCommentId == null ||
        authorization.targetCommentId!.isEmpty ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(authorization.engagementPlanHashHex) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(authorization.replyDraftHashHex) ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(authorization.authorizationHashHex) ||
        observedAt == null ||
        !observedAt.isUtc ||
        authorization.policyVersion != 1 ||
        authorization.maxDailyWrites < 1 ||
        authorization.maxDailyWrites > 12 ||
        authorization.writesToday < 0 ||
        authorization.writesToday >= authorization.maxDailyWrites ||
        authorization.minIntervalMinutes < 5 ||
        authorization.minIntervalMinutes > 1440 ||
        !authorization.safetyFlags.contains('exact_reply_draft_bound') ||
        !authorization.safetyFlags.contains('engagement_plan_bound') ||
        sha256
                .convert(utf8.encode(authorization.canonicalAuthorizationJson))
                .toString() !=
            authorization.authorizationHashHex) {
      throw const FormatException('Malformed delegated reply authorization');
    }
    return authorization;
  }
}

class MoltbookStoredDraft {
  static const String awaitingApproval = 'awaiting_approval';

  final MoltbookDraftPreview preview;
  final DateTime createdAtUtc;
  final String status;

  const MoltbookStoredDraft({
    required this.preview,
    required this.createdAtUtc,
    this.status = awaitingApproval,
  });

  factory MoltbookStoredDraft.fromJson(Map<String, dynamic> json) {
    final rawPreview = json['preview'];
    if (json['schema_version'] != 1 ||
        rawPreview is! Map ||
        json['status'] != awaitingApproval) {
      throw const FormatException('Invalid stored Moltbook draft');
    }
    final createdAt = DateTime.tryParse(
      json['created_at_utc']?.toString() ?? '',
    );
    if (createdAt == null ||
        !createdAt.isUtc ||
        createdAt.toIso8601String() != json['created_at_utc']) {
      throw const FormatException('Invalid stored Moltbook draft timestamp');
    }
    return MoltbookStoredDraft(
      preview: MoltbookDraftPreview.fromHostResult(
        Map<String, dynamic>.from(rawPreview),
      ),
      createdAtUtc: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': 1,
    'status': status,
    'created_at_utc': createdAtUtc.toIso8601String(),
    'preview': preview.toHostResult(),
  };
}

class MoltbookAmbassadorConfiguration {
  static const int schemaVersion = 3;
  static const int previousSchemaVersion = 2;
  static const int legacySchemaVersion = 1;
  static const String approvalDraft = 'draft';
  static const String approvalAssisted = 'assisted';
  static const String approvalBounded = 'bounded';
  static const String triggerOnDemand = 'on_demand';
  static const String triggerSession = 'session';
  static const String triggerContinuous = 'continuous_while_running';

  final String agentName;
  final String agentDescription;
  final String personaSummary;
  final List<String> allowedTopics;
  final String approvalMode;
  final String triggerPolicy;
  final bool enabled;

  const MoltbookAmbassadorConfiguration({
    required this.agentName,
    required this.agentDescription,
    required this.personaSummary,
    required this.allowedTopics,
    required this.approvalMode,
    this.triggerPolicy = triggerOnDemand,
    required this.enabled,
  });

  factory MoltbookAmbassadorConfiguration.defaults() {
    return const MoltbookAmbassadorConfiguration(
      agentName: 'hivra_ambassador',
      agentDescription:
          'Technical ambassador for Hivra, a local-first runtime for user-owned Capsules and isolated WASM drones.',
      personaSummary: 'Explain public Hivra development clearly and factually.',
      allowedTopics: <String>[
        'hivra-development',
        'capsule-runtime',
        'wasm-drones',
      ],
      approvalMode: approvalAssisted,
      triggerPolicy: triggerOnDemand,
      enabled: true,
    );
  }

  factory MoltbookAmbassadorConfiguration.fromJson(Map<String, dynamic> json) {
    final sourceSchemaVersion = json['schema_version'];
    if (sourceSchemaVersion != legacySchemaVersion &&
        sourceSchemaVersion != previousSchemaVersion &&
        sourceSchemaVersion != schemaVersion) {
      throw const FormatException('Unsupported Moltbook configuration schema');
    }
    if (json['plugin_id'] != moltbookAmbassadorPluginId) {
      throw const FormatException('Configuration belongs to another plugin');
    }
    final rawTopics = json['allowed_topics'];
    if (rawTopics is! List) {
      throw const FormatException('allowed_topics must be a list');
    }
    final topics =
        rawTopics.map((value) {
          if (value is! String) {
            throw const FormatException('allowed_topics must contain strings');
          }
          return value.trim();
        }).toList();
    if (json['enabled'] is! bool) {
      throw const FormatException('enabled must be a boolean');
    }
    final config = MoltbookAmbassadorConfiguration(
      agentName:
          json['agent_name'] is String ? json['agent_name'] as String : '',
      agentDescription:
          json['agent_description'] is String
              ? json['agent_description'] as String
              : '',
      personaSummary:
          json['persona_summary'] is String
              ? json['persona_summary'] as String
              : '',
      allowedTopics: topics,
      approvalMode:
          json['approval_mode'] is String
              ? json['approval_mode'] as String
              : '',
      triggerPolicy:
          sourceSchemaVersion == legacySchemaVersion
              ? triggerOnDemand
              : json['trigger_policy'] is String
              ? json['trigger_policy'] as String
              : '',
      enabled: json['enabled'] as bool,
    );
    if (sourceSchemaVersion != schemaVersion &&
        config.approvalMode == approvalBounded) {
      throw const FormatException(
        'bounded approval requires configuration schema v3',
      );
    }
    config.validate();
    return config;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'plugin_id': moltbookAmbassadorPluginId,
    'agent_name': agentName,
    'agent_description': agentDescription,
    'persona_summary': personaSummary,
    'allowed_topics': allowedTopics,
    'approval_mode': approvalMode,
    'trigger_policy': triggerPolicy,
    'enabled': enabled,
  };

  void validate() {
    _bounded('agent_name', agentName, 1, 64);
    _bounded('agent_description', agentDescription, 1, 280);
    _bounded('persona_summary', personaSummary, 1, 500);
    if (allowedTopics.isEmpty || allowedTopics.length > 16) {
      throw const FormatException('allowed_topics must contain 1..16 items');
    }
    if (allowedTopics.toSet().length != allowedTopics.length) {
      throw const FormatException('allowed_topics must not contain duplicates');
    }
    for (final topic in allowedTopics) {
      _bounded('allowed_topic', topic, 1, 64);
      if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(topic)) {
        throw const FormatException('allowed_topics contains an invalid value');
      }
    }
    if (approvalMode != approvalDraft &&
        approvalMode != approvalAssisted &&
        approvalMode != approvalBounded) {
      throw const FormatException(
        'approval_mode must be draft, assisted, or bounded',
      );
    }
    if (triggerPolicy != triggerOnDemand &&
        triggerPolicy != triggerSession &&
        triggerPolicy != triggerContinuous) {
      throw const FormatException(
        'trigger_policy must be on_demand, session, or continuous_while_running',
      );
    }
  }

  void _bounded(String field, String value, int min, int max) {
    final length = value.trim().length;
    if (length < min || length > max) {
      throw FormatException('$field must contain $min..$max characters');
    }
  }
}

enum MoltbookEngagementWritePolicy { assisted, bounded }

class MoltbookPublicationContract {
  static const String repositoryUrl = 'https://github.com/WSorr/Hivra-App';

  const MoltbookPublicationContract._();

  static String operationMarker(String operationId) {
    return 'hivra-effect:$operationId';
  }

  static String attribution() {
    return '[Hivra on GitHub]($repositoryUrl)';
  }

  static String legacyAttribution(String operationId) {
    final marker = operationMarker(operationId);
    return '[Hivra on GitHub]($repositoryUrl#$marker)';
  }

  static String legacyMarker(String operationId) {
    return '[${operationMarker(operationId)}]';
  }

  static bool matchesLegacyApprovedContent({
    required String operationId,
    required String operationMarker,
    required String content,
  }) {
    final currentMarker = MoltbookPublicationContract.operationMarker(
      operationId,
    );
    if (operationMarker == currentMarker) {
      return content.endsWith(legacyAttribution(operationId));
    }
    final legacy = legacyMarker(operationId);
    return operationMarker == legacy && content.endsWith(legacy);
  }
}

class MoltbookHeartbeatPlan {
  static const Set<String> priorities = <String>{
    'review_activity',
    'inspect_feed',
    'idle',
  };

  final String observedAtUtc;
  final String priority;
  final String reason;
  final List<String> candidatePostIds;
  final bool publishAllowed;
  final bool humanReviewRequired;
  final List<String> safetyFlags;
  final String planHashHex;
  final String canonicalPlanJson;

  const MoltbookHeartbeatPlan({
    required this.observedAtUtc,
    required this.priority,
    required this.reason,
    required this.candidatePostIds,
    required this.publishAllowed,
    required this.humanReviewRequired,
    required this.safetyFlags,
    required this.planHashHex,
    required this.canonicalPlanJson,
  });

  factory MoltbookHeartbeatPlan.fromHostResult(Map<String, dynamic> result) {
    if (result['schema_version'] != 1 ||
        result['plugin_id'] != moltbookAmbassadorPluginId ||
        result['contract_kind'] != 'moltbook_ambassador_heartbeat_plan' ||
        result['publish_allowed'] != false ||
        result['human_review_required'] != true) {
      throw const FormatException('Invalid Moltbook heartbeat plan');
    }
    final observedAt = DateTime.tryParse(
      result['observed_at_utc']?.toString() ?? '',
    );
    final priority = result['priority']?.toString() ?? '';
    final reason = result['reason']?.toString().trim() ?? '';
    final rawCandidates = result['candidate_post_ids'];
    final rawFlags = result['safety_flags'];
    final planHash = result['plan_hash_hex']?.toString() ?? '';
    final canonicalJson = result['canonical_plan_json']?.toString() ?? '';
    if (observedAt == null ||
        !observedAt.isUtc ||
        observedAt.toIso8601String() != result['observed_at_utc'] ||
        !priorities.contains(priority) ||
        reason.isEmpty ||
        reason.length > 500 ||
        rawCandidates is! List ||
        rawFlags is! List ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(planHash) ||
        canonicalJson.isEmpty) {
      throw const FormatException('Malformed Moltbook heartbeat plan');
    }
    final candidates = rawCandidates
        .map((value) {
          if (value is! String || value.isEmpty || value.length > 256) {
            throw const FormatException('Invalid Moltbook heartbeat candidate');
          }
          return value;
        })
        .toList(growable: false);
    if (candidates.length > 5 ||
        candidates.toSet().length != candidates.length) {
      throw const FormatException('Invalid Moltbook heartbeat candidates');
    }
    final flags = rawFlags
        .map((value) {
          if (value is! String || value.isEmpty || value.length > 80) {
            throw const FormatException(
              'Invalid Moltbook heartbeat safety flag',
            );
          }
          return value;
        })
        .toList(growable: false);
    if (!flags.contains('remote_content_untrusted') ||
        !flags.contains('no_external_effect')) {
      throw const FormatException('Moltbook heartbeat safety gate is missing');
    }
    return MoltbookHeartbeatPlan(
      observedAtUtc: observedAt.toIso8601String(),
      priority: priority,
      reason: reason,
      candidatePostIds: candidates,
      publishAllowed: false,
      humanReviewRequired: true,
      safetyFlags: flags,
      planHashHex: planHash,
      canonicalPlanJson: canonicalJson,
    );
  }
}

class MoltbookCycleSummary {
  final String ownerCapsuleHex;
  final String accountBindingId;
  final String startedAtUtc;
  final String completedAtUtc;
  final int inspectedCount;
  final int candidateCount;
  final int reconciledCount;
  final int challengedCount;
  final int blockedCount;
  final MoltbookHeartbeatPlan heartbeatPlan;
  final MoltbookFeedCheckpoint checkpoint;

  const MoltbookCycleSummary({
    required this.ownerCapsuleHex,
    required this.accountBindingId,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.inspectedCount,
    required this.candidateCount,
    required this.reconciledCount,
    required this.challengedCount,
    required this.blockedCount,
    required this.heartbeatPlan,
    required this.checkpoint,
  });

  void validate() {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(ownerCapsuleHex) ||
        accountBindingId.trim() != accountBindingId ||
        accountBindingId.isEmpty ||
        accountBindingId.length > 256 ||
        inspectedCount < 0 ||
        inspectedCount > 100 ||
        candidateCount < 0 ||
        candidateCount > 5 ||
        reconciledCount < 0 ||
        challengedCount < 0 ||
        blockedCount < 0) {
      throw const FormatException('Invalid Moltbook cycle summary');
    }
    final started = DateTime.tryParse(startedAtUtc);
    final completed = DateTime.tryParse(completedAtUtc);
    if (started == null ||
        completed == null ||
        !started.isUtc ||
        !completed.isUtc ||
        completed.isBefore(started) ||
        started.toIso8601String() != startedAtUtc ||
        completed.toIso8601String() != completedAtUtc) {
      throw const FormatException('Invalid Moltbook cycle timestamps');
    }
    checkpoint.validate();
  }
}

enum MoltbookCycleTriggerPhase { idle, running, waiting, stopped, failed }

class MoltbookCycleTriggerSnapshot {
  final String scope;
  final String policy;
  final MoltbookCycleTriggerPhase phase;
  final MoltbookCycleSummary? lastSummary;
  final String? lastError;

  const MoltbookCycleTriggerSnapshot({
    required this.scope,
    required this.policy,
    required this.phase,
    required this.lastSummary,
    required this.lastError,
  });
}

enum MoltbookWorkspaceCyclePhase {
  idle,
  observing,
  proposing,
  delivering,
  stopped,
  blocked,
}

enum MoltbookWorkspaceNextAction {
  connect,
  verify,
  reconcile,
  publish,
  reviewReply,
  reviewDraft,
  runCycle,
  none,
}

class MoltbookWorkspaceProjection {
  final MoltbookWorkspaceCyclePhase phase;
  final MoltbookWorkspaceNextAction nextAction;
  final int readCount;
  final int eligibleCount;
  final int proposedCount;
  final int publishedCount;
  final int challengedCount;
  final int blockedCount;

  const MoltbookWorkspaceProjection({
    required this.phase,
    required this.nextAction,
    required this.readCount,
    required this.eligibleCount,
    required this.proposedCount,
    required this.publishedCount,
    required this.challengedCount,
    required this.blockedCount,
  });

  factory MoltbookWorkspaceProjection.resolve({
    required bool connected,
    required bool enabled,
    required MoltbookCycleTriggerPhase? triggerPhase,
    required MoltbookCycleSummary? cycleSummary,
    required bool observing,
    required bool proposing,
    required bool delivering,
    required bool hasVerification,
    required bool hasRecoverableEffect,
    required bool hasQueuedEffect,
    required bool hasReplyDraft,
    required bool hasLocalDraft,
    required int proposedCount,
    required int publishedCount,
    required int challengedCount,
    required int blockedCount,
  }) {
    if (proposedCount < 0 ||
        publishedCount < 0 ||
        challengedCount < 0 ||
        blockedCount < 0) {
      throw ArgumentError('Moltbook workspace counts must be non-negative');
    }

    final phase = switch ((enabled, triggerPhase)) {
      (false, _) || (_, MoltbookCycleTriggerPhase.stopped) =>
        MoltbookWorkspaceCyclePhase.stopped,
      (_, MoltbookCycleTriggerPhase.failed) =>
        MoltbookWorkspaceCyclePhase.blocked,
      _ when delivering => MoltbookWorkspaceCyclePhase.delivering,
      _ when proposing => MoltbookWorkspaceCyclePhase.proposing,
      _ when observing || triggerPhase == MoltbookCycleTriggerPhase.running =>
        MoltbookWorkspaceCyclePhase.observing,
      _ => MoltbookWorkspaceCyclePhase.idle,
    };

    final nextAction = switch ((
      connected,
      hasVerification,
      hasRecoverableEffect,
      hasQueuedEffect,
      hasReplyDraft,
      hasLocalDraft,
      enabled,
    )) {
      (false, _, _, _, _, _, _) => MoltbookWorkspaceNextAction.connect,
      (_, true, _, _, _, _, _) => MoltbookWorkspaceNextAction.verify,
      (_, _, true, _, _, _, _) => MoltbookWorkspaceNextAction.reconcile,
      (_, _, _, _, _, _, false) => MoltbookWorkspaceNextAction.none,
      (_, _, _, true, _, _, _) => MoltbookWorkspaceNextAction.publish,
      (_, _, _, _, true, _, _) => MoltbookWorkspaceNextAction.reviewReply,
      (_, _, _, _, _, true, _) => MoltbookWorkspaceNextAction.reviewDraft,
      (_, _, _, _, _, _, true) => MoltbookWorkspaceNextAction.runCycle,
    };

    return MoltbookWorkspaceProjection(
      phase: phase,
      nextAction: nextAction,
      readCount: cycleSummary?.inspectedCount ?? 0,
      eligibleCount: cycleSummary?.candidateCount ?? 0,
      proposedCount: proposedCount,
      publishedCount: publishedCount,
      challengedCount: challengedCount,
      blockedCount: blockedCount,
    );
  }
}

class MoltbookEngagementPlan {
  static const Set<String> actionClasses = <String>{
    'reply_draft',
    'comment_draft',
    'upvote_candidate',
    'follow_candidate',
    'no_action',
  };

  final String observedAtUtc;
  final String actionClass;
  final String targetPostId;
  final String? targetCommentId;
  final String reason;
  final bool publishAllowed;
  final bool humanReviewRequired;
  final List<String> safetyFlags;
  final String planHashHex;
  final String canonicalPlanJson;

  const MoltbookEngagementPlan({
    required this.observedAtUtc,
    required this.actionClass,
    required this.targetPostId,
    required this.targetCommentId,
    required this.reason,
    required this.publishAllowed,
    required this.humanReviewRequired,
    required this.safetyFlags,
    required this.planHashHex,
    required this.canonicalPlanJson,
  });

  factory MoltbookEngagementPlan.fromHostResult(Map<String, dynamic> result) {
    if (result['schema_version'] != 1 ||
        result['plugin_id'] != moltbookAmbassadorPluginId ||
        result['contract_kind'] != 'moltbook_ambassador_engagement_plan' ||
        result['publish_allowed'] != false ||
        result['human_review_required'] != true) {
      throw const FormatException('Invalid Moltbook engagement plan');
    }
    final observedAt = DateTime.tryParse(
      result['observed_at_utc']?.toString() ?? '',
    );
    final actionClass = result['action_class']?.toString() ?? '';
    final postId = result['target_post_id']?.toString() ?? '';
    final rawCommentId = result['target_comment_id'];
    final commentId = rawCommentId is String ? rawCommentId : null;
    final reason = result['reason']?.toString().trim() ?? '';
    final rawFlags = result['safety_flags'];
    final planHash = result['plan_hash_hex']?.toString() ?? '';
    final canonicalJson = result['canonical_plan_json']?.toString() ?? '';
    if (observedAt == null ||
        !observedAt.isUtc ||
        observedAt.toIso8601String() != result['observed_at_utc'] ||
        !actionClasses.contains(actionClass) ||
        postId.isEmpty ||
        postId.length > 256 ||
        (rawCommentId != null &&
            (commentId == null ||
                commentId.isEmpty ||
                commentId.length > 256)) ||
        reason.isEmpty ||
        reason.length > 500 ||
        rawFlags is! List ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(planHash) ||
        canonicalJson.isEmpty) {
      throw const FormatException('Malformed Moltbook engagement plan');
    }
    final flags = rawFlags
        .map((value) {
          if (value is! String || value.isEmpty || value.length > 80) {
            throw const FormatException(
              'Invalid Moltbook engagement safety flag',
            );
          }
          return value;
        })
        .toList(growable: false);
    if (!flags.contains('remote_content_untrusted') ||
        !flags.contains('no_external_effect') ||
        !flags.contains('ai_text_not_generated')) {
      throw const FormatException('Moltbook engagement safety gate is missing');
    }
    return MoltbookEngagementPlan(
      observedAtUtc: observedAt.toIso8601String(),
      actionClass: actionClass,
      targetPostId: postId,
      targetCommentId: commentId,
      reason: reason,
      publishAllowed: false,
      humanReviewRequired: true,
      safetyFlags: flags,
      planHashHex: planHash,
      canonicalPlanJson: canonicalJson,
    );
  }
}
