import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_observability_models.dart';

class BingxFuturesObservabilityEnvelopeService {
  const BingxFuturesObservabilityEnvelopeService();

  BingxFuturesLogEnvelope buildDecisionEnvelope({
    required String screen,
    required String pluginId,
    required String method,
    required String status,
    required String symbol,
    required String side,
    required String orderType,
    required String entryMode,
    required String executionSource,
    String? intentHashHex,
    String? errorCode,
    String? marketSnapshotHashHex,
    String? featureHashHex,
    String? tvhDecisionHashHex,
    String? liveDecisionHashHex,
    List<String> blockingFactCodes = const <String>[],
    DateTime? nowUtc,
  }) {
    final codes = blockingFactCodes
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList()
      ..sort();
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'kind': 'bingx_futures_decision_log_v1',
      'timestamp_utc': (nowUtc ?? DateTime.now().toUtc()).toIso8601String(),
      'screen': screen.trim(),
      'plugin_id': pluginId.trim(),
      'method': method.trim(),
      'status': status.trim(),
      'execution_source': executionSource.trim(),
      'symbol': symbol.trim().toUpperCase(),
      'side': side.trim().toLowerCase(),
      'order_type': orderType.trim().toLowerCase(),
      'entry_mode': entryMode.trim().toLowerCase(),
      'intent_hash_hex': (intentHashHex ?? '').trim().toLowerCase(),
      'error_code': (errorCode ?? '').trim(),
      'market_snapshot_hash_hex':
          (marketSnapshotHashHex ?? '').trim().toLowerCase(),
      'feature_hash_hex': (featureHashHex ?? '').trim().toLowerCase(),
      'tvh_decision_hash_hex': (tvhDecisionHashHex ?? '').trim().toLowerCase(),
      'live_decision_hash_hex':
          (liveDecisionHashHex ?? '').trim().toLowerCase(),
      'blocking_fact_codes': codes,
    });
    final hashHex = sha256.convert(utf8.encode(canonical)).toString();
    return BingxFuturesLogEnvelope(
      canonicalJson: canonical,
      envelopeHashHex: hashHex,
    );
  }

  BingxFuturesLogEnvelope buildExecutionEnvelope({
    required String screen,
    required String symbol,
    required String side,
    required String orderType,
    required String idempotencyKey,
    required int attempts,
    required bool fromIdempotentCache,
    required bool isSuccess,
    required int httpStatusCode,
    required String exchangeCode,
    required String endpointPath,
    String? orderId,
    String? intentHashHex,
    String? riskDecisionCode,
    String? riskDecisionHashHex,
    String? marketSnapshotHashHex,
    String? featureHashHex,
    String? tvhDecisionHashHex,
    String? liveDecisionHashHex,
    DateTime? nowUtc,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'kind': 'bingx_futures_execution_log_v1',
      'timestamp_utc': (nowUtc ?? DateTime.now().toUtc()).toIso8601String(),
      'screen': screen.trim(),
      'symbol': symbol.trim().toUpperCase(),
      'side': side.trim().toLowerCase(),
      'order_type': orderType.trim().toLowerCase(),
      'idempotency_key': idempotencyKey.trim(),
      'attempts': attempts,
      'from_idempotent_cache': fromIdempotentCache,
      'success': isSuccess,
      'http_status_code': httpStatusCode,
      'exchange_code': exchangeCode.trim(),
      'endpoint_path': endpointPath.trim(),
      'order_id': (orderId ?? '').trim(),
      'intent_hash_hex': (intentHashHex ?? '').trim().toLowerCase(),
      'risk_decision_code': (riskDecisionCode ?? '').trim(),
      'risk_decision_hash_hex':
          (riskDecisionHashHex ?? '').trim().toLowerCase(),
      'market_snapshot_hash_hex':
          (marketSnapshotHashHex ?? '').trim().toLowerCase(),
      'feature_hash_hex': (featureHashHex ?? '').trim().toLowerCase(),
      'tvh_decision_hash_hex': (tvhDecisionHashHex ?? '').trim().toLowerCase(),
      'live_decision_hash_hex':
          (liveDecisionHashHex ?? '').trim().toLowerCase(),
    });
    final hashHex = sha256.convert(utf8.encode(canonical)).toString();
    return BingxFuturesLogEnvelope(
      canonicalJson: canonical,
      envelopeHashHex: hashHex,
    );
  }
}
