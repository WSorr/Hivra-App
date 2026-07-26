import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'plugin_contract_ids.dart';

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
  static const int schemaVersion = 1;
  static const String approvalDraft = 'draft';
  static const String approvalAssisted = 'assisted';

  final String agentName;
  final String agentDescription;
  final String personaSummary;
  final List<String> allowedTopics;
  final String approvalMode;
  final bool enabled;

  const MoltbookAmbassadorConfiguration({
    required this.agentName,
    required this.agentDescription,
    required this.personaSummary,
    required this.allowedTopics,
    required this.approvalMode,
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
      enabled: true,
    );
  }

  factory MoltbookAmbassadorConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
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
      enabled: json['enabled'] as bool,
    );
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
    if (approvalMode != approvalDraft && approvalMode != approvalAssisted) {
      throw const FormatException('approval_mode must be draft or assisted');
    }
  }

  void _bounded(String field, String value, int min, int max) {
    final length = value.trim().length;
    if (length < min || length > max) {
      throw FormatException('$field must contain $min..$max characters');
    }
  }
}

class MoltbookPublicationContract {
  static const String repositoryUrl = 'https://github.com/WSorr/Hivra-App';

  const MoltbookPublicationContract._();

  static String operationMarker(String operationId) {
    return 'hivra-effect:$operationId';
  }

  static String attribution(String operationId) {
    final marker = operationMarker(operationId);
    return '[Hivra on GitHub]($repositoryUrl#$marker)';
  }

  static String legacyMarker(String operationId) {
    return '[${operationMarker(operationId)}]';
  }

  static bool matchesApprovedContent({
    required String operationId,
    required String operationMarker,
    required String content,
  }) {
    final currentMarker = MoltbookPublicationContract.operationMarker(
      operationId,
    );
    if (operationMarker == currentMarker) {
      return content.endsWith(attribution(operationId));
    }
    final legacy = legacyMarker(operationId);
    return operationMarker == legacy && content.endsWith(legacy);
  }
}
