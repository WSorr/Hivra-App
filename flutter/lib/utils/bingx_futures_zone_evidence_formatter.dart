import '../models/bingx_futures_live_decision_models.dart';

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
  final match = RegExp(r'^(4h|1d|1w)_fresh_(high|low)$').firstMatch(source);
  if (match != null) {
    return '${match.group(1)} unswept ${match.group(2)}';
  }
  if (source == 'micro_sweep_reclaim') {
    return 'current 5m sweep/reclaim';
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
