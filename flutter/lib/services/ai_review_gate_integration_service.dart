import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AiReviewGateScope {
  developerAdvisory,
  patchProposal,
  pluginSourceAudit,
  releaseReadiness,
}

class AiReviewGateRequirement {
  final String command;
  final String reason;

  const AiReviewGateRequirement({
    required this.command,
    required this.reason,
  });
}

class AiReviewGateReport {
  final int schemaVersion;
  final AiReviewGateScope scope;
  final String subjectHashHex;
  final bool verified;
  final String verificationStatus;
  final List<AiReviewGateRequirement> requiredGates;
  final bool aiOutputCanOverrideGates;
  final bool releaseAllowed;
  final String reportHashHex;

  const AiReviewGateReport({
    required this.schemaVersion,
    required this.scope,
    required this.subjectHashHex,
    required this.verified,
    required this.verificationStatus,
    required this.requiredGates,
    required this.aiOutputCanOverrideGates,
    required this.releaseAllowed,
    required this.reportHashHex,
  });
}

class AiReviewGateIntegrationService {
  const AiReviewGateIntegrationService();

  AiReviewGateReport markUnverified({
    required AiReviewGateScope scope,
    required Object subject,
  }) {
    final subjectHash = _hashCanonical(_subjectToJson(subject));
    final requiredGates = _requiredGates(scope);
    final canonical = <String, dynamic>{
      'schema_version': 1,
      'scope': scope.name,
      'subject_hash_hex': subjectHash,
      'verified': false,
      'verification_status': 'unverified_until_user_runs_required_gates',
      'required_gates': requiredGates
          .map((gate) => <String, dynamic>{
                'command': gate.command,
                'reason': gate.reason,
              })
          .toList(growable: false),
      'ai_output_can_override_gates': false,
      'release_allowed': false,
    };
    return AiReviewGateReport(
      schemaVersion: 1,
      scope: scope,
      subjectHashHex: subjectHash,
      verified: false,
      verificationStatus: 'unverified_until_user_runs_required_gates',
      requiredGates: requiredGates,
      aiOutputCanOverrideGates: false,
      releaseAllowed: false,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  List<AiReviewGateRequirement> _requiredGates(AiReviewGateScope scope) {
    final gates = <AiReviewGateRequirement>[
      const AiReviewGateRequirement(
        command: 'flutter analyze',
        reason: 'Dart/Flutter static analysis must pass after any change.',
      ),
      const AiReviewGateRequirement(
        command: 'tools/review/review_all.sh',
        reason: 'Hivra architecture, dependency, security, and release gates.',
      ),
    ];
    switch (scope) {
      case AiReviewGateScope.developerAdvisory:
        gates.add(const AiReviewGateRequirement(
          command: 'targeted tests for touched files',
          reason:
              'AI advisory output is not evidence until code-level tests pass.',
        ));
      case AiReviewGateScope.patchProposal:
        gates.addAll(const <AiReviewGateRequirement>[
          AiReviewGateRequirement(
            command: 'targeted tests for proposed patch scope',
            reason: 'Patch preview must be validated before application.',
          ),
          AiReviewGateRequirement(
            command: 'manual code review',
            reason: 'Applying remains a separate human-confirmed action.',
          ),
        ]);
      case AiReviewGateScope.pluginSourceAudit:
        gates.addAll(const <AiReviewGateRequirement>[
          AiReviewGateRequirement(
            command: 'flutter test test/ai_plugin_audit_service_test.dart',
            reason: 'Plugin source evidence audit must remain read-only.',
          ),
          AiReviewGateRequirement(
            command: 'hivra-plugins/scripts/review_all.sh',
            reason: 'Plugin repository gates own plugin source correctness.',
          ),
        ]);
      case AiReviewGateScope.releaseReadiness:
        gates.addAll(const <AiReviewGateRequirement>[
          AiReviewGateRequirement(
            command: 'flutter build macos --release',
            reason: 'Release readiness requires a buildable macOS artifact.',
          ),
          AiReviewGateRequirement(
            command: 'manual smoke checklist',
            reason: 'AI output cannot replace manual capsule/runtime smoke.',
          ),
        ]);
    }
    return gates;
  }

  Object? _subjectToJson(Object subject) {
    if (subject is String) return subject;
    if (subject is num || subject is bool) return subject;
    if (subject is Map) {
      return subject.map((key, value) => MapEntry(key.toString(), value));
    }
    if (subject is Iterable) return subject.toList(growable: false);
    return subject.toString();
  }

  String _hashCanonical(Object? value) {
    return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}
