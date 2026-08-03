import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_doctor_credential_store.dart';
import 'inference_provider_adapter.dart';

enum CapsuleInferenceProviderPolicyV1 { preferred }

enum CapsuleInferenceModelPolicyV1 { providerDefault }

enum CapsuleInferenceFailureCode {
  invalidRequest,
  invalidResponse,
  capsuleUnavailable,
  capsuleChanged,
  sessionLocked,
  inputTooLarge,
  outputTooLarge,
  superseded,
  timeout,
}

class CapsuleInferenceFailure implements Exception {
  final CapsuleInferenceFailureCode code;
  final String message;

  const CapsuleInferenceFailure(this.code, this.message);

  @override
  String toString() => message;
}

class CapsuleInferenceRequestV1 {
  static const int schemaVersion = 1;
  static const int maxSupportedInputBytes = 131072;
  static const int maxSupportedOutputBytes = 32768;
  static const int maxSupportedTimeoutMilliseconds = 120000;

  final String requestId;
  final String capsuleRootHex;
  final String capabilityId;
  final int disclosureSchemaVersion;
  final String disclosureHashHex;
  final List<String> disclosedSectionIds;
  final int disclosureByteCount;
  final String proposalSchemaId;
  final int proposalSchemaVersion;
  final CapsuleInferenceProviderPolicyV1 providerPolicy;
  final CapsuleInferenceModelPolicyV1 modelPolicy;
  final int maxInputBytes;
  final int maxOutputBytes;
  final int timeoutMilliseconds;
  final int maxConcurrentRequests;
  final String cancellationScope;
  final String instructions;
  final String inputJson;

  const CapsuleInferenceRequestV1._({
    required this.requestId,
    required this.capsuleRootHex,
    required this.capabilityId,
    required this.disclosureSchemaVersion,
    required this.disclosureHashHex,
    required this.disclosedSectionIds,
    required this.disclosureByteCount,
    required this.proposalSchemaId,
    required this.proposalSchemaVersion,
    required this.providerPolicy,
    required this.modelPolicy,
    required this.maxInputBytes,
    required this.maxOutputBytes,
    required this.timeoutMilliseconds,
    required this.maxConcurrentRequests,
    required this.cancellationScope,
    required this.instructions,
    required this.inputJson,
  });

  factory CapsuleInferenceRequestV1.create({
    required String capsuleRootHex,
    required String capabilityId,
    required int disclosureSchemaVersion,
    required List<String> disclosedSectionIds,
    required String proposalSchemaId,
    required int proposalSchemaVersion,
    required String cancellationScope,
    required String instructions,
    required Object input,
    int maxInputBytes = maxSupportedInputBytes,
    int maxOutputBytes = maxSupportedOutputBytes,
    int timeoutMilliseconds = 60000,
  }) {
    final normalizedCapsule = capsuleRootHex.trim().toLowerCase();
    final normalizedCapability = capabilityId.trim();
    final normalizedProposalSchema = proposalSchemaId.trim();
    final normalizedCancellationScope = cancellationScope.trim();
    final normalizedInstructions = instructions.trim();
    final normalizedSections = disclosedSectionIds
      .map((section) => section.trim())
      .where((section) => section.isNotEmpty)
      .toSet()
      .toList(growable: false)..sort();
    final inputJson = CapsuleInferenceCanonicalJson.encode(input);
    final disclosureBytes = utf8.encode(inputJson);
    final disclosureHashHex = sha256.convert(disclosureBytes).toString();
    final instructionsHashHex =
        sha256.convert(utf8.encode(normalizedInstructions)).toString();
    final identityJson = CapsuleInferenceCanonicalJson.encode(<String, dynamic>{
      'schema_version': schemaVersion,
      'capsule_root': normalizedCapsule,
      'capability_id': normalizedCapability,
      'disclosure_schema_version': disclosureSchemaVersion,
      'disclosure_hash_hex': disclosureHashHex,
      'disclosed_section_ids': normalizedSections,
      'proposal_schema_id': normalizedProposalSchema,
      'proposal_schema_version': proposalSchemaVersion,
      'provider_policy': CapsuleInferenceProviderPolicyV1.preferred.name,
      'model_policy': CapsuleInferenceModelPolicyV1.providerDefault.name,
      'max_input_bytes': maxInputBytes,
      'max_output_bytes': maxOutputBytes,
      'timeout_milliseconds': timeoutMilliseconds,
      'max_concurrent_requests': 1,
      'cancellation_scope': normalizedCancellationScope,
      'instructions_hash_hex': instructionsHashHex,
    });
    return CapsuleInferenceRequestV1._(
      requestId: sha256.convert(utf8.encode(identityJson)).toString(),
      capsuleRootHex: normalizedCapsule,
      capabilityId: normalizedCapability,
      disclosureSchemaVersion: disclosureSchemaVersion,
      disclosureHashHex: disclosureHashHex,
      disclosedSectionIds: List<String>.unmodifiable(normalizedSections),
      disclosureByteCount: disclosureBytes.length,
      proposalSchemaId: normalizedProposalSchema,
      proposalSchemaVersion: proposalSchemaVersion,
      providerPolicy: CapsuleInferenceProviderPolicyV1.preferred,
      modelPolicy: CapsuleInferenceModelPolicyV1.providerDefault,
      maxInputBytes: maxInputBytes,
      maxOutputBytes: maxOutputBytes,
      timeoutMilliseconds: timeoutMilliseconds,
      maxConcurrentRequests: 1,
      cancellationScope: normalizedCancellationScope,
      instructions: normalizedInstructions,
      inputJson: inputJson,
    );
  }
}

class CapsuleInferenceResultV1 {
  final String requestId;
  final String capsuleRootHex;
  final String capabilityId;
  final String disclosureHashHex;
  final String proposalSchemaId;
  final int proposalSchemaVersion;
  final String proposalText;
  final String providerId;
  final String providerLabel;
  final String model;
  final String responseHashHex;
  final int elapsedMilliseconds;

  const CapsuleInferenceResultV1({
    required this.requestId,
    required this.capsuleRootHex,
    required this.capabilityId,
    required this.disclosureHashHex,
    required this.proposalSchemaId,
    required this.proposalSchemaVersion,
    required this.proposalText,
    required this.providerId,
    required this.providerLabel,
    required this.model,
    required this.responseHashHex,
    required this.elapsedMilliseconds,
  });
}

abstract class CapsuleInferenceRuntime {
  String requireActiveCapsuleRootHex();

  Future<void> unlockPreferredProviderSession();

  Future<CapsuleInferenceResultV1> infer(CapsuleInferenceRequestV1 request);
}

class CapsuleAiRuntimeService implements CapsuleInferenceRuntime {
  static Future<void> _schedulerTail = Future<void>.value();
  static final Map<String, int> _scopeGenerations = <String, int>{};

  final AiDoctorCredentialStore _credentialStore;
  final InferenceProviderAdapter Function(InferenceProviderKind provider)
  _adapterFactory;
  final String? Function() _readActiveCapsuleRootHex;

  CapsuleAiRuntimeService({
    required AiDoctorCredentialStore credentialStore,
    required String? Function() readActiveCapsuleRootHex,
    InferenceProviderAdapter Function(InferenceProviderKind provider)?
    adapterFactory,
  }) : _credentialStore = credentialStore,
       _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _adapterFactory = adapterFactory ?? inferenceProviderAdapterFor;

  @override
  String requireActiveCapsuleRootHex() {
    final capsule = _readActiveCapsuleRootHex()?.trim().toLowerCase();
    if (capsule == null || !_isHex(capsule, 64)) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.capsuleUnavailable,
        'Active Capsule identity is unavailable for inference',
      );
    }
    return capsule;
  }

  @override
  Future<void> unlockPreferredProviderSession() async {
    await _credentialStore.unlockPreferredProviderSession();
  }

  @override
  Future<CapsuleInferenceResultV1> infer(CapsuleInferenceRequestV1 request) {
    final completer = Completer<CapsuleInferenceResultV1>();
    final scopeKey = _scopeKey(request);
    final generation = (_scopeGenerations[scopeKey] ?? 0) + 1;
    _scopeGenerations[scopeKey] = generation;
    _schedulerTail = _schedulerTail.then((_) async {
      try {
        completer.complete(await _execute(request, scopeKey, generation));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (_scopeGenerations[scopeKey] == generation) {
          _scopeGenerations.remove(scopeKey);
        }
      }
    });
    return completer.future;
  }

  Future<CapsuleInferenceResultV1> _execute(
    CapsuleInferenceRequestV1 request,
    String scopeKey,
    int generation,
  ) async {
    _validateRequest(request);
    _requireCurrentGeneration(scopeKey, generation);
    _requireMatchingCapsule(request.capsuleRootHex, stale: false);
    final provider = _credentialStore.sessionPreferredProvider;
    if (provider == null || !_credentialStore.isPreferredProviderUnlocked) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.sessionLocked,
        'AI access is locked for this app session',
      );
    }
    final apiKey = _credentialStore.sessionApiKey(provider);
    final baseUrl = _credentialStore.sessionBaseUrl(provider);
    final adapter = _adapterFactory(provider);
    if (adapter.provider != provider) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.invalidResponse,
        'AI provider adapter binding is invalid',
      );
    }
    final stopwatch = Stopwatch()..start();
    late final InferenceProviderResponse response;
    try {
      response = await adapter
          .ask(
            apiKey: apiKey ?? '',
            model: provider.defaultModel,
            baseUrl: baseUrl,
            prompt: InferencePrompt(
              instructions: request.instructions,
              inputJson: request.inputJson,
            ),
          )
          .timeout(Duration(milliseconds: request.timeoutMilliseconds));
    } on TimeoutException {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.timeout,
        'AI provider request timed out',
      );
    } finally {
      stopwatch.stop();
    }
    _requireCurrentGeneration(scopeKey, generation);
    _requireMatchingCapsule(request.capsuleRootHex, stale: true);
    final proposalText = response.text.trim();
    final model = response.model.trim();
    if (response.provider != provider || model.isEmpty) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.invalidResponse,
        'AI provider response evidence is invalid',
      );
    }
    final responseBytes = utf8.encode(proposalText);
    if (responseBytes.isEmpty ||
        responseBytes.length > request.maxOutputBytes) {
      throw CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.outputTooLarge,
        'AI provider output must contain 1..${request.maxOutputBytes} UTF-8 bytes',
      );
    }
    return CapsuleInferenceResultV1(
      requestId: request.requestId,
      capsuleRootHex: request.capsuleRootHex,
      capabilityId: request.capabilityId,
      disclosureHashHex: request.disclosureHashHex,
      proposalSchemaId: request.proposalSchemaId,
      proposalSchemaVersion: request.proposalSchemaVersion,
      proposalText: proposalText,
      providerId: response.provider.id,
      providerLabel: response.provider.label,
      model: model,
      responseHashHex: sha256.convert(responseBytes).toString(),
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  void _validateRequest(CapsuleInferenceRequestV1 request) {
    if (!_isHex(request.requestId, 64) ||
        !_isHex(request.capsuleRootHex, 64) ||
        !_isHex(request.disclosureHashHex, 64) ||
        request.capabilityId.isEmpty ||
        request.disclosureSchemaVersion != 1 ||
        request.disclosedSectionIds.isEmpty ||
        request.proposalSchemaId.isEmpty ||
        request.proposalSchemaVersion != 1 ||
        request.cancellationScope.isEmpty ||
        request.instructions.isEmpty ||
        request.maxConcurrentRequests != 1 ||
        request.maxInputBytes < 1 ||
        request.maxInputBytes >
            CapsuleInferenceRequestV1.maxSupportedInputBytes ||
        request.maxOutputBytes < 1 ||
        request.maxOutputBytes >
            CapsuleInferenceRequestV1.maxSupportedOutputBytes ||
        request.timeoutMilliseconds < 1 ||
        request.timeoutMilliseconds >
            CapsuleInferenceRequestV1.maxSupportedTimeoutMilliseconds) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.invalidRequest,
        'Capsule inference request is invalid or unsupported',
      );
    }
    final inputBytes = utf8.encode(request.inputJson);
    final actualHash = sha256.convert(inputBytes).toString();
    if (request.disclosureByteCount != inputBytes.length ||
        request.disclosureHashHex != actualHash) {
      throw const CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.invalidRequest,
        'Capsule inference disclosure evidence does not match its input',
      );
    }
    if (inputBytes.length > request.maxInputBytes) {
      throw CapsuleInferenceFailure(
        CapsuleInferenceFailureCode.inputTooLarge,
        'Inference input exceeds ${request.maxInputBytes} UTF-8 bytes',
      );
    }
  }

  void _requireMatchingCapsule(String expected, {required bool stale}) {
    final active = requireActiveCapsuleRootHex();
    if (active == expected) return;
    throw CapsuleInferenceFailure(
      stale
          ? CapsuleInferenceFailureCode.capsuleChanged
          : CapsuleInferenceFailureCode.invalidRequest,
      stale
          ? 'Active Capsule changed before inference completed'
          : 'Inference request does not belong to the active Capsule',
    );
  }

  void _requireCurrentGeneration(String scope, int generation) {
    if (_scopeGenerations[scope] == generation) return;
    throw const CapsuleInferenceFailure(
      CapsuleInferenceFailureCode.superseded,
      'Inference request was superseded by a newer request in the same scope',
    );
  }

  static String _scopeKey(CapsuleInferenceRequestV1 request) =>
      '${request.capsuleRootHex}:${request.capabilityId}:${request.cancellationScope}';

  static bool _isHex(String value, int length) {
    return value.length == length && RegExp(r'^[0-9a-f]+$').hasMatch(value);
  }
}

class CapsuleInferenceCanonicalJson {
  const CapsuleInferenceCanonicalJson._();

  static String encode(Object? value) => jsonEncode(_normalize(value));

  static Object? _normalize(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      return <String, dynamic>{
        for (final entry in entries) entry.key: _normalize(entry.value),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw ArgumentError('Canonical inference JSON contains unsupported value');
  }
}
