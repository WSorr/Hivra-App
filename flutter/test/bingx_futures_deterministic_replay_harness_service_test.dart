import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';

void main() {
  group('BingxFuturesDeterministicReplayHarnessService', () {
    const service = BingxFuturesDeterministicReplayHarnessService(
      policy: BingxTvhPolicy(
        minAbsTradeDelta: 0.5,
        minAbsSessionNetDelta: 1.0,
        maxAbsFundingRate: 0.01,
        requireWhaleActivation: true,
        requireConsensusSignable: true,
      ),
    );

    final fixtures = <BingxFuturesReplayFixture>[
      _fixtureLong(),
      _fixtureShort(),
      _fixtureNoSignal(),
      _fixtureBlocked(),
    ];

    test('matches expected decision branches', () {
      for (final fixture in fixtures) {
        final run = service.runFixture(fixture);
        expect(run.decision, fixture.expectedDecision,
            reason: 'fixture=${fixture.id}');
        expect(run.topReasonCode, fixture.expectedReasonCode,
            reason: 'fixture=${fixture.id}');
      }
    });

    test('is bit-stable across repeated replay cycles', () {
      final runs = service.runMany(fixtures: fixtures, repeat: 4);
      final byFixture = <String, List<BingxFuturesReplayRunResult>>{};
      for (final run in runs) {
        final history = byFixture.putIfAbsent(
          run.fixtureId,
          () => <BingxFuturesReplayRunResult>[],
        );
        history.add(run);
      }

      for (final fixture in fixtures) {
        final history = byFixture[fixture.id]!;
        final snapshotHashes =
            history.map((item) => item.marketSnapshotHashHex).toSet();
        final featureHashes =
            history.map((item) => item.featureHashHex).toSet();
        final decisionHashes =
            history.map((item) => item.decisionHashHex).toSet();
        expect(snapshotHashes.length, 1,
            reason: 'snapshot drift ${fixture.id}');
        expect(featureHashes.length, 1, reason: 'feature drift ${fixture.id}');
        expect(decisionHashes.length, 1,
            reason: 'decision drift ${fixture.id}');
      }
    });

    test('stays deterministic across input ordering permutations', () {
      for (final fixture in fixtures) {
        final base = service.runFixture(fixture);
        final permuted = service.runFixture(
          BingxFuturesReplayFixture(
            id: fixture.id,
            snapshotInput: _permuteInput(fixture.snapshotInput),
            fundingRateDecimal: fixture.fundingRateDecimal,
            isConsensusSignable: fixture.isConsensusSignable,
            blockingFactCodes: fixture.blockingFactCodes,
            expectedDecision: fixture.expectedDecision,
            expectedReasonCode: fixture.expectedReasonCode,
          ),
        );
        expect(permuted.marketSnapshotHashHex, base.marketSnapshotHashHex,
            reason: 'snapshot permutation drift ${fixture.id}');
        expect(permuted.featureHashHex, base.featureHashHex,
            reason: 'feature permutation drift ${fixture.id}');
        expect(permuted.decisionHashHex, base.decisionHashHex,
            reason: 'decision permutation drift ${fixture.id}');
      }
    });
  });
}

BingxFuturesReplayFixture _fixtureLong() {
  return BingxFuturesReplayFixture(
    id: 'long',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bullish,
      includeBuyWhale: true,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[20.0, 35.0, 10.0],
      openInterestStart: 500000,
      openInterestEnd: 500140,
    ),
    fundingRateDecimal: '0.0008',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.long,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureShort() {
  return BingxFuturesReplayFixture(
    id: 'short',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bearish,
      includeBuyWhale: false,
      includeSellWhale: true,
      sessionDeltaSigns: const <double>[-18.0, -22.0, -9.0],
      openInterestStart: 500140,
      openInterestEnd: 499900,
    ),
    fundingRateDecimal: '-0.0009',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.short,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureNoSignal() {
  return BingxFuturesReplayFixture(
    id: 'no_signal',
    snapshotInput: _buildInput(
      trend: _TrendPattern.neutral,
      includeBuyWhale: false,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[0.1, -0.1, 0.0],
      openInterestStart: 500000,
      openInterestEnd: 500000,
      keepLiquidityFarFromTrades: true,
    ),
    fundingRateDecimal: '0.0001',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.noSignal,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureBlocked() {
  return BingxFuturesReplayFixture(
    id: 'blocked',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bullish,
      includeBuyWhale: true,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[20.0, 35.0, 10.0],
      openInterestStart: 500000,
      openInterestEnd: 500140,
    ),
    fundingRateDecimal: '0.0008',
    isConsensusSignable: false,
    blockingFactCodes: const <String>['pending_remote_break'],
    expectedDecision: BingxTvhDecisionKind.blocked,
    expectedReasonCode: 'consensus_guard',
  );
}

BingxFuturesMarketSnapshotInput _permuteInput(
    BingxFuturesMarketSnapshotInput a) {
  return BingxFuturesMarketSnapshotInput(
    instrument: a.instrument,
    prices: a.prices,
    candles: a.candles.reversed.toList(),
    trades: a.trades.reversed.toList(),
    openInterest: a.openInterest.reversed.toList(),
    funding: a.funding,
    liquidityLevels: a.liquidityLevels.reversed.toList(),
    sessionVolumes: a.sessionVolumes.reversed.toList(),
    orderBookTopLevels: a.orderBookTopLevels.reversed.toList(),
  );
}

enum _TrendPattern {
  bullish,
  bearish,
  neutral,
}

BingxFuturesMarketSnapshotInput _buildInput({
  required _TrendPattern trend,
  required bool includeBuyWhale,
  required bool includeSellWhale,
  required List<double> sessionDeltaSigns,
  required double openInterestStart,
  required double openInterestEnd,
  bool keepLiquidityFarFromTrades = false,
}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandles(trend: trend, count: 220),
    ..._generate5mCandles(count: 80),
    _singleCandle(
      timeframe: '1m',
      openTimeUtc: '2026-04-25T09:59:00Z',
      closeTimeUtc: '2026-04-25T10:00:00Z',
      open: 100.0,
      high: 100.8,
      low: 99.8,
      close: 100.2,
    ),
    _singleCandle(
      timeframe: '1h',
      openTimeUtc: '2026-04-25T09:00:00Z',
      closeTimeUtc: '2026-04-25T10:00:00Z',
      open: 98.0,
      high: 104.0,
      low: 96.0,
      close: 100.0,
    ),
    _singleCandle(
      timeframe: '4h',
      openTimeUtc: '2026-04-25T08:00:00Z',
      closeTimeUtc: '2026-04-25T12:00:00Z',
      open: 97.0,
      high: 105.0,
      low: 95.0,
      close: 100.1,
    ),
    _singleCandle(
      timeframe: '1d',
      openTimeUtc: '2026-04-24T00:00:00Z',
      closeTimeUtc: '2026-04-25T00:00:00Z',
      open: 95.0,
      high: 106.0,
      low: 94.0,
      close: 100.0,
    ),
    _singleCandle(
      timeframe: '1w',
      openTimeUtc: '2026-04-18T00:00:00Z',
      closeTimeUtc: '2026-04-25T00:00:00Z',
      open: 92.0,
      high: 108.0,
      low: 90.0,
      close: 100.0,
    ),
  ];

  final trades = <BingxFuturesTrade>[
    const BingxFuturesTrade(
      tradeId: 't01',
      timestampUtc: '2026-04-25T09:59:20Z',
      side: 'buy',
      priceDecimal: '100.10',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't02',
      timestampUtc: '2026-04-25T09:59:25Z',
      side: 'sell',
      priceDecimal: '100.00',
      quantityDecimal: '0.19',
    ),
    const BingxFuturesTrade(
      tradeId: 't03',
      timestampUtc: '2026-04-25T09:59:30Z',
      side: 'buy',
      priceDecimal: '100.20',
      quantityDecimal: '0.21',
    ),
    const BingxFuturesTrade(
      tradeId: 't04',
      timestampUtc: '2026-04-25T09:59:35Z',
      side: 'sell',
      priceDecimal: '100.15',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't05',
      timestampUtc: '2026-04-25T09:59:40Z',
      side: 'buy',
      priceDecimal: '100.30',
      quantityDecimal: '0.22',
    ),
    if (includeBuyWhale)
      const BingxFuturesTrade(
        tradeId: 't06',
        timestampUtc: '2026-04-25T09:59:50Z',
        side: 'buy',
        priceDecimal: '106.02',
        quantityDecimal: '8.00',
      ),
    if (includeSellWhale)
      const BingxFuturesTrade(
        tradeId: 't07',
        timestampUtc: '2026-04-25T09:59:55Z',
        side: 'sell',
        priceDecimal: '93.98',
        quantityDecimal: '8.00',
      ),
  ];

  final liquidityLevels = <BingxFuturesLiquidityLevel>[
    BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'sellside',
      timeframe: '1h',
      priceDecimal: keepLiquidityFarFromTrades ? '120.00' : '106.00',
    ),
    BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'buyside',
      timeframe: '1h',
      priceDecimal: keepLiquidityFarFromTrades ? '80.00' : '94.00',
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

  final sessions = <BingxFuturesSessionVolumePoint>[
    BingxFuturesSessionVolumePoint(
      session: 'asia',
      bucketStartUtc: '2026-04-25T00:00:00Z',
      volumeDecimal: '1100.0',
      deltaDecimal: sessionDeltaSigns[0].toStringAsFixed(4),
    ),
    BingxFuturesSessionVolumePoint(
      session: 'london',
      bucketStartUtc: '2026-04-25T07:00:00Z',
      volumeDecimal: '1800.0',
      deltaDecimal: sessionDeltaSigns[1].toStringAsFixed(4),
    ),
    BingxFuturesSessionVolumePoint(
      session: 'newyork',
      bucketStartUtc: '2026-04-25T13:00:00Z',
      volumeDecimal: '1500.0',
      deltaDecimal: sessionDeltaSigns[2].toStringAsFixed(4),
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
      lastTradePriceDecimal: '100.20',
      markPriceDecimal: '100.15',
      indexPriceDecimal: '100.10',
    ),
    candles: candles,
    trades: trades,
    openInterest: <BingxFuturesOpenInterestPoint>[
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-25T09:45:00Z',
        openInterestDecimal: openInterestStart.toStringAsFixed(4),
      ),
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-25T10:00:00Z',
        openInterestDecimal: openInterestEnd.toStringAsFixed(4),
      ),
    ],
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-25T10:00:00Z',
      fundingRateDecimal: '0.0001',
      nextFundingAtUtc: '2026-04-25T12:00:00Z',
    ),
    liquidityLevels: liquidityLevels,
    sessionVolumes: sessions,
    orderBookTopLevels: const <BingxFuturesOrderBookLevel>[
      BingxFuturesOrderBookLevel(
        side: 'bid',
        priceDecimal: '100.10',
        quantityDecimal: '9.0',
      ),
      BingxFuturesOrderBookLevel(
        side: 'ask',
        priceDecimal: '100.20',
        quantityDecimal: '9.5',
      ),
    ],
  );
}

List<BingxFuturesCandle> _generate15mCandles({
  required _TrendPattern trend,
  required int count,
}) {
  final result = <BingxFuturesCandle>[];
  var close = 100.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close = switch (trend) {
      _TrendPattern.bullish => close + 0.05,
      _TrendPattern.bearish => close - 0.05,
      _TrendPattern.neutral => 100.0,
    };
    final high = (open > close ? open : close) + 0.2;
    final low = (open < close ? open : close) - 0.2;
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
    final drift = (i % 6) * 0.02;
    final spike = i % 16 == 5
        ? 0.8
        : i % 16 == 11
            ? -0.8
            : 0.0;
    close = 100.0 + drift + spike;
    final high = (open > close ? open : close) + 0.6;
    final low = (open < close ? open : close) - 0.6;
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
        volumeBaseDecimal: '100.0',
        volumeQuoteDecimal: '10000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

BingxFuturesCandle _singleCandle({
  required String timeframe,
  required String openTimeUtc,
  required String closeTimeUtc,
  required double open,
  required double high,
  required double low,
  required double close,
}) {
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
