import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_live_decision_service.dart';
import 'package:hivra_app/services/bingx_futures_market_snapshot_service.dart';
import 'package:hivra_app/services/bingx_futures_tvh_rule_engine_service.dart';

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
        ),
      );

      expect(result.canPrepareIntent, isFalse);
      expect(result.decision, BingxTvhDecisionKind.blocked);
      expect(result.side, isNull);
      expect(result.zoneLowDecimal, isNull);
      expect(result.reasons.first.code, 'consensus_guard');
    });
  });
}

BingxFuturesMarketSnapshotInput _buildInput({required bool permuted}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandles(count: 220),
    ..._generate5mCandles(count: 80),
    _singleCandle('1m', '2026-04-25T09:59:00Z', '2026-04-25T10:00:00Z',
        102, 103, 101, 102.2),
    _singleCandle('1h', '2026-04-25T09:00:00Z', '2026-04-25T10:00:00Z',
        99, 104, 98, 102),
    _singleCandle('4h', '2026-04-25T08:00:00Z', '2026-04-25T12:00:00Z',
        97, 105, 96, 102.5),
    _singleCandle('1d', '2026-04-24T00:00:00Z', '2026-04-25T00:00:00Z',
        95, 106, 94, 101.8),
    _singleCandle('1w', '2026-04-18T00:00:00Z', '2026-04-25T00:00:00Z',
        92, 108, 90, 101.8),
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
