import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_market_snapshot_models.dart';
import 'bingx_futures_market_snapshot_service.dart';

enum BingxTrendDirection { bullish, bearish, neutral }

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
  final String tradeImbalanceRatioDecimal;
  final String openInterestDeltaDecimal;
  final String sessionNetDeltaDecimal;
  final String sessionImbalanceRatioDecimal;
  final bool sessionEvidenceComplete;
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
    required this.tradeImbalanceRatioDecimal,
    required this.openInterestDeltaDecimal,
    required this.sessionNetDeltaDecimal,
    required this.sessionImbalanceRatioDecimal,
    this.sessionEvidenceComplete = true,
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
  final double whaleProximityBps;

  const BingxFuturesFeatureExtractorService({
    this.liqLen = 7,
    this.liqMar = 10 / 6.9,
    this.maxTrackedLevelsPerSide = 3,
    this.whaleProximityBps = 10.0,
  });

  BingxFuturesFeatureExtractionResult extract(
    BingxFuturesMarketSnapshotDigest snapshot, {
    String strategyVersion = bingxLiquidityStrategyVersion,
  }) {
    if (strategyVersion != bingxLiquidityStrategyVersion &&
        strategyVersion != bingxHourlyLiquidityStrategyVersion &&
        strategyVersion != bingxPrebreachLineStrategyVersion) {
      throw const FormatException('unsupported liquidity strategy');
    }
    final candles = _readCandles(snapshot.normalizedSnapshot);
    final candles15m =
        candles.where((c) => c.timeframe == '15m').toList()
          ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    final candles5m =
        candles.where((c) => c.timeframe == '5m').toList()
          ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    final candles4h =
        candles.where((c) => c.timeframe == '4h').toList()
          ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    final candles1h =
        candles.where((c) => c.timeframe == '1h').toList()
          ..sort((a, b) => a.closeTimeUtc.compareTo(b.closeTimeUtc));
    if (candles15m.length < 200) {
      throw const FormatException('need at least 200 closed candles on 15m');
    }
    if (candles5m.length < 15) {
      throw const FormatException('need at least 15 closed candles on 5m');
    }

    final ema50 = _ema(candles15m.map((c) => c.close).toList(), period: 50);
    final ema200 = _ema(candles15m.map((c) => c.close).toList(), period: 200);
    final trend =
        ema50 > ema200
            ? BingxTrendDirection.bullish
            : ema50 < ema200
            ? BingxTrendDirection.bearish
            : BingxTrendDirection.neutral;
    final atr14 = _atr(candles5m, period: 14);
    final prebreach = strategyVersion == bingxPrebreachLineStrategyVersion;
    final detectedLevels =
        prebreach
            ? <BingxDetectedLiquidityLevel>[
              for (final timeframe
                  in BingxFuturesMarketSnapshotService.prebreachLineTimeframes)
                ..._detectPivotClusterLevels(
                  candles.where((c) => c.timeframe == timeframe).toList(),
                  timeframe: timeframe,
                  lineBreach: true,
                ),
            ]
            : _detectPivotClusterLevels(
              strategyVersion == bingxHourlyLiquidityStrategyVersion
                  ? candles1h
                  : candles4h,
            );
    if (prebreach) {
      detectedLevels.sort((a, b) {
        final byTimeframe = a.timeframe.compareTo(b.timeframe);
        if (byTimeframe != 0) return byTimeframe;
        final bySide = a.side.compareTo(b.side);
        if (bySide != 0) return bySide;
        return a.anchorAtUtc.compareTo(b.anchorAtUtc);
      });
    }
    final tradeDelta = _tradeDelta(snapshot.normalizedSnapshot);
    final tradeImbalanceRatio = _tradeImbalanceRatio(
      snapshot.normalizedSnapshot,
    );
    final oiDelta = _openInterestDelta(snapshot.normalizedSnapshot);
    final sessionNetDelta = _sessionNetDelta(snapshot.normalizedSnapshot);
    final sessionImbalanceRatio = _sessionImbalanceRatio(
      snapshot.normalizedSnapshot,
    );
    final sessionEvidenceComplete = _sessionEvidenceComplete(
      snapshot.normalizedSnapshot,
    );
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
      'trade_imbalance_ratio_decimal': _fmtDecimal(tradeImbalanceRatio, 8),
      'open_interest_delta_decimal': _fmtDecimal(oiDelta, 8),
      'session_net_delta_decimal': _fmtDecimal(sessionNetDelta, 8),
      'session_imbalance_ratio_decimal': _fmtDecimal(sessionImbalanceRatio, 8),
      'session_evidence_complete': sessionEvidenceComplete,
      'liquidity_levels':
          detectedLevels
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
                  if (prebreach) 'timeframe': item.timeframe,
                  if (prebreach) 'anchor_at_utc': item.anchorAtUtc,
                  if (prebreach) 'confirmed_at_utc': item.confirmedAtUtc,
                  if (prebreach)
                    'observed_through_utc': item.observedThroughUtc,
                },
              )
              .toList(),
      'whale_activations':
          whaleEvents
              .map(
                (item) => <String, dynamic>{
                  'activation_side': item.activationSide,
                  'activation_price_decimal': item.activationPriceDecimal,
                  'activation_size_decimal': item.activationSizeDecimal,
                  'activation_window_start_utc': item.activationWindowStartUtc,
                  'activation_window_end_utc': item.activationWindowEndUtc,
                  'activation_confidence_decimal':
                      item.activationConfidenceDecimal,
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
      tradeImbalanceRatioDecimal: _fmtDecimal(tradeImbalanceRatio, 8),
      openInterestDeltaDecimal: _fmtDecimal(oiDelta, 8),
      sessionNetDeltaDecimal: _fmtDecimal(sessionNetDelta, 8),
      sessionImbalanceRatioDecimal: _fmtDecimal(sessionImbalanceRatio, 8),
      sessionEvidenceComplete: sessionEvidenceComplete,
      liquidityLevels: detectedLevels,
      whaleActivations: whaleEvents,
      hasBuyWhaleActivation: whaleEvents.any(
        (item) => item.activationSide == 'buy',
      ),
      hasSellWhaleActivation: whaleEvents.any(
        (item) => item.activationSide == 'sell',
      ),
    );
  }

  List<BingxDetectedLiquidityLevel> _detectPivotClusterLevels(
    List<_CandleRow> candles, {
    String timeframe = '',
    bool lineBreach = false,
  }) {
    if (lineBreach && !_continuousClosedCandles(candles, timeframe)) {
      throw FormatException('incomplete closed candles on $timeframe');
    }
    final highPivots = <_Pivot>[];
    final lowPivots = <_Pivot>[];
    final buyLevels = <_MutableLevel>[];
    final sellLevels = <_MutableLevel>[];
    String? lastPivotSide;

    for (var i = 0; i < candles.length; i++) {
      final p = i - 1;
      if (p < liqLen) continue;
      final band =
          i < 10 ? 0.0 : _atr(candles, period: 10, endIndex: i) / liqMar;
      if (_isPivotHigh(candles, p, left: liqLen, right: 1)) {
        final pivot = _Pivot(index: p, price: candles[p].high);
        final record =
            !lineBreach ||
            lastPivotSide != 'buyside' ||
            (highPivots.isNotEmpty && pivot.price > highPivots.first.price);
        if (record) {
          if (lineBreach && lastPivotSide == 'buyside') {
            highPivots.removeAt(0);
          }
          highPivots.insert(0, pivot);
          lastPivotSide = 'buyside';
          if (highPivots.length > 50) highPivots.removeLast();
        }
        final cluster = record
            ? highPivots
                .where(
                  (item) =>
                      item.price >= pivot.price - band &&
                      item.price <= pivot.price + band,
                )
                .toList()
            : const <_Pivot>[];
        if (cluster.length > 2 && i >= 10) {
          final anchor = cluster
              .map((e) => e.index)
              .reduce((a, b) => a < b ? a : b);
          final minP = cluster
              .map((e) => e.price)
              .reduce((a, b) => a < b ? a : b);
          final maxP = cluster
              .map((e) => e.price)
              .reduce((a, b) => a > b ? a : b);
          final center =
              lineBreach
                  ? cluster.firstWhere((item) => item.index == anchor).price
                  : (minP + maxP) / 2.0;
          _upsertLevel(
            levels: buyLevels,
            side: 'buyside',
            anchor: anchor,
            center: center,
            top: center + band,
            bottom: center - band,
            pivotCount: cluster.length,
            freezeOnFormation: lineBreach,
            confirmedAtUtc: candles[i].closeTimeUtc,
          );
        }
      }

      if (_isPivotLow(candles, p, left: liqLen, right: 1)) {
        final pivot = _Pivot(index: p, price: candles[p].low);
        final record =
            !lineBreach ||
            lastPivotSide != 'sellside' ||
            (lowPivots.isNotEmpty && pivot.price < lowPivots.first.price);
        if (record) {
          if (lineBreach && lastPivotSide == 'sellside') {
            lowPivots.removeAt(0);
          }
          lowPivots.insert(0, pivot);
          lastPivotSide = 'sellside';
          if (lowPivots.length > 50) lowPivots.removeLast();
        }
        final cluster = record
            ? lowPivots
                .where(
                  (item) =>
                      item.price >= pivot.price - band &&
                      item.price <= pivot.price + band,
                )
                .toList()
            : const <_Pivot>[];
        if (cluster.length > 2 && i >= 10) {
          final anchor = cluster
              .map((e) => e.index)
              .reduce((a, b) => a < b ? a : b);
          final minP = cluster
              .map((e) => e.price)
              .reduce((a, b) => a < b ? a : b);
          final maxP = cluster
              .map((e) => e.price)
              .reduce((a, b) => a > b ? a : b);
          final center =
              lineBreach
                  ? cluster.firstWhere((item) => item.index == anchor).price
                  : (minP + maxP) / 2.0;
          _upsertLevel(
            levels: sellLevels,
            side: 'sellside',
            anchor: anchor,
            center: center,
            top: center + band,
            bottom: center - band,
            pivotCount: cluster.length,
            freezeOnFormation: lineBreach,
            confirmedAtUtc: candles[i].closeTimeUtc,
          );
        }
      }

      for (final level in buyLevels) {
        if (!level.breached &&
            (lineBreach
                ? candles[i].high >= level.center
                : candles[i].high > level.top)) {
          level.breached = true;
          level.breachedIndex = i;
        }
      }
      for (final level in sellLevels) {
        if (!level.breached &&
            (lineBreach
                ? candles[i].low <= level.center
                : candles[i].low < level.bottom)) {
          level.breached = true;
          level.breachedIndex = i;
        }
      }
      for (final levels in [buyLevels, sellLevels]) {
        var activeCount = 0;
        var sweptCount = 0;
        levels.removeWhere((level) {
          if (level.breached) {
            sweptCount++;
            return sweptCount > maxTrackedLevelsPerSide;
          }
          activeCount++;
          return activeCount > maxTrackedLevelsPerSide;
        });
      }
    }

    final activeBuyside =
        buyLevels.where((item) => !item.breached).toList()
          ..sort((a, b) => b.center.compareTo(a.center));
    final activeSellside =
        sellLevels.where((item) => !item.breached).toList()
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
          timeframe: timeframe,
          anchorAtUtc:
              timeframe.isEmpty ? '' : candles[item.anchorIndex].closeTimeUtc,
          confirmedAtUtc: item.confirmedAtUtc,
          observedThroughUtc:
              timeframe.isEmpty ? '' : candles.last.closeTimeUtc,
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
          timeframe: timeframe,
          anchorAtUtc:
              timeframe.isEmpty ? '' : candles[item.anchorIndex].closeTimeUtc,
          confirmedAtUtc: item.confirmedAtUtc,
          observedThroughUtc:
              timeframe.isEmpty ? '' : candles.last.closeTimeUtc,
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

  bool _continuousClosedCandles(List<_CandleRow> candles, String timeframe) {
    final interval = switch (timeframe) {
      '5m' => const Duration(minutes: 5),
      '15m' => const Duration(minutes: 15),
      '30m' => const Duration(minutes: 30),
      '1h' => const Duration(hours: 1),
      '4h' => const Duration(hours: 4),
      '1d' => const Duration(days: 1),
      _ => null,
    };
    if (interval == null || candles.length < liqLen * 3) return false;
    DateTime? previous;
    for (final candle in candles) {
      final close = DateTime.tryParse(candle.closeTimeUtc)?.toUtc();
      if (close == null ||
          !candle.closeTimeUtc.endsWith('Z') ||
          (previous != null && close.difference(previous) != interval)) {
        return false;
      }
      previous = close;
    }
    return true;
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
    final tradeRows =
        tradesRaw.map((item) => Map<String, dynamic>.from(item as Map)).toList()
          ..sort(
            (a, b) => (a['timestamp_utc'] as String).compareTo(
              b['timestamp_utc'] as String,
            ),
          );
    final quantities =
        tradeRows
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
      final byTime = a.activationWindowStartUtc.compareTo(
        b.activationWindowStartUtc,
      );
      if (byTime != 0) return byTime;
      final bySide = a.activationSide.compareTo(b.activationSide);
      if (bySide != 0) return bySide;
      return a.activationPriceDecimal.compareTo(b.activationPriceDecimal);
    });
    return events;
  }

  List<_LevelCandidate> _readLiquidityFromSnapshot(
    Map<String, dynamic> snapshot,
  ) {
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

  double _tradeImbalanceRatio(Map<String, dynamic> snapshot) {
    final raw = snapshot['trades'];
    if (raw is! List) return 0;
    var buyNotional = 0.0;
    var sellNotional = 0.0;
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      final price = _parseDecimal(map['price_decimal'] as String);
      final quantity = _parseDecimal(map['quantity_decimal'] as String);
      final notional = price * quantity;
      final side = (map['side'] as String).toLowerCase();
      if (side == 'buy') {
        buyNotional += notional;
      } else if (side == 'sell') {
        sellNotional += notional;
      }
    }
    final total = buyNotional + sellNotional;
    if (total <= 0) return 0;
    return (buyNotional - sellNotional) / total;
  }

  double _openInterestDelta(Map<String, dynamic> snapshot) {
    final raw = snapshot['open_interest'];
    if (raw is! List || raw.length < 2) return 0;
    final rows =
        raw.map((item) => Map<String, dynamic>.from(item as Map)).toList()
          ..sort(
            (a, b) => (a['timestamp_utc'] as String).compareTo(
              b['timestamp_utc'] as String,
            ),
          );
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

  double _sessionImbalanceRatio(Map<String, dynamic> snapshot) {
    final raw = snapshot['session_volumes'];
    if (raw is! List) return 0;
    var volume = 0.0;
    var delta = 0.0;
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      volume += _parseDecimal(map['volume_decimal'] as String);
      delta += _parseDecimal(map['delta_decimal'] as String);
    }
    if (volume <= 0) return 0;
    return delta / volume;
  }

  bool _sessionEvidenceComplete(Map<String, dynamic> snapshot) {
    final metadata = snapshot['metadata'];
    return metadata is Map<String, dynamic> &&
        metadata['session_evidence_state'] == 'complete';
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

  double _atr(List<_CandleRow> candles, {required int period, int? endIndex}) {
    final end = endIndex ?? candles.length - 1;
    if (end < period || end >= candles.length) {
      throw FormatException('not enough candles for ATR$period');
    }
    final trueRanges = <double>[];
    for (var i = end - period + 1; i <= end; i++) {
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
    bool freezeOnFormation = false,
    String confirmedAtUtc = '',
  }) {
    final existing =
        levels.where((item) => item.anchorIndex == anchor).toList();
    if (existing.isNotEmpty) {
      final level = existing.first;
      if (level.breached) return;
      if (freezeOnFormation) return;
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
        confirmedAtUtc: confirmedAtUtc,
      ),
    );
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

  const _Pivot({required this.index, required this.price});
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
  final String confirmedAtUtc;

  _MutableLevel({
    required this.side,
    required this.anchorIndex,
    required this.center,
    required this.top,
    required this.bottom,
    required this.pivotCount,
    required this.confirmedAtUtc,
  }) : breached = false,
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
