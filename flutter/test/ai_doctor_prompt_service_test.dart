import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_doctor_prompt_service.dart';

void main() {
  group('AiDoctorPromptService', () {
    test('builds deterministic bounded prompt with selected sections only', () {
      const service = AiDoctorPromptService();
      final snapshot = _snapshot();

      final prompt = service.buildPrompt(
        snapshot: snapshot,
        userQuery: ' why is consensus blocked? ',
        sections: const <AiDoctorContextSection>[
          AiDoctorContextSection.consensus,
          AiDoctorContextSection.transport,
        ],
      );
      final second = service.buildPrompt(
        snapshot: snapshot,
        userQuery: 'why is consensus blocked?',
        sections: const <AiDoctorContextSection>[
          AiDoctorContextSection.transport,
          AiDoctorContextSection.consensus,
        ],
      );

      expect(prompt.inputJson, second.inputJson);
      expect(prompt.preview.snapshotHashHex, 'abc123');
      expect(prompt.preview.secretsRedacted, isTrue);
      expect(prompt.preview.sections, <AiDoctorContextSection>[
        AiDoctorContextSection.transport,
        AiDoctorContextSection.consensus,
      ]);

      final decoded = jsonDecode(prompt.inputJson) as Map<String, dynamic>;
      final context = decoded['context'] as Map<String, dynamic>;
      expect(
          context.keys,
          containsAll(<String>[
            'transport_summary',
            'consensus_summary',
          ]));
      expect(context.keys, isNot(contains('ledger_summary')));
      expect(prompt.inputJson, isNot(contains('seed phrase')));
      expect(prompt.inputJson, isNot(contains('super-secret-private-key')));
    });

    test('rejects empty query and empty section list', () {
      const service = AiDoctorPromptService();
      final snapshot = _snapshot();

      expect(
        () => service.buildPrompt(
          snapshot: snapshot,
          userQuery: ' ',
          sections: const <AiDoctorContextSection>[
            AiDoctorContextSection.ledger,
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.buildPrompt(
          snapshot: snapshot,
          userQuery: 'check',
          sections: const <AiDoctorContextSection>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

AiCapsuleInspectionSnapshot _snapshot() {
  return const AiCapsuleInspectionSnapshot(
    schemaVersion: 1,
    mode: 'capsule_diagnostics_local',
    capsule: <String, dynamic>{
      'root_preview': 'h1abc...xyz',
      'has_runtime_key': true,
    },
    ledgerSummary: <String, dynamic>{
      'has_history': true,
      'version': 7,
    },
    invitationSummary: <String, dynamic>{
      'pending_total': 0,
    },
    relationshipSummary: <String, dynamic>{
      'active_peer_group_count': 1,
    },
    transportSummary: <String, dynamic>{
      'pending_count': 2,
    },
    consensusSummary: <String, dynamic>{
      'blocked_count': 1,
    },
    pluginSummary: <String, dynamic>{
      'installed_count': 1,
    },
    bootstrapSummary: <String, dynamic>{
      'issue': 'none',
    },
    traceSummary: <String, dynamic>{
      'issue_count': 0,
    },
    redaction: <String, dynamic>{
      'secrets_redacted': true,
      'raw_seed_included': false,
      'private_keys_included': false,
    },
    snapshotHashHex: 'abc123',
  );
}
