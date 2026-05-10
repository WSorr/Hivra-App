import 'dart:convert';

import 'package:crypto/crypto.dart';

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

class BingxFuturesMarketSnapshotService {
  static const List<String> requiredTimeframes = <String>[
    '1m',
    '5m',
    '15m',
    '1h',
    '4h',
    '1d',
    '1w',
  ];

  const BingxFuturesMarketSnapshotService();

  BingxFuturesMarketSnapshotDigest build(
      BingxFuturesMarketSnapshotInput input) {
    final instrument = _normalizeInstrument(input.instrument);
    final prices = _normalizePrices(input.prices);
    final candles = _normalizeCandles(input.candles);
    _ensureRequiredTimeframesPresent(candles);
    final trades = _normalizeTrades(input.trades);
    final openInterest = _normalizeOpenInterest(input.openInterest);
    final funding = _normalizeFunding(input.funding);
    final liquidity = _normalizeLiquidityLevels(input.liquidityLevels);
    final sessions = _normalizeSessionVolumes(input.sessionVolumes);
    final orderBook = _normalizeOrderBook(input.orderBookTopLevels);

    final hasExternal = liquidity.any((item) => item['kind'] == 'external');
    final hasInternal = liquidity.any((item) => item['kind'] == 'internal');
    if (!hasExternal || !hasInternal) {
      throw const FormatException(
        'liquidity_levels must include external and internal entries',
      );
    }
    final liquidationFeedAvailable =
        liquidity.any((item) => item['kind'] == 'liquidation');

    final snapshot = <String, dynamic>{
      'schema_version': 1,
      'source': 'bingx_futures_market_snapshot_v1',
      'instrument': instrument,
      'prices': prices,
      'candles': candles,
      'trades': trades,
      'open_interest': openInterest,
      'funding': funding,
      'liquidity_levels': liquidity,
      'session_volumes': sessions,
      'orderbook_top_levels': orderBook,
      'metadata': <String, dynamic>{
        'liquidation_feed_state':
            liquidationFeedAvailable ? 'known' : 'unknown',
      },
    };

    final canonicalJson = jsonEncode(snapshot);
    final marketSnapshotHashHex =
        sha256.convert(utf8.encode(canonicalJson)).toString();
    return BingxFuturesMarketSnapshotDigest(
      normalizedSnapshot: snapshot,
      canonicalJson: canonicalJson,
      marketSnapshotHashHex: marketSnapshotHashHex,
      liquidationFeedAvailable: liquidationFeedAvailable,
    );
  }

  Map<String, dynamic> _normalizeInstrument(BingxFuturesInstrumentMeta value) {
    final symbol = value.symbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,20}([-_/][A-Z0-9]{2,20})?$').hasMatch(symbol)) {
      throw const FormatException('instrument.symbol format is invalid');
    }
    final baseAsset = value.baseAsset.trim().toUpperCase();
    final quoteAsset = value.quoteAsset.trim().toUpperCase();
    if (baseAsset.isEmpty || quoteAsset.isEmpty) {
      throw const FormatException(
        'instrument.baseAsset and instrument.quoteAsset are required',
      );
    }
    return <String, dynamic>{
      'symbol': symbol,
      'base_asset': baseAsset,
      'quote_asset': quoteAsset,
      'tick_size_decimal': _normalizeDecimal(value.tickSizeDecimal, scale: 8),
      'qty_step_decimal': _normalizeDecimal(value.qtyStepDecimal, scale: 8),
      'min_qty_decimal': _normalizeDecimal(value.minQtyDecimal, scale: 8),
      'max_leverage_decimal':
          _normalizeDecimal(value.maxLeverageDecimal, scale: 8),
    };
  }

  Map<String, dynamic> _normalizePrices(BingxFuturesPriceSnapshot value) {
    return <String, dynamic>{
      'last_trade_price_decimal':
          _normalizeDecimal(value.lastTradePriceDecimal, scale: 8),
      'mark_price_decimal': _normalizeDecimal(value.markPriceDecimal, scale: 8),
      'index_price_decimal':
          _normalizeDecimal(value.indexPriceDecimal, scale: 8),
    };
  }

  List<Map<String, dynamic>> _normalizeCandles(List<BingxFuturesCandle> value) {
    final closedCandles = value.where((item) => item.isClosed).toList();
    if (closedCandles.isEmpty) {
      throw const FormatException('candles must contain closed entries');
    }
    final rows = closedCandles.map((item) {
      final timeframe = _normalizeTimeframe(item.timeframe);
      final openTimeUtc = _normalizeUtcInstant(item.openTimeUtc);
      final closeTimeUtc = _normalizeUtcInstant(item.closeTimeUtc);
      return <String, dynamic>{
        'timeframe': timeframe,
        'open_time_utc': openTimeUtc,
        'close_time_utc': closeTimeUtc,
        'open_decimal': _normalizeDecimal(item.openDecimal, scale: 8),
        'high_decimal': _normalizeDecimal(item.highDecimal, scale: 8),
        'low_decimal': _normalizeDecimal(item.lowDecimal, scale: 8),
        'close_decimal': _normalizeDecimal(item.closeDecimal, scale: 8),
        'volume_base_decimal':
            _normalizeDecimal(item.volumeBaseDecimal, scale: 8),
        'volume_quote_decimal':
            _normalizeDecimal(item.volumeQuoteDecimal, scale: 8),
      };
    }).toList();
    rows.sort(_compareCandles);
    return rows;
  }

  void _ensureRequiredTimeframesPresent(List<Map<String, dynamic>> candles) {
    final seen = candles.map((item) => item['timeframe'] as String).toSet();
    final missing =
        requiredTimeframes.where((tf) => !seen.contains(tf)).toList()..sort();
    if (missing.isNotEmpty) {
      throw FormatException(
        'missing required candle timeframes: ${missing.join(", ")}',
      );
    }
  }

  List<Map<String, dynamic>> _normalizeTrades(List<BingxFuturesTrade> value) {
    if (value.isEmpty) {
      throw const FormatException('trades are required');
    }
    final rows = value.map((item) {
      final side = _normalizeTradeSide(item.side);
      return <String, dynamic>{
        'trade_id': item.tradeId.trim().isEmpty ? '-' : item.tradeId.trim(),
        'timestamp_utc': _normalizeUtcInstant(item.timestampUtc),
        'side': side,
        'price_decimal': _normalizeDecimal(item.priceDecimal, scale: 8),
        'quantity_decimal': _normalizeDecimal(item.quantityDecimal, scale: 8),
      };
    }).toList();
    rows.sort(_compareTrades);
    return rows;
  }

  List<Map<String, dynamic>> _normalizeOpenInterest(
    List<BingxFuturesOpenInterestPoint> value,
  ) {
    if (value.isEmpty) {
      throw const FormatException('open_interest is required');
    }
    final rows = value
        .map(
          (item) => <String, dynamic>{
            'timestamp_utc': _normalizeUtcInstant(item.timestampUtc),
            'open_interest_decimal':
                _normalizeDecimal(item.openInterestDecimal, scale: 8),
          },
        )
        .toList();
    rows.sort((a, b) => _compareString(
          a['timestamp_utc'] as String,
          b['timestamp_utc'] as String,
        ));
    return rows;
  }

  Map<String, dynamic> _normalizeFunding(BingxFuturesFundingSnapshot value) {
    return <String, dynamic>{
      'timestamp_utc': _normalizeUtcInstant(value.timestampUtc),
      'funding_rate_decimal': _normalizeDecimal(value.fundingRateDecimal,
          scale: 10, allowNegative: true),
      'next_funding_at_utc': _normalizeUtcInstant(value.nextFundingAtUtc),
    };
  }

  List<Map<String, dynamic>> _normalizeLiquidityLevels(
    List<BingxFuturesLiquidityLevel> value,
  ) {
    if (value.isEmpty) {
      throw const FormatException('liquidity_levels are required');
    }
    final rows = value.map((item) {
      final kind = _normalizeLiquidityKind(item.kind);
      final side = _normalizeLiquiditySide(item.side);
      return <String, dynamic>{
        'kind': kind,
        'side': side,
        'timeframe': _normalizeTimeframe(item.timeframe),
        'price_decimal': _normalizeDecimal(item.priceDecimal, scale: 8),
      };
    }).toList();
    rows.sort((a, b) {
      final byKind = _compareString(a['kind'] as String, b['kind'] as String);
      if (byKind != 0) return byKind;
      final bySide = _compareString(a['side'] as String, b['side'] as String);
      if (bySide != 0) return bySide;
      final byTimeframe =
          _compareTimeframe(a['timeframe'] as String, b['timeframe'] as String);
      if (byTimeframe != 0) return byTimeframe;
      return _compareString(
        a['price_decimal'] as String,
        b['price_decimal'] as String,
      );
    });
    return rows;
  }

  List<Map<String, dynamic>> _normalizeSessionVolumes(
    List<BingxFuturesSessionVolumePoint> value,
  ) {
    if (value.isEmpty) {
      throw const FormatException('session_volumes are required');
    }
    final rows = value.map((item) {
      return <String, dynamic>{
        'session': _normalizeSession(item.session),
        'bucket_start_utc': _normalizeUtcInstant(item.bucketStartUtc),
        'volume_decimal': _normalizeDecimal(item.volumeDecimal, scale: 8),
        'delta_decimal': _normalizeDecimal(
          item.deltaDecimal,
          scale: 8,
          allowNegative: true,
        ),
      };
    }).toList();
    rows.sort((a, b) {
      final bySession =
          _compareString(a['session'] as String, b['session'] as String);
      if (bySession != 0) return bySession;
      return _compareString(
        a['bucket_start_utc'] as String,
        b['bucket_start_utc'] as String,
      );
    });
    final sessions = rows.map((item) => item['session'] as String).toSet();
    const required = <String>{'asia', 'london', 'newyork'};
    final missing = required.where((item) => !sessions.contains(item)).toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw FormatException(
        'missing required sessions: ${missing.join(", ")}',
      );
    }
    return rows;
  }

  List<Map<String, dynamic>> _normalizeOrderBook(
    List<BingxFuturesOrderBookLevel> value,
  ) {
    final rows = value
        .map(
          (item) => <String, dynamic>{
            'side': _normalizeOrderBookSide(item.side),
            'price_decimal': _normalizeDecimal(item.priceDecimal, scale: 8),
            'quantity_decimal':
                _normalizeDecimal(item.quantityDecimal, scale: 8),
          },
        )
        .toList();
    rows.sort((a, b) {
      final bySide = _compareString(a['side'] as String, b['side'] as String);
      if (bySide != 0) return bySide;
      final byPrice = _compareString(
          a['price_decimal'] as String, b['price_decimal'] as String);
      if (byPrice != 0) return byPrice;
      return _compareString(
        a['quantity_decimal'] as String,
        b['quantity_decimal'] as String,
      );
    });
    return rows;
  }

  String _normalizeUtcInstant(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('UTC timestamp is required');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('invalid UTC timestamp: $value');
    }
    return parsed.toUtc().toIso8601String();
  }

  String _normalizeTimeframe(String raw) {
    final value = raw.trim().toLowerCase();
    const aliases = <String, String>{
      '1m': '1m',
      '5m': '5m',
      '15m': '15m',
      '1h': '1h',
      '4h': '4h',
      '1d': '1d',
      '1w': '1w',
      '1min': '1m',
      '5min': '5m',
      '15min': '15m',
      '60m': '1h',
      '240m': '4h',
      '1day': '1d',
      '1week': '1w',
    };
    final normalized = aliases[value];
    if (normalized == null) {
      throw FormatException('unsupported timeframe: $raw');
    }
    return normalized;
  }

  int _compareCandles(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTimeframe =
        _compareTimeframe(a['timeframe'] as String, b['timeframe'] as String);
    if (byTimeframe != 0) return byTimeframe;
    final byClose = _compareString(
      a['close_time_utc'] as String,
      b['close_time_utc'] as String,
    );
    if (byClose != 0) return byClose;
    return _compareString(
      a['open_time_utc'] as String,
      b['open_time_utc'] as String,
    );
  }

  int _compareTimeframe(String left, String right) {
    final leftIndex = requiredTimeframes.indexOf(left);
    final rightIndex = requiredTimeframes.indexOf(right);
    if (leftIndex == -1 || rightIndex == -1) {
      return _compareString(left, right);
    }
    return leftIndex.compareTo(rightIndex);
  }

  int _compareTrades(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTime = _compareString(
      a['timestamp_utc'] as String,
      b['timestamp_utc'] as String,
    );
    if (byTime != 0) return byTime;
    final bySide = _compareString(a['side'] as String, b['side'] as String);
    if (bySide != 0) return bySide;
    final byPrice = _compareString(
        a['price_decimal'] as String, b['price_decimal'] as String);
    if (byPrice != 0) return byPrice;
    return _compareString(
      a['quantity_decimal'] as String,
      b['quantity_decimal'] as String,
    );
  }

  String _normalizeTradeSide(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'buy' || value == 'sell') return value;
    throw FormatException('unsupported trade side: $raw');
  }

  String _normalizeOrderBookSide(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'bid' || value == 'ask') return value;
    throw FormatException('unsupported orderbook side: $raw');
  }

  String _normalizeLiquidityKind(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'external' || value == 'internal' || value == 'liquidation') {
      return value;
    }
    throw FormatException('unsupported liquidity kind: $raw');
  }

  String _normalizeLiquiditySide(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'buyside' || value == 'sellside') return value;
    throw FormatException('unsupported liquidity side: $raw');
  }

  String _normalizeSession(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'asia') return 'asia';
    if (value == 'london') return 'london';
    if (value == 'newyork' || value == 'new_york' || value == 'ny') {
      return 'newyork';
    }
    throw FormatException('unsupported session: $raw');
  }

  int _compareString(String left, String right) => left.compareTo(right);

  String _normalizeDecimal(
    String raw, {
    required int scale,
    bool allowNegative = false,
  }) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('decimal value is required');
    }
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
      throw FormatException('invalid decimal value: $raw');
    }
    final negative = value.startsWith('-');
    if (negative && !allowNegative) {
      throw FormatException('negative decimal is not allowed: $raw');
    }
    final unsigned = negative ? value.substring(1) : value;
    final parts = unsigned.split('.');
    final wholeRaw = parts[0].replaceFirst(RegExp(r'^0+'), '');
    final whole = wholeRaw.isEmpty ? '0' : wholeRaw;
    var fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > scale) {
      fraction = fraction.substring(0, scale);
    }
    if (fraction.length < scale) {
      fraction = fraction.padRight(scale, '0');
    }
    final result = '$whole.$fraction';
    if (negative && result != '0.${'0' * scale}') {
      return '-$result';
    }
    return result;
  }
}
