import '../models/bingx_futures_exchange_models.dart';
import 'bingx_futures_exchange_service.dart';

class BingxFuturesExchangeRiskInput {
  final String accountEquityQuoteDecimal;
  final String realizedDailyPnlQuoteDecimal;
  final int concurrentPositions;
  final bool usedBalanceFallback;
  final bool usedPnlFallback;
  final bool usedPositionsFallback;

  const BingxFuturesExchangeRiskInput({
    required this.accountEquityQuoteDecimal,
    required this.realizedDailyPnlQuoteDecimal,
    required this.concurrentPositions,
    required this.usedBalanceFallback,
    required this.usedPnlFallback,
    required this.usedPositionsFallback,
  });
}

class BingxFuturesExchangeRiskInputService {
  const BingxFuturesExchangeRiskInputService();

  Future<BingxFuturesExchangeRiskInput> read({
    required BingxFuturesExchangeService exchangeService,
    required BingxFuturesApiCredentials credentials,
    double fallbackEquityQuote = 100.0,
  }) async {
    final safeFallbackEquity =
        fallbackEquityQuote > 0 ? fallbackEquityQuote : 100.0;

    final balance = await exchangeService.getUserBalance(
      credentials: credentials,
    );
    final positions = await exchangeService.getUserPositions(
      credentials: credentials,
    );

    final parsedEquity = _parseFinite(balance.accountEquityQuoteDecimal);
    final parsedPnl = _parseFinite(balance.realizedPnlQuoteDecimal);
    final concurrentPositions = _countConcurrentPositions(positions.positions);

    final usedBalanceFallback = !balance.isSuccess || parsedEquity == null;
    final usedPnlFallback = !balance.isSuccess || parsedPnl == null;
    final usedPositionsFallback = !positions.isSuccess;

    return BingxFuturesExchangeRiskInput(
      accountEquityQuoteDecimal: usedBalanceFallback
          ? safeFallbackEquity.toStringAsFixed(8)
          : parsedEquity.toStringAsFixed(8),
      realizedDailyPnlQuoteDecimal:
          usedPnlFallback ? '0.00000000' : parsedPnl.toStringAsFixed(8),
      concurrentPositions:
          usedPositionsFallback ? 0 : concurrentPositions.clamp(0, 1000),
      usedBalanceFallback: usedBalanceFallback,
      usedPnlFallback: usedPnlFallback,
      usedPositionsFallback: usedPositionsFallback,
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
