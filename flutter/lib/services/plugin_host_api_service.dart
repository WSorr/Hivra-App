import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bingx_trading_contract_service.dart';
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
  final String executionSource;
  final String? executionPackageId;
  final String? executionPackageVersion;
  final String? executionPackageKind;
  final String? executionContractKind;
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
    required this.executionSource,
    required this.executionPackageId,
    required this.executionPackageVersion,
    required this.executionPackageKind,
    required this.executionContractKind,
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
typedef BingxSpotOrderRunner = BingxTradingExecutionResult Function({
  required String peerHex,
  required String clientOrderId,
  required String symbol,
  required String side,
  required String orderType,
  required String quantityDecimal,
  required String? limitPriceDecimal,
  required String? timeInForce,
  required String? entryMode,
  required String? zoneSide,
  required String? zoneLowDecimal,
  required String? zoneHighDecimal,
  required String? zonePriceRule,
  required String? manualEntryPriceDecimal,
  required String? triggerPriceDecimal,
  required String? stopLossDecimal,
  required String? takeProfitDecimal,
  required String createdAtUtc,
  required String? strategyTag,
});

class PluginRuntimeBinding {
  final String source;
  final String? packageId;
  final String? packageVersion;
  final String? packageKind;
  final String? contractKind;

  const PluginRuntimeBinding({
    required this.source,
    required this.packageId,
    required this.packageVersion,
    required this.packageKind,
    required this.contractKind,
  });

  const PluginRuntimeBinding.hostFallback()
      : source = 'host_fallback',
        packageId = null,
        packageVersion = null,
        packageKind = null,
        contractKind = null;

  const PluginRuntimeBinding.externalPackage({
    required this.packageId,
    required this.packageVersion,
    required this.packageKind,
    required this.contractKind,
  })  : source = 'external_package',
        assert(packageId != null),
        assert(packageKind != null);
}

typedef PluginRuntimeBindingResolver = Future<PluginRuntimeBinding> Function(
  String pluginId,
);

class PluginHostApiService {
  static const int schemaVersion = 1;
  static const String temperaturePluginId =
      'hivra.contract.temperature-li.tomorrow.v1';
  static const String settleTemperatureMethod = 'settle_temperature_tomorrow';
  static const String bingxTradingPluginId =
      BingxTradingContractService.pluginId;
  static const String placeBingxSpotOrderIntentMethod =
      'place_bingx_spot_order_intent';
  static const String capsuleChatPluginId = CapsuleChatContractService.pluginId;
  static const String postCapsuleChatMethod = 'post_capsule_chat_message';

  final TemperatureDemoRunner _runTemperatureDemo;
  final BingxSpotOrderRunner _runBingxSpotOrder;
  final CapsuleChatRunner _runCapsuleChat;
  final PluginRuntimeBindingResolver? _resolveRuntimeBinding;

  const PluginHostApiService({
    required TemperatureDemoRunner runTemperatureDemo,
    required BingxSpotOrderRunner runBingxSpotOrder,
    required CapsuleChatRunner runCapsuleChat,
    PluginRuntimeBindingResolver? resolveRuntimeBinding,
  })  : _runTemperatureDemo = runTemperatureDemo,
        _runBingxSpotOrder = runBingxSpotOrder,
        _runCapsuleChat = runCapsuleChat,
        _resolveRuntimeBinding = resolveRuntimeBinding;

  PluginHostApiResponse execute(PluginHostApiRequest request) {
    return _executeResolved(
      request,
      const PluginRuntimeBinding.hostFallback(),
    );
  }

  Future<PluginHostApiResponse> executeWithRuntimeHook(
    PluginHostApiRequest request,
  ) async {
    if (_resolveRuntimeBinding == null) {
      return execute(request);
    }
    final runtimeBinding = await _resolveRuntimeBinding(request.pluginId);
    return _executeResolved(request, runtimeBinding);
  }

  PluginHostApiResponse _executeResolved(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
  ) {
    if (request.schemaVersion != schemaVersion) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_schema_version',
        message: 'Plugin host API schema version mismatch',
        runtimeBinding: runtimeBinding,
      );
    }
    if (request.pluginId == temperaturePluginId) {
      return _executeTemperature(request, runtimeBinding);
    }
    if (request.pluginId == bingxTradingPluginId) {
      return _executeBingx(request, runtimeBinding);
    }
    if (request.pluginId == capsuleChatPluginId) {
      return _executeCapsuleChat(request, runtimeBinding);
    }
    return _rejected(
      pluginId: request.pluginId,
      method: request.method,
      code: 'unsupported_plugin',
      message: 'Unsupported plugin id',
      runtimeBinding: runtimeBinding,
    );
  }

  PluginHostApiResponse _executeTemperature(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
  ) {
    if (request.method != settleTemperatureMethod) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
        runtimeBinding: runtimeBinding,
      );
    }

    final parse = _parseTemperatureArgs(request.args);
    if (parse.error != null) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message: parse.error!,
        runtimeBinding: runtimeBinding,
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
        runtimeBinding: runtimeBinding,
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
          runtimeBinding: runtimeBinding,
        ),
    };
  }

  PluginHostApiResponse _executeCapsuleChat(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
  ) {
    if (request.method != postCapsuleChatMethod) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
        runtimeBinding: runtimeBinding,
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
        runtimeBinding: runtimeBinding,
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
        runtimeBinding: runtimeBinding,
      );
    }

    if (runResult.envelope != null) {
      return _executed(
        pluginId: request.pluginId,
        method: request.method,
        runtimeBinding: runtimeBinding,
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
      runtimeBinding: runtimeBinding,
    );
  }

  PluginHostApiResponse _executeBingx(
    PluginHostApiRequest request,
    PluginRuntimeBinding runtimeBinding,
  ) {
    if (request.method != placeBingxSpotOrderIntentMethod) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'unsupported_method',
        message: 'Unsupported plugin method',
        runtimeBinding: runtimeBinding,
      );
    }

    final peerHex = request.args['peer_hex']?.toString().trim().toLowerCase();
    final clientOrderId = request.args['client_order_id']?.toString().trim();
    final symbol = request.args['symbol']?.toString().trim();
    final side = request.args['side']?.toString().trim();
    final orderType = request.args['order_type']?.toString().trim();
    final quantityDecimal = request.args['quantity_decimal']?.toString().trim();
    final limitPriceDecimal =
        request.args['limit_price_decimal']?.toString().trim();
    final timeInForce = request.args['time_in_force']?.toString().trim();
    final entryMode = request.args['entry_mode']?.toString().trim();
    final zoneSide = request.args['zone_side']?.toString().trim();
    final zoneLowDecimal = request.args['zone_low_decimal']?.toString().trim();
    final zoneHighDecimal =
        request.args['zone_high_decimal']?.toString().trim();
    final zonePriceRule = request.args['zone_price_rule']?.toString().trim();
    final manualEntryPriceDecimal =
        request.args['manual_entry_price_decimal']?.toString().trim();
    final triggerPriceDecimal =
        request.args['trigger_price_decimal']?.toString().trim();
    final stopLossDecimal =
        request.args['stop_loss_decimal']?.toString().trim();
    final takeProfitDecimal =
        request.args['take_profit_decimal']?.toString().trim();
    final createdAtUtc = request.args['created_at_utc']?.toString().trim();
    final strategyTag = request.args['strategy_tag']?.toString().trim();

    if (peerHex == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex) ||
        clientOrderId == null ||
        clientOrderId.isEmpty ||
        symbol == null ||
        symbol.isEmpty ||
        side == null ||
        side.isEmpty ||
        orderType == null ||
        orderType.isEmpty ||
        quantityDecimal == null ||
        quantityDecimal.isEmpty ||
        createdAtUtc == null ||
        createdAtUtc.isEmpty) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message:
            'peer_hex/client_order_id/symbol/side/order_type/quantity_decimal/created_at_utc are required',
        runtimeBinding: runtimeBinding,
      );
    }

    late final BingxTradingExecutionResult runResult;
    try {
      runResult = _runBingxSpotOrder(
        peerHex: peerHex,
        clientOrderId: clientOrderId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        quantityDecimal: quantityDecimal,
        limitPriceDecimal: limitPriceDecimal,
        timeInForce: timeInForce,
        entryMode: entryMode,
        zoneSide: zoneSide,
        zoneLowDecimal: zoneLowDecimal,
        zoneHighDecimal: zoneHighDecimal,
        zonePriceRule: zonePriceRule,
        manualEntryPriceDecimal: manualEntryPriceDecimal,
        triggerPriceDecimal: triggerPriceDecimal,
        stopLossDecimal: stopLossDecimal,
        takeProfitDecimal: takeProfitDecimal,
        createdAtUtc: createdAtUtc,
        strategyTag: strategyTag,
      );
    } on FormatException catch (error) {
      return _rejected(
        pluginId: request.pluginId,
        method: request.method,
        code: 'invalid_args',
        message: error.message,
        runtimeBinding: runtimeBinding,
      );
    }

    if (runResult.intent != null) {
      return _executed(
        pluginId: request.pluginId,
        method: request.method,
        runtimeBinding: runtimeBinding,
        result: <String, dynamic>{
          'peer_hex': runResult.intent!.peerHex,
          'client_order_id': runResult.intent!.clientOrderId,
          'symbol': runResult.intent!.symbol,
          'side': runResult.intent!.side.name,
          'order_type': runResult.intent!.orderType.name,
          'quantity_decimal': runResult.intent!.quantityDecimal,
          'limit_price_decimal': runResult.intent!.limitPriceDecimal,
          'time_in_force': runResult.intent!.timeInForce,
          'entry_mode':
              runResult.intent!.entryMode == BingxEntryMode.zonePending
                  ? 'zone_pending'
                  : 'direct',
          'zone_side': runResult.intent!.zoneSide?.name,
          'zone_low_decimal': runResult.intent!.zoneLowDecimal,
          'zone_high_decimal': runResult.intent!.zoneHighDecimal,
          'zone_price_rule': switch (runResult.intent!.zonePriceRule) {
            BingxZonePriceRule.zoneLow => 'zone_low',
            BingxZonePriceRule.zoneMid => 'zone_mid',
            BingxZonePriceRule.zoneHigh => 'zone_high',
            BingxZonePriceRule.manual => 'manual',
            null => null,
          },
          'trigger_price_decimal': runResult.intent!.triggerPriceDecimal,
          'stop_loss_decimal': runResult.intent!.stopLossDecimal,
          'take_profit_decimal': runResult.intent!.takeProfitDecimal,
          'created_at_utc': runResult.intent!.createdAtUtc,
          'strategy_tag': runResult.intent!.strategyTag,
          'intent_hash_hex': runResult.intent!.intentHashHex,
          'canonical_intent_json': runResult.intent!.canonicalJson,
        },
      );
    }

    return _blocked(
      pluginId: request.pluginId,
      method: request.method,
      blockingFacts: runResult.blockingFacts,
      runtimeBinding: runtimeBinding,
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
    required PluginRuntimeBinding runtimeBinding,
    required Map<String, dynamic> result,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      errorCode: null,
      errorMessage: null,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: result,
    );
    return _buildResponse(
      status: PluginHostApiStatus.executed,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
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
    required PluginRuntimeBinding runtimeBinding,
    required List<ConsensusBlockingFact> blockingFacts,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      errorCode: null,
      errorMessage: null,
      blockingFacts: blockingFacts,
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.blocked,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
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
    required PluginRuntimeBinding runtimeBinding,
  }) {
    final canonical = _canonical(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
      errorCode: code,
      errorMessage: message,
      blockingFacts: const <ConsensusBlockingFact>[],
      result: null,
    );
    return _buildResponse(
      status: PluginHostApiStatus.rejected,
      pluginId: pluginId,
      method: method,
      runtimeBinding: runtimeBinding,
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
    required PluginRuntimeBinding runtimeBinding,
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
      executionSource: runtimeBinding.source,
      executionPackageId: runtimeBinding.packageId,
      executionPackageVersion: runtimeBinding.packageVersion,
      executionPackageKind: runtimeBinding.packageKind,
      executionContractKind: runtimeBinding.contractKind,
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
    required PluginRuntimeBinding runtimeBinding,
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
      'execution_source': runtimeBinding.source,
      'execution_package_id': runtimeBinding.packageId,
      'execution_package_version': runtimeBinding.packageVersion,
      'execution_package_kind': runtimeBinding.packageKind,
      'execution_contract_kind': runtimeBinding.contractKind,
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
