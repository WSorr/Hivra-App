import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_tvh_rule_models.dart';
import 'bingx_futures_feature_extractor_service.dart';

class BingxFuturesTvhRuleEngineService {
  const BingxFuturesTvhRuleEngineService();

  BingxTvhDecisionResult evaluate({
    required BingxFuturesFeatureExtractionResult features,
    required String fundingRateDecimal,
    required bool isConsensusSignable,
    List<String> blockingFactCodes = const <String>[],
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  }) {
    final reasons = <BingxTvhDecisionReason>[];
    final normalizedBlocking = blockingFactCodes
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList()
      ..sort();

    if (policy.requireConsensusSignable &&
        (!isConsensusSignable || normalizedBlocking.isNotEmpty)) {
      reasons.add(
        BingxTvhDecisionReason(
          code: 'consensus_guard',
          passed: false,
          detail: normalizedBlocking.isEmpty
              ? 'consensus_signable=false'
              : 'blocking=${normalizedBlocking.join(",")}',
        ),
      );
      return _result(
        features: features,
        decision: BingxTvhDecisionKind.blocked,
        fundingRateDecimal: fundingRateDecimal,
        reasons: reasons,
      );
    }

    final fundingRate = _parseDecimal(
      fundingRateDecimal,
      field: 'funding_rate_decimal',
    );
    final tradeDelta = _parseDecimal(
      features.tradeDeltaDecimal,
      field: 'trade_delta_decimal',
    );
    final sessionNetDelta = _parseDecimal(
      features.sessionNetDeltaDecimal,
      field: 'session_net_delta_decimal',
    );

    final fundingOk = fundingRate.abs() <= policy.maxAbsFundingRate;
    reasons.add(
      BingxTvhDecisionReason(
        code: 'funding_guard',
        passed: fundingOk,
        detail:
            'abs=${_fmt(fundingRate)} max=${_fmt(policy.maxAbsFundingRate)}',
      ),
    );
    if (!fundingOk) {
      return _result(
        features: features,
        decision: BingxTvhDecisionKind.noSignal,
        fundingRateDecimal: fundingRateDecimal,
        reasons: reasons,
      );
    }

    final longTradeOk = tradeDelta >= policy.minAbsTradeDelta;
    final longSessionOk = sessionNetDelta >= policy.minAbsSessionNetDelta;
    final longWhaleOk =
        !policy.requireWhaleActivation || features.hasBuyWhaleActivation;
    final shortTradeOk = tradeDelta <= -policy.minAbsTradeDelta;
    final shortSessionOk = sessionNetDelta <= -policy.minAbsSessionNetDelta;
    final shortWhaleOk =
        !policy.requireWhaleActivation || features.hasSellWhaleActivation;

    final longReady = features.trendDirection == BingxTrendDirection.bullish &&
        longTradeOk &&
        longSessionOk &&
        longWhaleOk;
    final shortReady = features.trendDirection == BingxTrendDirection.bearish &&
        shortTradeOk &&
        shortSessionOk &&
        shortWhaleOk;

    reasons.add(
      BingxTvhDecisionReason(
        code: 'trend',
        passed: features.trendDirection != BingxTrendDirection.neutral,
        detail: features.trendDirection.name,
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_trade_delta',
        passed: longTradeOk,
        detail:
            'value=${features.tradeDeltaDecimal} threshold=${_fmt(policy.minAbsTradeDelta)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_session_delta',
        passed: longSessionOk,
        detail:
            'value=${features.sessionNetDeltaDecimal} threshold=${_fmt(policy.minAbsSessionNetDelta)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_whale_activation',
        passed: longWhaleOk,
        detail: 'required=${policy.requireWhaleActivation}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_trade_delta',
        passed: shortTradeOk,
        detail:
            'value=${features.tradeDeltaDecimal} threshold=-${_fmt(policy.minAbsTradeDelta)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_session_delta',
        passed: shortSessionOk,
        detail:
            'value=${features.sessionNetDeltaDecimal} threshold=-${_fmt(policy.minAbsSessionNetDelta)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_whale_activation',
        passed: shortWhaleOk,
        detail: 'required=${policy.requireWhaleActivation}',
      ),
    );

    final decision = longReady
        ? BingxTvhDecisionKind.long
        : shortReady
            ? BingxTvhDecisionKind.short
            : BingxTvhDecisionKind.noSignal;
    return _result(
      features: features,
      decision: decision,
      fundingRateDecimal: fundingRateDecimal,
      reasons: reasons,
    );
  }

  BingxTvhDecisionResult _result({
    required BingxFuturesFeatureExtractionResult features,
    required BingxTvhDecisionKind decision,
    required String fundingRateDecimal,
    required List<BingxTvhDecisionReason> reasons,
  }) {
    final canonicalReasons = reasons
        .map(
          (reason) => <String, dynamic>{
            'code': reason.code,
            'passed': reason.passed,
            'detail': reason.detail,
          },
        )
        .toList();
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'rule_set': features.ruleSet,
      'feature_hash_hex': features.featureHashHex,
      'decision': decision.name,
      'funding_rate_decimal': fundingRateDecimal,
      'reasons': canonicalReasons,
    });
    final decisionHashHex = sha256.convert(utf8.encode(canonical)).toString();
    return BingxTvhDecisionResult(
      ruleSet: features.ruleSet,
      featureHashHex: features.featureHashHex,
      decision: decision,
      reasons: reasons,
      canonicalJson: canonical,
      decisionHashHex: decisionHashHex,
    );
  }

  double _parseDecimal(String raw, {required String field}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) {
      throw FormatException('$field must be a decimal number');
    }
    return parsed;
  }

  String _fmt(double value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
}
