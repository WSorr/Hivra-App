import '../models/bingx_futures_exchange_models.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_risk_history_service.dart';

class BingxFuturesExchangeRiskInput {
  final String? accountEquityQuoteDecimal;
  final String? realizedDailyPnlQuoteDecimal;
  final int? concurrentPositions;
  final int? lossStreakCount;
  final String? lastLossAtUtc;
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
    this.balanceUnavailableCode,
    this.balanceUnavailableMessage,
    this.positionsUnavailableCode,
    this.positionsUnavailableMessage,
    this.pnlUnavailableCode,
    this.pnlUnavailableMessage,
  });

  bool get isComplete =>
      accountEquityQuoteDecimal != null &&
      realizedDailyPnlQuoteDecimal != null &&
      concurrentPositions != null &&
      lossStreakCount != null &&
      firstUnavailableReason == null;

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
  }) async {
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
    final hasPositiveEquity = parsedEquity != null && parsedEquity > 0;
    final concurrentPositions = _countConcurrentPositions(positions.positions);

    final balanceUnavailable = !balance.isSuccess || !hasPositiveEquity;
    final pnlUnavailable = !riskHistory.isComplete;
    final positionsUnavailable = !positions.isSuccess;

    return BingxFuturesExchangeRiskInput(
      accountEquityQuoteDecimal:
          balanceUnavailable ? null : parsedEquity.toStringAsFixed(8),
      realizedDailyPnlQuoteDecimal:
          pnlUnavailable ? null : riskHistory.realizedDailyPnlQuoteDecimal,
      concurrentPositions:
          positionsUnavailable ? null : concurrentPositions.clamp(0, 1000),
      lossStreakCount: pnlUnavailable ? null : riskHistory.lossStreakCount,
      lastLossAtUtc: pnlUnavailable ? null : riskHistory.lastLossAtUtc,
      balanceUnavailableCode:
          balanceUnavailable
              ? balance.isSuccess && !hasPositiveEquity
                  ? 'account_equity_non_positive'
                  : balance.exchangeCode
              : null,
      balanceUnavailableMessage:
          balanceUnavailable
              ? balance.isSuccess && !hasPositiveEquity
                  ? 'BingX account equity must be positive'
                  : balance.exchangeMessage
              : null,
      positionsUnavailableCode:
          positionsUnavailable ? positions.exchangeCode : null,
      positionsUnavailableMessage:
          positionsUnavailable ? positions.exchangeMessage : null,
      pnlUnavailableCode: pnlUnavailable ? riskHistory.unavailableCode : null,
      pnlUnavailableMessage:
          pnlUnavailable ? riskHistory.unavailableMessage : null,
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
