import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/services/bingx_futures_feature_extractor_service.dart';
import 'package:hivra_app/services/bingx_futures_market_snapshot_service.dart';

void main() {
  group('BingxFuturesFeatureExtractorService', () {
    const snapshotService = BingxFuturesMarketSnapshotService();
    const featureService = BingxFuturesFeatureExtractorService();

    test('extracts deterministic features for permuted snapshot payloads', () {
      final digestA = snapshotService.build(_buildInput(permuted: false));
      final digestB = snapshotService.build(_buildInput(permuted: true));

      final featuresA = featureService.extract(digestA);
      final featuresB = featureService.extract(digestB);

      expect(featuresA.featureHashHex, featuresB.featureHashHex);
      expect(featuresA.canonicalJson, featuresB.canonicalJson);
      expect(featuresA.trendDirection, BingxTrendDirection.bullish);
      expect(featuresA.liquidityLevels, isNotEmpty);
      expect(featuresA.hasBuyWhaleActivation, isTrue);
      expect(featuresA.hasSellWhaleActivation, isFalse);
    });

    test('later volatility cannot resize already formed clusters', () {
      final prefix = _generate5mCandles(count: 80);
      final before = featureService.extract(
        snapshotService.build(
          _buildInput(permuted: false, microCandles: prefix),
        ),
      );
      final after = featureService.extract(
        snapshotService.build(
          _buildInput(
            permuted: false,
            microCandles: [
              ...prefix,
              _singleCandle(
                '5m',
                '2026-04-25T09:55:00Z',
                '2026-04-25T10:00:00Z',
                102,
                500,
                1,
                102,
              ),
            ],
          ),
        ),
      );
      List<Object> geometry(BingxFuturesFeatureExtractionResult result) =>
          result.liquidityLevels
              .map(
                (level) => [
                  level.side,
                  level.anchorIndex,
                  level.centerPriceDecimal,
                  level.zoneTopDecimal,
                  level.zoneBottomDecimal,
                  level.pivotCount,
                ],
              )
              .toList();
      expect(before.liquidityLevels, isNotEmpty);
      expect(geometry(after), geometry(before));
    });

    test('later pivot cannot rewrite a breached cluster', () {
      final candles = List<BingxFuturesCandle>.generate(46, (index) {
        final start = DateTime.utc(2026, 4, 25, 6).add(Duration(minutes: index * 5));
        final high = [8, 16, 24].contains(index) ? 101.0 :
            index == 35 ? 110.0 : index == 44 ? 102.0 : 99.0;
        return _singleCandle('5m', start.toIso8601String(),
            start.add(const Duration(minutes: 5)).toIso8601String(),
            97, high, 95, 97);
      });
      BingxDetectedLiquidityLevel cluster(int count) => featureService.extract(
        snapshotService.build(_buildInput(permuted: false,
          microCandles: candles.take(count).toList())),
      ).liquidityLevels.singleWhere((level) => level.side == 'buyside' && level.anchorIndex == 8);
      final before = cluster(36);
      final after = cluster(46);
      expect(before.breached, isTrue);
      expect(after.breachedIndex, before.breachedIndex);
      expect(after.centerPriceDecimal, before.centerPriceDecimal);
      expect(after.zoneTopDecimal, before.zoneTopDecimal);
      expect(after.zoneBottomDecimal, before.zoneBottomDecimal);
      expect(after.pivotCount, before.pivotCount);
    });

    test('uses notional imbalance independent of base-asset units', () {
      final btcLike = featureService.extract(
        snapshotService.build(_buildInput(permuted: false)),
      );
      final lowPriceAsset = featureService.extract(
        snapshotService.build(
          _buildInput(
            permuted: false,
            tradePriceScale: 0.01,
            tradeQuantityScale: 100,
            sessionScale: 100,
          ),
        ),
      );

      expect(
        lowPriceAsset.tradeImbalanceRatioDecimal,
        btcLike.tradeImbalanceRatioDecimal,
      );
      expect(
        lowPriceAsset.sessionImbalanceRatioDecimal,
        btcLike.sessionImbalanceRatioDecimal,
      );
      expect(lowPriceAsset.tradeDeltaDecimal, isNot(btcLike.tradeDeltaDecimal));
      expect(
        lowPriceAsset.sessionNetDeltaDecimal,
        isNot(btcLike.sessionNetDeltaDecimal),
      );
    });

    test('marks recent-trade session evidence incomplete', () {
      final features = featureService.extract(
        snapshotService.build(
          _buildInput(permuted: false, sessionCoverageComplete: false),
        ),
      );

      expect(features.sessionEvidenceComplete, isFalse);
    });

    test('fails when 15m candles are insufficient for ema200', () {
      final digest = snapshotService.build(_buildInput(
        permuted: false,
        fifteenMinuteCount: 80,
      ));

      expect(
        () => featureService.extract(digest),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('need at least 200 closed candles on 15m'),
          ),
        ),
      );
    });
  });
}

BingxFuturesMarketSnapshotInput _buildInput({
  required bool permuted,
  int fifteenMinuteCount = 220,
  double tradePriceScale = 1,
  double tradeQuantityScale = 1,
  double sessionScale = 1,
  bool sessionCoverageComplete = true,
  List<BingxFuturesCandle>? microCandles,
}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandles(count: fifteenMinuteCount),
    ...microCandles ?? _generate5mCandles(count: 80),
    _singleCandle('1m', '2026-04-25T09:59:00Z', '2026-04-25T10:00:00Z', 102,
        103, 101, 102.2),
    _singleCandle(
        '1h', '2026-04-25T09:00:00Z', '2026-04-25T10:00:00Z', 99, 104, 98, 102),
    _singleCandle('4h', '2026-04-25T08:00:00Z', '2026-04-25T12:00:00Z', 97, 105,
        96, 102.5),
    _singleCandle('1d', '2026-04-24T00:00:00Z', '2026-04-25T00:00:00Z', 95, 106,
        94, 101.8),
    _singleCandle('1w', '2026-04-18T00:00:00Z', '2026-04-25T00:00:00Z', 92, 108,
        90, 101.8),
  ];
  final trades = <BingxFuturesTrade>[
    const BingxFuturesTrade(
      tradeId: 't01',
      timestampUtc: '2026-04-25T09:59:20Z',
      side: 'buy',
      priceDecimal: '102.10',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't02',
      timestampUtc: '2026-04-25T09:59:25Z',
      side: 'sell',
      priceDecimal: '102.00',
      quantityDecimal: '0.18',
    ),
    const BingxFuturesTrade(
      tradeId: 't03',
      timestampUtc: '2026-04-25T09:59:30Z',
      side: 'buy',
      priceDecimal: '102.20',
      quantityDecimal: '0.21',
    ),
    const BingxFuturesTrade(
      tradeId: 't04',
      timestampUtc: '2026-04-25T09:59:35Z',
      side: 'sell',
      priceDecimal: '102.15',
      quantityDecimal: '0.19',
    ),
    const BingxFuturesTrade(
      tradeId: 't05',
      timestampUtc: '2026-04-25T09:59:40Z',
      side: 'buy',
      priceDecimal: '102.30',
      quantityDecimal: '0.22',
    ),
    const BingxFuturesTrade(
      tradeId: 't06',
      timestampUtc: '2026-04-25T09:59:45Z',
      side: 'buy',
      priceDecimal: '102.40',
      quantityDecimal: '0.24',
    ),
    const BingxFuturesTrade(
      tradeId: 't07',
      timestampUtc: '2026-04-25T09:59:50Z',
      side: 'sell',
      priceDecimal: '102.35',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't08',
      timestampUtc: '2026-04-25T09:59:55Z',
      side: 'buy',
      priceDecimal: '102.50',
      quantityDecimal: '0.26',
    ),
    const BingxFuturesTrade(
      tradeId: 't09',
      timestampUtc: '2026-04-25T10:00:00Z',
      side: 'sell',
      priceDecimal: '102.45',
      quantityDecimal: '0.23',
    ),
    const BingxFuturesTrade(
      tradeId: 't10',
      timestampUtc: '2026-04-25T10:00:05Z',
      side: 'buy',
      priceDecimal: '106.04',
      quantityDecimal: '8.00',
    ),
  ];

  final liquidityLevels = <BingxFuturesLiquidityLevel>[
    const BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'sellside',
      timeframe: '1h',
      priceDecimal: '106.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'buyside',
      timeframe: '1h',
      priceDecimal: '94.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'sellside',
      timeframe: '5m',
      priceDecimal: '104.20',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'buyside',
      timeframe: '5m',
      priceDecimal: '98.40',
    ),
  ];

  final sessionVolumes = <BingxFuturesSessionVolumePoint>[
    BingxFuturesSessionVolumePoint(
      session: 'asia',
      bucketStartUtc: '2026-04-25T00:00:00Z',
      volumeDecimal: (1100 * sessionScale).toString(),
      deltaDecimal: (45 * sessionScale).toString(),
      coverageComplete: sessionCoverageComplete,
    ),
    BingxFuturesSessionVolumePoint(
      session: 'london',
      bucketStartUtc: '2026-04-25T07:00:00Z',
      volumeDecimal: (1800 * sessionScale).toString(),
      deltaDecimal: (85 * sessionScale).toString(),
      coverageComplete: sessionCoverageComplete,
    ),
    BingxFuturesSessionVolumePoint(
      session: 'newyork',
      bucketStartUtc: '2026-04-25T13:00:00Z',
      volumeDecimal: (1500 * sessionScale).toString(),
      deltaDecimal: (20 * sessionScale).toString(),
      coverageComplete: sessionCoverageComplete,
    ),
  ];

  final openInterest = <BingxFuturesOpenInterestPoint>[
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T09:45:00Z',
      openInterestDecimal: '500000.0',
    ),
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T09:50:00Z',
      openInterestDecimal: '500050.0',
    ),
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T09:55:00Z',
      openInterestDecimal: '500110.0',
    ),
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T10:00:00Z',
      openInterestDecimal: '500190.0',
    ),
  ];

  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.10',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '102.50',
      markPriceDecimal: '102.45',
      indexPriceDecimal: '102.40',
    ),
    candles: permuted ? candles.reversed.toList() : candles,
    trades: (permuted ? trades.reversed : trades)
        .map(
          (trade) => BingxFuturesTrade(
            tradeId: trade.tradeId,
            timestampUtc: trade.timestampUtc,
            side: trade.side,
            priceDecimal:
                (double.parse(trade.priceDecimal) * tradePriceScale).toString(),
            quantityDecimal:
                (double.parse(trade.quantityDecimal) * tradeQuantityScale)
                    .toString(),
          ),
        )
        .toList(),
    openInterest: permuted ? openInterest.reversed.toList() : openInterest,
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-25T10:00:00Z',
      fundingRateDecimal: '0.0001200',
      nextFundingAtUtc: '2026-04-25T12:00:00Z',
    ),
    liquidityLevels:
        permuted ? liquidityLevels.reversed.toList() : liquidityLevels,
    sessionVolumes:
        permuted ? sessionVolumes.reversed.toList() : sessionVolumes,
    orderBookTopLevels: const <BingxFuturesOrderBookLevel>[
      BingxFuturesOrderBookLevel(
        side: 'bid',
        priceDecimal: '102.40',
        quantityDecimal: '10',
      ),
      BingxFuturesOrderBookLevel(
        side: 'ask',
        priceDecimal: '102.50',
        quantityDecimal: '11',
      ),
    ],
  );
}

List<BingxFuturesCandle> _generate15mCandles({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 90.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close = close + 0.08;
    final high = close + 0.2;
    final low = open - 0.2;
    final openTime = DateTime.utc(2026, 4, 23).add(Duration(minutes: 15 * i));
    final closeTime = openTime.add(const Duration(minutes: 15));
    result.add(
      BingxFuturesCandle(
        timeframe: '15m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: high.toStringAsFixed(4),
        lowDecimal: low.toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '10.0',
        volumeQuoteDecimal: '1000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate5mCandles({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 100.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    var spike = 0.0;
    if (i % 8 == 2) spike = 4.5;
    if (i % 8 == 6) spike = -4.5;
    close = 100.0 + (i * 0.03) + spike;
    final high = (open > close ? open : close) + 1.2;
    final low = (open < close ? open : close) - 1.2;
    final openTime = DateTime.utc(2026, 4, 25, 3).add(Duration(minutes: 5 * i));
    final closeTime = openTime.add(const Duration(minutes: 5));
    result.add(
      BingxFuturesCandle(
        timeframe: '5m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: high.toStringAsFixed(4),
        lowDecimal: low.toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: (120 + (i % 5) * 10).toStringAsFixed(2),
        volumeQuoteDecimal: (12000 + (i % 5) * 800).toStringAsFixed(2),
        isClosed: true,
      ),
    );
  }
  return result;
}

BingxFuturesCandle _singleCandle(
  String timeframe,
  String openTimeUtc,
  String closeTimeUtc,
  double open,
  double high,
  double low,
  double close,
) {
  return BingxFuturesCandle(
    timeframe: timeframe,
    openTimeUtc: openTimeUtc,
    closeTimeUtc: closeTimeUtc,
    openDecimal: open.toStringAsFixed(4),
    highDecimal: high.toStringAsFixed(4),
    lowDecimal: low.toStringAsFixed(4),
    closeDecimal: close.toStringAsFixed(4),
    volumeBaseDecimal: '100.0',
    volumeQuoteDecimal: '10000.0',
    isClosed: true,
  );
}
