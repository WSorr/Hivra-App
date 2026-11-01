import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_doctor_prompt_service.dart';

void main() {
  group('AiDoctorPromptService', () {
    test('includes all technical modules without a section selection', () {
      const service = AiDoctorPromptService();
      final prompt = service.buildPrompt(
        snapshot: _snapshot(),
        userQuery: ' check ',
      );
      final second = service.buildPrompt(
        snapshot: _snapshot(),
        userQuery: 'check',
      );
      expect(prompt.inputJson, second.inputJson);
      expect(prompt.preview.sections, AiDoctorContextSection.values);
      final context = (prompt.payload as Map)['context'] as Map;
      expect(
        context.keys,
        unorderedEquals(AiDoctorContextSection.values.map((s) => s.key)),
      );
      expect(context['ledger_summary']['version'], 7);
      expect(context['transport_summary']['pending_count'], 2);
      expect(context['consensus_summary']['blocked_count'], 1);
      expect(prompt.preview.secretsRedacted, true);
    });

    test(
      'outbound context excludes addresses, personal data, paths and arbitrary fields',
      () {
        const service = AiDoctorPromptService();
        final prompt = service.buildPrompt(
          snapshot: _snapshot(),
          userQuery: 'check',
        );
        for (final privateValue in [
          'owner-private-address',
          'peer-private-address',
          '/Users/private-person',
          'private@example.org',
          'private-token',
          'private-chat-body',
          'raw-local-fingerprint',
        ]) {
          expect(
            prompt.inputJson,
            isNot(contains(privateValue)),
            reason: privateValue,
          );
        }
        final context = (prompt.payload as Map)['context'] as Map;
        expect(context['transport_summary']['error_codes'], [
          'network_unavailable',
        ]);
        expect(context['plugin_summary']['plugin_ids'], ['hivra.chat']);
        expect(context['trace_summary']['issue_count'], 1);
        expect(
          context['bootstrap_summary']['seed_matches_active_capsule'],
          false,
        );
        expect(context['bootstrap_summary']['error_codes'], [
          'secure_storage_unavailable',
        ]);
      },
    );

    test(
      'redaction changes neither local snapshot nor its original fingerprint',
      () {
        const service = AiDoctorPromptService();
        final snapshot = _snapshot();
        final before = jsonEncode(snapshot.toJson());
        final prompt = service.buildPrompt(
          snapshot: snapshot,
          userQuery: 'check',
        );
        expect(jsonEncode(snapshot.toJson()), before);
        expect(prompt.preview.snapshotHashHex, isNot(snapshot.snapshotHashHex));
        final another = service.buildPrompt(
          snapshot: _snapshot(privateOwner: 'different-owner'),
          userQuery: 'check',
        );
        expect(prompt.preview.snapshotHashHex, another.preview.snapshotHashHex);
        expect(prompt.inputJson, another.inputJson);
      },
    );

    test('rejects empty query and oversized input before inference', () {
      const service = AiDoctorPromptService();
      expect(
        () => service.buildPrompt(snapshot: _snapshot(), userQuery: ' '),
        throwsArgumentError,
      );
      expect(
        () =>
            service.buildPrompt(snapshot: _snapshot(), userQuery: 'x' * 64001),
        throwsStateError,
      );
    });
  });
}

AiCapsuleInspectionSnapshot _snapshot({
  String privateOwner = 'owner-private-address',
}) {
  return AiCapsuleInspectionSnapshot(
    schemaVersion: 1,
    mode: 'capsule_diagnostics_local',
    capsule: <String, dynamic>{
      'root_hex': privateOwner,
      'root_preview': privateOwner,
      'secret': 'private-token',
      'has_runtime_key': true,
    },
    ledgerSummary: <String, dynamic>{'has_history': true, 'version': 7},
    invitationSummary: <String, dynamic>{'pending_total': 0},
    relationshipSummary: <String, dynamic>{
      'active_peer_group_count': 1,
      'peer_name': 'private@example.org',
    },
    transportSummary: <String, dynamic>{
      'pending_count': 2,
      'last_errors': [
        'SocketException: private-token at /Users/private-person to private@example.org',
      ],
    },
    consensusSummary: <String, dynamic>{
      'blocked_count': 1,
      'hashes': [
        {'peer': 'peer-private-address', 'hash_hex': privateOwner},
      ],
    },
    pluginSummary: <String, dynamic>{
      'installed_count': 1,
      'plugin_ids': ['hivra.chat', 'private@example.org'],
      'private_state': {
        'messages': ['private-chat-body'],
      },
    },
    bootstrapSummary: <String, dynamic>{
      'issue': 'Keychain private-token /Users/private-person',
      'seed_matches_active_capsule': false,
    },
    traceSummary: <String, dynamic>{
      'issue_count': 1,
      'capsule_dir_path': '/Users/private-person',
    },
    redaction: <String, dynamic>{
      'secrets_redacted': true,
      'raw_seed_included': false,
      'private_keys_included': false,
    },
    snapshotHashHex: 'raw-local-fingerprint',
  );
}
