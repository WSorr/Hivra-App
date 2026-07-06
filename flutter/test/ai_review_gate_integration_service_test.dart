import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_review_gate_integration_service.dart';

void main() {
  group('AiReviewGateIntegrationService', () {
    test('marks AI advisory output unverified until gates run', () {
      const service = AiReviewGateIntegrationService();

      final first = service.markUnverified(
        scope: AiReviewGateScope.developerAdvisory,
        subject: const <String, Object?>{
          'answer': 'inspect invitation projection',
        },
      );
      final second = service.markUnverified(
        scope: AiReviewGateScope.developerAdvisory,
        subject: const <String, Object?>{
          'answer': 'inspect invitation projection',
        },
      );

      expect(first.reportHashHex, second.reportHashHex);
      expect(first.verified, isFalse);
      expect(first.verificationStatus,
          'unverified_until_user_runs_required_gates');
      expect(first.aiOutputCanOverrideGates, isFalse);
      expect(first.releaseAllowed, isFalse);
      expect(
        first.requiredGates.map((gate) => gate.command),
        containsAll(<String>[
          'flutter analyze',
          'tools/review/review_all.sh',
          'targeted tests for touched files',
        ]),
      );
    });

    test('patch proposals require targeted tests and manual review', () {
      const service = AiReviewGateIntegrationService();

      final report = service.markUnverified(
        scope: AiReviewGateScope.patchProposal,
        subject: const <String, Object?>{
          'proposal_hash_hex': 'abc',
        },
      );

      expect(report.verified, isFalse);
      expect(
        report.requiredGates.map((gate) => gate.command),
        containsAll(<String>[
          'flutter analyze',
          'tools/review/review_all.sh',
          'targeted tests for proposed patch scope',
          'manual code review',
        ]),
      );
    });

    test('plugin source audit stays subordinate to app and plugin repo gates',
        () {
      const service = AiReviewGateIntegrationService();

      final report = service.markUnverified(
        scope: AiReviewGateScope.pluginSourceAudit,
        subject: const <String, Object?>{
          'plugin_id': 'hivra.contract.demo.v1',
        },
      );

      expect(report.verified, isFalse);
      expect(report.releaseAllowed, isFalse);
      expect(
        report.requiredGates.map((gate) => gate.command),
        containsAll(<String>[
          'tools/review/review_all.sh',
          'flutter test test/ai_plugin_audit_service_test.dart',
          'hivra-plugins/scripts/review_all.sh',
        ]),
      );
    });

    test('release readiness still requires build and manual smoke', () {
      const service = AiReviewGateIntegrationService();

      final report = service.markUnverified(
        scope: AiReviewGateScope.releaseReadiness,
        subject: const <String, Object?>{'build_tag': 'test'},
      );

      expect(report.verified, isFalse);
      expect(report.aiOutputCanOverrideGates, isFalse);
      expect(
        report.requiredGates.map((gate) => gate.command),
        containsAll(<String>[
          'flutter build macos --release',
          'manual smoke checklist',
        ]),
      );
    });
  });
}
