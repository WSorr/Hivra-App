class BingxFuturesInstrumentMeta {
  final String symbol;
  final String baseAsset;
  final String quoteAsset;
  final String tickSizeDecimal;
  final String qtyStepDecimal;
  final String minQtyDecimal;
  final String maxLeverageDecimal;

  const BingxFuturesInstrumentMeta({
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
    required this.tickSizeDecimal,
    required this.qtyStepDecimal,
    required this.minQtyDecimal,
    required this.maxLeverageDecimal,
  });
}

class BingxFuturesPriceSnapshot {
  final String lastTradePriceDecimal;
  final String markPriceDecimal;
  final String indexPriceDecimal;

  const BingxFuturesPriceSnapshot({
    required this.lastTradePriceDecimal,
    required this.markPriceDecimal,
    required this.indexPriceDecimal,
  });
}

class BingxFuturesCandle {
  final String timeframe;
  final String openTimeUtc;
  final String closeTimeUtc;
  final String openDecimal;
  final String highDecimal;
  final String lowDecimal;
  final String closeDecimal;
  final String volumeBaseDecimal;
  final String volumeQuoteDecimal;
  final bool isClosed;

  const BingxFuturesCandle({
    required this.timeframe,
    required this.openTimeUtc,
    required this.closeTimeUtc,
    required this.openDecimal,
    required this.highDecimal,
    required this.lowDecimal,
    required this.closeDecimal,
    required this.volumeBaseDecimal,
    required this.volumeQuoteDecimal,
    required this.isClosed,
  });
}

class BingxFuturesOrderBookLevel {
  final String side;
  final String priceDecimal;
  final String quantityDecimal;

  const BingxFuturesOrderBookLevel({
    required this.side,
    required this.priceDecimal,
    required this.quantityDecimal,
  });
}

class BingxFuturesTrade {
  final String tradeId;
  final String timestampUtc;
  final String side;
  final String priceDecimal;
  final String quantityDecimal;

  const BingxFuturesTrade({
    required this.tradeId,
    required this.timestampUtc,
    required this.side,
    required this.priceDecimal,
    required this.quantityDecimal,
  });
}

class BingxFuturesOpenInterestPoint {
  final String timestampUtc;
  final String openInterestDecimal;

  const BingxFuturesOpenInterestPoint({
    required this.timestampUtc,
    required this.openInterestDecimal,
  });
}

class BingxFuturesFundingSnapshot {
  final String timestampUtc;
  final String fundingRateDecimal;
  final String nextFundingAtUtc;

  const BingxFuturesFundingSnapshot({
    required this.timestampUtc,
    required this.fundingRateDecimal,
    required this.nextFundingAtUtc,
  });
}

class BingxFuturesLiquidityLevel {
  final String kind; // external | internal | liquidation
  final String side; // buyside | sellside
  final String timeframe;
  final String priceDecimal;

  const BingxFuturesLiquidityLevel({
    required this.kind,
    required this.side,
    required this.timeframe,
    required this.priceDecimal,
  });
}

class BingxFuturesSessionVolumePoint {
  final String session; // asia | london | newyork
  final String bucketStartUtc;
  final String volumeDecimal;
  final String deltaDecimal;

  const BingxFuturesSessionVolumePoint({
    required this.session,
    required this.bucketStartUtc,
    required this.volumeDecimal,
    required this.deltaDecimal,
  });
}

class BingxFuturesMarketSnapshotInput {
  final BingxFuturesInstrumentMeta instrument;
  final BingxFuturesPriceSnapshot prices;
  final List<BingxFuturesCandle> candles;
  final List<BingxFuturesTrade> trades;
  final List<BingxFuturesOpenInterestPoint> openInterest;
  final BingxFuturesFundingSnapshot funding;
  final List<BingxFuturesLiquidityLevel> liquidityLevels;
  final List<BingxFuturesSessionVolumePoint> sessionVolumes;
  final List<BingxFuturesOrderBookLevel> orderBookTopLevels;

  const BingxFuturesMarketSnapshotInput({
    required this.instrument,
    required this.prices,
    required this.candles,
    required this.trades,
    required this.openInterest,
    required this.funding,
    required this.liquidityLevels,
    required this.sessionVolumes,
    this.orderBookTopLevels = const <BingxFuturesOrderBookLevel>[],
  });
}

class BingxFuturesMarketSnapshotDigest {
  final Map<String, dynamic> normalizedSnapshot;
  final String canonicalJson;
  final String marketSnapshotHashHex;
  final bool liquidationFeedAvailable;

  const BingxFuturesMarketSnapshotDigest({
    required this.normalizedSnapshot,
    required this.canonicalJson,
    required this.marketSnapshotHashHex,
    required this.liquidationFeedAvailable,
  });
}
