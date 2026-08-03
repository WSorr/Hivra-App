import 'capsule_ai_runtime_service.dart';
import 'capsule_history_projection_service.dart';

class CapsuleHistoryAiResult {
  final String text;
  final String model;
  final String providerLabel;

  const CapsuleHistoryAiResult({
    required this.text,
    required this.model,
    required this.providerLabel,
  });
}

class CapsuleHistoryAiAdvisorService {
  static const int maxHistoryEvents = 100;
  static const String capabilityId = 'hivra.capsule_history.advisor';
  static const String proposalSchemaId = 'hivra.capsule_history.explanation.v1';

  final CapsuleInferenceRuntime _runtime;

  CapsuleHistoryAiAdvisorService({required CapsuleInferenceRuntime runtime})
    : _runtime = runtime;

  Future<void> unlockSession() => _runtime.unlockPreferredProviderSession();

  Future<CapsuleHistoryAiResult> explain(
    CapsuleHistoryProjection projection,
  ) async {
    if (projection.entries.isEmpty) {
      throw StateError('No confirmed ledger history exists for this item');
    }
    final events =
        projection.entries.length <= maxHistoryEvents
            ? projection.entries
            : projection.entries.sublist(
              projection.entries.length - maxHistoryEvents,
            );
    final payload = <String, dynamic>{
      'schema_version': 1,
      'mode': 'scoped_capsule_history_explanation',
      'history': <String, dynamic>{
        ...projection.toAdvisoryJson(),
        'events': events.map((entry) => entry.toAdvisoryJson()).toList(),
        'truncated': events.length != projection.entries.length,
        'total_event_count': projection.entries.length,
      },
      'constraints': <String, dynamic>{
        'advisory_only': true,
        'no_ledger_mutation': true,
        'facts_only_from_supplied_projection': true,
        'distinguish_fact_from_inference': true,
        'no_secret_request': true,
      },
      'redaction': <String, dynamic>{
        'raw_payload_included': false,
        'signatures_included': false,
        'private_keys_included': false,
        'credentials_included': false,
      },
    };
    final capsuleRootHex = _runtime.requireActiveCapsuleRootHex();
    final request = CapsuleInferenceRequestV1.create(
      capsuleRootHex: capsuleRootHex,
      capabilityId: capabilityId,
      disclosureSchemaVersion: 1,
      disclosedSectionIds: const <String>['ledger_history_projection'],
      proposalSchemaId: proposalSchemaId,
      proposalSchemaVersion: 1,
      cancellationScope: '$capabilityId:$capsuleRootHex',
      instructions: _instructions,
      input: payload,
      maxInputBytes: 65536,
      maxOutputBytes: 12000,
    );
    final response = await _runtime.infer(request);
    return CapsuleHistoryAiResult(
      text: response.proposalText,
      model: response.model,
      providerLabel: response.providerLabel,
    );
  }

  static const String _instructions = '''
You are Hivra Capsule History Analyst.
Explain the supplied entity history in concise, plain language.
The local ledger projection is the only source of confirmed facts.
Describe the lifecycle in chronological order, current meaning, and any visible inconsistency.
Explicitly distinguish confirmed facts from inference. If evidence is insufficient, say so.
Do not request or infer seeds, private keys, credentials, raw payloads, or repository access.
Your answer is advisory only and cannot change Capsule state.
''';
}
