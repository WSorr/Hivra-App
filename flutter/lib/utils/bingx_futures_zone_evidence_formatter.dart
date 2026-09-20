import '../models/bingx_futures_live_decision_models.dart';

String formatBingxFuturesLiquidityObservation(
  BingxFuturesLiveDecisionResult? decision,
) {
  if (decision == null) {
    return 'Observed liquidity (4h)\nScan and select a symbol to inspect its clusters.';
  }
  final lines = <String>[
    'Observed liquidity (4h) — snapshot, not order prices',
  ];
  final parent = decision.parentZone;
  if (parent != null) {
    lines.add(
      '4h ${parent['side']} sweep/reclaim: '
      '${parent['low_decimal']}–${parent['high_decimal']} '
      '· confirmed ${parent['confirmed_at_utc']}',
    );
    if (!decision.zoneAnchorExecutable) {
      lines.add('No valid 5m confirmation inside this parent zone.');
    }
  }
  if (decision.observedLiquidityLevels.isEmpty) {
    lines.add('No pivot clusters detected in this snapshot.');
  }
  for (final level in decision.observedLiquidityLevels) {
    final side = level.side == 'buyside' ? 'Buyside' : 'Sellside';
    final state = level.breached ? 'Swept' : 'Untouched';
    lines.add(
      '$side ${level.zoneBottomDecimal}–${level.zoneTopDecimal}'
      ' · ${level.pivotCount} pivots · $state',
    );
  }
  lines.add(
    decision.zoneAnchorExecutable
        ? (decision.canPrepareIntent
            ? 'Liquidity entry confirmed. Order preparation still requires risk and mandate checks.'
            : 'Liquidity entry confirmed; other entry checks block preparation.')
        : 'No confirmed executable setup. A swept cluster alone does not authorize entry.',
  );
  lines.add('Offline monitoring requires an active authorized Runner session.');
  return lines.join('\n');
}

String formatBingxFuturesZoneEvidence(BingxFuturesLiveDecisionResult decision) {
  final parts = <String>['Pending liquidity zone — not current market price'];
  final source = _formatAnchorSource(decision.zoneAnchorSource);
  if (source != null) {
    parts.add(source);
  }

  final eventAt =
      DateTime.tryParse(decision.liquidityEventAtUtc ?? '')?.toUtc();
  final observedAt =
      DateTime.tryParse(decision.latestClosedMicroBarAtUtc ?? '')?.toUtc();
  if (eventAt != null) {
    parts.add('formed ${_formatUtc(eventAt)}');
  }
  if (eventAt != null && observedAt != null && !observedAt.isBefore(eventAt)) {
    parts.add('age ${_formatAge(observedAt.difference(eventAt))}');
  }

  final distance = _zoneDistancePercent(decision);
  if (distance != null) {
    parts.add('${distance.value.toStringAsFixed(1)}% ${distance.direction}');
  }
  parts.add('Run Intent revalidates it');
  return parts.join(' · ');
}

String? _formatAnchorSource(String? raw) {
  final source = raw?.trim().toLowerCase() ?? '';
  if (source == '4h_sweep_reclaim_5m') {
    return '4h sweep/reclaim, confirmed on 5m';
  }
  final match = RegExp(r'^(4h|1d|1w)_fresh_(high|low)$').firstMatch(source);
  if (match != null) {
    return '${match.group(1)} unswept ${match.group(2)}';
  }
  if (source == 'micro_sweep_reclaim') {
    return 'current 5m sweep/reclaim';
  }
  if (source == 'micro_liquidity_void') {
    return 'fresh untouched 5m liquidity void';
  }
  if (source.isEmpty || source == 'internal_diagnostic') {
    return null;
  }
  return source.replaceAll('_', ' ');
}

({double value, String direction})? _zoneDistancePercent(
  BingxFuturesLiveDecisionResult decision,
) {
  final reference = double.tryParse(decision.referencePriceDecimal ?? '');
  final zoneLow = double.tryParse(decision.zoneLowDecimal ?? '');
  final zoneHigh = double.tryParse(decision.zoneHighDecimal ?? '');
  if (reference == null ||
      zoneLow == null ||
      zoneHigh == null ||
      reference <= 0 ||
      zoneLow <= 0 ||
      zoneHigh <= 0) {
    return null;
  }
  final nearest = switch (decision.side) {
    'sell' => zoneLow,
    'buy' => zoneHigh,
    _ => (zoneLow + zoneHigh) / 2,
  };
  final difference = nearest - reference;
  final direction =
      difference > 0
          ? 'above'
          : difference < 0
          ? 'below'
          : 'away';
  return (value: difference.abs() / reference * 100, direction: direction);
}

String _formatAge(Duration age) {
  final days = age.inDays;
  final hours = age.inHours.remainder(24);
  if (days > 0 && hours > 0) return '${days}d ${hours}h';
  if (days > 0) return '${days}d';
  if (age.inHours > 0) return '${age.inHours}h';
  return '${age.inMinutes.clamp(0, 59)}m';
}

String _formatUtc(DateTime value) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day ${months[value.month - 1]} ${value.year} $hour:$minute UTC';
}
