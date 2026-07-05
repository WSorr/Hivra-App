import 'dart:convert';

import 'ai_capsule_inspection_service.dart';

enum AiDoctorContextSection {
  capsule('capsule', 'Capsule'),
  ledger('ledger_summary', 'Ledger'),
  invitations('invitation_summary', 'Invitations'),
  relationships('relationship_summary', 'Relationships'),
  transport('transport_summary', 'Transport'),
  consensus('consensus_summary', 'Consensus'),
  plugins('plugin_summary', 'Plugins'),
  bootstrap('bootstrap_summary', 'Bootstrap'),
  trace('trace_summary', 'Filesystem Trace');

  final String key;
  final String label;

  const AiDoctorContextSection(this.key, this.label);
}

class AiDoctorOutboundPreview {
  final String snapshotHashHex;
  final List<AiDoctorContextSection> sections;
  final int payloadBytes;
  final int userQueryBytes;
  final bool secretsRedacted;

  const AiDoctorOutboundPreview({
    required this.snapshotHashHex,
    required this.sections,
    required this.payloadBytes,
    required this.userQueryBytes,
    required this.secretsRedacted,
  });

  String get sectionsLabel =>
      sections.map((section) => section.label).join(', ');
}

class AiDoctorPrompt {
  final String instructions;
  final String inputJson;
  final AiDoctorOutboundPreview preview;

  const AiDoctorPrompt({
    required this.instructions,
    required this.inputJson,
    required this.preview,
  });
}

class AiDoctorPromptService {
  static const int maxPayloadBytes = 64000;

  const AiDoctorPromptService();

  AiDoctorPrompt buildPrompt({
    required AiCapsuleInspectionSnapshot snapshot,
    required String userQuery,
    required Iterable<AiDoctorContextSection> sections,
  }) {
    final normalizedQuery = userQuery.trim();
    if (normalizedQuery.isEmpty) {
      throw ArgumentError('AI Doctor query is empty');
    }
    final selected = sections.toSet().toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    if (selected.isEmpty) {
      throw ArgumentError('At least one context section must be selected');
    }

    final context = <String, dynamic>{};
    for (final section in selected) {
      context[section.key] = _sectionPayload(snapshot, section);
    }

    final payload = <String, dynamic>{
      'schema_version': 1,
      'mode': 'scoped_ai_doctor_chat',
      'snapshot_hash_hex': snapshot.snapshotHashHex,
      'user_query': normalizedQuery,
      'context': context,
      'constraints': <String, dynamic>{
        'advisory_only': true,
        'no_ledger_mutation': true,
        'no_repository_access': true,
        'no_secret_request': true,
        'source_of_truth': 'local_capsule_ledger_projection',
      },
      'redaction': <String, dynamic>{
        'source_snapshot_redaction': snapshot.redaction,
        'provider_upload': true,
        'upload_scope': 'user_selected_summary_sections_only',
        'raw_seed_included': false,
        'private_keys_included': false,
        'plugin_credentials_included': false,
      },
    };
    final inputJson = const JsonEncoder.withIndent('  ').convert(payload);
    final payloadBytes = utf8.encode(inputJson).length;
    if (payloadBytes > maxPayloadBytes) {
      throw StateError(
        'AI Doctor context is too large: $payloadBytes > $maxPayloadBytes bytes',
      );
    }

    return AiDoctorPrompt(
      instructions: _instructions,
      inputJson: inputJson,
      preview: AiDoctorOutboundPreview(
        snapshotHashHex: snapshot.snapshotHashHex,
        sections: selected,
        payloadBytes: payloadBytes,
        userQueryBytes: utf8.encode(normalizedQuery).length,
        secretsRedacted: snapshot.redaction['secrets_redacted'] == true,
      ),
    );
  }

  Object? _sectionPayload(
    AiCapsuleInspectionSnapshot snapshot,
    AiDoctorContextSection section,
  ) {
    return switch (section) {
      AiDoctorContextSection.capsule => snapshot.capsule,
      AiDoctorContextSection.ledger => snapshot.ledgerSummary,
      AiDoctorContextSection.invitations => snapshot.invitationSummary,
      AiDoctorContextSection.relationships => snapshot.relationshipSummary,
      AiDoctorContextSection.transport => snapshot.transportSummary,
      AiDoctorContextSection.consensus => snapshot.consensusSummary,
      AiDoctorContextSection.plugins => snapshot.pluginSummary,
      AiDoctorContextSection.bootstrap => snapshot.bootstrapSummary,
      AiDoctorContextSection.trace => snapshot.traceSummary,
    };
  }

  static const String _instructions = '''
You are Hivra Capsule Doctor.
Analyze only the provided user-selected redacted capsule snapshot.
Do not ask for seeds, private keys, exchange credentials, filesystem dumps, or repository access.
Treat the local capsule ledger projection as the source of truth.
Your answer is advisory only: do not claim that you changed capsule state.
Prefer concrete findings, likely causes, and safe next checks.
If evidence is insufficient, say exactly what local evidence is missing.
''';
}
