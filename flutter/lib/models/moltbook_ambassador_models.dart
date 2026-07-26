import 'plugin_contract_ids.dart';

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
