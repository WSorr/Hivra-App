import 'dart:convert';

import 'package:crypto/crypto.dart';
import '../models/bingx_futures_market_snapshot_models.dart';

class BingxFuturesShadowMarketProposalCodec {
  const BingxFuturesShadowMarketProposalCodec();

  bool validate({
    required String? status,
    required String? proposalJson,
    required String decisionHashHex,
    required String decision,
    required String marketSnapshotHashHex,
    required String featureHashHex,
    bool requireExecutableProposal = true,
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
      return !requireExecutableProposal ||
          status != 'READY' ||
          _isExecutable(decoded);
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
          'parent',
          'atr14_5m_decimal',
          'liquidity_event_id',
          'liquidity_event_at_utc',
          'latest_closed_micro_bar_at_utc',
        }) ||
        zone['anchor_executable'] != true ||
        zone['conflict'] != false ||
        !_isPositiveDecimal(zone['low_decimal']) ||
        !_isPositiveDecimal(zone['high_decimal']) ||
        !_isPositiveDecimal(zone['atr14_5m_decimal']) ||
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
    final parent = zone['parent'];
    if (parent is! Map<String, dynamic> ||
        !_hasExactKeys(parent, const {
          'strategy_version',
          'timeframe',
          'side',
          'low_decimal',
          'high_decimal',
          'sweep_at_utc',
          'confirmed_at_utc',
        }) ||
        parent['strategy_version'] != bingxLiquidityStrategyVersion ||
        parent['timeframe'] != '4h' ||
        parent['side'] != side ||
        zone['anchor_source'] != '4h_sweep_reclaim_5m' ||
        zone['anchor_lifecycle'] != 'reclaimed' ||
        !_isPositiveDecimal(parent['low_decimal']) ||
        !_isPositiveDecimal(parent['high_decimal']) ||
        !_isUtcTimestamp(parent['sweep_at_utc']) ||
        !_isUtcTimestamp(parent['confirmed_at_utc'])) {
      return false;
    }
    final low = double.parse(zone['low_decimal'] as String);
    final high = double.parse(zone['high_decimal'] as String);
    final known = DateTime.parse(parent['confirmed_at_utc'] as String);
    final confirmed = DateTime.parse(zone['liquidity_event_at_utc'] as String);
    if (low >= high ||
        low < double.parse(parent['low_decimal'] as String) ||
        high > double.parse(parent['high_decimal'] as String) ||
        known.isBefore(DateTime.parse(parent['sweep_at_utc'] as String)) ||
        confirmed.difference(known) < const Duration(minutes: 5) ||
        confirmed.isAfter(
          DateTime.parse(zone['latest_closed_micro_bar_at_utc'] as String),
        )) {
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
    final number = double.tryParse(value);
    return number != null && number.isFinite && number > 0;
  }

  bool _isUtcTimestamp(Object? value) =>
      value is String &&
      value.endsWith('Z') &&
      DateTime.tryParse(value)?.isUtc == true;
}
