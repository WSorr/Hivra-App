import 'bingx_futures_live_decision_models.dart';
import 'plugin_host_api_models.dart';

class BingxFuturesSignalRankCandidate {
  final String symbol;
  final BingxFuturesLiveDecisionResult decision;

  const BingxFuturesSignalRankCandidate({
    required this.symbol,
    required this.decision,
  });
}

class BingxFuturesSignalRankCommand {
  final List<BingxFuturesSignalRankCandidate> candidates;

  const BingxFuturesSignalRankCommand({
    required this.candidates,
  });
}

class BingxFuturesSignalRankEntry {
  final String symbol;
  final String bucket;
  final int score;
  final String decision;
  final String? side;
  final String? zoneLowDecimal;
  final String? zoneHighDecimal;
  final String trendGateCode;
  final bool canPrepareIntent;
  final String? liveDecisionHashHex;
  final List<String> failedReasonCodes;

  const BingxFuturesSignalRankEntry({
    required this.symbol,
    required this.bucket,
    required this.score,
    required this.decision,
    required this.side,
    required this.zoneLowDecimal,
    required this.zoneHighDecimal,
    required this.trendGateCode,
    required this.canPrepareIntent,
    required this.liveDecisionHashHex,
    required this.failedReasonCodes,
  });

  factory BingxFuturesSignalRankEntry.fromJson(Map<String, dynamic> json) {
    final failedRaw = json['failed_reason_codes'];
    return BingxFuturesSignalRankEntry(
      symbol: json['symbol']?.toString() ?? '',
      bucket: json['bucket']?.toString() ?? 'error',
      score: int.tryParse(json['score']?.toString() ?? '') ?? 0,
      decision: json['decision']?.toString() ?? 'no_signal',
      side: _nonEmpty(json['side']),
      zoneLowDecimal: _nonEmpty(json['zone_low_decimal']),
      zoneHighDecimal: _nonEmpty(json['zone_high_decimal']),
      trendGateCode: json['trend_gate_code']?.toString() ?? 'unknown',
      canPrepareIntent: json['can_prepare_intent'] == true,
      liveDecisionHashHex: _nonEmpty(json['live_decision_hash_hex']),
      failedReasonCodes: failedRaw is List
          ? failedRaw.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

class BingxFuturesSignalRankResult {
  final PluginHostApiResponse response;
  final List<BingxFuturesSignalRankEntry> entries;
  final String? scanHashHex;

  const BingxFuturesSignalRankResult({
    required this.response,
    required this.entries,
    required this.scanHashHex,
  });

  bool get isSuccess => response.status == PluginHostApiStatus.executed;
}

String? _nonEmpty(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
