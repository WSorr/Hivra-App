class BingxFuturesZoneDecisionInput {
  final num midPrice;
  final String fallbackSide;
  final List<num> microHighs;
  final List<num> microLows;
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
    required this.microHighs,
    required this.microLows,
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
      final fallbackSide = _normalizeSide(input.fallbackSide);
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
    final sideDecision = _selectAutoSide(
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
    );

    final selectedSide = sideDecision.side;
    final reversalSignal = selectedSide == 'sell' ? sweepUp : sweepDown;
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
      ...input.higherHighs.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.00, source: '4h_high'),
      ),
      ...input.dailyHighs.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.25, source: '1d_high'),
      ),
      ...input.weeklyHighs.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.55, source: '1w_high'),
      ),
      ...input.liquidationSellLevels.map(
        (price) => _ExternalLevelPoint(
          price: price,
          weight: 1.75,
          source: 'liq_sell',
        ),
      ),
    ];
    final externalLowCandidates = <_ExternalLevelPoint>[
      ...input.higherLows.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.00, source: '4h_low'),
      ),
      ...input.dailyLows.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.25, source: '1d_low'),
      ),
      ...input.weeklyLows.map(
        (price) =>
            _ExternalLevelPoint(price: price, weight: 1.55, source: '1w_low'),
      ),
      ...input.liquidationBuyLevels.map(
        (price) => _ExternalLevelPoint(
          price: price,
          weight: 1.75,
          source: 'liq_buy',
        ),
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
    var anchorSource = 'internal';

    num zoneLow;
    num zoneHigh;
    if (selectedSide == 'sell') {
      var anchorHigh = sweepUp ? recentHigh : olderHigh;
      if (externalSellRetest != null &&
          (!aligned ||
              !reversalSignal ||
              externalSellRetest.price > anchorHigh)) {
        anchorHigh = externalSellRetest.price;
        usedExternalLiquidity = true;
        anchorSource = externalSellRetest.source;
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
      var anchorLow = sweepDown ? recentLow : olderLow;
      if (externalBuyRetest != null &&
          (!aligned ||
              !reversalSignal ||
              externalBuyRetest.price < anchorLow)) {
        anchorLow = externalBuyRetest.price;
        usedExternalLiquidity = true;
        anchorSource = externalBuyRetest.source;
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
      strength: strength,
      usedFallback: false,
    );
  }

  String _normalizeSide(String side) {
    final normalized = side.trim().toLowerCase();
    if (normalized == 'buy' || normalized == 'sell') return normalized;
    return 'sell';
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
