import '../models/bingx_futures_market_snapshot_models.dart';
import '../models/bingx_futures_exchange_models.dart';
import 'bingx_futures_public_market_data_port.dart';

DateTime _systemClockUtc() => DateTime.now().toUtc();

class BingxFuturesLiveSnapshotBuildResult {
  final bool isSuccess;
  final String errorCode;
  final String errorMessage;
  final BingxFuturesMarketSnapshotInput? snapshotInput;
  final String symbol;

  const BingxFuturesLiveSnapshotBuildResult({
    required this.isSuccess,
    required this.errorCode,
    required this.errorMessage,
    required this.snapshotInput,
    required this.symbol,
  });
}

class BingxFuturesLiveSnapshotBuilderService {
  final DateTime Function() _clockUtc;

  const BingxFuturesLiveSnapshotBuilderService({
    DateTime Function() clockUtc = _systemClockUtc,
  }) : _clockUtc = clockUtc;

  Future<BingxFuturesLiveSnapshotBuildResult> fetchAndBuild({
    required BingxFuturesPublicMarketDataPort exchange,
    required String symbol,
    List<BingxFuturesSessionVolumePoint>? sessionVolumes,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) {
      return const BingxFuturesLiveSnapshotBuildResult(
        isSuccess: false,
        errorCode: 'invalid_symbol',
        errorMessage: 'Symbol is required',
        snapshotInput: null,
        symbol: '',
      );
    }

    final price = await exchange.getPublicPrice(symbol: normalizedSymbol);
    if (!price.isSuccess || price.priceDecimal == null) {
      return _fail(
        symbol: normalizedSymbol,
        code: price.exchangeCode,
        message: 'Quote unavailable: ${price.exchangeMessage}',
      );
    }

    final k5mFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '5m',
      limit: 120,
    );
    final k15mFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '15m',
      limit: 220,
    );
    final k1hFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1h',
      limit: 120,
    );
    final k4hFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '4h',
      limit: 500,
    );
    final k1dFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1d',
      limit: 120,
    );
    final k1wFuture = exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1w',
      limit: 60,
    );
    final k5m = await k5mFuture;
    final k15m = await k15mFuture;
    final k1h = await k1hFuture;
    final k4h = await k4hFuture;
    final k1d = await k1dFuture;
    final k1w = await k1wFuture;

    final klineResults = <BingxFuturesPublicKlinesResult>[
      k5m,
      k15m,
      k1h,
      k4h,
      k1d,
      k1w,
    ];
    for (final result in klineResults) {
      if (!result.isSuccess || result.klines.isEmpty) {
        return _fail(
          symbol: normalizedSymbol,
          code: result.exchangeCode,
          message: 'Klines unavailable (${result.interval})',
        );
      }
    }

    final tradesFuture = exchange.getPublicTrades(
      symbol: normalizedSymbol,
      limit: 200,
    );
    final premiumFuture = exchange.getPublicPremiumIndex(
      symbol: normalizedSymbol,
    );
    final openInterestFuture = exchange.getPublicOpenInterest(
      symbol: normalizedSymbol,
    );
    final openInterestHistoryFuture = exchange.getPublicOpenInterestHistory(
      symbol: normalizedSymbol,
      period: '5m',
      limit: 24,
    );
    final depthFuture = exchange.getPublicDepth(
      symbol: normalizedSymbol,
      limit: 20,
    );
    final trades = await tradesFuture;
    final premium = await premiumFuture;
    final oi = await openInterestFuture;
    final oiHistory = await openInterestHistoryFuture;
    final depth = await depthFuture;
    if (!trades.isSuccess || trades.trades.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: trades.exchangeCode,
        message: 'Trades unavailable: ${trades.exchangeMessage}',
      );
    }

    if (!premium.isSuccess ||
        premium.fundingRateDecimal == null ||
        premium.fundingRateDecimal!.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: premium.exchangeCode,
        message: 'Funding unavailable: ${premium.exchangeMessage}',
      );
    }

    if (!oi.isSuccess ||
        oi.openInterestDecimal == null ||
        oi.openInterestDecimal!.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: oi.exchangeCode,
        message: 'Open interest unavailable: ${oi.exchangeMessage}',
      );
    }
    if (!depth.isSuccess || (depth.bids.isEmpty && depth.asks.isEmpty)) {
      return _fail(
        symbol: normalizedSymbol,
        code: depth.exchangeCode,
        message: 'Depth unavailable: ${depth.exchangeMessage}',
      );
    }
    try {
      final observationTime = _clockUtc().toUtc();
      final allCandles = <BingxFuturesCandle>[
        ..._mapCandles('5m', k5m.klines, observedAtUtc: observationTime),
        ..._mapCandles('15m', k15m.klines, observedAtUtc: observationTime),
        ..._mapCandles('1h', k1h.klines, observedAtUtc: observationTime),
        ..._mapCandles('4h', k4h.klines, observedAtUtc: observationTime),
        ..._mapCandles('1d', k1d.klines, observedAtUtc: observationTime),
        ..._mapCandles('1w', k1w.klines, observedAtUtc: observationTime),
      ];
      final tradeRows = _mapTrades(trades.trades);
      final openInterestRows = _buildOpenInterestRows(
        oi: oi,
        oiHistory: oiHistory,
      );
      final funding = BingxFuturesFundingSnapshot(
        timestampUtc: _msToUtcIso(
          premium.timestampMs ??
              premium.nextFundingTimeMs ??
              oi.timestampMs ??
              DateTime.now().millisecondsSinceEpoch.toString(),
        ),
        fundingRateDecimal: premium.fundingRateDecimal!,
        nextFundingAtUtc: _msToUtcIso(
          premium.nextFundingTimeMs ?? premium.timestampMs ?? '0',
        ),
      );
      final liquidity = _deriveLiquidity(
        candles5m: _closedKlines('5m', k5m.klines, observationTime),
        candles1h: _closedKlines('1h', k1h.klines, observationTime),
        depth: depth,
        trades: trades.trades,
        openInterest: openInterestRows,
        fundingRateDecimal: funding.fundingRateDecimal,
        priceDecimal: price.priceDecimal!,
        observedAtUtc: observationTime,
      );
      final sessions = sessionVolumes ?? _deriveSessions(tradeRows);
      final orderBookLevels = _mapOrderBook(depth);

      final instrument = _buildInstrumentMeta(normalizedSymbol);
      return BingxFuturesLiveSnapshotBuildResult(
        isSuccess: true,
        errorCode: '0',
        errorMessage: 'ok',
        snapshotInput: BingxFuturesMarketSnapshotInput(
          instrument: instrument,
          prices: BingxFuturesPriceSnapshot(
            lastTradePriceDecimal: price.priceDecimal!,
            markPriceDecimal: premium.markPriceDecimal ?? price.priceDecimal!,
            indexPriceDecimal: premium.indexPriceDecimal ?? price.priceDecimal!,
          ),
          candles: allCandles,
          trades: tradeRows,
          openInterest: openInterestRows,
          funding: funding,
          liquidityLevels: liquidity,
          sessionVolumes: sessions,
          orderBookTopLevels: orderBookLevels,
        ),
        symbol: normalizedSymbol,
      );
    } on FormatException catch (error) {
      return _fail(
        symbol: normalizedSymbol,
        code: 'snapshot_format_error',
        message: error.message,
      );
    }
  }

  BingxFuturesInstrumentMeta _buildInstrumentMeta(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    final chunks = normalized.split(RegExp(r'[-_/]'));
    final baseAsset = chunks.isNotEmpty ? chunks.first : normalized;
    final quoteAsset = chunks.length >= 2 ? chunks.sublist(1).join('') : 'USDT';
    return BingxFuturesInstrumentMeta(
      symbol: normalized,
      baseAsset: baseAsset,
      quoteAsset: quoteAsset,
      tickSizeDecimal: '0.1',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    );
  }

  BingxFuturesLiveSnapshotBuildResult _fail({
    required String symbol,
    required String code,
    required String message,
  }) {
    return BingxFuturesLiveSnapshotBuildResult(
      isSuccess: false,
      errorCode: code,
      errorMessage: message,
      snapshotInput: null,
      symbol: symbol,
    );
  }

  List<BingxFuturesCandle> _mapCandles(
    String timeframe,
    List<BingxFuturesPublicKline> input, {
    DateTime? observedAtUtc,
  }) {
    final minutes = _timeframeMinutes(timeframe);
    final observedAt = (observedAtUtc ?? DateTime.now()).toUtc();
    return input
        .map((kline) {
          final openTime = DateTime.fromMillisecondsSinceEpoch(
            kline.openTimeMs,
            isUtc: true,
          );
          final closeTime = openTime.add(Duration(minutes: minutes));
          return BingxFuturesCandle(
            timeframe: timeframe,
            openTimeUtc: openTime.toIso8601String(),
            closeTimeUtc: closeTime.toIso8601String(),
            openDecimal: kline.openDecimal,
            highDecimal: kline.highDecimal,
            lowDecimal: kline.lowDecimal,
            closeDecimal: kline.closeDecimal,
            volumeBaseDecimal: kline.volumeBaseDecimal ?? '0',
            volumeQuoteDecimal: kline.volumeQuoteDecimal ?? '0',
            isClosed: !closeTime.isAfter(observedAt),
          );
        })
        .toList(growable: false);
  }

  int _timeframeMinutes(String timeframe) {
    return switch (timeframe) {
      '1m' => 1,
      '5m' => 5,
      '15m' => 15,
      '1h' => 60,
      '4h' => 240,
      '1d' => 1440,
      '1w' => 10080,
      _ => 1,
    };
  }

  List<BingxFuturesPublicKline> _closedKlines(
    String timeframe,
    List<BingxFuturesPublicKline> input,
    DateTime observedAtUtc,
  ) {
    final duration = Duration(minutes: _timeframeMinutes(timeframe));
    return input
        .where((kline) {
          final openTime = DateTime.fromMillisecondsSinceEpoch(
            kline.openTimeMs,
            isUtc: true,
          );
          return !openTime.add(duration).isAfter(observedAtUtc);
        })
        .toList(growable: false);
  }

  List<BingxFuturesTrade> _mapTrades(List<BingxFuturesPublicTrade> input) {
    return input
        .where((trade) => trade.side == 'buy' || trade.side == 'sell')
        .map(
          (trade) => BingxFuturesTrade(
            tradeId: trade.tradeId ?? '-',
            timestampUtc: _msToUtcIso(
              trade.timestampMs ??
                  DateTime.now().millisecondsSinceEpoch.toString(),
            ),
            side: trade.side,
            priceDecimal: trade.priceDecimal,
            quantityDecimal: trade.quantityDecimal,
          ),
        )
        .toList(growable: false);
  }

  BingxFuturesOpenInterestPoint _openInterestPoint(
    String openInterestDecimal,
    String? timestampMs,
  ) {
    return BingxFuturesOpenInterestPoint(
      timestampUtc: _msToUtcIso(
        timestampMs ?? DateTime.now().millisecondsSinceEpoch.toString(),
      ),
      openInterestDecimal: openInterestDecimal,
    );
  }

  List<BingxFuturesLiquidityLevel> _deriveLiquidity({
    required List<BingxFuturesPublicKline> candles5m,
    required List<BingxFuturesPublicKline> candles1h,
    required BingxFuturesPublicOrderBookResult depth,
    required List<BingxFuturesPublicTrade> trades,
    required List<BingxFuturesOpenInterestPoint> openInterest,
    required String fundingRateDecimal,
    required String priceDecimal,
    required DateTime observedAtUtc,
  }) {
    final highs1h = candles1h
        .map((k) => num.tryParse(k.highDecimal) ?? 0)
        .where((v) => v > 0)
        .toList(growable: false);
    final lows1h = candles1h
        .map((k) => num.tryParse(k.lowDecimal) ?? 0)
        .where((v) => v > 0)
        .toList(growable: false);
    final highs5m = candles5m
        .map((k) => num.tryParse(k.highDecimal) ?? 0)
        .where((v) => v > 0)
        .toList(growable: false);
    final lows5m = candles5m
        .map((k) => num.tryParse(k.lowDecimal) ?? 0)
        .where((v) => v > 0)
        .toList(growable: false);

    final extHigh =
        highs1h.isEmpty
            ? 0
            : highs1h.reduce((a, b) => a > b ? a : b).toDouble();
    final extLow =
        lows1h.isEmpty ? 0 : lows1h.reduce((a, b) => a < b ? a : b).toDouble();
    final intHigh =
        highs5m.isEmpty
            ? extHigh
            : highs5m.reduce((a, b) => a > b ? a : b).toDouble();
    final intLow =
        lows5m.isEmpty
            ? extLow
            : lows5m.reduce((a, b) => a < b ? a : b).toDouble();

    final baseLevels = <BingxFuturesLiquidityLevel>[
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'sellside',
        timeframe: '1h',
        priceDecimal: _fmt(extHigh > 0 ? extHigh : intHigh),
      ),
      BingxFuturesLiquidityLevel(
        kind: 'external',
        side: 'buyside',
        timeframe: '1h',
        priceDecimal: _fmt(extLow > 0 ? extLow : intLow),
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'sellside',
        timeframe: '5m',
        priceDecimal: _fmt(intHigh > 0 ? intHigh : extHigh),
      ),
      BingxFuturesLiquidityLevel(
        kind: 'internal',
        side: 'buyside',
        timeframe: '5m',
        priceDecimal: _fmt(intLow > 0 ? intLow : extLow),
      ),
    ];
    final liquidation = _deriveLiquidationProxyLevels(
      depth: depth,
      trades: trades,
      openInterest: openInterest,
      fundingRateDecimal: fundingRateDecimal,
      structurePrices: <num>[...highs1h, ...lows1h, ...highs5m, ...lows5m],
      priceDecimal: priceDecimal,
      observedAtUtc: observedAtUtc,
    );
    return <BingxFuturesLiquidityLevel>[...baseLevels, ...liquidation];
  }

  List<BingxFuturesSessionVolumePoint> _deriveSessions(
    List<BingxFuturesTrade> trades,
  ) {
    num deltaForHour(int hour, String side, num qty) {
      return side == 'buy' ? qty : -qty;
    }

    final bySession = <String, num>{'asia': 0, 'london': 0, 'newyork': 0};
    for (final trade in trades) {
      final ts = DateTime.tryParse(trade.timestampUtc)?.toUtc();
      if (ts == null) continue;
      final qty = num.tryParse(trade.quantityDecimal) ?? 0;
      final session =
          ts.hour < 8
              ? 'asia'
              : ts.hour < 16
              ? 'london'
              : 'newyork';
      bySession[session] =
          (bySession[session] ?? 0) + deltaForHour(ts.hour, trade.side, qty);
    }

    return <BingxFuturesSessionVolumePoint>[
      _sessionPoint('asia', bySession['asia'] ?? 0),
      _sessionPoint('london', bySession['london'] ?? 0),
      _sessionPoint('newyork', bySession['newyork'] ?? 0),
    ];
  }

  BingxFuturesSessionVolumePoint _sessionPoint(String session, num delta) {
    final now = DateTime.now().toUtc();
    return BingxFuturesSessionVolumePoint(
      session: session,
      bucketStartUtc:
          DateTime.utc(now.year, now.month, now.day).toIso8601String(),
      volumeDecimal: _fmt(delta.abs()),
      deltaDecimal: _fmt(delta),
      evidenceSource: 'recent_trade_sample',
      coverageComplete: false,
    );
  }

  List<BingxFuturesOrderBookLevel> _mapOrderBook(
    BingxFuturesPublicOrderBookResult depth,
  ) {
    return <BingxFuturesOrderBookLevel>[
      ...depth.bids.map(
        (row) => BingxFuturesOrderBookLevel(
          side: 'bid',
          priceDecimal: row.priceDecimal,
          quantityDecimal: row.quantityDecimal,
        ),
      ),
      ...depth.asks.map(
        (row) => BingxFuturesOrderBookLevel(
          side: 'ask',
          priceDecimal: row.priceDecimal,
          quantityDecimal: row.quantityDecimal,
        ),
      ),
    ];
  }

  List<BingxFuturesOpenInterestPoint> _buildOpenInterestRows({
    required BingxFuturesPublicOpenInterestResult oi,
    required BingxFuturesPublicOpenInterestHistoryResult oiHistory,
  }) {
    final rows = <BingxFuturesOpenInterestPoint>[];
    if (oiHistory.isSuccess && oiHistory.points.isNotEmpty) {
      for (final point in oiHistory.points) {
        rows.add(
          BingxFuturesOpenInterestPoint(
            timestampUtc: _msToUtcIso(point.timestampMs),
            openInterestDecimal: point.openInterestDecimal,
          ),
        );
      }
    }
    if (rows.isEmpty) {
      rows.add(_openInterestPoint(oi.openInterestDecimal!, oi.timestampMs));
    }
    return rows;
  }

  List<BingxFuturesLiquidityLevel> _deriveLiquidationProxyLevels({
    required BingxFuturesPublicOrderBookResult depth,
    required List<BingxFuturesPublicTrade> trades,
    required List<BingxFuturesOpenInterestPoint> openInterest,
    required String fundingRateDecimal,
    required List<num> structurePrices,
    required String priceDecimal,
    required DateTime observedAtUtc,
  }) {
    final mid = num.tryParse(priceDecimal) ?? 0;
    if (mid <= 0) return const <BingxFuturesLiquidityLevel>[];
    final depthTimestampMs = int.tryParse(depth.timestampMs?.trim() ?? '');
    if (depthTimestampMs == null) {
      return const <BingxFuturesLiquidityLevel>[];
    }
    final depthTime = DateTime.fromMillisecondsSinceEpoch(
      depthTimestampMs,
      isUtc: true,
    );
    final depthAge = observedAtUtc.toUtc().difference(depthTime);
    if (depthAge > const Duration(seconds: 30) ||
        depthAge < const Duration(seconds: -5)) {
      return const <BingxFuturesLiquidityLevel>[];
    }

    final buyAggression = trades
        .where((trade) => trade.side == 'buy')
        .map((trade) {
          final qty = num.tryParse(trade.quantityDecimal) ?? 0;
          final price = num.tryParse(trade.priceDecimal) ?? 0;
          return qty > 0 && price > 0 ? qty * price : 0;
        })
        .fold<num>(0, (acc, value) => acc + value);
    final sellAggression = trades
        .where((trade) => trade.side == 'sell')
        .map((trade) {
          final qty = num.tryParse(trade.quantityDecimal) ?? 0;
          final price = num.tryParse(trade.priceDecimal) ?? 0;
          return qty > 0 && price > 0 ? qty * price : 0;
        })
        .fold<num>(0, (acc, value) => acc + value);
    final oiDeltaPct = _openInterestDeltaPct(openInterest);
    final fundingRate = num.tryParse(fundingRateDecimal) ?? 0;

    return <BingxFuturesLiquidityLevel>[
      ..._rankDepthClusters(
        levels: depth.asks,
        side: 'sellside',
        mid: mid,
        requireAboveMid: true,
        directionalAggression: buyAggression,
        opposingAggression: sellAggression,
        oiDeltaPct: oiDeltaPct,
        fundingCrowdingAligned: fundingRate < 0,
        structurePrices: structurePrices,
      ),
      ..._rankDepthClusters(
        levels: depth.bids,
        side: 'buyside',
        mid: mid,
        requireAboveMid: false,
        directionalAggression: sellAggression,
        opposingAggression: buyAggression,
        oiDeltaPct: oiDeltaPct,
        fundingCrowdingAligned: fundingRate > 0,
        structurePrices: structurePrices,
      ),
    ];
  }

  List<BingxFuturesLiquidityLevel> _rankDepthClusters({
    required List<BingxFuturesPublicOrderBookLevel> levels,
    required String side,
    required num mid,
    required bool requireAboveMid,
    required num directionalAggression,
    required num opposingAggression,
    required num oiDeltaPct,
    required bool fundingCrowdingAligned,
    required List<num> structurePrices,
  }) {
    const clusterWidthBps = 5.0;
    const maxInputLevels = 100;
    const maxOutputClusters = 3;
    final buckets = <int, _DepthClusterAccumulator>{};
    final canonicalLevels =
        levels
            .map((level) {
              final price = num.tryParse(level.priceDecimal) ?? 0;
              final quantity = num.tryParse(level.quantityDecimal) ?? 0;
              return (price: price, quantity: quantity);
            })
            .where((level) => level.price > 0 && level.quantity > 0)
            .where(
              (level) =>
                  requireAboveMid ? level.price > mid : level.price < mid,
            )
            .toList()
          ..sort((left, right) {
            final byPrice = left.price.compareTo(right.price);
            if (byPrice != 0) return byPrice;
            return left.quantity.compareTo(right.quantity);
          });
    for (final level in canonicalLevels.take(maxInputLevels)) {
      final price = level.price;
      final quantity = level.quantity;
      final distanceBps = ((price - mid).abs() / mid) * 10000;
      final bucket = (distanceBps / clusterWidthBps).floor();
      final accumulator = buckets.putIfAbsent(
        bucket,
        () => _DepthClusterAccumulator(),
      );
      final notional = price * quantity;
      accumulator.notional += notional;
      accumulator.weightedPrice += price * notional;
    }
    if (buckets.isEmpty) {
      return const <BingxFuturesLiquidityLevel>[];
    }

    final totalNotional = buckets.values.fold<num>(
      0,
      (total, cluster) => total + cluster.notional,
    );
    if (totalNotional <= 0) {
      return const <BingxFuturesLiquidityLevel>[];
    }
    final totalAggression = directionalAggression + opposingAggression;
    final aggressionShare =
        totalAggression <= 0
            ? 0.0
            : (directionalAggression / totalAggression).toDouble();
    final candidates =
        buckets.values.map((cluster) {
            final center = cluster.weightedPrice / cluster.notional;
            final depthShare = cluster.notional / totalNotional;
            final structureDistanceBps = structurePrices
                .where((price) => price > 0)
                .map((price) => ((center - price).abs() / mid) * 10000)
                .fold<num>(
                  double.infinity,
                  (best, value) => value < best ? value : best,
                );
            final structureScore =
                structureDistanceBps <= 20
                    ? 0.15
                    : structureDistanceBps <= 50
                    ? 0.05
                    : 0.0;
            final oiScore = oiDeltaPct >= 0.005 ? 0.05 : 0.0;
            final fundingScore = fundingCrowdingAligned ? 0.05 : 0.0;
            final flowScore =
                aggressionShare >= 0.6
                    ? 0.10
                    : aggressionShare >= 0.5
                    ? 0.05
                    : 0.0;
            return _RankedDepthCluster(
              center: center,
              depthShare: depthShare,
              score:
                  depthShare +
                  structureScore +
                  oiScore +
                  fundingScore +
                  flowScore,
            );
          }).toList()
          ..sort((left, right) {
            final byScore = right.score.compareTo(left.score);
            if (byScore != 0) return byScore;
            return left.center.compareTo(right.center);
          });

    final selected = <_RankedDepthCluster>[];
    for (final candidate in candidates) {
      if (selected.isNotEmpty &&
          (candidate.depthShare < 0.12 || candidate.score < 0.22)) {
        continue;
      }
      selected.add(candidate);
      if (selected.length == maxOutputClusters) break;
    }
    selected.sort((left, right) => left.center.compareTo(right.center));
    return selected
        .map(
          (cluster) => BingxFuturesLiquidityLevel(
            kind: 'liquidation_proxy',
            side: side,
            timeframe: '5m',
            priceDecimal: _fmt(cluster.center),
          ),
        )
        .toList(growable: false);
  }

  num _openInterestDeltaPct(List<BingxFuturesOpenInterestPoint> values) {
    if (values.length < 2) return 0;
    final sorted =
        values.toList()..sort(
          (left, right) => left.timestampUtc.compareTo(right.timestampUtc),
        );
    final first = num.tryParse(sorted.first.openInterestDecimal) ?? 0;
    final last = num.tryParse(sorted.last.openInterestDecimal) ?? 0;
    if (first <= 0) return 0;
    return (last - first) / first;
  }

  String _msToUtcIso(String rawMs) {
    final ms = int.tryParse(rawMs.trim()) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      ms,
      isUtc: true,
    ).toIso8601String();
  }

  String _fmt(num value) {
    return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _DepthClusterAccumulator {
  num notional = 0;
  num weightedPrice = 0;
}

class _RankedDepthCluster {
  final num center;
  final num depthShare;
  final num score;

  const _RankedDepthCluster({
    required this.center,
    required this.depthShare,
    required this.score,
  });
}
