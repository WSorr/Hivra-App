import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capsule_chat_contract_service.dart';
import 'consensus_processor.dart';
import 'plugin_demo_contract_runner_service.dart';
import 'temperature_tomorrow_contract_service.dart';

enum PluginHostApiStatus {
  executed,
  blocked,
  rejected,
}

class PluginHostApiRequest {
  final int schemaVersion;
  final String pluginId;
  final String method;
  final Map<String, dynamic> args;

  const PluginHostApiRequest({
    required this.schemaVersion,
    required this.pluginId,
    required this.method,
    required this.args,
  });
}

class PluginHostApiResponse {
  final PluginHostApiStatus status;
  final String pluginId;
  final String method;
  final String? errorCode;
  final String? errorMessage;
  final List<ConsensusBlockingFact> blockingFacts;
  final Map<String, dynamic>? result;
  final String canonicalJson;
  final String responseHashHex;

  const PluginHostApiResponse({
    required this.status,
    required this.pluginId,
    required this.method,
    required this.errorCode,
    required this.errorMessage,
    required this.blockingFacts,
    required this.result,
    required this.canonicalJson,
    required this.responseHashHex,
  });
}

typedef TemperatureDemoRunner = PluginDemoRunResult Function({
  required TemperatureTomorrowContractSpec contract,
  required TemperatureOracleObservation observation,
});
typedef CapsuleChatRunner = CapsuleChatExecutionResult Function({
  required String peerHex,
  required String clientMessageId,
  required String messageText,
  required String createdAtUtc,
});

class PluginHostApiService {
  static const int schemaVersion = 1;
  static const String temperaturePluginId =
      'hivra.contract.temperature-li.tomorrow.v1';
  static const String settleTemperatureMethod = 'settle_temperature_tomorrow';
  static const String capsuleChatPluginId = CapsuleChatContractService.pluginId;
  static const String postCapsuleChatMethod = 'post_capsule_chat_message';

  final TemperatureDemoRunner _runTemperatureDemo;
  final CapsuleChatRunner _runCapsuleChat;

  const PluginHostApiService({
    required TemperatureDemoRunner runTemperatureDemo,
    required CapsuleChatRunner runCapsuleChat,
  })  : _runTemperatureDemo = runTemperatureDemo,
        _runCapsuleChat = runCapsuleChat;

  PluginHostApiResponse execute(PluginHostApiRequest request) {
    if (request.schemaVersion != schemaVersion) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_schema_version',
        message: 'Plugin host API schema version mismatch',
      );
    }
    if (request.pluginId == temperaturePluginId) {
      return _executeTemperature(request);
    }
    if (request.pluginId == capsuleChatPluginId) {
      return _executeCapsuleChat(request);
    }
    return _rejected(
      pluginId: request.pluginId,
      method: request.method,
      code: 'unsupported_plugin',
      message: 'Unsupported plugin id',
    );
  }

  PluginHostApiResponse _executeTemperature(PluginHostApiRequest request) {
    if (request.method != settleTemperatureMethod) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
      );
    }

    final parse = _parseTemperatureArgs(request.args);
    if (parse.error != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message: parse.error!,
      );
    }

    final runResult = _runTemperatureDemo(
      contract: parse.contract!,
      observation: parse.observation!,
    );

    if (runResult.settlement != null) {
      return _executed(
        pluginId: request.pluginId,
        method: request.method,
        result: <String, dynamic>{
          'peer_hex': runResult.peerHex,
          'peer_label': runResult.peerLabel,
          'outcome': runResult.settlement!.outcome.name,
          'winner_role': runResult.settlement!.winnerRole,
          'settlement_hash_hex': runResult.settlement!.settlementHashHex,
          'canonical_settlement_json': runResult.settlement!.canonicalJson,
          'ready_pair_count': runResult.readyPairCount,
          'blocked_pair_count': runResult.blockedPairCount,
        },
      );
    }

    return switch (runResult.state) {
      PluginDemoRunState.blocked ||
      PluginDemoRunState.noPairwisePaths ||
      PluginDemoRunState.partial ||
      PluginDemoRunState.executed =>
        _blocked(
          pluginId: request.pluginId,
          method: request.method,
          blockingFacts: runResult.blockingFacts,
        ),
    };
  }

  PluginHostApiResponse _executeCapsuleChat(PluginHostApiRequest request) {
    if (request.method != postCapsuleChatMethod) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
      );
    }

    final peerHex = request.args['peer_hex']?.toString().trim().toLowerCase();
    final clientMessageId =
        request.args['client_message_id']?.toString().trim();
    final messageText = request.args['message_text']?.toString();
    final createdAtUtc = request.args['created_at_utc']?.toString().trim();

    if (peerHex == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex) ||
        clientMessageId == null ||
        clientMessageId.isEmpty ||
        messageText == null ||
        messageText.trim().isEmpty ||
        createdAtUtc == null ||
        createdAtUtc.isEmpty) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message:
            'peer_hex/client_message_id/message_text/created_at_utc are required',
      );
    }

    late final CapsuleChatExecutionResult runResult;
    try {
      runResult = _runCapsuleChat(
        peerHex: peerHex,
        clientMessageId: clientMessageId,
        messageText: messageText,
        createdAtUtc: createdAtUtc,
      );
    } on FormatException catch (error) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message: error.message,
      );
    }

    if (runResult.envelope != null) {
      return _executed(
        pluginId: request.pluginId,
        method: request.method,
        result: <String, dynamic>{
          'peer_hex': runResult.envelope!.peerHex,
          'client_message_id': runResult.envelope!.clientMessageId,
          'message_text': runResult.envelope!.messageText,
          'created_at_utc': runResult.envelope!.createdAtUtc,
          'envelope_hash_hex': runResult.envelope!.envelopeHashHex,
          'canonical_envelope_json': runResult.envelope!.canonicalJson,
        },
      );
    }

    return _blocked(
      pluginId: request.pluginId,
      method: request.method,
      blockingFacts: runResult.blockingFacts,
    );
  }

  _TemperatureParseResult _parseTemperatureArgs(Map<String, dynamic> args) {
    final targetDateUtc = args['target_date_utc']?.toString().trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(targetDateUtc)) {
      return const _TemperatureParseResult(
        error: 'target_date_utc must be YYYY-MM-DD',
      );
    }
    final threshold = _parseInt(args['threshold_deci_celsius']);
    if (threshold == null) {
      return const _TemperatureParseResult(
        error: 'threshold_deci_celsius must be an integer',
      );
    }
    final proposerRuleRaw = args['proposer_rule']?.toString().trim();
    final proposerRule = switch (proposerRuleRaw) {
      'above' => TemperatureOutcomeRule.above,
      'below' => TemperatureOutcomeRule.below,
      _ => null,
    };
    if (proposerRule == null) {
      return const _TemperatureParseResult(
        error: 'proposer_rule must be above or below',
      );
    }
    final observed = _parseInt(args['observed_deci_celsius']);
    if (observed == null) {
      return const _TemperatureParseResult(
        error: 'observed_deci_celsius must be an integer',
      );
    }

    final sourceId = args['oracle_source_id']?.toString().trim() ?? '';
    final eventId = args['oracle_event_id']?.toString().trim() ?? '';
    final recordedAtUtc =
        args['oracle_recorded_at_utc']?.toString().trim() ?? '';
    if (sourceId.isEmpty || eventId.isEmpty || recordedAtUtc.isEmpty) {
      return const _TemperatureParseResult(
        error:
            'oracle_source_id/oracle_event_id/oracle_recorded_at_utc are required',
      );
    }
    if (!_isIsoUtc(recordedAtUtc)) {
      return const _TemperatureParseResult(
        error: 'oracle_recorded_at_utc must be ISO-8601 UTC instant',
      );
    }

    final drawOnEqual = args['draw_on_equal'] == true;
    final locationCode =
        (args['location_code']?.toString().trim() ?? 'LI').toUpperCase();

    return _TemperatureParseResult(
      contract: TemperatureTomorrowContractSpec(
        pluginId: temperaturePluginId,
        locationCode: locationCode,
        targetDateUtc: targetDateUtc,
        thresholdDeciCelsius: threshold,
        proposerRule: proposerRule,
        drawOnEqual: drawOnEqual,
      ),
      observation: TemperatureOracleObservation(
        sourceId: sourceId,
        eventId: eventId,
        locationCode: locationCode,
        targetDateUtc: targetDateUtc,
        recordedAtUtc: recordedAtUtc,
        observedDeciCelsius: observed,
      ),
    );
  }

  PluginHostApiResponse _executed({
    required String pluginId,
    required String method,
    required Map<String, dynamic> result,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
    );
    return _buildResponse(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _blocked({
    required String pluginId,
    required String method,
    required List<ConsensusBlockingFact> blockingFacts,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      errorCode: null,
      errorMessage: null,
      blockingFacts: blockingFacts,
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      errorCode: null,
      errorMessage: null,
      blockingFacts: blockingFacts,
      result: null,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _rejected({
    required String pluginId,
    required String method,
    required String code,
    required String message,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      errorCode: code,
      errorMessage: message,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      errorCode: code,
      errorMessage: message,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: null,
      canonical: canonical,
    );
  }

  PluginHostApiResponse _buildResponse({
    required PluginHostApiStatus status,
    required String pluginId,
    required String method,
    required String? errorCode,
    required String? errorMessage,
    required List<ConsensusBlockingFact> blockingFacts,
    required Map<String, dynamic>? result,
    required String canonical,
  }) {
    final responseHashHex = sha256.convert(utf8.encode(canonical)).toString();
    return PluginHostApiResponse(
      status: status,
      pluginId: pluginId,
      method: method,
      errorCode: errorCode,
      errorMessage: errorMessage,
      blockingFacts: (blockingFacts.toList()
        ..sort((a, b) => a.key.compareTo(b.key))),
      result: result,
      canonicalJson: canonical,
      responseHashHex: responseHashHex,
    );
  }

  String _canonical({
    required PluginHostApiStatus status,
    required String pluginId,
    required String method,
    required String? errorCode,
    required String? errorMessage,
    required List<ConsensusBlockingFact> blockingFacts,
    required Map<String, dynamic>? result,
  }) {
    return jsonEncode({
      'schema_version': schemaVersion,
      'status': status.name,
      'plugin_id': pluginId,
      'method': method,
      'error_code': errorCode,
      'error_message': errorMessage,
      'blocking_facts': (blockingFacts
          .map((fact) => <String, dynamic>{
                'code': fact.code,
                'subject_id': fact.subjectId,
              })
          .toList()
        ..sort(
          (a, b) => '${a['code']}:${a['subject_id'] ?? ''}'
              .compareTo('${b['code']}:${b['subject_id'] ?? ''}'),
        )),
      'result': result,
    });
  }

  int? _parseInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  bool _isIsoUtc(String value) {
    try {
      return DateTime.parse(value).isUtc;
    } catch (_) {
      return false;
    }
  }
}

class _TemperatureParseResult {
  final TemperatureTomorrowContractSpec? contract;
  final TemperatureOracleObservation? observation;
  final String? error;

  const _TemperatureParseResult({
    this.contract,
    this.observation,
    this.error,
  });
}
