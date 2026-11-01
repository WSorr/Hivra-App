import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/starter.dart';
import 'ai_capsule_inspection_service.dart';
import 'capsule_ai_runtime_service.dart';

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
  final Object payload;
  final String inputJson;
  final AiDoctorOutboundPreview preview;

  const AiDoctorPrompt({
    required this.instructions,
    required this.payload,
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
  }) {
    final normalizedQuery = userQuery.trim();
    if (normalizedQuery.isEmpty) {
      throw ArgumentError('AI Analyst query is empty');
    }
    final context = _technicalContext(snapshot);
    // The outbound fingerprint must not identify the unredacted local snapshot.
    final contextHash =
        sha256
            .convert(utf8.encode(CapsuleInferenceCanonicalJson.encode(context)))
            .toString();

    final payload = <String, dynamic>{
      'schema_version': 1,
      'mode': 'scoped_ai_capsule_analyst_chat',
      'snapshot_hash_hex': contextHash,
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
        'provider_upload': true,
        'upload_scope': 'all_module_technical_summaries',
        'raw_seed_included': false,
        'private_keys_included': false,
        'plugin_credentials_included': false,
        'personal_content_included': false,
        'owner_and_peer_addresses_included': false,
        'filesystem_paths_included': false,
        'raw_error_text_included': false,
      },
    };
    final inputJson = CapsuleInferenceCanonicalJson.encode(payload);
    final payloadBytes = utf8.encode(inputJson).length;
    if (payloadBytes > maxPayloadBytes) {
      throw StateError(
        'AI Analyst context is too large: $payloadBytes > $maxPayloadBytes bytes',
      );
    }

    return AiDoctorPrompt(
      instructions: _instructions,
      payload: payload,
      inputJson: inputJson,
      preview: AiDoctorOutboundPreview(
        snapshotHashHex: contextHash,
        sections: AiDoctorContextSection.values,
        payloadBytes: payloadBytes,
        userQueryBytes: utf8.encode(normalizedQuery).length,
        secretsRedacted: true,
      ),
    );
  }

  Map<String, dynamic> _technicalContext(AiCapsuleInspectionSnapshot s) {
    // Project known technical fields, never arbitrary maps, plugin state,
    // names, peer hashes, paths or exception strings from the local report.
    return {
      'capsule': _technicalFields(s.capsule, ['has_runtime_key']),
      'ledger_summary': {
        ..._technicalFields(s.ledgerSummary, [
          'has_history',
          'version',
          'starter_count',
          'relationship_count',
          'pending_invitation_count',
          'locked_starter_slots',
        ]),
        if (s.ledgerSummary['starter_kinds'] is List)
          'starter_kinds': (s.ledgerSummary['starter_kinds'] as List)
              .map(
                (kind) =>
                    kind == null
                        ? null
                        : StarterKind.values.any(
                          (known) => known.displayName == kind,
                        )
                        ? kind
                        : 'Unknown',
              )
              .toList(growable: false),
      },
      'invitation_summary': _technicalFields(s.invitationSummary, [
        'total',
        'pending_total',
        'pending_incoming',
        'pending_outgoing',
        'accepted',
        'rejected',
        'expired',
      ]),
      'relationship_summary': _technicalFields(s.relationshipSummary, [
        'peer_group_count',
        'active_peer_group_count',
        'active_relationship_count',
        'broken_relationship_count',
        'pending_remote_break_count',
      ]),
      'transport_summary': {
        ..._technicalFields(s.transportSummary, [
          'outbox_count',
          'pending_count',
          'published_count',
          'quarantined_count',
          'dead_count',
          'max_attempts',
        ]),
        'error_codes': _errorCodes(s.transportSummary['last_errors']),
        'kinds': _technicalIds(s.transportSummary['kinds']),
      },
      'consensus_summary': {
        ..._technicalFields(s.consensusSummary, [
          'peer_count',
          'signable_count',
          'blocked_count',
        ]),
        'blocking_codes': _technicalIds(s.consensusSummary['blocking_codes']),
      },
      'plugin_summary': {
        ..._technicalFields(s.pluginSummary, ['installed_count']),
        'plugin_ids': _technicalIds(s.pluginSummary['plugin_ids']),
        'capabilities': _technicalIds(s.pluginSummary['capabilities']),
      },
      'bootstrap_summary': {
        ..._technicalFields(s.bootstrapSummary, [
          'available',
          'seed_available',
          'seed_matches_active_capsule',
          'root_matches_active_capsule',
          'nostr_matches_active_capsule',
          'runtime_matches_root',
          'runtime_matches_nostr',
          'state_file_exists',
          'ledger_file_exists',
          'backup_file_exists',
          'worker_bootstrap_available',
          'ledger_importable',
        ]),
        if (const [
          'root_owner',
          'legacy_nostr_owner',
          'unknown',
        ].contains(s.bootstrapSummary['identity_mode']))
          'identity_mode': s.bootstrapSummary['identity_mode'],
        if (const [
          'ledger',
          'backup',
          'none',
          'error',
        ].contains(s.bootstrapSummary['bootstrap_source']))
          'bootstrap_source': s.bootstrapSummary['bootstrap_source'],
        'error_codes': _errorCodes([s.bootstrapSummary['issue']]),
      },
      'trace_summary': _technicalFields(s.traceSummary, [
        'available',
        'runtime_seed_exists',
        'index_has_entry',
        'secure_seed_exists',
        'fallback_seed_exists',
        'capsule_dir_exists',
        'ledger_file_exists',
        'state_file_exists',
        'backup_file_exists',
        'legacy_ledger_exists',
        'legacy_state_exists',
        'legacy_backup_exists',
        'issue_count',
      ]),
    };
  }

  Map<String, dynamic> _technicalFields(
    Map<String, dynamic> source,
    List<String> keys,
  ) => {
    for (final key in keys)
      if (source[key] is bool ||
          source[key] is int ||
          (source[key] is List &&
              (source[key] as List).every((value) => value is int)))
        key: source[key],
  };

  List<String> _technicalIds(Object? values) =>
      values is! List
            ? []
            : values
                .whereType<String>()
                .where(
                  (value) =>
                      value.length <= 128 &&
                      RegExp(
                        r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
                      ).hasMatch(value),
                )
                .toSet()
                .toList()
        ..sort();

  List<String> _errorCodes(Object? values) {
    if (values is! List) return [];
    return values
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty && value != 'none')
        .map((value) {
          final error = value.toLowerCase();
          if (error.contains('timeout') || error.contains('timed out')) {
            return 'timeout';
          }
          if (error.contains('socket') ||
              error.contains('network') ||
              error.contains('dns') ||
              error.contains('host lookup')) {
            return 'network_unavailable';
          }
          if (error.contains('keychain') || error.contains('secure storage')) {
            return 'secure_storage_unavailable';
          }
          if (error.contains('permission') || error.contains('denied')) {
            return 'access_denied';
          }
          if (error.contains('mismatch')) return 'identity_or_history_mismatch';
          return 'diagnostic_error';
        })
        .toSet()
        .toList()
      ..sort();
  }

  static const String _instructions = '''
You are Hivra Capsule Analyst.
Analyze the technical summaries of all modules in the provided capsule snapshot.
Personal content, owner and peer addresses, filesystem paths and raw errors are omitted.
Error codes are diagnostic categories, not full original error messages.
Do not ask for seeds, private keys, exchange credentials, filesystem dumps, or repository access.
Treat the local capsule ledger projection as the source of truth.
Your answer is advisory only: do not claim that you changed capsule state.
Prefer concrete findings, likely causes, and safe next checks.
If evidence is insufficient, say exactly what local evidence is missing.
''';
}
