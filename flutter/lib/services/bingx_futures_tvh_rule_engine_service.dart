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
    String? requiredSide,
    List<String> blockingFactCodes = const <String>[],
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  }) {
    final reasons = <BingxTvhDecisionReason>[];
    final normalizedBlocking =
        blockingFactCodes
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
          detail:
              normalizedBlocking.isEmpty
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

    return evaluateMarket(
      features: features,
      fundingRateDecimal: fundingRateDecimal,
      requiredSide: requiredSide,
      policy: policy,
    );
  }

  BingxTvhDecisionResult evaluateMarket({
    required BingxFuturesFeatureExtractionResult features,
    required String fundingRateDecimal,
    String? requiredSide,
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  }) {
    final reasons = <BingxTvhDecisionReason>[];
    final normalizedRequiredSide = _normalizeOptionalSide(requiredSide);

    final fundingRate = _parseDecimal(
      fundingRateDecimal,
      field: 'funding_rate_decimal',
    );
    final tradeImbalanceRatio = _parseDecimal(
      features.tradeImbalanceRatioDecimal,
      field: 'trade_imbalance_ratio_decimal',
    );
    final sessionImbalanceRatio = _parseDecimal(
      features.sessionImbalanceRatioDecimal,
      field: 'session_imbalance_ratio_decimal',
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

    final longTradeOk = tradeImbalanceRatio >= policy.minAbsTradeImbalanceRatio;
    final shortTradeOk =
        tradeImbalanceRatio <= -policy.minAbsTradeImbalanceRatio;
    final longSessionAligned =
        features.sessionEvidenceComplete && sessionImbalanceRatio > 0;
    final shortSessionAligned =
        features.sessionEvidenceComplete && sessionImbalanceRatio < 0;

    final longReady = longTradeOk && normalizedRequiredSide != 'sell';
    final shortReady = shortTradeOk && normalizedRequiredSide != 'buy';

    reasons.add(
      BingxTvhDecisionReason(
        code: 'trend_context',
        passed: true,
        detail: features.trendDirection.name,
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'session_context',
        passed: true,
        detail:
            features.sessionEvidenceComplete
                ? 'coverage=complete'
                : 'coverage=incomplete',
      ),
    );
    if (normalizedRequiredSide != null) {
      reasons.add(
        BingxTvhDecisionReason(
          code: 'liquidity_side_constraint',
          passed: true,
          detail: normalizedRequiredSide,
        ),
      );
    }
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_trade_imbalance',
        passed: longTradeOk,
        detail:
            'value=${features.tradeImbalanceRatioDecimal} threshold=${_fmt(policy.minAbsTradeImbalanceRatio)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_session_context',
        passed: true,
        detail:
            'aligned=$longSessionAligned '
            'value=${features.sessionImbalanceRatioDecimal}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'long_whale_context',
        passed: true,
        detail: 'observed=${features.hasBuyWhaleActivation}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_trade_imbalance',
        passed: shortTradeOk,
        detail:
            'value=${features.tradeImbalanceRatioDecimal} threshold=-${_fmt(policy.minAbsTradeImbalanceRatio)}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_session_context',
        passed: true,
        detail:
            'aligned=$shortSessionAligned '
            'value=${features.sessionImbalanceRatioDecimal}',
      ),
    );
    reasons.add(
      BingxTvhDecisionReason(
        code: 'short_whale_context',
        passed: true,
        detail: 'observed=${features.hasSellWhaleActivation}',
      ),
    );

    final decision =
        longReady
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
    final canonicalReasons =
        reasons
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

  String? _normalizeOptionalSide(String? side) {
    final normalized = side?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'buy' || normalized == 'sell') return normalized;
    throw FormatException('requiredSide must be buy or sell: $side');
  }

  String _fmt(double value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
}
