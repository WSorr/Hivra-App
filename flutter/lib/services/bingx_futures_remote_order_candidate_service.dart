import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_order_sizing_models.dart';
import '../models/bingx_futures_order_tracking_models.dart';
import '../models/bingx_futures_risk_models.dart';
import 'bingx_futures_deterministic_replay_harness_service.dart';
import 'bingx_futures_exchange_risk_input_service.dart';
import 'bingx_futures_order_sizing_service.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_trading_cycle_use_case_service.dart';

enum BingxFuturesRemoteOrderCandidateStatus { ready, blocked }

class BingxFuturesRemoteOrderCandidateResult {
  final BingxFuturesRemoteOrderCandidateStatus status;
  final String reasonCode;
  final String? canonicalJson;
  final String? candidateHashHex;

  const BingxFuturesRemoteOrderCandidateResult({
    required this.status,
    required this.reasonCode,
    required this.canonicalJson,
    required this.candidateHashHex,
  });

  BingxFuturesIntentPayload? toExactOrderIntent({required DateTime nowUtc}) {
    if (status != BingxFuturesRemoteOrderCandidateStatus.ready ||
        canonicalJson == null ||
        candidateHashHex == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(candidateHashHex!) ||
        sha256.convert(utf8.encode(canonicalJson!)).toString() !=
            candidateHashHex) {
      return null;
    }
    try {
      final decoded = jsonDecode(canonicalJson!);
      const candidateKeys = <String>{
        'contract_version',
        'market_evidence_hash_hex',
        'market_decision_hash_hex',
        'mandate_id',
        'risk_decision_hash_hex',
        'symbol',
        'side',
        'client_order_id',
        'quantity_decimal',
        'limit_price_decimal',
        'trigger_price_decimal',
        'stop_loss_decimal',
        'take_profit_decimal',
        'liquidity_event_id',
        'market_observed_at_utc',
        'account_risk_observed_at_utc',
        'composed_at_utc',
        'valid_until_utc',
        'test_order',
      };
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference(candidateKeys).isNotEmpty ||
          candidateKeys.difference(decoded.keys.toSet()).isNotEmpty ||
          decoded['test_order'] is! bool ||
          decoded['contract_version'] !=
              BingxFuturesRemoteOrderCandidateService.contractVersion) {
        return null;
      }
      for (final key in <String>[
        'quantity_decimal',
        'limit_price_decimal',
        'trigger_price_decimal',
        'stop_loss_decimal',
        'take_profit_decimal',
      ]) {
        final value = num.tryParse(decoded[key]?.toString() ?? '');
        if (value == null || !value.isFinite || value <= 0) return null;
      }
      final composedAt =
          DateTime.parse(decoded['composed_at_utc']?.toString() ?? '').toUtc();
      final validUntil =
          DateTime.parse(decoded['valid_until_utc']?.toString() ?? '').toUtc();
      final now = nowUtc.toUtc();
      if (composedAt.isAfter(now) || now.isAfter(validUntil)) return null;
      return BingxFuturesIntentPayload.fromPluginResult(<String, dynamic>{
        'client_order_id': decoded['client_order_id'],
        'symbol': decoded['symbol'],
        'side': decoded['side'],
        'order_type': 'limit',
        'quantity_decimal': decoded['quantity_decimal'],
        'limit_price_decimal': decoded['limit_price_decimal'],
        'time_in_force': 'GTC',
        'entry_mode': 'zone_pending',
        'trigger_price_decimal': decoded['trigger_price_decimal'],
        'stop_loss_decimal': decoded['stop_loss_decimal'],
        'take_profit_decimal': decoded['take_profit_decimal'],
        'intent_hash_hex': candidateHashHex,
      });
    } catch (_) {
      return null;
    }
  }
}

class BingxFuturesRemoteOrderCandidateService {
  static const String contractVersion =
      'hivra-trading-remote-order-candidate-v1';
  static const Duration maximumAccountRiskAge = Duration(seconds: 30);

  final BingxFuturesDeterministicReplayHarnessService _shadow;
  final BingxFuturesOrderSizingService _sizing;
  final BingxFuturesRiskGovernorService _risk;

  const BingxFuturesRemoteOrderCandidateService({
    required BingxFuturesOrderSizingService sizing,
    BingxFuturesDeterministicReplayHarnessService shadow =
        const BingxFuturesDeterministicReplayHarnessService(),
    BingxFuturesRiskGovernorService risk =
        const BingxFuturesRiskGovernorService(),
  }) : _shadow = shadow,
       _sizing = sizing,
       _risk = risk;

  Future<BingxFuturesRemoteOrderCandidateResult> compose({
    required List<int> untrustedMarketEvidenceBytes,
    required SimplePublicKey trustedRunnerKey,
    required int lastAcceptedSequence,
    required String lastAcceptedEvidenceHashHex,
    required String expectedRunnerBuildId,
    required String expectedPluginId,
    required String expectedPluginVersion,
    required String expectedPackageDigestHex,
    required String expectedHostAbi,
    required BingxFuturesTradingMandate mandate,
    required BingxFuturesExchangeRiskInput accountRisk,
    required DateTime accountRiskObservedAtUtc,
    required BingxFuturesContractRules contractRules,
    required DateTime nowUtc,
    required double stopLossPercent,
    required double minimumRiskReward,
  }) async {
    final continuity = await _shadow.verifyShadowEvidenceContinuity(
      untrustedWireBytes: untrustedMarketEvidenceBytes,
      trustedRunnerKey: trustedRunnerKey,
      lastAcceptedSequence: lastAcceptedSequence,
      lastAcceptedEvidenceHashHex: lastAcceptedEvidenceHashHex,
    );
    if (continuity != BingxFuturesShadowEvidenceVerdict.accepted) {
      return _blocked('market_evidence_${continuity.name}');
    }
    final evidence = _shadow.parseShadowEvidence(untrustedMarketEvidenceBytes);
    final now = nowUtc.toUtc();
    if (evidence.contractVersion != 'trading-shadow-evidence-v2' ||
        evidence.runnerBuildId != expectedRunnerBuildId ||
        evidence.pluginId != expectedPluginId ||
        evidence.pluginVersion != expectedPluginVersion ||
        evidence.packageDigestHex != expectedPackageDigestHex ||
        evidence.hostAbi != expectedHostAbi) {
      return _blocked('market_evidence_identity_mismatch');
    }
    if (now.millisecondsSinceEpoch < evidence.observedAtEpochMs ||
        now.millisecondsSinceEpoch > evidence.validUntilEpochMs) {
      return _blocked('market_evidence_stale');
    }
    if (evidence.marketProposalStatus != 'READY') {
      return _blocked('market_proposal_blocked');
    }
    if (!mandate.isActiveAt(now)) return _blocked('mandate_inactive');
    if (accountRisk.usedBalanceFallback ||
        accountRisk.usedPnlFallback ||
        accountRisk.usedPositionsFallback ||
        accountRisk.firstUnavailableReason != null) {
      return _blocked('account_risk_incomplete');
    }
    final accountObservedAt = accountRiskObservedAtUtc.toUtc();
    if (accountObservedAt.isAfter(now) ||
        now.difference(accountObservedAt) > maximumAccountRiskAge) {
      return _blocked('account_risk_stale');
    }
    if (!stopLossPercent.isFinite ||
        !minimumRiskReward.isFinite ||
        stopLossPercent <= 0 ||
        minimumRiskReward <= 0) {
      return _blocked('strategy_risk_input_invalid');
    }

    final proposal = jsonDecode(evidence.marketProposalJson!);
    if (proposal is! Map<String, dynamic>) {
      return _blocked('market_proposal_malformed');
    }
    final symbol = mandate.symbol;
    if (evidence.marketSymbol != symbol) {
      return _blocked('market_symbol_mismatch');
    }
    if (contractRules.symbol.trim().toUpperCase() != symbol) {
      return _blocked('contract_rules_symbol_mismatch');
    }
    final side = proposal['side'];
    final zone = proposal['zone'];
    final target = proposal['profit_target'];
    if ((side != 'buy' && side != 'sell') ||
        zone is! Map<String, dynamic> ||
        target is! Map<String, dynamic>) {
      return _blocked('market_proposal_incomplete');
    }
    final low = num.tryParse(zone['low_decimal']?.toString() ?? '');
    final high = num.tryParse(zone['high_decimal']?.toString() ?? '');
    if (low == null ||
        high == null ||
        !low.isFinite ||
        !high.isFinite ||
        low <= 0 ||
        high <= low) {
      return _blocked('market_zone_invalid');
    }
    final entry = (low + high) / 2;
    final trigger = side == 'buy' ? high : low;
    final targets = deriveBingxFuturesLiquidityTargets(
      side: side,
      entryPrice: entry,
      stopLossPercent: stopLossPercent,
      minimumRiskReward: minimumRiskReward,
      oppositeLiquidityTargetDecimal: target['price_decimal']?.toString(),
    );
    if (targets.blockerCode != null ||
        targets.stopLossDecimal == null ||
        targets.takeProfitDecimal == null) {
      return _blocked(targets.blockerCode ?? 'liquidity_target_invalid');
    }
    final maxNotional = num.tryParse(mandate.maxOrderNotionalQuoteDecimal);
    if (maxNotional == null || !maxNotional.isFinite || maxNotional <= 0) {
      return _blocked('mandate_notional_invalid');
    }
    final sizing = _sizing.calculate(
      maximumNotionalQuote: maxNotional,
      referencePriceDecimal: _decimal(entry),
      rules: contractRules,
    );
    if (sizing.status != BingxFuturesOrderSizingStatus.sized ||
        sizing.quantityDecimal == null) {
      return _blocked(sizing.reasonCode);
    }
    final risk = _risk.evaluate(
      input: BingxFuturesRiskGovernorInput(
        symbol: symbol,
        quantityDecimal: sizing.quantityDecimal!,
        entryPriceDecimal: _decimal(entry),
        stopLossDecimal: targets.stopLossDecimal!,
        accountEquityQuoteDecimal: accountRisk.accountEquityQuoteDecimal,
        realizedDailyPnlQuoteDecimal: accountRisk.realizedDailyPnlQuoteDecimal,
        concurrentPositions: accountRisk.concurrentPositions,
        lossStreakCount: accountRisk.lossStreakCount,
        lastLossAtUtc: accountRisk.lastLossAtUtc,
        nowUtc: now.toIso8601String(),
        exchangeMinimumQuantityDecimal: contractRules.minimumQuantityDecimal,
        exchangeMinimumNotionalQuoteDecimal:
            contractRules.minimumNotionalQuoteDecimal,
        exchangeReferencePriceDecimal: _decimal(entry),
      ),
      policy: BingxFuturesRiskPolicy(
        maxRiskPerTradePercent: mandate.maxRiskPerTradePercent,
        maxDailyLossPercent: mandate.maxDailyLossPercent,
        maxConcurrentPositions: mandate.maxConcurrentPositions,
        cooldownAfterLossStreak: mandate.cooldownAfterLossStreak,
        cooldownMinutes: mandate.cooldownMinutes,
        symbolAllowlist: <String>{symbol},
      ),
    );
    if (risk.status != BingxFuturesRiskDecisionStatus.allowed) {
      return _blocked(risk.reasonCode);
    }
    final liquidityEventId = zone['liquidity_event_id']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(liquidityEventId)) {
      return _blocked('liquidity_event_evidence_missing');
    }
    final evidenceExpiry = DateTime.fromMillisecondsSinceEpoch(
      evidence.validUntilEpochMs,
      isUtc: true,
    );
    final mandateExpiry = DateTime.parse(mandate.expiresAtUtc).toUtc();
    final candidateExpiry =
        evidenceExpiry.isBefore(mandateExpiry) ? evidenceExpiry : mandateExpiry;
    final canonical = jsonEncode(<String, dynamic>{
      'contract_version': contractVersion,
      'market_evidence_hash_hex': evidence.evidenceHashHex,
      'market_decision_hash_hex': evidence.decisionHashHex,
      'mandate_id': mandate.mandateId,
      'risk_decision_hash_hex': risk.decisionHashHex,
      'symbol': symbol,
      'side': side,
      'client_order_id': 'hivra-${liquidityEventId.substring(0, 32)}',
      'quantity_decimal': sizing.quantityDecimal,
      'limit_price_decimal': _decimal(entry),
      'trigger_price_decimal': _decimal(trigger),
      'stop_loss_decimal': targets.stopLossDecimal,
      'take_profit_decimal': targets.takeProfitDecimal,
      'liquidity_event_id': liquidityEventId,
      'market_observed_at_utc':
          DateTime.fromMillisecondsSinceEpoch(
            evidence.observedAtEpochMs,
            isUtc: true,
          ).toIso8601String(),
      'account_risk_observed_at_utc': accountObservedAt.toIso8601String(),
      'composed_at_utc': now.toIso8601String(),
      'valid_until_utc': candidateExpiry.toIso8601String(),
      'test_order': mandate.testOrder,
    });
    return BingxFuturesRemoteOrderCandidateResult(
      status: BingxFuturesRemoteOrderCandidateStatus.ready,
      reasonCode: 'order_candidate_ready',
      canonicalJson: canonical,
      candidateHashHex: sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  BingxFuturesRemoteOrderCandidateResult _blocked(String reasonCode) =>
      BingxFuturesRemoteOrderCandidateResult(
        status: BingxFuturesRemoteOrderCandidateStatus.blocked,
        reasonCode: reasonCode,
        canonicalJson: null,
        candidateHashHex: null,
      );

  static String _decimal(num value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
}
