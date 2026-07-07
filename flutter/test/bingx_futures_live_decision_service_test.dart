import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_feature_extractor_service.dart';
import 'package:hivra_app/services/bingx_futures_live_decision_service.dart';
import 'package:hivra_app/services/bingx_futures_market_snapshot_service.dart';
import 'package:hivra_app/services/bingx_futures_tvh_rule_engine_service.dart';
import 'package:hivra_app/services/bingx_futures_zone_decision_service.dart';

void main() {
  group('BingxFuturesLiveDecisionService', () {
    const service = BingxFuturesLiveDecisionService();

    test('prepares deterministic live long decision from TVH pipeline', () {
      final input = BingxFuturesLiveDecisionInput(
        snapshotInput: _buildInput(permuted: false),
        isConsensusSignable: true,
      );

      final first = service.decide(input);
      final second = service.decide(input);

      expect(first.canPrepareIntent, isTrue);
      expect(first.decision, BingxTvhDecisionKind.long);
      expect(first.side, 'buy');
      expect(first.zoneSide, 'buyside');
      expect(first.zoneLowDecimal, isNotNull);
      expect(first.zoneHighDecimal, isNotNull);
      expect(first.liveDecisionHashHex, second.liveDecisionHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('stays stable when snapshot input ordering changes', () {
      final base = service.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildInput(permuted: false),
          isConsensusSignable: true,
        ),
      );
      final permuted = service.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildInput(permuted: true),
          isConsensusSignable: true,
        ),
      );

      expect(permuted.marketSnapshotHashHex, base.marketSnapshotHashHex);
      expect(permuted.featureHashHex, base.featureHashHex);
      expect(permuted.tvhDecisionHashHex, base.tvhDecisionHashHex);
      expect(permuted.liveDecisionHashHex, base.liveDecisionHashHex);
    });

    test('blocks live entry when consensus guard blocks TVH decision', () {
      final result = service.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildInput(permuted: false),
          isConsensusSignable: false,
          blockingFactCodes: const <String>['pending_remote_break'],
          policy: const BingxTvhPolicy(
            requireConsensusSignable: true,
          ),
        ),
      );

      expect(result.canPrepareIntent, isFalse);
      expect(result.decision, BingxTvhDecisionKind.blocked);
      expect(result.side, isNull);
      expect(result.zoneLowDecimal, isNull);
      expect(result.reasons.first.code, 'consensus_guard');
    });

    test('produces deterministic live short decision from TVH pipeline', () {
      final input = BingxFuturesLiveDecisionInput(
        snapshotInput: _buildShortInput(permuted: false),
        isConsensusSignable: true,
        policy: const BingxTvhPolicy(
          requireWhaleActivation: false,
        ),
      );

      final first = service.decide(input);
      final second = service.decide(input);

      expect(first.decision, BingxTvhDecisionKind.short);
      expect(first.side, 'sell');
      expect(first.canPrepareIntent, isTrue);
      expect(first.zoneSide, 'sellside');
      expect(first.zoneLowDecimal, isNotNull);
      expect(first.zoneHighDecimal, isNotNull);
      expect(first.liveDecisionHashHex, second.liveDecisionHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('returns deterministic NO_SIGNAL when funding guard blocks', () {
      final result = service.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildInput(permuted: false),
          isConsensusSignable: true,
          policy: const BingxTvhPolicy(
            maxAbsFundingRate: 0.00001,
          ),
        ),
      );

      expect(result.decision, BingxTvhDecisionKind.noSignal);
      expect(result.canPrepareIntent, isFalse);
      expect(result.side, isNull);
      expect(result.zoneSide, isNull);
      expect(result.reasons.any((r) => r.code == 'funding_guard'), isTrue);
      expect(
        result.reasons
            .where((r) => r.code == 'funding_guard')
            .every((r) => r.passed == false),
        isTrue,
      );
    });

    test('NO_SIGNAL can evaluate a side-locked structural zone without intent',
        () {
      final input = BingxFuturesLiveDecisionInput(
        snapshotInput: _buildInput(permuted: false),
        isConsensusSignable: true,
        zoneEvaluationSide: 'buy',
        policy: const BingxTvhPolicy(
          maxAbsFundingRate: 0.00001,
        ),
      );

      final first = service.decide(input);
      final second = service.decide(input);

      expect(first.decision, BingxTvhDecisionKind.noSignal);
      expect(first.canPrepareIntent, isFalse);
      expect(first.side, isNull);
      expect(first.zoneEvaluationSide, 'buy');
      expect(first.zoneSide, 'buyside');
      expect(first.zoneLowDecimal, isNotNull);
      expect(first.zoneHighDecimal, isNotNull);
      expect(first.liveDecisionHashHex, second.liveDecisionHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('blocks far retest short in strong bearish continuation trend gate',
        () {
      final gatedService = BingxFuturesLiveDecisionService(
        snapshotService: _StubSnapshotService(),
        featureExtractor: _StubFeatureExtractor(
          trendDirection: BingxTrendDirection.bearish,
        ),
        ruleEngine: _StubRuleEngine(
          decision: BingxTvhDecisionKind.short,
        ),
        zoneDecision: _StubZoneDecision(
          side: 'sell',
          zoneSide: 'sellside',
          trend4h: 'bear',
          trend1d: 'bear',
          needsFartherRetest: true,
          targetRetestPct: 0.09,
        ),
      );

      final result = gatedService.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildMinimalInput(),
          isConsensusSignable: true,
        ),
      );

      expect(result.decision, BingxTvhDecisionKind.short);
      expect(result.side, 'sell');
      expect(result.trendGateBlocked, isTrue);
      expect(result.trendGateCode, 'trend_gate_short_far_retest');
      expect(result.canPrepareIntent, isFalse);
      expect(
        result.reasons.any(
          (reason) => reason.code == 'trend_gate_short_far_retest',
        ),
        isTrue,
      );
    });

    test('blocks missed short retest after bearish momentum continuation', () {
      final gatedService = BingxFuturesLiveDecisionService(
        snapshotService: _StubSnapshotService(),
        featureExtractor: _StubFeatureExtractor(
          trendDirection: BingxTrendDirection.bearish,
        ),
        ruleEngine: _StubRuleEngine(
          decision: BingxTvhDecisionKind.short,
        ),
        zoneDecision: _StubZoneDecision(
          side: 'sell',
          zoneSide: 'sellside',
          trend4h: 'bear',
          trend1d: 'bear',
          needsFartherRetest: false,
          targetRetestPct: 0.03,
          zoneLow: 104,
          zoneHigh: 105,
          recentHigh: 100,
          recentLow: 98,
          sweepUp: false,
        ),
      );

      final result = gatedService.decide(
        BingxFuturesLiveDecisionInput(
          snapshotInput: _buildMinimalInput(),
          isConsensusSignable: true,
        ),
      );

      expect(result.decision, BingxTvhDecisionKind.short);
      expect(result.side, 'sell');
      expect(result.trendGateBlocked, isTrue);
      expect(result.trendGateCode, 'momentum_gate_short_missed_retest');
      expect(result.canPrepareIntent, isFalse);
      expect(
        result.reasons.any(
          (reason) => reason.code == 'momentum_gate_short_missed_retest',
        ),
        isTrue,
      );
    });
  });
}

BingxFuturesMarketSnapshotInput _buildMinimalInput() {
  return const BingxFuturesMarketSnapshotInput(
    instrument: BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.10',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    ),
    prices: BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '100.0',
      markPriceDecimal: '100.0',
      indexPriceDecimal: '100.0',
    ),
    candles: <BingxFuturesCandle>[],
    trades: <BingxFuturesTrade>[],
    openInterest: <BingxFuturesOpenInterestPoint>[],
    funding: BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-25T10:00:00Z',
      fundingRateDecimal: '0.0001',
      nextFundingAtUtc: '2026-04-25T12:00:00Z',
    ),
    liquidityLevels: <BingxFuturesLiquidityLevel>[
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'sellside',
        timeframe: '1h',
        priceDecimal: '101.0',
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'buyside',
        timeframe: '5m',
        priceDecimal: '99.0',
      ),
    ],
    sessionVolumes: <BingxFuturesSessionVolumePoint>[],
    orderBookTopLevels: <BingxFuturesOrderBookLevel>[],
  );
}

BingxFuturesMarketSnapshotInput _buildInput({required bool permuted}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandles(count: 220),
    ..._generate5mCandles(count: 80),
    ..._generate1hCandles(count: 24),
    ..._generate4hCandlesWithFreshLow(),
    _singleCandle('1m', '2026-04-25T09:59:00Z', '2026-04-25T10:00:00Z', 102,
        103, 101, 102.2),
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
      timestampUtc: '2026-04-25T10:00:05Z',
      side: 'buy',
      priceDecimal: '106.04',
      quantityDecimal: '8.00',
    ),
  ];
  final openInterest = <BingxFuturesOpenInterestPoint>[
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T09:45:00Z',
      openInterestDecimal: '500000.0',
    ),
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T10:00:00Z',
      openInterestDecimal: '500190.0',
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
      kind: 'liquidation',
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
    const BingxFuturesSessionVolumePoint(
      session: 'asia',
      bucketStartUtc: '2026-04-25T00:00:00Z',
      volumeDecimal: '1100.0',
      deltaDecimal: '45.0',
    ),
    const BingxFuturesSessionVolumePoint(
      session: 'london',
      bucketStartUtc: '2026-04-25T07:00:00Z',
      volumeDecimal: '1800.0',
      deltaDecimal: '85.0',
    ),
    const BingxFuturesSessionVolumePoint(
      session: 'newyork',
      bucketStartUtc: '2026-04-25T13:00:00Z',
      volumeDecimal: '1500.0',
      deltaDecimal: '20.0',
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
    trades: permuted ? trades.reversed.toList() : trades,
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

BingxFuturesMarketSnapshotInput _buildShortInput({required bool permuted}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandlesBearish(count: 220),
    ..._generate5mCandlesBearish(count: 80),
    ..._generate1hCandlesBearish(count: 24),
    ..._generate4hCandlesWithFreshHigh(),
    _singleCandle('1m', '2026-04-25T09:59:00Z', '2026-04-25T10:00:00Z', 97,
        97.2, 95.8, 96.0),
    _singleCandle('1d', '2026-04-24T00:00:00Z', '2026-04-25T00:00:00Z', 106,
        107, 93.8, 96.1),
    _singleCandle('1w', '2026-04-18T00:00:00Z', '2026-04-25T00:00:00Z', 110,
        111, 92.5, 95.9),
  ];
  final trades = <BingxFuturesTrade>[
    const BingxFuturesTrade(
      tradeId: 't01',
      timestampUtc: '2026-04-25T09:59:20Z',
      side: 'sell',
      priceDecimal: '96.30',
      quantityDecimal: '0.40',
    ),
    const BingxFuturesTrade(
      tradeId: 't02',
      timestampUtc: '2026-04-25T09:59:25Z',
      side: 'sell',
      priceDecimal: '96.10',
      quantityDecimal: '0.38',
    ),
    const BingxFuturesTrade(
      tradeId: 't03',
      timestampUtc: '2026-04-25T09:59:30Z',
      side: 'buy',
      priceDecimal: '96.05',
      quantityDecimal: '0.08',
    ),
    const BingxFuturesTrade(
      tradeId: 't04',
      timestampUtc: '2026-04-25T09:59:35Z',
      side: 'sell',
      priceDecimal: '95.95',
      quantityDecimal: '0.34',
    ),
  ];
  final openInterest = <BingxFuturesOpenInterestPoint>[
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T09:45:00Z',
      openInterestDecimal: '500000.0',
    ),
    const BingxFuturesOpenInterestPoint(
      timestampUtc: '2026-04-25T10:00:00Z',
      openInterestDecimal: '500220.0',
    ),
  ];
  final liquidityLevels = <BingxFuturesLiquidityLevel>[
    const BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'sellside',
      timeframe: '1h',
      priceDecimal: '102.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'liquidation',
      side: 'sellside',
      timeframe: '1h',
      priceDecimal: '102.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'buyside',
      timeframe: '1h',
      priceDecimal: '92.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'sellside',
      timeframe: '5m',
      priceDecimal: '99.20',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'buyside',
      timeframe: '5m',
      priceDecimal: '94.20',
    ),
  ];
  final sessionVolumes = <BingxFuturesSessionVolumePoint>[
    const BingxFuturesSessionVolumePoint(
      session: 'asia',
      bucketStartUtc: '2026-04-25T00:00:00Z',
      volumeDecimal: '1200.0',
      deltaDecimal: '-30.0',
    ),
    const BingxFuturesSessionVolumePoint(
      session: 'london',
      bucketStartUtc: '2026-04-25T07:00:00Z',
      volumeDecimal: '1900.0',
      deltaDecimal: '-80.0',
    ),
    const BingxFuturesSessionVolumePoint(
      session: 'newyork',
      bucketStartUtc: '2026-04-25T13:00:00Z',
      volumeDecimal: '1500.0',
      deltaDecimal: '-25.0',
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
      lastTradePriceDecimal: '96.00',
      markPriceDecimal: '95.95',
      indexPriceDecimal: '95.90',
    ),
    candles: permuted ? candles.reversed.toList() : candles,
    trades: permuted ? trades.reversed.toList() : trades,
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
        priceDecimal: '95.90',
        quantityDecimal: '12',
      ),
      BingxFuturesOrderBookLevel(
        side: 'ask',
        priceDecimal: '96.00',
        quantityDecimal: '14',
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
    final openTime = DateTime.utc(2026, 4, 23).add(Duration(minutes: 15 * i));
    final closeTime = openTime.add(const Duration(minutes: 15));
    result.add(
      BingxFuturesCandle(
        timeframe: '15m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: (close + 0.2).toStringAsFixed(4),
        lowDecimal: (open - 0.2).toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '10.0',
        volumeQuoteDecimal: '1000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate15mCandlesBearish({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 118.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close = close - 0.08;
    final openTime = DateTime.utc(2026, 4, 23).add(Duration(minutes: 15 * i));
    final closeTime = openTime.add(const Duration(minutes: 15));
    result.add(
      BingxFuturesCandle(
        timeframe: '15m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: (open + 0.2).toStringAsFixed(4),
        lowDecimal: (close - 0.2).toStringAsFixed(4),
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
    final spike = i % 8 == 2 ? 4.5 : 0.0;
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
        volumeBaseDecimal: '120.0',
        volumeQuoteDecimal: '12000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate5mCandlesBearish({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 100.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    final spike = i % 8 == 2 ? -4.5 : 0.0;
    close = 100.0 - (i * 0.03) + spike;
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
        volumeBaseDecimal: '10.0',
        volumeQuoteDecimal: '1000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate1hCandles({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 98.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close += 0.16;
    final openTime = DateTime.utc(2026, 4, 24, 10).add(Duration(hours: i));
    final closeTime = openTime.add(const Duration(hours: 1));
    result.add(
      BingxFuturesCandle(
        timeframe: '1h',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: (close + 0.7).toStringAsFixed(4),
        lowDecimal: (open - 0.7).toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '500.0',
        volumeQuoteDecimal: '50000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate1hCandlesBearish({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 102.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close -= 0.16;
    final openTime = DateTime.utc(2026, 4, 24, 10).add(Duration(hours: i));
    final closeTime = openTime.add(const Duration(hours: 1));
    result.add(
      BingxFuturesCandle(
        timeframe: '1h',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: (open + 0.7).toStringAsFixed(4),
        lowDecimal: (close - 0.7).toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '500.0',
        volumeQuoteDecimal: '50000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate4hCandlesWithFreshLow() {
  const highs = <double>[101, 102, 100, 103, 104, 105, 106];
  const lows = <double>[99, 98, 94, 98, 99, 100, 101];
  const closes = <double>[100, 99, 98, 100, 101, 102, 103];
  return _generateFixedCandles(
    timeframe: '4h',
    interval: const Duration(hours: 4),
    highs: highs,
    lows: lows,
    closes: closes,
  );
}

List<BingxFuturesCandle> _generate4hCandlesWithFreshHigh() {
  const highs = <double>[99, 100, 104, 100, 99, 98, 97];
  const lows = <double>[97, 98, 99, 96, 95, 94, 93];
  const closes = <double>[98, 99, 101, 98, 97, 96, 95];
  return _generateFixedCandles(
    timeframe: '4h',
    interval: const Duration(hours: 4),
    highs: highs,
    lows: lows,
    closes: closes,
  );
}

List<BingxFuturesCandle> _generateFixedCandles({
  required String timeframe,
  required Duration interval,
  required List<double> highs,
  required List<double> lows,
  required List<double> closes,
}) {
  final result = <BingxFuturesCandle>[];
  final start = DateTime.utc(2026, 4, 24, 8);
  for (var i = 0; i < closes.length; i++) {
    final openTime = start.add(Duration(seconds: interval.inSeconds * i));
    result.add(
      BingxFuturesCandle(
        timeframe: timeframe,
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: openTime.add(interval).toIso8601String(),
        openDecimal: closes[i].toStringAsFixed(4),
        highDecimal: highs[i].toStringAsFixed(4),
        lowDecimal: lows[i].toStringAsFixed(4),
        closeDecimal: closes[i].toStringAsFixed(4),
        volumeBaseDecimal: '800.0',
        volumeQuoteDecimal: '80000.0',
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

class _StubSnapshotService extends BingxFuturesMarketSnapshotService {
  @override
  BingxFuturesMarketSnapshotDigest build(
      BingxFuturesMarketSnapshotInput input) {
    return const BingxFuturesMarketSnapshotDigest(
      normalizedSnapshot: <String, dynamic>{
        'schema_version': 1,
      },
      canonicalJson: '{"schema_version":1}',
      marketSnapshotHashHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      liquidationFeedAvailable: true,
    );
  }
}

class _StubFeatureExtractor extends BingxFuturesFeatureExtractorService {
  final BingxTrendDirection trendDirection;

  const _StubFeatureExtractor({
    required this.trendDirection,
  });

  @override
  BingxFuturesFeatureExtractionResult extract(
    BingxFuturesMarketSnapshotDigest snapshot,
  ) {
    return BingxFuturesFeatureExtractionResult(
      ruleSet: 'tvh_v1',
      marketSnapshotHashHex: snapshot.marketSnapshotHashHex,
      canonicalJson: '{"feature":"stub"}',
      featureHashHex:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      trendDirection: trendDirection,
      ema50m15Decimal: '100',
      ema200m15Decimal: '99',
      atr14m5Decimal: '1',
      tradeDeltaDecimal: '-0.1',
      openInterestDeltaDecimal: '0.01',
      sessionNetDeltaDecimal: '-0.1',
      liquidityLevels: const <BingxDetectedLiquidityLevel>[],
      whaleActivations: const <BingxWhaleActivationEvent>[],
      hasBuyWhaleActivation: false,
      hasSellWhaleActivation: true,
    );
  }
}

class _StubRuleEngine extends BingxFuturesTvhRuleEngineService {
  final BingxTvhDecisionKind decision;

  const _StubRuleEngine({
    required this.decision,
  });

  @override
  BingxTvhDecisionResult evaluate({
    required BingxFuturesFeatureExtractionResult features,
    required String fundingRateDecimal,
    required bool isConsensusSignable,
    List<String> blockingFactCodes = const <String>[],
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  }) {
    return BingxTvhDecisionResult(
      ruleSet: 'tvh_v1',
      featureHashHex: features.featureHashHex,
      decision: decision,
      reasons: const <BingxTvhDecisionReason>[
        BingxTvhDecisionReason(
          code: 'stub_rule',
          passed: true,
          detail: 'stub',
        ),
      ],
      canonicalJson: '{"decision":"stub"}',
      decisionHashHex:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    );
  }
}

class _StubZoneDecision extends BingxFuturesZoneDecisionService {
  final String side;
  final String zoneSide;
  final String trend4h;
  final String trend1d;
  final bool needsFartherRetest;
  final num targetRetestPct;
  final num zoneLow;
  final num zoneHigh;
  final num recentHigh;
  final num recentLow;
  final bool sweepUp;

  const _StubZoneDecision({
    required this.side,
    required this.zoneSide,
    required this.trend4h,
    required this.trend1d,
    required this.needsFartherRetest,
    required this.targetRetestPct,
    this.zoneLow = 90,
    this.zoneHigh = 91,
    this.recentHigh = 105,
    this.recentLow = 85,
    this.sweepUp = true,
  });

  @override
  BingxFuturesZoneDecisionResult decide({
    required BingxFuturesZoneDecisionInput input,
  }) {
    return BingxFuturesZoneDecisionResult(
      side: side,
      zoneSide: zoneSide,
      zoneLow: zoneLow,
      zoneHigh: zoneHigh,
      source: 'stub',
      sideReason: 'stub',
      olderHigh: 110,
      olderLow: 80,
      recentHigh: recentHigh,
      recentLow: recentLow,
      sweepUp: sweepUp,
      sweepDown: false,
      trend4h: trend4h,
      trend1d: trend1d,
      contextBias: -2,
      aligned: false,
      contrarian: false,
      needsFartherRetest: needsFartherRetest,
      rangePct1h: 0.01,
      rangePct4h: 0.03,
      rangePct1d: 0.05,
      rangePct1w: 0.08,
      targetRetestPct: targetRetestPct,
      externalSellRetest: 90,
      externalBuyRetest: 80,
      anchorSource: 'stub',
      anchorExecutable: true,
      anchorLifecycle: 'fresh',
      strength: 70,
      usedFallback: false,
    );
  }
}
