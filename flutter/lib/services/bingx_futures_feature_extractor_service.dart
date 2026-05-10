import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bingx_futures_market_snapshot_service.dart';

enum BingxTrendDirection {
  bullish,
  bearish,
  neutral,
}

class BingxDetectedLiquidityLevel {
  final String side; // buyside | sellside
  final String levelClass; // external | internal
  final String centerPriceDecimal;
  final String zoneTopDecimal;
  final String zoneBottomDecimal;
  final int pivotCount;
  final bool breached;
  final int anchorIndex;
  final int? breachedIndex;

  const BingxDetectedLiquidityLevel({
    required this.side,
    required this.levelClass,
    required this.centerPriceDecimal,
    required this.zoneTopDecimal,
    required this.zoneBottomDecimal,
    required this.pivotCount,
    required this.breached,
    required this.anchorIndex,
    required this.breachedIndex,
  });
}

class BingxWhaleActivationEvent {
  final String activationSide; // buy | sell
  final String activationPriceDecimal;
  final String activationSizeDecimal;
  final String activationWindowStartUtc;
  final String activationWindowEndUtc;
  final String activationConfidenceDecimal;
  final String linkedLiquiditySide; // buyside | sellside
  final String linkedLiquidityClass; // external | internal

  const BingxWhaleActivationEvent({
    required this.activationSide,
    required this.activationPriceDecimal,
    required this.activationSizeDecimal,
    required this.activationWindowStartUtc,
    required this.activationWindowEndUtc,
    required this.activationConfidenceDecimal,
    required this.linkedLiquiditySide,
    required this.linkedLiquidityClass,
  });
}

class BingxFuturesFeatureExtractionResult {
  final String ruleSet;
  final String marketSnapshotHashHex;
  final String canonicalJson;
  final String featureHashHex;
  final BingxTrendDirection trendDirection;
  final String ema50m15Decimal;
  final String ema200m15Decimal;
  final String atr14m5Decimal;
  final String tradeDeltaDecimal;
  final String openInterestDeltaDecimal;
  final String sessionNetDeltaDecimal;
  final List<BingxDetectedLiquidityLevel> liquidityLevels;
  final List<BingxWhaleActivationEvent> whaleActivations;
  final bool hasBuyWhaleActivation;
  final bool hasSellWhaleActivation;

  const BingxFuturesFeatureExtractionResult({
    required this.ruleSet,
    required this.marketSnapshotHashHex,
    required this.canonicalJson,
    required this.featureHashHex,
    required this.trendDirection,
    required this.ema50m15Decimal,
    required this.ema200m15Decimal,
    required this.atr14m5Decimal,
    required this.tradeDeltaDecimal,
    required this.openInterestDeltaDecimal,
    required this.sessionNetDeltaDecimal,
    required this.liquidityLevels,
    required this.whaleActivations,
    required this.hasBuyWhaleActivation,
    required this.hasSellWhaleActivation,
  });
}

class BingxFuturesFeatureExtractorService {
  final int liqLen;
  final double liqMar;
  final int maxTrackedLevelsPerSide;
  final double buyPctBreak;
  final double sellPctBreak;
  final double whaleProximityBps;

  const BingxFuturesFeatureExtractorService({
    this.liqLen = 7,
    this.liqMar = 10 / 6.9,
    this.maxTrackedLevelsPerSide = 3,
    this.buyPctBreak = 1.0,
    this.sellPctBreak = 1.0,
    this.whaleProximityBps = 10.0,
  });

  BingxFuturesFeatureExtractionResult extract(
    BingxFuturesMarketSnapshotDigest snapshot,
  ) {
    final candles = _readCandles(snapshot.normalizedSnapshot);
    final candles15m = candles.where((c) => c.timeframe == '15m').toList()
      ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    final candles5m = candles.where((c) => c.timeframe == '5m').toList()
      ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    if (candles15m.length < 200) {
      throw const FormatException('need at least 200 closed candles on 15m');
    }
    if (candles5m.length < 15) {
      throw const FormatException('need at least 15 closed candles on 5m');
    }

    final ema50 = _ema(candles15m.map((c) => c.close).toList(), period: 50);
    final ema200 = _ema(candles15m.map((c) => c.close).toList(), period: 200);
    final trend = ema50 > ema200
        ? BingxTrendDirection.bullish
        : ema50 < ema200
            ? BingxTrendDirection.bearish
            : BingxTrendDirection.neutral;
    final atr14 = _atr(candles5m, period: 14);
    final atr10 = _atr(candles5m, period: 10);

    final detectedLevels = _detectPivotClusterLevels(candles5m, atr10);
    final tradeDelta = _tradeDelta(snapshot.normalizedSnapshot);
    final oiDelta = _openInterestDelta(snapshot.normalizedSnapshot);
    final sessionNetDelta = _sessionNetDelta(snapshot.normalizedSnapshot);
    final whaleEvents = _detectWhaleActivations(
      snapshot: snapshot.normalizedSnapshot,
      levels: detectedLevels,
      oiDelta: oiDelta,
      sessionNetDelta: sessionNetDelta,
    );

    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'rule_set': 'tvh_v1',
      'market_snapshot_hash_hex': snapshot.marketSnapshotHashHex,
      'trend': trend.name,
      'ema50_15m_decimal': _fmtDecimal(ema50, 8),
      'ema200_15m_decimal': _fmtDecimal(ema200, 8),
      'atr14_5m_decimal': _fmtDecimal(atr14, 8),
      'trade_delta_decimal': _fmtDecimal(tradeDelta, 8),
      'open_interest_delta_decimal': _fmtDecimal(oiDelta, 8),
      'session_net_delta_decimal': _fmtDecimal(sessionNetDelta, 8),
      'liquidity_levels': detectedLevels
          .map(
            (item) => <String, dynamic>{
              'side': item.side,
              'class': item.levelClass,
              'center_price_decimal': item.centerPriceDecimal,
              'zone_top_decimal': item.zoneTopDecimal,
              'zone_bottom_decimal': item.zoneBottomDecimal,
              'pivot_count': item.pivotCount,
              'breached': item.breached,
              'anchor_index': item.anchorIndex,
              'breached_index': item.breachedIndex,
            },
          )
          .toList(),
      'whale_activations': whaleEvents
          .map(
            (item) => <String, dynamic>{
              'activation_side': item.activationSide,
              'activation_price_decimal': item.activationPriceDecimal,
              'activation_size_decimal': item.activationSizeDecimal,
              'activation_window_start_utc': item.activationWindowStartUtc,
              'activation_window_end_utc': item.activationWindowEndUtc,
              'activation_confidence_decimal': item.activationConfidenceDecimal,
              'linked_liquidity_side': item.linkedLiquiditySide,
              'linked_liquidity_class': item.linkedLiquidityClass,
            },
          )
          .toList(),
    });
    final featureHashHex = sha256.convert(utf8.encode(canonical)).toString();

    return BingxFuturesFeatureExtractionResult(
      ruleSet: 'tvh_v1',
      marketSnapshotHashHex: snapshot.marketSnapshotHashHex,
      canonicalJson: canonical,
      featureHashHex: featureHashHex,
      trendDirection: trend,
      ema50m15Decimal: _fmtDecimal(ema50, 8),
      ema200m15Decimal: _fmtDecimal(ema200, 8),
      atr14m5Decimal: _fmtDecimal(atr14, 8),
      tradeDeltaDecimal: _fmtDecimal(tradeDelta, 8),
      openInterestDeltaDecimal: _fmtDecimal(oiDelta, 8),
      sessionNetDeltaDecimal: _fmtDecimal(sessionNetDelta, 8),
      liquidityLevels: detectedLevels,
      whaleActivations: whaleEvents,
      hasBuyWhaleActivation:
          whaleEvents.any((item) => item.activationSide == 'buy'),
      hasSellWhaleActivation:
          whaleEvents.any((item) => item.activationSide == 'sell'),
    );
  }

  List<BingxDetectedLiquidityLevel> _detectPivotClusterLevels(
    List<_CandleRow> candles5m,
    double atr10,
  ) {
    final band = atr10 / liqMar;
    final highPivots = <_Pivot>[];
    final lowPivots = <_Pivot>[];
    final buyLevels = <_MutableLevel>[];
    final sellLevels = <_MutableLevel>[];

    for (var i = 0; i < candles5m.length; i++) {
      final p = i - 1;
      if (p < liqLen || i >= candles5m.length) continue;
      if (_isPivotHigh(candles5m, p, left: liqLen, right: 1)) {
        final pivot = _Pivot(index: p, price: candles5m[p].high);
        highPivots.insert(0, pivot);
        if (highPivots.length > 50) highPivots.removeLast();
        final cluster = highPivots
            .where(
              (item) =>
                  item.price >= pivot.price - band &&
                  item.price <= pivot.price + band,
            )
            .toList();
        if (cluster.length > 2) {
          final anchor =
              cluster.map((e) => e.index).reduce((a, b) => a < b ? a : b);
          final minP =
              cluster.map((e) => e.price).reduce((a, b) => a < b ? a : b);
          final maxP =
              cluster.map((e) => e.price).reduce((a, b) => a > b ? a : b);
          final center = (minP + maxP) / 2.0;
          _upsertLevel(
            levels: buyLevels,
            side: 'buyside',
            anchor: anchor,
            center: center,
            top: center + band,
            bottom: center - band,
            pivotCount: cluster.length,
          );
        }
      }

      if (_isPivotLow(candles5m, p, left: liqLen, right: 1)) {
        final pivot = _Pivot(index: p, price: candles5m[p].low);
        lowPivots.insert(0, pivot);
        if (lowPivots.length > 50) lowPivots.removeLast();
        final cluster = lowPivots
            .where(
              (item) =>
                  item.price >= pivot.price - band &&
                  item.price <= pivot.price + band,
            )
            .toList();
        if (cluster.length > 2) {
          final anchor =
              cluster.map((e) => e.index).reduce((a, b) => a < b ? a : b);
          final minP =
              cluster.map((e) => e.price).reduce((a, b) => a < b ? a : b);
          final maxP =
              cluster.map((e) => e.price).reduce((a, b) => a > b ? a : b);
          final center = (minP + maxP) / 2.0;
          _upsertLevel(
            levels: sellLevels,
            side: 'sellside',
            anchor: anchor,
            center: center,
            top: center + band,
            bottom: center - band,
            pivotCount: cluster.length,
          );
        }
      }

      for (final level in buyLevels) {
        if (!level.breached && candles5m[i].high > level.top) {
          level.breached = true;
          level.breachedIndex = i;
        }
      }
      for (final level in sellLevels) {
        if (!level.breached && candles5m[i].low < level.bottom) {
          level.breached = true;
          level.breachedIndex = i;
        }
      }
    }

    final activeBuyside = buyLevels.where((item) => !item.breached).toList()
      ..sort((a, b) => b.center.compareTo(a.center));
    final activeSellside = sellLevels.where((item) => !item.breached).toList()
      ..sort((a, b) => a.center.compareTo(b.center));

    String classForBuy(_MutableLevel level) {
      if (activeBuyside.isNotEmpty && identical(level, activeBuyside.first)) {
        return 'external';
      }
      return 'internal';
    }

    String classForSell(_MutableLevel level) {
      if (activeSellside.isNotEmpty && identical(level, activeSellside.first)) {
        return 'external';
      }
      return 'internal';
    }

    final combined = <BingxDetectedLiquidityLevel>[
      ...buyLevels.map(
        (item) => BingxDetectedLiquidityLevel(
          side: item.side,
          levelClass: classForBuy(item),
          centerPriceDecimal: _fmtDecimal(item.center, 8),
          zoneTopDecimal: _fmtDecimal(item.top, 8),
          zoneBottomDecimal: _fmtDecimal(item.bottom, 8),
          pivotCount: item.pivotCount,
          breached: item.breached,
          anchorIndex: item.anchorIndex,
          breachedIndex: item.breachedIndex,
        ),
      ),
      ...sellLevels.map(
        (item) => BingxDetectedLiquidityLevel(
          side: item.side,
          levelClass: classForSell(item),
          centerPriceDecimal: _fmtDecimal(item.center, 8),
          zoneTopDecimal: _fmtDecimal(item.top, 8),
          zoneBottomDecimal: _fmtDecimal(item.bottom, 8),
          pivotCount: item.pivotCount,
          breached: item.breached,
          anchorIndex: item.anchorIndex,
          breachedIndex: item.breachedIndex,
        ),
      ),
    ];
    combined.sort((a, b) {
      final bySide = a.side.compareTo(b.side);
      if (bySide != 0) return bySide;
      final byClass = a.levelClass.compareTo(b.levelClass);
      if (byClass != 0) return byClass;
      final byCenter = a.centerPriceDecimal.compareTo(b.centerPriceDecimal);
      if (byCenter != 0) return byCenter;
      return a.anchorIndex.compareTo(b.anchorIndex);
    });
    return combined;
  }

  List<BingxWhaleActivationEvent> _detectWhaleActivations({
    required Map<String, dynamic> snapshot,
    required List<BingxDetectedLiquidityLevel> levels,
    required double oiDelta,
    required double sessionNetDelta,
  }) {
    final tradesRaw = snapshot['trades'];
    if (tradesRaw is! List || tradesRaw.isEmpty) {
      return const <BingxWhaleActivationEvent>[];
    }
    final tradeRows = tradesRaw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList()
      ..sort((a, b) => (a['timestamp_utc'] as String)
          .compareTo(b['timestamp_utc'] as String));
    final quantities = tradeRows
        .map((item) => _parseDecimal(item['quantity_decimal'] as String))
        .toList()
      ..sort();
    final idx90 = ((quantities.length - 1) * 0.9).floor();
    final q90 = quantities[idx90];
    final priceCandidates = <_LevelCandidate>[
      ...levels.map(
        (item) => _LevelCandidate(
          price: _parseDecimal(item.centerPriceDecimal),
          side: item.side,
          levelClass: item.levelClass,
        ),
      ),
      ..._readLiquidityFromSnapshot(snapshot).map(
        (item) => _LevelCandidate(
          price: item.price,
          side: item.side,
          levelClass: item.levelClass,
        ),
      ),
    ];
    final events = <BingxWhaleActivationEvent>[];
    final seen = <String>{};
    for (final trade in tradeRows) {
      final quantity = _parseDecimal(trade['quantity_decimal'] as String);
      if (quantity < q90) continue;
      final price = _parseDecimal(trade['price_decimal'] as String);
      final timestamp = trade['timestamp_utc'] as String;
      final side = (trade['side'] as String).toLowerCase();
      _LevelCandidate? nearest;
      var nearestDistance = double.infinity;
      for (final candidate in priceCandidates) {
        final distanceBps =
            ((price - candidate.price).abs() / candidate.price) * 10000.0;
        if (distanceBps <= whaleProximityBps && distanceBps < nearestDistance) {
          nearestDistance = distanceBps;
          nearest = candidate;
        }
      }
      if (nearest == null) continue;

      final oiAligned = side == 'buy' ? oiDelta >= 0 : oiDelta <= 0;
      final sessionAligned =
          side == 'buy' ? sessionNetDelta >= 0 : sessionNetDelta <= 0;
      var confidence = 0.5;
      if (oiAligned) confidence += 0.2;
      if (sessionAligned) confidence += 0.2;
      if (nearest.levelClass == 'external') confidence += 0.1;
      if (confidence > 1.0) confidence = 1.0;
      if (confidence < 0.7) continue;
      final key = '${side}_${timestamp}_${nearest.side}_${nearest.levelClass}';
      if (!seen.add(key)) continue;
      final start = DateTime.parse(timestamp).toUtc();
      final end = start.add(const Duration(minutes: 1));
      events.add(
        BingxWhaleActivationEvent(
          activationSide: side,
          activationPriceDecimal: _fmtDecimal(price, 8),
          activationSizeDecimal: _fmtDecimal(quantity, 8),
          activationWindowStartUtc: start.toIso8601String(),
          activationWindowEndUtc: end.toIso8601String(),
          activationConfidenceDecimal: _fmtDecimal(confidence, 4),
          linkedLiquiditySide: nearest.side,
          linkedLiquidityClass: nearest.levelClass,
        ),
      );
    }
    events.sort((a, b) {
      final byTime =
          a.activationWindowStartUtc.compareTo(b.activationWindowStartUtc);
      if (byTime != 0) return byTime;
      final bySide = a.activationSide.compareTo(b.activationSide);
      if (bySide != 0) return bySide;
      return a.activationPriceDecimal.compareTo(b.activationPriceDecimal);
    });
    return events;
  }

  List<_LevelCandidate> _readLiquidityFromSnapshot(
      Map<String, dynamic> snapshot) {
    final raw = snapshot['liquidity_levels'];
    if (raw is! List) return const <_LevelCandidate>[];
    final rows = <_LevelCandidate>[];
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      rows.add(
        _LevelCandidate(
          price: _parseDecimal(map['price_decimal'] as String),
          side: map['side'] as String,
          levelClass: map['kind'] == 'external' ? 'external' : 'internal',
        ),
      );
    }
    return rows;
  }

  double _tradeDelta(Map<String, dynamic> snapshot) {
    final raw = snapshot['trades'];
    if (raw is! List) return 0;
    var delta = 0.0;
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      final qty = _parseDecimal(map['quantity_decimal'] as String);
      final side = (map['side'] as String).toLowerCase();
      delta += side == 'buy' ? qty : -qty;
    }
    return delta;
  }

  double _openInterestDelta(Map<String, dynamic> snapshot) {
    final raw = snapshot['open_interest'];
    if (raw is! List || raw.length < 2) return 0;
    final rows = raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList()
      ..sort((a, b) => (a['timestamp_utc'] as String)
          .compareTo(b['timestamp_utc'] as String));
    final first = _parseDecimal(rows.first['open_interest_decimal'] as String);
    final last = _parseDecimal(rows.last['open_interest_decimal'] as String);
    return last - first;
  }

  double _sessionNetDelta(Map<String, dynamic> snapshot) {
    final raw = snapshot['session_volumes'];
    if (raw is! List) return 0;
    var sum = 0.0;
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      sum += _parseDecimal(map['delta_decimal'] as String);
    }
    return sum;
  }

  List<_CandleRow> _readCandles(Map<String, dynamic> snapshot) {
    final raw = snapshot['candles'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('snapshot candles are required');
    }
    return raw.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return _CandleRow(
        timeframe: map['timeframe'] as String,
        openTimeUtc: map['open_time_utc'] as String,
        closeTimeUtc: map['close_time_utc'] as String,
        open: _parseDecimal(map['open_decimal'] as String),
        high: _parseDecimal(map['high_decimal'] as String),
        low: _parseDecimal(map['low_decimal'] as String),
        close: _parseDecimal(map['close_decimal'] as String),
      );
    }).toList();
  }

  double _atr(List<_CandleRow> candles, {required int period}) {
    if (candles.length <= period) {
      throw FormatException('not enough candles for ATR$period');
    }
    final trueRanges = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final current = candles[i];
      final prevClose = candles[i - 1].close;
      final tr1 = current.high - current.low;
      final tr2 = (current.high - prevClose).abs();
      final tr3 = (current.low - prevClose).abs();
      trueRanges.add([tr1, tr2, tr3].reduce((a, b) => a > b ? a : b));
    }
    final tail = trueRanges.sublist(trueRanges.length - period);
    final sum = tail.fold<double>(0, (acc, v) => acc + v);
    return sum / period;
  }

  double _ema(List<double> values, {required int period}) {
    if (values.length < period) {
      throw FormatException('not enough values for EMA$period');
    }
    final k = 2.0 / (period + 1.0);
    var ema = values.take(period).reduce((a, b) => a + b) / period;
    for (var i = period; i < values.length; i++) {
      ema = (values[i] * k) + (ema * (1.0 - k));
    }
    return ema;
  }

  bool _isPivotHigh(
    List<_CandleRow> candles,
    int pivotIndex, {
    required int left,
    required int right,
  }) {
    if (pivotIndex - left < 0 || pivotIndex + right >= candles.length) {
      return false;
    }
    final pivot = candles[pivotIndex].high;
    for (var i = 1; i <= left; i++) {
      if (pivot < candles[pivotIndex - i].high) return false;
    }
    for (var i = 1; i <= right; i++) {
      if (pivot <= candles[pivotIndex + i].high) return false;
    }
    return true;
  }

  bool _isPivotLow(
    List<_CandleRow> candles,
    int pivotIndex, {
    required int left,
    required int right,
  }) {
    if (pivotIndex - left < 0 || pivotIndex + right >= candles.length) {
      return false;
    }
    final pivot = candles[pivotIndex].low;
    for (var i = 1; i <= left; i++) {
      if (pivot > candles[pivotIndex - i].low) return false;
    }
    for (var i = 1; i <= right; i++) {
      if (pivot >= candles[pivotIndex + i].low) return false;
    }
    return true;
  }

  void _upsertLevel({
    required List<_MutableLevel> levels,
    required String side,
    required int anchor,
    required double center,
    required double top,
    required double bottom,
    required int pivotCount,
  }) {
    final existing =
        levels.where((item) => item.anchorIndex == anchor).toList();
    if (existing.isNotEmpty) {
      final level = existing.first;
      level.center = center;
      level.top = top;
      level.bottom = bottom;
      level.pivotCount = pivotCount;
      return;
    }
    levels.insert(
      0,
      _MutableLevel(
        side: side,
        anchorIndex: anchor,
        center: center,
        top: top,
        bottom: bottom,
        pivotCount: pivotCount,
      ),
    );
    if (levels.length > maxTrackedLevelsPerSide) {
      levels.removeRange(maxTrackedLevelsPerSide, levels.length);
    }
  }

  double _parseDecimal(String value) => double.parse(value);

  String _fmtDecimal(double value, int scale) {
    final fixed = value.toStringAsFixed(scale);
    return fixed;
  }
}

class _CandleRow {
  final String timeframe;
  final String openTimeUtc;
  final String closeTimeUtc;
  final double open;
  final double high;
  final double low;
  final double close;

  const _CandleRow({
    required this.timeframe,
    required this.openTimeUtc,
    required this.closeTimeUtc,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

class _Pivot {
  final int index;
  final double price;

  const _Pivot({
    required this.index,
    required this.price,
  });
}

class _MutableLevel {
  final String side;
  final int anchorIndex;
  double center;
  double top;
  double bottom;
  int pivotCount;
  bool breached;
  int? breachedIndex;

  _MutableLevel({
    required this.side,
    required this.anchorIndex,
    required this.center,
    required this.top,
    required this.bottom,
    required this.pivotCount,
  })  : breached = false,
        breachedIndex = null;
}

class _LevelCandidate {
  final double price;
  final String side;
  final String levelClass;

  const _LevelCandidate({
    required this.price,
    required this.side,
    required this.levelClass,
  });
}
