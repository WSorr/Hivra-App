import '../models/bingx_futures_signal_rank_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import 'plugin_host_api_service.dart';

class BingxFuturesSignalRankUseCaseService {
  final PluginHostApiService _hostApi;

  const BingxFuturesSignalRankUseCaseService({
    required PluginHostApiService hostApi,
  }) : _hostApi = hostApi;

  Future<BingxFuturesSignalRankResult> execute(
    BingxFuturesSignalRankCommand command,
  ) async {
    final response = await _hostApi.executeWithRuntimeHook(
      PluginHostApiRequest(
        schemaVersion: PluginHostApiService.schemaVersion,
        pluginId: bingxFuturesTradingPluginId,
        method: rankBingxFuturesSignalsMethod,
        args: <String, dynamic>{
          'candidates':
              command.candidates.map(_candidateJson).toList(growable: false),
        },
      ),
    );
    final entriesRaw = response.result?['entries'];
    final entries = entriesRaw is List
        ? entriesRaw
            .whereType<Map>()
            .map((entry) => BingxFuturesSignalRankEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ))
            .toList(growable: false)
        : const <BingxFuturesSignalRankEntry>[];
    return BingxFuturesSignalRankResult(
      response: response,
      entries: List<BingxFuturesSignalRankEntry>.unmodifiable(entries),
      scanHashHex: response.result?['scan_hash_hex']?.toString(),
    );
  }

  Map<String, dynamic> _candidateJson(BingxFuturesSignalRankCandidate item) {
    final decision = item.decision;
    final failed = decision.reasons
        .where((reason) => !reason.passed)
        .map((reason) => reason.code)
        .toSet()
        .toList()
      ..sort();
    return <String, dynamic>{
      'symbol': item.symbol.trim().toUpperCase(),
      'can_prepare_intent': decision.canPrepareIntent,
      'decision': decision.decision.name == 'noSignal'
          ? 'no_signal'
          : decision.decision.name,
      'side': decision.side,
      'zone_low_decimal': decision.zoneLowDecimal,
      'zone_high_decimal': decision.zoneHighDecimal,
      'trend_gate_code': decision.trendGateCode,
      'zone_anchor_source': decision.zoneAnchorSource,
      'zone_anchor_executable': decision.zoneAnchorExecutable,
      'zone_anchor_lifecycle': decision.zoneAnchorLifecycle,
      'trend_4h': decision.trend4h,
      'trend_1d': decision.trend1d,
      'live_decision_hash_hex': decision.liveDecisionHashHex,
      'failed_reason_codes': failed,
    };
  }
}
