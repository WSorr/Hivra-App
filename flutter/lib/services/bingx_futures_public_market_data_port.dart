import '../models/bingx_futures_exchange_models.dart';

abstract interface class BingxFuturesPublicMarketDataPort {
  Future<BingxFuturesPublicPriceResult> getPublicPrice({
    required String symbol,
  });

  Future<BingxFuturesPublicKlinesResult> getPublicKlines({
    required String symbol,
    required String interval,
    int limit = 120,
  });

  Future<BingxFuturesPublicOrderBookResult> getPublicDepth({
    required String symbol,
    int limit = 20,
  });

  Future<BingxFuturesPublicTradesResult> getPublicTrades({
    required String symbol,
    int limit = 100,
  });

  Future<BingxFuturesPublicPremiumIndexResult> getPublicPremiumIndex({
    required String symbol,
  });

  Future<BingxFuturesPublicOpenInterestResult> getPublicOpenInterest({
    required String symbol,
  });

  Future<BingxFuturesPublicOpenInterestHistoryResult>
  getPublicOpenInterestHistory({
    required String symbol,
    String period = '5m',
    int limit = 24,
  });
}
