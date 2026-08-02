enum BingxFuturesRiskDecisionStatus { allowed, blocked }

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

class BingxFuturesRealizedPnlRecord {
  final String recordId;
  final String symbol;
  final String incomeQuoteDecimal;
  final int timestampMs;
  final String transactionId;
  final String tradeId;

  const BingxFuturesRealizedPnlRecord({
    required this.recordId,
    required this.symbol,
    required this.incomeQuoteDecimal,
    required this.timestampMs,
    required this.transactionId,
    required this.tradeId,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'record_id': recordId,
    'symbol': symbol,
    'income_quote_decimal': incomeQuoteDecimal,
    'timestamp_ms': timestampMs,
    'transaction_id': transactionId,
    'trade_id': tradeId,
  };

  static BingxFuturesRealizedPnlRecord? fromJsonMap(Map<String, dynamic> map) {
    final recordId = map['record_id']?.toString().trim() ?? '';
    final symbol = map['symbol']?.toString().trim().toUpperCase() ?? '';
    final income = map['income_quote_decimal']?.toString().trim() ?? '';
    final timestampMs = int.tryParse(map['timestamp_ms']?.toString() ?? '');
    final transactionId = map['transaction_id']?.toString().trim() ?? '';
    final tradeId = map['trade_id']?.toString().trim() ?? '';
    final parsedIncome = double.tryParse(income);
    if (recordId.isEmpty ||
        symbol.isEmpty ||
        timestampMs == null ||
        timestampMs <= 0 ||
        parsedIncome == null ||
        !parsedIncome.isFinite ||
        (transactionId.isEmpty && tradeId.isEmpty)) {
      return null;
    }
    return BingxFuturesRealizedPnlRecord(
      recordId: recordId,
      symbol: symbol,
      incomeQuoteDecimal: parsedIncome.toStringAsFixed(8),
      timestampMs: timestampMs,
      transactionId: transactionId,
      tradeId: tradeId,
    );
  }
}

class BingxFuturesRiskHistorySnapshot {
  final List<BingxFuturesRealizedPnlRecord> records;
  final String refreshedAtUtc;

  const BingxFuturesRiskHistorySnapshot({
    required this.records,
    required this.refreshedAtUtc,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'refreshed_at_utc': refreshedAtUtc,
    'records': records.map((record) => record.toJson()).toList(),
  };

  static BingxFuturesRiskHistorySnapshot? fromJsonMap(
    Map<String, dynamic> map,
  ) {
    if (map['version'] != 1) return null;
    final refreshedAtUtc = map['refreshed_at_utc']?.toString().trim() ?? '';
    if (DateTime.tryParse(refreshedAtUtc)?.isUtc != true) return null;
    final rawRecords = map['records'];
    if (rawRecords is! List) return null;
    final records = <BingxFuturesRealizedPnlRecord>[];
    for (final raw in rawRecords) {
      if (raw is! Map) return null;
      final parsed = BingxFuturesRealizedPnlRecord.fromJsonMap(
        Map<String, dynamic>.from(raw),
      );
      if (parsed == null) return null;
      records.add(parsed);
    }
    return BingxFuturesRiskHistorySnapshot(
      records: List.unmodifiable(records),
      refreshedAtUtc: refreshedAtUtc,
    );
  }
}
