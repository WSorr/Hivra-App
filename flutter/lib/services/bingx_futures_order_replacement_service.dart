import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_execution_queue_service.dart';
import 'bingx_futures_live_decision_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_strategy_naming_service.dart';
import 'plugin_host_api_service.dart';

typedef BingxReplacementIntentPreparer = Future<PluginHostApiResponse> Function(
  Map<String, dynamic> hostArgs,
);
typedef BingxReplacementRiskEvaluator = Future<BingxFuturesRiskDecision?>
    Function(
  BingxFuturesIntentPayload payload,
  Map<String, dynamic> rawIntentResult,
);
typedef BingxReplacementExecutor = Future<BingxQueuedExecutionResult> Function(
  BingxFuturesIntentPayload payload,
  bool testOrder,
);

enum BingxFuturesReplacementPlanStatus {
  ready,
  skipped,
}

class BingxFuturesReplacementPlan {
  final BingxFuturesReplacementPlanStatus status;
  final String reasonCode;
  final String reasonMessage;
  final Map<String, dynamic>? hostArgs;

  const BingxFuturesReplacementPlan({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.hostArgs,
  });

  bool get isReady =>
      status == BingxFuturesReplacementPlanStatus.ready && hostArgs != null;
}

class BingxFuturesOrderReplacementService {
  final BingxFuturesStrategyNamingService _strategyNaming;

  const BingxFuturesOrderReplacementService({
    BingxFuturesStrategyNamingService strategyNaming =
        const BingxFuturesStrategyNamingService(),
  }) : _strategyNaming = strategyNaming;

  BingxFuturesReplacementPlan plan({
    required BingxManagedOrderProvenance provenance,
    required BingxFuturesLiveDecisionResult liveDecision,
    required String cancellationReasonCode,
    required String cycleAtUtc,
  }) {
    if (cancellationReasonCode != 'live_zone_mismatch') {
      return _skipped(
        'replacement_not_allowed_for_reason',
        'Automatic replacement is only allowed for a stale zone.',
      );
    }
    if (!liveDecision.canPrepareIntent ||
        liveDecision.side == null ||
        liveDecision.zoneSide == null ||
        liveDecision.zoneLowDecimal == null ||
        liveDecision.zoneHighDecimal == null) {
      return _skipped(
        'replacement_live_decision_not_actionable',
        'Fresh live decision is not actionable.',
      );
    }
    if (liveDecision.side != provenance.side) {
      return _skipped(
        'replacement_side_flip_forbidden',
        'Automatic replacement cannot reverse the original order side.',
      );
    }

    final cycleAt = DateTime.tryParse(cycleAtUtc);
    if (cycleAt == null || !cycleAt.isUtc) {
      return _skipped(
        'replacement_cycle_time_invalid',
        'Replacement cycle timestamp must be an ISO-8601 UTC instant.',
      );
    }

    final canonical = _decodeCanonicalIntent(provenance.canonicalIntentJson);
    if (canonical == null) {
      return _skipped(
        'replacement_provenance_invalid',
        'Managed order canonical intent is invalid.',
      );
    }

    final peerHex = _read(canonical, 'peer_hex').toLowerCase();
    final symbol = _read(canonical, 'symbol').toUpperCase();
    final quantity = _read(canonical, 'quantity_decimal');
    final oldEntry = _readPositive(canonical, 'limit_price_decimal');
    final oldStop = _readPositive(canonical, 'stop_loss_decimal');
    final oldTarget = _readPositive(canonical, 'take_profit_decimal');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex) ||
        symbol != provenance.symbol ||
        quantity.isEmpty) {
      return _skipped(
        'replacement_provenance_mismatch',
        'Managed order provenance does not match the canonical intent.',
      );
    }
    if (oldEntry == null || oldStop == null || oldTarget == null) {
      return _skipped(
        'replacement_risk_lineage_missing',
        'Original entry, stop-loss, and take-profit are required.',
      );
    }

    final zoneLow = double.tryParse(liveDecision.zoneLowDecimal!);
    final zoneHigh = double.tryParse(liveDecision.zoneHighDecimal!);
    if (zoneLow == null ||
        zoneHigh == null ||
        zoneLow <= 0 ||
        zoneHigh <= zoneLow) {
      return _skipped(
        'replacement_live_zone_invalid',
        'Fresh live decision zone is invalid.',
      );
    }

    final riskDistance = (oldEntry - oldStop).abs();
    final rewardDistance = (oldTarget - oldEntry).abs();
    if (riskDistance <= 0 || rewardDistance <= 0) {
      return _skipped(
        'replacement_risk_lineage_invalid',
        'Original stop-loss and take-profit geometry is invalid.',
      );
    }
    final stopFraction = riskDistance / oldEntry;
    final riskReward = rewardDistance / riskDistance;
    final newEntry = (zoneLow + zoneHigh) / 2;
    final newRiskDistance = newEntry * stopFraction;
    final isBuy = provenance.side == 'buy';
    final newStop =
        isBuy ? newEntry - newRiskDistance : newEntry + newRiskDistance;
    final newTarget = isBuy
        ? newEntry + (newRiskDistance * riskReward)
        : newEntry - (newRiskDistance * riskReward);
    if (newStop <= 0 || newTarget <= 0) {
      return _skipped(
        'replacement_risk_geometry_invalid',
        'Fresh replacement risk geometry is invalid.',
      );
    }

    final replacementSeed =
        '${provenance.intentHashHex}|${liveDecision.liveDecisionHashHex}';
    final replacementDigest =
        sha256.convert(utf8.encode(replacementSeed)).toString();
    final strategyTag = _strategyNaming.tagForDecision(liveDecision.decision);

    return BingxFuturesReplacementPlan(
      status: BingxFuturesReplacementPlanStatus.ready,
      reasonCode: 'replacement_ready',
      reasonMessage:
          'Fresh same-side TVH zone produced a deterministic replacement.',
      hostArgs: <String, dynamic>{
        'peer_hex': peerHex,
        'client_order_id': 'repl-${replacementDigest.substring(0, 32)}',
        'symbol': symbol,
        'side': provenance.side,
        'order_type': 'limit',
        'quantity_decimal': quantity,
        'limit_price_decimal': null,
        'time_in_force': _read(canonical, 'time_in_force').isEmpty
            ? 'GTC'
            : _read(canonical, 'time_in_force').toUpperCase(),
        'entry_mode': 'zone_pending',
        'zone_side': liveDecision.zoneSide,
        'zone_low_decimal': _formatDecimal(zoneLow),
        'zone_high_decimal': _formatDecimal(zoneHigh),
        'zone_price_rule': 'zone_mid',
        'trigger_price_decimal': _formatDecimal(isBuy ? zoneHigh : zoneLow),
        'stop_loss_decimal': _formatDecimal(newStop),
        'take_profit_decimal': _formatDecimal(newTarget),
        'created_at_utc': cycleAt.toUtc().toIso8601String(),
        'strategy_tag': strategyTag,
        'market_snapshot_hash_hex': liveDecision.marketSnapshotHashHex,
        'feature_hash_hex': liveDecision.featureHashHex,
        'tvh_decision_hash_hex': liveDecision.tvhDecisionHashHex,
        'live_decision_hash_hex': liveDecision.liveDecisionHashHex,
      },
    );
  }

  Future<BingxFuturesReplacementRuntimeResult> execute({
    required BingxManagedOrderProvenance provenance,
    required BingxFuturesLiveDecisionResult liveDecision,
    required String cancellationReasonCode,
    required String cycleAtUtc,
    required BingxReplacementIntentPreparer prepareIntent,
    required BingxReplacementRiskEvaluator evaluateRisk,
    required BingxReplacementExecutor executeOrder,
  }) async {
    final replacementPlan = plan(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
    );
    if (!replacementPlan.isReady) {
      return BingxFuturesReplacementRuntimeResult(
        status: BingxFuturesReplacementRuntimeStatus.skipped,
        plan: replacementPlan,
        hostResponse: null,
        payload: null,
        riskDecision: null,
        queuedExecution: null,
      );
    }

    final hostResponse = await prepareIntent(replacementPlan.hostArgs!);
    final rawResult = hostResponse.result;
    if (hostResponse.status != PluginHostApiStatus.executed ||
        rawResult == null) {
      return BingxFuturesReplacementRuntimeResult(
        status: BingxFuturesReplacementRuntimeStatus.hostBlocked,
        plan: replacementPlan,
        hostResponse: hostResponse,
        payload: null,
        riskDecision: null,
        queuedExecution: null,
      );
    }

    final payload = BingxFuturesIntentPayload.fromPluginResult(rawResult);
    final riskDecision = await evaluateRisk(payload, rawResult);
    if (riskDecision == null) {
      return BingxFuturesReplacementRuntimeResult(
        status: BingxFuturesReplacementRuntimeStatus.riskUnavailable,
        plan: replacementPlan,
        hostResponse: hostResponse,
        payload: payload,
        riskDecision: null,
        queuedExecution: null,
      );
    }
    if (riskDecision.status == BingxFuturesRiskDecisionStatus.blocked) {
      return BingxFuturesReplacementRuntimeResult(
        status: BingxFuturesReplacementRuntimeStatus.riskBlocked,
        plan: replacementPlan,
        hostResponse: hostResponse,
        payload: payload,
        riskDecision: riskDecision,
        queuedExecution: null,
      );
    }

    final queued = await executeOrder(payload, provenance.testOrder);
    return BingxFuturesReplacementRuntimeResult(
      status: queued.execution.isSuccess
          ? BingxFuturesReplacementRuntimeStatus.executed
          : BingxFuturesReplacementRuntimeStatus.executionFailed,
      plan: replacementPlan,
      hostResponse: hostResponse,
      payload: payload,
      riskDecision: riskDecision,
      queuedExecution: queued,
    );
  }

  Map<String, dynamic>? _decodeCanonicalIntent(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  String _read(Map<String, dynamic> map, String key) {
    return map[key]?.toString().trim() ?? '';
  }

  double? _readPositive(Map<String, dynamic> map, String key) {
    final value = double.tryParse(_read(map, key));
    if (value == null || value <= 0) return null;
    return value;
  }

  String _formatDecimal(double value) {
    final fixed = value.toStringAsFixed(8);
    final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  BingxFuturesReplacementPlan _skipped(String code, String message) {
    return BingxFuturesReplacementPlan(
      status: BingxFuturesReplacementPlanStatus.skipped,
      reasonCode: code,
      reasonMessage: message,
      hostArgs: null,
    );
  }
}

enum BingxFuturesReplacementRuntimeStatus {
  skipped,
  hostBlocked,
  riskUnavailable,
  riskBlocked,
  executionFailed,
  executed,
}

class BingxFuturesReplacementRuntimeResult {
  final BingxFuturesReplacementRuntimeStatus status;
  final BingxFuturesReplacementPlan plan;
  final PluginHostApiResponse? hostResponse;
  final BingxFuturesIntentPayload? payload;
  final BingxFuturesRiskDecision? riskDecision;
  final BingxQueuedExecutionResult? queuedExecution;

  const BingxFuturesReplacementRuntimeResult({
    required this.status,
    required this.plan,
    required this.hostResponse,
    required this.payload,
    required this.riskDecision,
    required this.queuedExecution,
  });

  bool get isExecuted =>
      status == BingxFuturesReplacementRuntimeStatus.executed &&
      queuedExecution?.execution.isSuccess == true;
}
