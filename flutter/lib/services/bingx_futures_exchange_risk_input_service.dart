import '../models/bingx_futures_exchange_models.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_risk_history_service.dart';

class BingxFuturesExchangeRiskInput {
  final String accountEquityQuoteDecimal;
  final String realizedDailyPnlQuoteDecimal;
  final int concurrentPositions;
  final int lossStreakCount;
  final String? lastLossAtUtc;
  final bool usedBalanceFallback;
  final bool usedPnlFallback;
  final bool usedPositionsFallback;
  final String? balanceUnavailableCode;
  final String? balanceUnavailableMessage;
  final String? positionsUnavailableCode;
  final String? positionsUnavailableMessage;
  final String? pnlUnavailableCode;
  final String? pnlUnavailableMessage;

  const BingxFuturesExchangeRiskInput({
    required this.accountEquityQuoteDecimal,
    required this.realizedDailyPnlQuoteDecimal,
    required this.concurrentPositions,
    required this.lossStreakCount,
    required this.lastLossAtUtc,
    required this.usedBalanceFallback,
    required this.usedPnlFallback,
    required this.usedPositionsFallback,
    this.balanceUnavailableCode,
    this.balanceUnavailableMessage,
    this.positionsUnavailableCode,
    this.positionsUnavailableMessage,
    this.pnlUnavailableCode,
    this.pnlUnavailableMessage,
  });

  String? get firstUnavailableReason {
    final balanceReason = _formatUnavailableReason(
      balanceUnavailableCode,
      balanceUnavailableMessage,
    );
    if (balanceReason != null) return balanceReason;
    final pnlReason = _formatUnavailableReason(
      pnlUnavailableCode,
      pnlUnavailableMessage,
    );
    if (pnlReason != null) return pnlReason;
    return _formatUnavailableReason(
      positionsUnavailableCode,
      positionsUnavailableMessage,
    );
  }

  static String? _formatUnavailableReason(String? code, String? message) {
    final safeCode = code?.trim() ?? '';
    final safeMessage = message?.trim() ?? '';
    if (safeCode.isEmpty && safeMessage.isEmpty) return null;
    if (safeCode.isEmpty) return safeMessage;
    if (safeMessage.isEmpty) return safeCode;
    return '$safeCode $safeMessage';
  }
}

class BingxFuturesExchangeRiskInputService {
  const BingxFuturesExchangeRiskInputService();

  Future<BingxFuturesExchangeRiskInput> read({
    required BingxFuturesExchangeService exchangeService,
    required BingxFuturesRiskHistoryService riskHistoryService,
    required BingxFuturesApiCredentials credentials,
    required DateTime nowUtc,
    double fallbackEquityQuote = 100.0,
  }) async {
    final safeFallbackEquity =
        fallbackEquityQuote > 0 ? fallbackEquityQuote : 100.0;

    final balanceFuture = exchangeService.getUserBalance(
      credentials: credentials,
    );
    final positionsFuture = exchangeService.getUserPositions(
      credentials: credentials,
    );
    final riskHistoryFuture = riskHistoryService.refresh(
      exchangeService: exchangeService,
      credentials: credentials,
      nowUtc: nowUtc,
    );
    final balance = await balanceFuture;
    final positions = await positionsFuture;
    final riskHistory = await riskHistoryFuture;

    final parsedEquity = _parseFinite(balance.accountEquityQuoteDecimal);
    final concurrentPositions = _countConcurrentPositions(positions.positions);

    final usedBalanceFallback = !balance.isSuccess || parsedEquity == null;
    final usedPnlFallback = !riskHistory.isComplete;
    final usedPositionsFallback = !positions.isSuccess;

    return BingxFuturesExchangeRiskInput(
      accountEquityQuoteDecimal:
          usedBalanceFallback
              ? safeFallbackEquity.toStringAsFixed(8)
              : parsedEquity.toStringAsFixed(8),
      realizedDailyPnlQuoteDecimal: riskHistory.realizedDailyPnlQuoteDecimal,
      concurrentPositions:
          usedPositionsFallback ? 0 : concurrentPositions.clamp(0, 1000),
      lossStreakCount: riskHistory.lossStreakCount,
      lastLossAtUtc: riskHistory.lastLossAtUtc,
      usedBalanceFallback: usedBalanceFallback,
      usedPnlFallback: usedPnlFallback,
      usedPositionsFallback: usedPositionsFallback,
      balanceUnavailableCode: usedBalanceFallback ? balance.exchangeCode : null,
      balanceUnavailableMessage:
          usedBalanceFallback ? balance.exchangeMessage : null,
      positionsUnavailableCode:
          usedPositionsFallback ? positions.exchangeCode : null,
      positionsUnavailableMessage:
          usedPositionsFallback ? positions.exchangeMessage : null,
      pnlUnavailableCode: usedPnlFallback ? riskHistory.unavailableCode : null,
      pnlUnavailableMessage:
          usedPnlFallback ? riskHistory.unavailableMessage : null,
    );
  }

  static double? _parseFinite(String? raw) {
    if (raw == null) return null;
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  static int _countConcurrentPositions(List<BingxFuturesUserPosition> rows) {
    var count = 0;
    for (final row in rows) {
      final qty = _parseFinite(row.quantityDecimal);
      if (qty != null && qty.abs() > 0) {
        count += 1;
      }
    }
    return count;
  }
}
