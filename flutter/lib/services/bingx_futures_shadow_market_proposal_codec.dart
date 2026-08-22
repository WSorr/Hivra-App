import 'dart:convert';

import 'package:crypto/crypto.dart';

class BingxFuturesShadowMarketProposalCodec {
  const BingxFuturesShadowMarketProposalCodec();

  bool validate({
    required String? status,
    required String? proposalJson,
    required String decisionHashHex,
    required String decision,
    required String marketSnapshotHashHex,
    required String featureHashHex,
  }) {
    if (status != 'READY' && status != 'BLOCKED' || proposalJson == null) {
      return false;
    }
    try {
      final decoded = jsonDecode(proposalJson);
      if (decoded is! Map<String, dynamic> ||
          jsonEncode(decoded) != proposalJson ||
          !_hasExactKeys(decoded, const <String>{
            'schema_version',
            'contract',
            'market_snapshot_hash_hex',
            'feature_hash_hex',
            'tvh_decision_hash_hex',
            'decision',
            'can_prepare_intent',
            'trend_bundle',
            'trend_gate',
            'side',
            'zone_evaluation_side',
            'zone',
            'profit_target',
            'reason_codes',
          }) ||
          decoded['schema_version'] != 2 ||
          decoded['contract'] != 'bingx_futures_live_decision_v2' ||
          decoded['market_snapshot_hash_hex'] != marketSnapshotHashHex ||
          decoded['feature_hash_hex'] != featureHashHex ||
          decoded['decision'] != decision ||
          decoded['can_prepare_intent'] != (status == 'READY') ||
          sha256.convert(utf8.encode(proposalJson)).toString() !=
              decisionHashHex) {
        return false;
      }
      final trendBundle = decoded['trend_bundle'];
      final trendGate = decoded['trend_gate'];
      final reasons = decoded['reason_codes'];
      if (trendBundle is! Map<String, dynamic> ||
          !_hasExactKeys(trendBundle, const <String>{
            'trend_15m',
            'trend_4h',
            'trend_1d',
          }) ||
          trendBundle.values.any((value) => value is! String) ||
          trendGate is! Map<String, dynamic> ||
          !_hasExactKeys(trendGate, const <String>{'blocked', 'code'}) ||
          trendGate['blocked'] is! bool ||
          trendGate['code'] is! String ||
          reasons is! List<dynamic> ||
          reasons.isEmpty ||
          reasons.any(
            (item) =>
                item is! Map<String, dynamic> ||
                !_hasExactKeys(item, const <String>{'code', 'passed'}) ||
                item['code'] is! String ||
                item['passed'] is! bool,
          )) {
        return false;
      }
      return status != 'READY' || _isExecutable(decoded);
    } on Object {
      return false;
    }
  }

  bool _isExecutable(Map<String, dynamic> proposal) {
    final side = proposal['side'];
    final zone = proposal['zone'];
    final target = proposal['profit_target'];
    if ((proposal['decision'] != 'long' && proposal['decision'] != 'short') ||
        (side != 'buy' && side != 'sell') ||
        zone is! Map<String, dynamic> ||
        !_hasExactKeys(zone, const <String>{
          'side',
          'low_decimal',
          'high_decimal',
          'source',
          'side_reason',
          'conflict',
          'target_retest_pct',
          'needs_farther_retest',
          'anchor_source',
          'anchor_executable',
          'anchor_lifecycle',
          'liquidity_event_id',
          'liquidity_event_at_utc',
          'latest_closed_micro_bar_at_utc',
        }) ||
        zone['anchor_executable'] != true ||
        zone['conflict'] != false ||
        !_isPositiveDecimal(zone['low_decimal']) ||
        !_isPositiveDecimal(zone['high_decimal']) ||
        !_isSha256(zone['liquidity_event_id']) ||
        !_isUtcTimestamp(zone['liquidity_event_at_utc']) ||
        !_isUtcTimestamp(zone['latest_closed_micro_bar_at_utc']) ||
        target is! Map<String, dynamic> ||
        !_hasExactKeys(target, const <String>{
          'kind',
          'price_decimal',
          'source',
          'event_at_utc',
        }) ||
        target['kind'] != 'opposite_external_liquidity' ||
        !_isPositiveDecimal(target['price_decimal']) ||
        target['source'] is! String ||
        !_isUtcTimestamp(target['event_at_utc'])) {
      return false;
    }
    return true;
  }

  bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length &&
      value.keys.toSet().containsAll(expected);

  bool _isSha256(Object? value) =>
      value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  bool _isPositiveDecimal(Object? value) {
    if (value is! String || !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(value)) {
      return false;
    }
    return (double.tryParse(value) ?? 0) > 0;
  }

  bool _isUtcTimestamp(Object? value) =>
      value is String &&
      value.endsWith('Z') &&
      DateTime.tryParse(value)?.isUtc == true;
}
