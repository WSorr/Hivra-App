enum BingxFuturesRiskDecisionStatus {
  allowed,
  blocked,
}

class BingxFuturesRiskPolicy {
  final double maxRiskPerTradePercent;
  final double maxDailyLossPercent;
  final int maxConcurrentPositions;
  final int cooldownAfterLossStreak;
  final int cooldownMinutes;
  final Set<String> symbolAllowlist;
  final Set<String> symbolDenylist;

  const BingxFuturesRiskPolicy({
    required this.maxRiskPerTradePercent,
    required this.maxDailyLossPercent,
    required this.maxConcurrentPositions,
    required this.cooldownAfterLossStreak,
    required this.cooldownMinutes,
    this.symbolAllowlist = const <String>{},
    this.symbolDenylist = const <String>{},
  });
}

class BingxFuturesRiskGovernorInput {
  final String symbol;
  final String quantityDecimal;
  final String entryPriceDecimal;
  final String stopLossDecimal;
  final String accountEquityQuoteDecimal;
  final String realizedDailyPnlQuoteDecimal;
  final int concurrentPositions;
  final int lossStreakCount;
  final String? lastLossAtUtc;
  final String nowUtc;
  final String? exchangeMinimumQuantityDecimal;
  final String? exchangeMinimumNotionalQuoteDecimal;
  final String? exchangeReferencePriceDecimal;

  const BingxFuturesRiskGovernorInput({
    required this.symbol,
    required this.quantityDecimal,
    required this.entryPriceDecimal,
    required this.stopLossDecimal,
    required this.accountEquityQuoteDecimal,
    required this.realizedDailyPnlQuoteDecimal,
    required this.concurrentPositions,
    required this.lossStreakCount,
    required this.lastLossAtUtc,
    required this.nowUtc,
    this.exchangeMinimumQuantityDecimal,
    this.exchangeMinimumNotionalQuoteDecimal,
    this.exchangeReferencePriceDecimal,
  });
}

class BingxFuturesRiskDecision {
  final BingxFuturesRiskDecisionStatus status;
  final String reasonCode;
  final String reasonMessage;
  final String canonicalJson;
  final String decisionHashHex;
  final String maxAllowedQuantityDecimal;
  final String tradeRiskQuoteDecimal;
  final String tradeRiskLimitQuoteDecimal;
  final String dailyLossQuoteDecimal;
  final String dailyLossLimitQuoteDecimal;

  const BingxFuturesRiskDecision({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.canonicalJson,
    required this.decisionHashHex,
    required this.maxAllowedQuantityDecimal,
    required this.tradeRiskQuoteDecimal,
    required this.tradeRiskLimitQuoteDecimal,
    required this.dailyLossQuoteDecimal,
    required this.dailyLossLimitQuoteDecimal,
  });
}
