import '../models/bingx_futures_market_snapshot_models.dart';
import 'bingx_futures_exchange_service.dart';

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
  const BingxFuturesLiveSnapshotBuilderService();

  Future<BingxFuturesLiveSnapshotBuildResult> fetchAndBuild({
    required BingxFuturesExchangeService exchange,
    required String symbol,
    BingxFuturesApiCredentials? credentials,
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

    final k1m = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1m',
      limit: 120,
    );
    final k5m = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '5m',
      limit: 120,
    );
    final k15m = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '15m',
      limit: 220,
    );
    final k1h = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1h',
      limit: 120,
    );
    final k4h = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '4h',
      limit: 500,
    );
    final k1d = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1d',
      limit: 120,
    );
    final k1w = await exchange.getPublicKlines(
      symbol: normalizedSymbol,
      interval: '1w',
      limit: 60,
    );

    final klineResults = <BingxFuturesPublicKlinesResult>[
      k1m,
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

    final trades = await exchange.getPublicTrades(
      symbol: normalizedSymbol,
      limit: 200,
    );
    if (!trades.isSuccess || trades.trades.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: trades.exchangeCode,
        message: 'Trades unavailable: ${trades.exchangeMessage}',
      );
    }

    final premium =
        await exchange.getPublicPremiumIndex(symbol: normalizedSymbol);
    if (!premium.isSuccess ||
        premium.fundingRateDecimal == null ||
        premium.fundingRateDecimal!.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: premium.exchangeCode,
        message: 'Funding unavailable: ${premium.exchangeMessage}',
      );
    }

    final oi = await exchange.getPublicOpenInterest(symbol: normalizedSymbol);
    if (!oi.isSuccess ||
        oi.openInterestDecimal == null ||
        oi.openInterestDecimal!.isEmpty) {
      return _fail(
        symbol: normalizedSymbol,
        code: oi.exchangeCode,
        message: 'Open interest unavailable: ${oi.exchangeMessage}',
      );
    }
    final oiHistory = await exchange.getPublicOpenInterestHistory(
      symbol: normalizedSymbol,
      period: '5m',
      limit: 24,
    );

    final depth = await exchange.getPublicDepth(
      symbol: normalizedSymbol,
      limit: 20,
    );
    if (!depth.isSuccess || (depth.bids.isEmpty && depth.asks.isEmpty)) {
      return _fail(
        symbol: normalizedSymbol,
        code: depth.exchangeCode,
        message: 'Depth unavailable: ${depth.exchangeMessage}',
      );
    }
    try {
      final allCandles = <BingxFuturesCandle>[
        ..._mapCandles('1m', k1m.klines),
        ..._mapCandles('5m', k5m.klines),
        ..._mapCandles('15m', k15m.klines),
        ..._mapCandles('1h', k1h.klines),
        ..._mapCandles('4h', k4h.klines),
        ..._mapCandles('1d', k1d.klines),
        ..._mapCandles('1w', k1w.klines),
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
        candles5m: k5m.klines,
        candles1h: k1h.klines,
        depth: depth,
        trades: trades.trades,
        priceDecimal: price.priceDecimal!,
      );
      final sessions = _deriveSessions(tradeRows);
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
    List<BingxFuturesPublicKline> input,
  ) {
    final minutes = _timeframeMinutes(timeframe);
    return input.map((kline) {
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
        volumeBaseDecimal: '0',
        volumeQuoteDecimal: '0',
        isClosed: true,
      );
    }).toList(growable: false);
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

  List<BingxFuturesTrade> _mapTrades(List<BingxFuturesPublicTrade> input) {
    return input
        .where((trade) => trade.side == 'buy' || trade.side == 'sell')
        .map((trade) => BingxFuturesTrade(
              tradeId: trade.tradeId ?? '-',
              timestampUtc: _msToUtcIso(
                trade.timestampMs ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
              ),
              side: trade.side,
              priceDecimal: trade.priceDecimal,
              quantityDecimal: trade.quantityDecimal,
            ))
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
    required String priceDecimal,
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

    final extHigh = highs1h.isEmpty
        ? 0
        : highs1h.reduce((a, b) => a > b ? a : b).toDouble();
    final extLow =
        lows1h.isEmpty ? 0 : lows1h.reduce((a, b) => a < b ? a : b).toDouble();
    final intHigh = highs5m.isEmpty
        ? extHigh
        : highs5m.reduce((a, b) => a > b ? a : b).toDouble();
    final intLow = lows5m.isEmpty
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
      priceDecimal: priceDecimal,
    );
    return <BingxFuturesLiquidityLevel>[
      ...baseLevels,
      ...liquidation,
    ];
  }

  List<BingxFuturesSessionVolumePoint> _deriveSessions(
    List<BingxFuturesTrade> trades,
  ) {
    num deltaForHour(int hour, String side, num qty) {
      return side == 'buy' ? qty : -qty;
    }

    final bySession = <String, num>{
      'asia': 0,
      'london': 0,
      'newyork': 0,
    };
    for (final trade in trades) {
      final ts = DateTime.tryParse(trade.timestampUtc)?.toUtc();
      if (ts == null) continue;
      final qty = num.tryParse(trade.quantityDecimal) ?? 0;
      final session = ts.hour < 8
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
      rows.add(
        _openInterestPoint(
          oi.openInterestDecimal!,
          oi.timestampMs,
        ),
      );
    }
    return rows;
  }

  List<BingxFuturesLiquidityLevel> _deriveLiquidationProxyLevels({
    required BingxFuturesPublicOrderBookResult depth,
    required List<BingxFuturesPublicTrade> trades,
    required String priceDecimal,
  }) {
    final mid = num.tryParse(priceDecimal) ?? 0;
    if (mid <= 0) return const <BingxFuturesLiquidityLevel>[];

    ({num price, num qty, num notional})? bestBid;
    for (final bid in depth.bids) {
      final price = num.tryParse(bid.priceDecimal) ?? 0;
      final qty = num.tryParse(bid.quantityDecimal) ?? 0;
      if (price <= 0 || qty <= 0 || price >= mid) continue;
      final notional = price * qty;
      if (bestBid == null || notional > bestBid.notional) {
        bestBid = (price: price, qty: qty, notional: notional);
      }
    }
    ({num price, num qty, num notional})? bestAsk;
    for (final ask in depth.asks) {
      final price = num.tryParse(ask.priceDecimal) ?? 0;
      final qty = num.tryParse(ask.quantityDecimal) ?? 0;
      if (price <= 0 || qty <= 0 || price <= mid) continue;
      final notional = price * qty;
      if (bestAsk == null || notional > bestAsk.notional) {
        bestAsk = (price: price, qty: qty, notional: notional);
      }
    }

    final buyAggression =
        trades.where((trade) => trade.side == 'buy').map((trade) {
      final qty = num.tryParse(trade.quantityDecimal) ?? 0;
      final price = num.tryParse(trade.priceDecimal) ?? 0;
      return qty > 0 && price > 0 ? qty * price : 0;
    }).fold<num>(0, (acc, value) => acc + value);
    final sellAggression =
        trades.where((trade) => trade.side == 'sell').map((trade) {
      final qty = num.tryParse(trade.quantityDecimal) ?? 0;
      final price = num.tryParse(trade.priceDecimal) ?? 0;
      return qty > 0 && price > 0 ? qty * price : 0;
    }).fold<num>(0, (acc, value) => acc + value);

    final levels = <BingxFuturesLiquidityLevel>[];
    if (bestAsk != null &&
        (buyAggression >= sellAggression * 0.8 || sellAggression == 0)) {
      levels.add(
        BingxFuturesLiquidityLevel(
          kind: 'liquidation_proxy',
          side: 'sellside',
          timeframe: '5m',
          priceDecimal: _fmt(bestAsk.price),
        ),
      );
    }
    if (bestBid != null &&
        (sellAggression >= buyAggression * 0.8 || buyAggression == 0)) {
      levels.add(
        BingxFuturesLiquidityLevel(
          kind: 'liquidation_proxy',
          side: 'buyside',
          timeframe: '5m',
          priceDecimal: _fmt(bestBid.price),
        ),
      );
    }
    return levels;
  }

  String _msToUtcIso(String rawMs) {
    final ms = int.tryParse(rawMs.trim()) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .toIso8601String();
  }

  String _fmt(num value) {
    return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
