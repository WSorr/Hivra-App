import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_risk_models.dart';
import 'package:hivra_app/services/bingx_futures_risk_governor_service.dart';

void main() {
  group('BingxFuturesRiskGovernorService', () {
    const service = BingxFuturesRiskGovernorService();
    const policy = BingxFuturesRiskPolicy(
      maxRiskPerTradePercent: 2.0,
      maxDailyLossPercent: 5.0,
      maxConcurrentPositions: 3,
      cooldownAfterLossStreak: 2,
      cooldownMinutes: 60,
      symbolAllowlist: <String>{'BTC-USDT', 'ETH-USDT'},
      symbolDenylist: <String>{'DOGE-USDT'},
    );

    test('allows request when all gates pass', () {
      final decision = service.evaluate(
        input: _input(),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.allowed);
      expect(decision.reasonCode, 'risk_allowed');
      expect(decision.maxAllowedQuantityDecimal, isNot('0'));
      expect(decision.decisionHashHex.length, 64);
    });

    test('blocks denied symbol', () {
      final decision = service.evaluate(
        input: _input(symbol: 'DOGE-USDT'),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_symbol_denied');
    });

    test('blocks symbol outside allowlist', () {
      final decision = service.evaluate(
        input: _input(symbol: 'SOL-USDT'),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_symbol_not_allowed');
    });

    test('blocks max concurrent positions', () {
      final decision = service.evaluate(
        input: _input(concurrentPositions: 3),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_max_concurrent_positions');
    });

    test('blocks active cooldown after loss streak', () {
      final decision = service.evaluate(
        input: _input(
          lossStreakCount: 2,
          lastLossAtUtc: '2026-05-13T11:30:00Z',
          nowUtc: '2026-05-13T12:00:00Z',
        ),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_loss_streak_cooldown');
    });

    test('blocks daily loss limit exceeded', () {
      final decision = service.evaluate(
        input: _input(realizedDailyPnlQuoteDecimal: '-600'),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_daily_loss_limit');
      expect(decision.dailyLossQuoteDecimal, isNot('0'));
      expect(decision.dailyLossLimitQuoteDecimal, isNot('0'));
    });

    test('blocks per-trade risk exceeded', () {
      final decision = service.evaluate(
        input: _input(quantityDecimal: '5'),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'risk_per_trade_exceeded');
      expect(decision.tradeRiskQuoteDecimal, isNot('0'));
      expect(decision.tradeRiskLimitQuoteDecimal, isNot('0'));
      expect(decision.maxAllowedQuantityDecimal, isNot('0'));
    });

    test('blocks quantity below exchange minimum before local risk', () {
      final decision = service.evaluate(
        input: _input(
          quantityDecimal: '0.001801',
          entryPriceDecimal: '1503.50',
          stopLossDecimal: '1428.33',
          exchangeMinimumQuantityDecimal: '0.01',
          exchangeMinimumNotionalQuoteDecimal: '2',
          exchangeReferencePriceDecimal: '1665.48',
        ),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'exchange_min_quantity');
      expect(decision.reasonMessage, contains('16.6548 USDT'));
    });

    test('blocks notional below exchange minimum', () {
      final decision = service.evaluate(
        input: _input(
          quantityDecimal: '0.01',
          entryPriceDecimal: '100',
          stopLossDecimal: '95',
          exchangeMinimumNotionalQuoteDecimal: '2',
          exchangeReferencePriceDecimal: '100',
        ),
        policy: policy,
      );

      expect(decision.status, BingxFuturesRiskDecisionStatus.blocked);
      expect(decision.reasonCode, 'exchange_min_notional');
    });

    test('is deterministic for identical inputs', () {
      final first = service.evaluate(
        input: _input(),
        policy: policy,
      );
      final second = service.evaluate(
        input: _input(),
        policy: policy,
      );

      expect(first.status, second.status);
      expect(first.reasonCode, second.reasonCode);
      expect(first.canonicalJson, second.canonicalJson);
      expect(first.decisionHashHex, second.decisionHashHex);
    });
  });
}

BingxFuturesRiskGovernorInput _input({
  String symbol = 'BTC-USDT',
  String quantityDecimal = '0.4',
  String entryPriceDecimal = '60000',
  String stopLossDecimal = '59800',
  String accountEquityQuoteDecimal = '10000',
  String realizedDailyPnlQuoteDecimal = '-100',
  int concurrentPositions = 1,
  int lossStreakCount = 0,
  String? lastLossAtUtc,
  String nowUtc = '2026-05-13T12:00:00Z',
  String? exchangeMinimumQuantityDecimal,
  String? exchangeMinimumNotionalQuoteDecimal,
  String? exchangeReferencePriceDecimal,
}) {
  return BingxFuturesRiskGovernorInput(
    symbol: symbol,
    quantityDecimal: quantityDecimal,
    entryPriceDecimal: entryPriceDecimal,
    stopLossDecimal: stopLossDecimal,
    accountEquityQuoteDecimal: accountEquityQuoteDecimal,
    realizedDailyPnlQuoteDecimal: realizedDailyPnlQuoteDecimal,
    concurrentPositions: concurrentPositions,
    lossStreakCount: lossStreakCount,
    lastLossAtUtc: lastLossAtUtc,
    nowUtc: nowUtc,
    exchangeMinimumQuantityDecimal: exchangeMinimumQuantityDecimal,
    exchangeMinimumNotionalQuoteDecimal: exchangeMinimumNotionalQuoteDecimal,
    exchangeReferencePriceDecimal: exchangeReferencePriceDecimal,
  );
}
