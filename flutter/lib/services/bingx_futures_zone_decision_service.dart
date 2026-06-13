class BingxFuturesZoneDecisionInput {
  final num midPrice;
  final String fallbackSide;
  final String? requiredSide;
  final List<num> microHighs;
  final List<num> microLows;
  final List<num> microCloses;
  final List<num> macroHighs;
  final List<num> macroLows;
  final List<num> higherHighs;
  final List<num> higherLows;
  final List<num> higherCloses;
  final List<num> dailyHighs;
  final List<num> dailyLows;
  final List<num> dailyCloses;
  final List<num> weeklyHighs;
  final List<num> weeklyLows;
  final List<num> weeklyCloses;
  final List<num> liquidationSellLevels;
  final List<num> liquidationBuyLevels;
  final num oiDeltaPct;
  final num sessionDominancePct;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;

  const BingxFuturesZoneDecisionInput({
    required this.midPrice,
    required this.fallbackSide,
    this.requiredSide,
    required this.microHighs,
    required this.microLows,
    this.microCloses = const <num>[],
    required this.macroHighs,
    required this.macroLows,
    required this.higherHighs,
    required this.higherLows,
    required this.higherCloses,
    required this.dailyHighs,
    required this.dailyLows,
    required this.dailyCloses,
    required this.weeklyHighs,
    required this.weeklyLows,
    this.weeklyCloses = const <num>[],
    this.liquidationSellLevels = const <num>[],
    this.liquidationBuyLevels = const <num>[],
    this.oiDeltaPct = 0,
    this.sessionDominancePct = 0,
    required this.recentMicroBars,
    required this.zoneNearBps,
    required this.zoneFarBps,
  });
}

class BingxFuturesZoneDecisionResult {
  final String side;
  final String zoneSide;
  final num zoneLow;
  final num zoneHigh;
  final String source;
  final String sideReason;
  final num olderHigh;
  final num olderLow;
  final num recentHigh;
  final num recentLow;
  final bool sweepUp;
  final bool sweepDown;
  final String trend4h;
  final String trend1d;
  final int contextBias;
  final bool aligned;
  final bool contrarian;
  final bool needsFartherRetest;
  final num rangePct1h;
  final num rangePct4h;
  final num rangePct1d;
  final num rangePct1w;
  final num targetRetestPct;
  final num? externalSellRetest;
  final num? externalBuyRetest;
  final String anchorSource;
  final bool anchorExecutable;
  final String anchorLifecycle;
  final int strength;
  final bool usedFallback;

  const BingxFuturesZoneDecisionResult({
    required this.side,
    required this.zoneSide,
    required this.zoneLow,
    required this.zoneHigh,
    required this.source,
    required this.sideReason,
    required this.olderHigh,
    required this.olderLow,
    required this.recentHigh,
    required this.recentLow,
    required this.sweepUp,
    required this.sweepDown,
    required this.trend4h,
    required this.trend1d,
    required this.contextBias,
    required this.aligned,
    required this.contrarian,
    required this.needsFartherRetest,
    required this.rangePct1h,
    required this.rangePct4h,
    required this.rangePct1d,
    required this.rangePct1w,
    required this.targetRetestPct,
    required this.externalSellRetest,
    required this.externalBuyRetest,
    required this.anchorSource,
    required this.anchorExecutable,
    required this.anchorLifecycle,
    required this.strength,
    required this.usedFallback,
  });
}

class _ExternalLevelPoint {
  final num price;
  final num weight;
  final String source;

  const _ExternalLevelPoint({
    required this.price,
    required this.weight,
    required this.source,
  });
}

enum _LiquidityLevelLifecycle {
  fresh,
  sweepOrigin,
  postSweepReaction,
  consumed,
}

class _SwingPivot {
  final int index;
  final num price;
  final _LiquidityLevelLifecycle lifecycle;

  const _SwingPivot({
    required this.index,
    required this.price,
    required this.lifecycle,
  });
}

class _ExternalRetestLevel {
  final num price;
  final String source;
  final num distancePct;

  const _ExternalRetestLevel({
    required this.price,
    required this.source,
    required this.distancePct,
  });
}

class BingxFuturesZoneDecisionService {
  const BingxFuturesZoneDecisionService();

  BingxFuturesZoneDecisionResult decide({
    required BingxFuturesZoneDecisionInput input,
  }) {
    final mid = input.midPrice;
    if (mid <= 0) {
      throw const FormatException('midPrice must be greater than zero');
    }

    if (input.microHighs.length < 20 ||
        input.microLows.length < 20 ||
        input.macroHighs.length < 20 ||
        input.macroLows.length < 20) {
      final fallbackSide =
          _normalizeSide(input.requiredSide ?? input.fallbackSide);
      final nearDelta = mid * (input.zoneNearBps / 10000.0);
      final farDelta = mid * (input.zoneFarBps / 10000.0);
      final zoneLow = fallbackSide == 'buy' ? mid - farDelta : mid + nearDelta;
      final zoneHigh = fallbackSide == 'buy' ? mid - nearDelta : mid + farDelta;
      return BingxFuturesZoneDecisionResult(
        side: fallbackSide,
        zoneSide: fallbackSide == 'buy' ? 'buyside' : 'sellside',
        zoneLow: zoneLow,
        zoneHigh: zoneHigh,
        source: 'fallback_quote',
        sideReason: 'fallback_quote',
        olderHigh: 0,
        olderLow: 0,
        recentHigh: 0,
        recentLow: 0,
        sweepUp: false,
        sweepDown: false,
        trend4h: 'flat',
        trend1d: 'flat',
        contextBias: 0,
        aligned: false,
        contrarian: false,
        needsFartherRetest: false,
        rangePct1h: 0,
        rangePct4h: 0,
        rangePct1d: 0,
        rangePct1w: 0,
        targetRetestPct: 0,
        externalSellRetest: null,
        externalBuyRetest: null,
        anchorSource: 'fallback',
        anchorExecutable: false,
        anchorLifecycle: 'unavailable',
        strength: 0,
        usedFallback: true,
      );
    }

    final microSplit = input.microHighs.length - input.recentMicroBars;
    if (microSplit < 5) {
      throw const FormatException('not enough structure bars');
    }

    final olderMicroHighs = input.microHighs.sublist(0, microSplit);
    final olderMicroLows = input.microLows.sublist(0, microSplit);
    final recentMicroHighs = input.microHighs.sublist(microSplit);
    final recentMicroLows = input.microLows.sublist(microSplit);

    final olderHigh = olderMicroHighs.reduce((a, b) => a > b ? a : b);
    final olderLow = olderMicroLows.reduce((a, b) => a < b ? a : b);
    final recentHigh = recentMicroHighs.reduce((a, b) => a > b ? a : b);
    final recentLow = recentMicroLows.reduce((a, b) => a < b ? a : b);

    final macroHigh = input.macroHighs.reduce((a, b) => a > b ? a : b);
    final macroLow = input.macroLows.reduce((a, b) => a < b ? a : b);
    final macroRange = macroHigh - macroLow;

    final minWidth = mid * 0.0010;
    final maxWidth = mid * 0.0040;
    final widthFromMacro = macroRange * 0.08;
    final width = _clamp(widthFromMacro, minWidth, maxWidth);
    final fallbackWidth = _fallbackZoneWidth(
      mid: mid,
      zoneNearBps: input.zoneNearBps,
      zoneFarBps: input.zoneFarBps,
    );

    final sweepUp = recentHigh > olderHigh;
    final sweepDown = recentLow < olderLow;
    final higherBias = _trendBiasFromCloses(input.higherCloses, window: 12);
    final dailyBias = _trendBiasFromCloses(input.dailyCloses, window: 10);
    final contextBias = higherBias + dailyBias;
    final sideDecision = input.requiredSide == null
        ? _selectAutoSide(
            sweepUp: sweepUp,
            sweepDown: sweepDown,
            higherBias: higherBias,
            dailyBias: dailyBias,
            contextBias: contextBias,
            mid: mid,
            olderHigh: olderHigh,
            olderLow: olderLow,
            recentHigh: recentHigh,
            recentLow: recentLow,
          )
        : (
            side: _normalizeSide(input.requiredSide!),
            reason: 'tvh_side_locked',
          );

    final selectedSide = sideDecision.side;
    final reversalSignal = selectedSide == 'sell' ? sweepUp : sweepDown;
    final confirmedMicroReclaim = _hasConfirmedMicroReclaim(
      side: selectedSide,
      closes: input.microCloses,
      olderHigh: olderHigh,
      olderLow: olderLow,
      sweepUp: sweepUp,
      sweepDown: sweepDown,
    );
    final aligned = (selectedSide == 'buy' && contextBias > 0) ||
        (selectedSide == 'sell' && contextBias < 0);
    final contrarian = (selectedSide == 'buy' && contextBias < 0) ||
        (selectedSide == 'sell' && contextBias > 0);
    final macroVolPct = macroRange / mid;

    num higherRangePct = macroVolPct;
    if (input.higherHighs.isNotEmpty && input.higherLows.isNotEmpty) {
      final higherHigh = input.higherHighs.reduce((a, b) => a > b ? a : b);
      final higherLow = input.higherLows.reduce((a, b) => a < b ? a : b);
      higherRangePct = (higherHigh - higherLow) / mid;
    }
    num dailyRangePct = higherRangePct;
    if (input.dailyHighs.isNotEmpty && input.dailyLows.isNotEmpty) {
      final dayHigh = input.dailyHighs.reduce((a, b) => a > b ? a : b);
      final dayLow = input.dailyLows.reduce((a, b) => a < b ? a : b);
      dailyRangePct = (dayHigh - dayLow) / mid;
    }
    num weeklyRangePct = dailyRangePct;
    if (input.weeklyHighs.isNotEmpty && input.weeklyLows.isNotEmpty) {
      final weekHigh = input.weeklyHighs.reduce((a, b) => a > b ? a : b);
      final weekLow = input.weeklyLows.reduce((a, b) => a < b ? a : b);
      weeklyRangePct = (weekHigh - weekLow) / mid;
    }

    var targetRetestDistancePct = _clamp(
      [
        macroVolPct * 1.9,
        higherRangePct * 0.42,
        dailyRangePct * 0.26,
        weeklyRangePct * 0.14,
      ].reduce((a, b) => a > b ? a : b),
      0.02,
      0.11,
    );
    if (input.oiDeltaPct.abs() >= 0.015) {
      targetRetestDistancePct =
          _clamp(targetRetestDistancePct + 0.006, 0.02, 0.11);
    }
    if (input.sessionDominancePct >= 0.55) {
      targetRetestDistancePct =
          _clamp(targetRetestDistancePct + 0.004, 0.02, 0.11);
    } else if (input.sessionDominancePct > 0 &&
        input.sessionDominancePct <= 0.38) {
      targetRetestDistancePct =
          _clamp(targetRetestDistancePct - 0.003, 0.02, 0.11);
    }
    final needsFartherRetest = (!reversalSignal && !aligned) ||
        (selectedSide == 'sell' && dailyBias > 0) ||
        (selectedSide == 'buy' && dailyBias < 0);
    if (needsFartherRetest) {
      targetRetestDistancePct =
          _clamp(targetRetestDistancePct + 0.012, 0.02, 0.11);
    }

    final externalHighCandidates = <_ExternalLevelPoint>[
      ..._freshSwingLevels(
        highs: input.higherHighs,
        lows: input.higherLows,
        closes: input.higherCloses,
        side: 'high',
        source: '4h_fresh_high',
        weight: 1.00,
      ),
      ..._freshSwingLevels(
        highs: input.dailyHighs,
        lows: input.dailyLows,
        closes: input.dailyCloses,
        side: 'high',
        source: '1d_fresh_high',
        weight: 1.25,
      ),
      ..._freshSwingLevels(
        highs: input.weeklyHighs,
        lows: input.weeklyLows,
        closes: input.weeklyCloses,
        side: 'high',
        source: '1w_fresh_high',
        weight: 1.55,
      ),
    ];
    final externalLowCandidates = <_ExternalLevelPoint>[
      ..._freshSwingLevels(
        highs: input.higherHighs,
        lows: input.higherLows,
        closes: input.higherCloses,
        side: 'low',
        source: '4h_fresh_low',
        weight: 1.00,
      ),
      ..._freshSwingLevels(
        highs: input.dailyHighs,
        lows: input.dailyLows,
        closes: input.dailyCloses,
        side: 'low',
        source: '1d_fresh_low',
        weight: 1.25,
      ),
      ..._freshSwingLevels(
        highs: input.weeklyHighs,
        lows: input.weeklyLows,
        closes: input.weeklyCloses,
        side: 'low',
        source: '1w_fresh_low',
        weight: 1.55,
      ),
    ];
    final externalSellRetest = _selectRetestLevelAbove(
      externalHighCandidates,
      mid,
      minDistancePct: 0.008,
      targetDistancePct: targetRetestDistancePct,
      maxDistancePct: 0.14,
      preferFarther: needsFartherRetest,
    );
    final externalBuyRetest = _selectRetestLevelBelow(
      externalLowCandidates,
      mid,
      minDistancePct: 0.008,
      targetDistancePct: targetRetestDistancePct,
      maxDistancePct: 0.14,
      preferFarther: needsFartherRetest,
    );

    var usedExternalLiquidity = false;
    var anchorSource = 'internal_diagnostic';
    var anchorExecutable = false;
    var anchorLifecycle = 'unavailable';

    num zoneLow;
    num zoneHigh;
    if (selectedSide == 'sell') {
      var anchorHigh = olderHigh;
      if (confirmedMicroReclaim) {
        anchorHigh = recentHigh;
        anchorSource = 'micro_sweep_reclaim';
        anchorExecutable = true;
        anchorLifecycle = 'reclaimed';
      } else if (externalSellRetest != null) {
        anchorHigh = externalSellRetest.price;
        usedExternalLiquidity = true;
        anchorSource = externalSellRetest.source;
        anchorExecutable = true;
        anchorLifecycle = 'fresh';
      }
      if (contrarian && !reversalSignal) {
        zoneLow = anchorHigh - width * 0.15;
        zoneHigh = anchorHigh + width * 0.35;
      } else if (aligned) {
        zoneLow = anchorHigh - width * 0.75;
        zoneHigh = anchorHigh - width * 0.25;
      } else {
        zoneLow = anchorHigh - width * 0.55;
        zoneHigh = anchorHigh - width * 0.05;
      }
      if (zoneHigh <= 0 || zoneLow <= 0 || zoneHigh <= zoneLow) {
        zoneLow = mid + (fallbackWidth * 0.40);
        zoneHigh = mid + (fallbackWidth * 1.00);
      }
      if (zoneHigh < mid) {
        final shift = (mid - zoneHigh) + (mid * 0.0005);
        zoneLow += shift;
        zoneHigh += shift;
      }
    } else {
      var anchorLow = olderLow;
      if (confirmedMicroReclaim) {
        anchorLow = recentLow;
        anchorSource = 'micro_sweep_reclaim';
        anchorExecutable = true;
        anchorLifecycle = 'reclaimed';
      } else if (externalBuyRetest != null) {
        anchorLow = externalBuyRetest.price;
        usedExternalLiquidity = true;
        anchorSource = externalBuyRetest.source;
        anchorExecutable = true;
        anchorLifecycle = 'fresh';
      }
      if (contrarian && !reversalSignal) {
        zoneLow = anchorLow - width * 0.35;
        zoneHigh = anchorLow + width * 0.15;
      } else if (aligned) {
        zoneLow = anchorLow + width * 0.25;
        zoneHigh = anchorLow + width * 0.75;
      } else {
        zoneLow = anchorLow + width * 0.05;
        zoneHigh = anchorLow + width * 0.55;
      }
      if (zoneHigh <= 0 || zoneLow <= 0 || zoneHigh <= zoneLow) {
        zoneLow = mid - (fallbackWidth * 1.00);
        zoneHigh = mid - (fallbackWidth * 0.40);
      }
      if (zoneLow > mid) {
        final shift = (zoneLow - mid) + (mid * 0.0005);
        zoneLow -= shift;
        zoneHigh -= shift;
      }
    }

    var strength = 50;
    if (reversalSignal) strength += 20;
    if (aligned) strength += 15;
    if (contrarian) strength -= 15;
    if (usedExternalLiquidity) strength += 10;
    if (macroVolPct > 0.02) {
      strength += 10;
    } else if (macroVolPct < 0.008) {
      strength -= 8;
    }
    if (input.oiDeltaPct > 0.005) {
      strength += 6;
    } else if (input.oiDeltaPct < -0.005) {
      strength -= 6;
    }
    if (input.sessionDominancePct >= 0.55) {
      strength += 4;
    } else if (input.sessionDominancePct > 0 &&
        input.sessionDominancePct <= 0.38) {
      strength -= 4;
    }
    strength = strength.clamp(0, 100).toInt();

    return BingxFuturesZoneDecisionResult(
      side: selectedSide,
      zoneSide: selectedSide == 'buy' ? 'buyside' : 'sellside',
      zoneLow: zoneLow,
      zoneHigh: zoneHigh,
      source: 'mtf_sweep_retest',
      sideReason: sideDecision.reason,
      olderHigh: olderHigh,
      olderLow: olderLow,
      recentHigh: recentHigh,
      recentLow: recentLow,
      sweepUp: sweepUp,
      sweepDown: sweepDown,
      trend4h: _trendLabel(higherBias),
      trend1d: _trendLabel(dailyBias),
      contextBias: contextBias,
      aligned: aligned,
      contrarian: contrarian,
      needsFartherRetest: needsFartherRetest,
      rangePct1h: macroVolPct,
      rangePct4h: higherRangePct,
      rangePct1d: dailyRangePct,
      rangePct1w: weeklyRangePct,
      targetRetestPct: targetRetestDistancePct,
      externalSellRetest: externalSellRetest?.price,
      externalBuyRetest: externalBuyRetest?.price,
      anchorSource: anchorSource,
      anchorExecutable: anchorExecutable,
      anchorLifecycle: anchorLifecycle,
      strength: strength,
      usedFallback: false,
    );
  }

  String _normalizeSide(String side) {
    final normalized = side.trim().toLowerCase();
    if (normalized == 'buy' || normalized == 'sell') return normalized;
    return 'sell';
  }

  bool _hasConfirmedMicroReclaim({
    required String side,
    required List<num> closes,
    required num olderHigh,
    required num olderLow,
    required bool sweepUp,
    required bool sweepDown,
  }) {
    if (closes.length < 2) return false;
    final lastClose = closes.last;
    final previousClose = closes[closes.length - 2];
    if (side == 'buy') {
      return sweepDown && lastClose > olderLow && lastClose > previousClose;
    }
    return sweepUp && lastClose < olderHigh && lastClose < previousClose;
  }

  List<_ExternalLevelPoint> _freshSwingLevels({
    required List<num> highs,
    required List<num> lows,
    required List<num> closes,
    required String side,
    required String source,
    required num weight,
  }) {
    if (highs.length != lows.length ||
        highs.length != closes.length ||
        highs.length < 5) {
      return const <_ExternalLevelPoint>[];
    }
    final pivots = <_SwingPivot>[];
    _SwingPivot? previousPivot;
    for (var index = 2; index < highs.length - 2; index += 1) {
      final isHigh = side == 'high';
      final price = isHigh ? highs[index] : lows[index];
      final isPivot = isHigh
          ? price > highs[index - 1] &&
              price >= highs[index - 2] &&
              price > highs[index + 1] &&
              price >= highs[index + 2]
          : price < lows[index - 1] &&
              price <= lows[index - 2] &&
              price < lows[index + 1] &&
              price <= lows[index + 2];
      if (!isPivot) continue;

      final isSweepOrigin = previousPivot != null &&
          (isHigh ? price > previousPivot.price : price < previousPivot.price);
      final isPostSweepReaction =
          previousPivot?.lifecycle == _LiquidityLevelLifecycle.sweepOrigin &&
              !isSweepOrigin;
      var consumed = false;
      for (var later = index + 1; later < highs.length; later += 1) {
        if (isHigh ? highs[later] > price : lows[later] < price) {
          consumed = true;
          break;
        }
      }
      final lifecycle = consumed
          ? _LiquidityLevelLifecycle.consumed
          : isSweepOrigin
              ? _LiquidityLevelLifecycle.sweepOrigin
              : isPostSweepReaction
                  ? _LiquidityLevelLifecycle.postSweepReaction
                  : _LiquidityLevelLifecycle.fresh;
      final pivot = _SwingPivot(
        index: index,
        price: price,
        lifecycle: lifecycle,
      );
      pivots.add(pivot);
      previousPivot = pivot;
    }
    return pivots
        .where((pivot) => pivot.lifecycle == _LiquidityLevelLifecycle.fresh)
        .map(
          (pivot) => _ExternalLevelPoint(
            price: pivot.price,
            weight: weight,
            source: source,
          ),
        )
        .toList(growable: false);
  }

  num _fallbackZoneWidth({
    required num mid,
    required double zoneNearBps,
    required double zoneFarBps,
  }) {
    return mid * ((zoneFarBps - zoneNearBps) / 10000.0);
  }

  num _clamp(num value, num min, num max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int _trendBiasFromCloses(
    List<num> closes, {
    int window = 12,
  }) {
    if (closes.length < window * 2) return 0;
    final recent = closes.sublist(closes.length - window);
    final prior = closes.sublist(
      closes.length - (window * 2),
      closes.length - window,
    );
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final priorAvg = prior.reduce((a, b) => a + b) / prior.length;
    if (priorAvg <= 0) return 0;
    final drift = (recentAvg - priorAvg) / priorAvg;
    if (drift > 0.003) return 1;
    if (drift < -0.003) return -1;
    return 0;
  }

  String _trendLabel(int bias) {
    return switch (bias) {
      > 0 => 'bull',
      < 0 => 'bear',
      _ => 'flat',
    };
  }

  ({String side, String reason}) _selectAutoSide({
    required bool sweepUp,
    required bool sweepDown,
    required int higherBias,
    required int dailyBias,
    required int contextBias,
    required num mid,
    required num olderHigh,
    required num olderLow,
    required num recentHigh,
    required num recentLow,
  }) {
    if (sweepUp && !sweepDown) {
      return (side: 'sell', reason: 'sweep_up_reversal');
    }
    if (sweepDown && !sweepUp) {
      return (side: 'buy', reason: 'sweep_down_reversal');
    }
    if (contextBias >= 2) {
      return (side: 'buy', reason: 'mtf_bull_alignment');
    }
    if (contextBias <= -2) {
      return (side: 'sell', reason: 'mtf_bear_alignment');
    }
    if (dailyBias > 0 && higherBias >= 0) {
      return (side: 'buy', reason: 'higher_tf_bull_bias');
    }
    if (dailyBias < 0 && higherBias <= 0) {
      return (side: 'sell', reason: 'higher_tf_bear_bias');
    }

    final refHigh = recentHigh > olderHigh ? recentHigh : olderHigh;
    final refLow = recentLow < olderLow ? recentLow : olderLow;
    final distToHighPct = ((refHigh - mid) / mid).abs();
    final distToLowPct = ((mid - refLow) / mid).abs();
    if (distToHighPct < distToLowPct * 0.72) {
      return (side: 'sell', reason: 'near_upper_liquidity');
    }
    if (distToLowPct < distToHighPct * 0.72) {
      return (side: 'buy', reason: 'near_lower_liquidity');
    }
    return (side: 'sell', reason: 'balanced_tiebreak_sell');
  }

  _ExternalRetestLevel? _selectRetestLevelAbove(
    List<_ExternalLevelPoint> levels,
    num reference, {
    required num minDistancePct,
    required num targetDistancePct,
    num maxDistancePct = 0.20,
    bool preferFarther = false,
  }) {
    _ExternalRetestLevel? best;
    num bestScore = -1e9;
    final target = targetDistancePct.clamp(minDistancePct, maxDistancePct);
    for (final level in levels) {
      if (level.price <= reference) continue;
      final distancePct = (level.price - reference) / reference;
      if (distancePct < minDistancePct || distancePct > maxDistancePct) {
        continue;
      }
      final deltaToTarget = (distancePct - target).abs();
      final closenessScore = 1.0 - (deltaToTarget / maxDistancePct);
      final tooClosePenalty = distancePct < target * 0.65 ? 0.22 : 0.0;
      final fartherBias = preferFarther ? distancePct * 1.35 : 0.0;
      final score =
          closenessScore + level.weight + fartherBias - tooClosePenalty;
      if (best == null || score > bestScore) {
        bestScore = score;
        best = _ExternalRetestLevel(
          price: level.price,
          source: level.source,
          distancePct: distancePct,
        );
      }
    }
    return best;
  }

  _ExternalRetestLevel? _selectRetestLevelBelow(
    List<_ExternalLevelPoint> levels,
    num reference, {
    required num minDistancePct,
    required num targetDistancePct,
    num maxDistancePct = 0.20,
    bool preferFarther = false,
  }) {
    _ExternalRetestLevel? best;
    num bestScore = -1e9;
    final target = targetDistancePct.clamp(minDistancePct, maxDistancePct);
    for (final level in levels) {
      if (level.price >= reference) continue;
      final distancePct = (reference - level.price) / reference;
      if (distancePct < minDistancePct || distancePct > maxDistancePct) {
        continue;
      }
      final deltaToTarget = (distancePct - target).abs();
      final closenessScore = 1.0 - (deltaToTarget / maxDistancePct);
      final tooClosePenalty = distancePct < target * 0.65 ? 0.22 : 0.0;
      final fartherBias = preferFarther ? distancePct * 1.35 : 0.0;
      final score =
          closenessScore + level.weight + fartherBias - tooClosePenalty;
      if (best == null || score > bestScore) {
        bestScore = score;
        best = _ExternalRetestLevel(
          price: level.price,
          source: level.source,
          distancePct: distancePct,
        );
      }
    }
    return best;
  }
}
