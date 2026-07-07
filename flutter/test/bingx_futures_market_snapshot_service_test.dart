import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/services/bingx_futures_market_snapshot_service.dart';

void main() {
  group('BingxFuturesMarketSnapshotService', () {
    const service = BingxFuturesMarketSnapshotService();

    test('produces stable canonical json/hash for permuted inputs', () {
      final first = service.build(_inputA());
      final second = service.build(_inputB());

      expect(first.marketSnapshotHashHex.length, 64);
      expect(first.marketSnapshotHashHex, second.marketSnapshotHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('fails when required candle timeframe is missing', () {
      expect(
        () => service.build(_inputMissing1w()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('missing required candle timeframes'),
          ),
        ),
      );
    });

    test('keeps liquidation feed optional and marks metadata unknown', () {
      final digest = service.build(_inputA());

      expect(digest.liquidationFeedAvailable, isFalse);
      expect(
        digest.normalizedSnapshot['metadata']?['liquidation_feed_state'],
        'unknown',
      );
      expect(
        (digest.normalizedSnapshot['orderbook_top_levels'] as List).isEmpty,
        isTrue,
      );
    });
  });
}

BingxFuturesMarketSnapshotInput _inputA() {
  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'btc-usdt',
      baseAsset: 'btc',
      quoteAsset: 'usdt',
      tickSizeDecimal: '0.10',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '60300',
      markPriceDecimal: '60295.5',
      indexPriceDecimal: '60298.2',
    ),
    candles: _candlesA(),
    trades: const <BingxFuturesTrade>[
      BingxFuturesTrade(
        tradeId: '2',
        timestampUtc: '2026-04-22T10:00:02+03:00',
        side: 'sell',
        priceDecimal: '60300.25',
        quantityDecimal: '0.01',
      ),
      BingxFuturesTrade(
        tradeId: '1',
        timestampUtc: '2026-04-22T07:00:00Z',
        side: 'buy',
        priceDecimal: '60299.8',
        quantityDecimal: '0.0050',
      ),
    ],
    openInterest: const <BingxFuturesOpenInterestPoint>[
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-22T06:55:00Z',
        openInterestDecimal: '502300.5',
      ),
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-22T07:00:00Z',
        openInterestDecimal: '502400.0',
      ),
    ],
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-22T07:00:00Z',
      fundingRateDecimal: '-0.0001200',
      nextFundingAtUtc: '2026-04-22T08:00:00Z',
    ),
    liquidityLevels: const <BingxFuturesLiquidityLevel>[
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'buyside',
        timeframe: '5m',
        priceDecimal: '60050',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'sellside',
        timeframe: '1w',
        priceDecimal: '62000',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'buyside',
        timeframe: '1d',
        priceDecimal: '59000',
      ),
    ],
    sessionVolumes: const <BingxFuturesSessionVolumePoint>[
      BingxFuturesSessionVolumePoint(
        session: 'London',
        bucketStartUtc: '2026-04-22T07:00:00Z',
        volumeDecimal: '1200.5',
        deltaDecimal: '30.2',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'Asia',
        bucketStartUtc: '2026-04-22T00:00:00Z',
        volumeDecimal: '950.2',
        deltaDecimal: '-10.4',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'NY',
        bucketStartUtc: '2026-04-22T13:00:00Z',
        volumeDecimal: '800.9',
        deltaDecimal: '5.1',
      ),
    ],
  );
}

BingxFuturesMarketSnapshotInput _inputB() {
  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.10000000',
      qtyStepDecimal: '0.00100000',
      minQtyDecimal: '0.00100000',
      maxLeverageDecimal: '125.00000000',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '60300.00000',
      markPriceDecimal: '60295.50000000',
      indexPriceDecimal: '60298.20000000',
    ),
    candles: _candlesB(),
    trades: const <BingxFuturesTrade>[
      BingxFuturesTrade(
        tradeId: '1',
        timestampUtc: '2026-04-22T07:00:00.000Z',
        side: 'buy',
        priceDecimal: '60299.8000000',
        quantityDecimal: '0.005',
      ),
      BingxFuturesTrade(
        tradeId: '2',
        timestampUtc: '2026-04-22T07:00:02Z',
        side: 'sell',
        priceDecimal: '60300.250000',
        quantityDecimal: '0.0100000',
      ),
    ],
    openInterest: const <BingxFuturesOpenInterestPoint>[
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-22T07:00:00Z',
        openInterestDecimal: '502400',
      ),
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-22T06:55:00Z',
        openInterestDecimal: '502300.500000',
      ),
    ],
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-22T07:00:00.000Z',
      fundingRateDecimal: '-0.00012',
      nextFundingAtUtc: '2026-04-22T11:00:00+03:00',
    ),
    liquidityLevels: const <BingxFuturesLiquidityLevel>[
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'buyside',
        timeframe: '1day',
        priceDecimal: '59000.0',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'sellside',
        timeframe: '1week',
        priceDecimal: '62000.0000',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'buyside',
        timeframe: '5min',
        priceDecimal: '60050.000',
      ),
    ],
    sessionVolumes: const <BingxFuturesSessionVolumePoint>[
      BingxFuturesSessionVolumePoint(
        session: 'asia',
        bucketStartUtc: '2026-04-22T00:00:00Z',
        volumeDecimal: '950.200000',
        deltaDecimal: '-10.400',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'new_york',
        bucketStartUtc: '2026-04-22T13:00:00Z',
        volumeDecimal: '800.900',
        deltaDecimal: '5.1000',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'london',
        bucketStartUtc: '2026-04-22T07:00:00Z',
        volumeDecimal: '1200.5000',
        deltaDecimal: '30.2000',
      ),
    ],
  );
}

BingxFuturesMarketSnapshotInput _inputMissing1w() {
  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.1',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '60300',
      markPriceDecimal: '60295',
      indexPriceDecimal: '60298',
    ),
    candles: _candlesA().where((item) => item.timeframe != '1w').toList(),
    trades: const <BingxFuturesTrade>[
      BingxFuturesTrade(
        tradeId: '1',
        timestampUtc: '2026-04-22T07:00:00Z',
        side: 'buy',
        priceDecimal: '60299.8',
        quantityDecimal: '0.0050',
      ),
    ],
    openInterest: const <BingxFuturesOpenInterestPoint>[
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-22T07:00:00Z',
        openInterestDecimal: '502400.0',
      ),
    ],
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-22T07:00:00Z',
      fundingRateDecimal: '-0.0001',
      nextFundingAtUtc: '2026-04-22T08:00:00Z',
    ),
    liquidityLevels: const <BingxFuturesLiquidityLevel>[
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'buyside',
        timeframe: '1d',
        priceDecimal: '59000',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'sellside',
        timeframe: '5m',
        priceDecimal: '61000',
      ),
    ],
    sessionVolumes: const <BingxFuturesSessionVolumePoint>[
      BingxFuturesSessionVolumePoint(
        session: 'asia',
        bucketStartUtc: '2026-04-22T00:00:00Z',
        volumeDecimal: '100',
        deltaDecimal: '1',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'london',
        bucketStartUtc: '2026-04-22T07:00:00Z',
        volumeDecimal: '200',
        deltaDecimal: '2',
      ),
      BingxFuturesSessionVolumePoint(
        session: 'newyork',
        bucketStartUtc: '2026-04-22T13:00:00Z',
        volumeDecimal: '300',
        deltaDecimal: '3',
      ),
    ],
  );
}

List<BingxFuturesCandle> _candlesA() {
  return const <BingxFuturesCandle>[
    BingxFuturesCandle(
      timeframe: '1w',
      openTimeUtc: '2026-04-14T00:00:00Z',
      closeTimeUtc: '2026-04-21T00:00:00Z',
      openDecimal: '58000',
      highDecimal: '61000',
      lowDecimal: '57000',
      closeDecimal: '60200',
      volumeBaseDecimal: '10000',
      volumeQuoteDecimal: '600000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1m',
      openTimeUtc: '2026-04-22T06:59:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60290',
      highDecimal: '60310',
      lowDecimal: '60280',
      closeDecimal: '60300',
      volumeBaseDecimal: '20',
      volumeQuoteDecimal: '1206000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '5m',
      openTimeUtc: '2026-04-22T06:55:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60200',
      highDecimal: '60320',
      lowDecimal: '60190',
      closeDecimal: '60300',
      volumeBaseDecimal: '120',
      volumeQuoteDecimal: '7230000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '15m',
      openTimeUtc: '2026-04-22T06:45:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60150',
      highDecimal: '60320',
      lowDecimal: '60120',
      closeDecimal: '60300',
      volumeBaseDecimal: '250',
      volumeQuoteDecimal: '15000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1h',
      openTimeUtc: '2026-04-22T06:00:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60000',
      highDecimal: '60350',
      lowDecimal: '59950',
      closeDecimal: '60300',
      volumeBaseDecimal: '900',
      volumeQuoteDecimal: '54000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '4h',
      openTimeUtc: '2026-04-22T04:00:00Z',
      closeTimeUtc: '2026-04-22T08:00:00Z',
      openDecimal: '59800',
      highDecimal: '60400',
      lowDecimal: '59700',
      closeDecimal: '60300',
      volumeBaseDecimal: '2500',
      volumeQuoteDecimal: '150000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1d',
      openTimeUtc: '2026-04-21T00:00:00Z',
      closeTimeUtc: '2026-04-22T00:00:00Z',
      openDecimal: '59000',
      highDecimal: '60500',
      lowDecimal: '58800',
      closeDecimal: '60200',
      volumeBaseDecimal: '12000',
      volumeQuoteDecimal: '710000000',
      isClosed: true,
    ),
  ];
}

List<BingxFuturesCandle> _candlesB() {
  return const <BingxFuturesCandle>[
    BingxFuturesCandle(
      timeframe: '4h',
      openTimeUtc: '2026-04-22T04:00:00+00:00',
      closeTimeUtc: '2026-04-22T08:00:00+00:00',
      openDecimal: '59800.000000',
      highDecimal: '60400.00000',
      lowDecimal: '59700.000',
      closeDecimal: '60300',
      volumeBaseDecimal: '2500.0',
      volumeQuoteDecimal: '150000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1day',
      openTimeUtc: '2026-04-21T03:00:00+03:00',
      closeTimeUtc: '2026-04-22T03:00:00+03:00',
      openDecimal: '59000',
      highDecimal: '60500',
      lowDecimal: '58800',
      closeDecimal: '60200',
      volumeBaseDecimal: '12000',
      volumeQuoteDecimal: '710000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1week',
      openTimeUtc: '2026-04-14T00:00:00.000Z',
      closeTimeUtc: '2026-04-21T00:00:00.000Z',
      openDecimal: '58000',
      highDecimal: '61000',
      lowDecimal: '57000',
      closeDecimal: '60200',
      volumeBaseDecimal: '10000',
      volumeQuoteDecimal: '600000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1h',
      openTimeUtc: '2026-04-22T06:00:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60000',
      highDecimal: '60350',
      lowDecimal: '59950',
      closeDecimal: '60300',
      volumeBaseDecimal: '900',
      volumeQuoteDecimal: '54000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '15m',
      openTimeUtc: '2026-04-22T06:45:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60150',
      highDecimal: '60320',
      lowDecimal: '60120',
      closeDecimal: '60300',
      volumeBaseDecimal: '250',
      volumeQuoteDecimal: '15000000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '1m',
      openTimeUtc: '2026-04-22T06:59:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60290',
      highDecimal: '60310',
      lowDecimal: '60280',
      closeDecimal: '60300',
      volumeBaseDecimal: '20',
      volumeQuoteDecimal: '1206000',
      isClosed: true,
    ),
    BingxFuturesCandle(
      timeframe: '5min',
      openTimeUtc: '2026-04-22T06:55:00Z',
      closeTimeUtc: '2026-04-22T07:00:00Z',
      openDecimal: '60200',
      highDecimal: '60320',
      lowDecimal: '60190',
      closeDecimal: '60300',
      volumeBaseDecimal: '120',
      volumeQuoteDecimal: '7230000',
      isClosed: true,
    ),
  ];
}
