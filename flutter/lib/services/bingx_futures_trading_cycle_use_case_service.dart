import 'dart:async';
import 'dart:math' as math;

import '../models/bingx_futures_exchange_execution_models.dart';
import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_intent_models.dart';
import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_live_strategy_models.dart';
import '../models/bingx_futures_order_sizing_models.dart';
import '../models/bingx_futures_risk_models.dart';
import '../models/plugin_host_api_models.dart';
import 'bingx_futures_exchange_execution_use_case_service.dart';
import 'bingx_futures_intent_use_case_service.dart';
import 'bingx_futures_live_strategy_use_case_service.dart';
import 'bingx_futures_order_sizing_service.dart';
import 'bingx_futures_strategy_naming_service.dart';

enum BingxFuturesTradingCycleStatus {
  invalidInput,
  marketUnavailable,
  marketBlocked,
  sizingBlocked,
  intentBlocked,
  prepared,
  executionBlocked,
  validated,
  executed,
}

class BingxFuturesTradingCycleCommand {
  final String screen;
  final String symbol;
  final String preferredSide;
  final num maximumNotionalQuote;
  final double stopLossPercent;
  final double takeProfitRiskReward;
  final BingxFuturesApiCredentials? credentials;
  final BingxFuturesRiskPolicy riskPolicy;
  final bool testOrder;
  final bool executeEffect;
  final int recentMicroBars;
  final double zoneNearBps;
  final double zoneFarBps;

  const BingxFuturesTradingCycleCommand({
    required this.screen,
    required this.symbol,
    required this.preferredSide,
    required this.maximumNotionalQuote,
    required this.stopLossPercent,
    required this.takeProfitRiskReward,
    required this.credentials,
    required this.riskPolicy,
    required this.testOrder,
    required this.executeEffect,
    required this.recentMicroBars,
    required this.zoneNearBps,
    required this.zoneFarBps,
  });
}

class BingxFuturesTradingCycleResult {
  final BingxFuturesTradingCycleStatus status;
  final String reasonCode;
  final String reasonMessage;
  final BingxFuturesLiveDecisionResult? decision;
  final BingxFuturesOrderSizingResult? sizing;
  final BingxFuturesIntentUseCaseResult? intent;
  final BingxFuturesExchangeExecutionUseCaseResult? execution;
  final String? stopLossDecimal;
  final String? takeProfitDecimal;

  const BingxFuturesTradingCycleResult({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.decision,
    required this.sizing,
    required this.intent,
    required this.execution,
    required this.stopLossDecimal,
    required this.takeProfitDecimal,
  });

  bool get isPrepared =>
      status == BingxFuturesTradingCycleStatus.prepared ||
      status == BingxFuturesTradingCycleStatus.validated ||
      status == BingxFuturesTradingCycleStatus.executed;
}

typedef BingxFuturesLiveStrategyCycleRunner =
    Future<BingxFuturesLiveStrategyResult> Function(
      BingxFuturesLiveStrategyCommand command,
    );
typedef BingxFuturesOrderSizingCycleRunner =
    Future<BingxFuturesOrderSizingResult> Function({
      required String symbol,
      required num maximumNotionalQuote,
      required String referencePriceDecimal,
      required BingxFuturesContractRules rules,
    });
typedef BingxFuturesIntentCycleRunner =
    Future<BingxFuturesIntentUseCaseResult> Function(
      BingxFuturesIntentCommand command,
    );
typedef BingxFuturesExecutionCycleRunner =
    Future<BingxFuturesExchangeExecutionUseCaseResult> Function({
      required String screen,
      required Map<String, dynamic> rawIntentResult,
      required BingxFuturesApiCredentials credentials,
      required BingxFuturesRiskPolicy riskPolicy,
      required bool testOrder,
      BingxFuturesLiveDecisionResult? preparedDecision,
      Future<BingxFuturesLiveDecisionResult?> Function()? refreshDecision,
    });

class BingxFuturesTradingCycleUseCaseService {
  final BingxFuturesLiveStrategyCycleRunner _runLiveStrategy;
  final BingxFuturesOrderSizingCycleRunner _runSizing;
  final Future<BingxFuturesContractRules?> Function(String) _loadContractRules;
  final BingxFuturesIntentCycleRunner _runIntent;
  final BingxFuturesExecutionCycleRunner _runExecution;
  final BingxFuturesStrategyNamingService _strategyNaming;
  final DateTime Function() _nowUtc;
  final Duration _intentTimeout;

  BingxFuturesTradingCycleUseCaseService({
    BingxFuturesLiveStrategyUseCaseService? liveStrategy,
    BingxFuturesOrderSizingService? orderSizing,
    BingxFuturesIntentUseCaseService? intentUseCase,
    BingxFuturesExchangeExecutionUseCaseService? executionUseCase,
    BingxFuturesStrategyNamingService strategyNaming =
        const BingxFuturesStrategyNamingService(),
    BingxFuturesLiveStrategyCycleRunner? liveStrategyRunner,
    BingxFuturesOrderSizingCycleRunner? sizingRunner,
    Future<BingxFuturesContractRules?> Function(String)? contractRulesLoader,
    BingxFuturesIntentCycleRunner? intentRunner,
    BingxFuturesExecutionCycleRunner? executionRunner,
    DateTime Function()? nowUtc,
    Duration intentTimeout = const Duration(seconds: 20),
  }) : assert(liveStrategyRunner != null || liveStrategy != null),
       assert(sizingRunner != null || orderSizing != null),
       assert(intentRunner != null || intentUseCase != null),
       assert(executionRunner != null || executionUseCase != null),
       _runLiveStrategy = liveStrategyRunner ?? liveStrategy!.execute,
       _loadContractRules =
           contractRulesLoader ?? orderSizing!.loadContractRules,
       _runSizing =
           sizingRunner ??
           (({
             required String symbol,
             required num maximumNotionalQuote,
             required String referencePriceDecimal,
             required BingxFuturesContractRules rules,
           }) async => orderSizing!.calculate(
             rules: rules,
             maximumNotionalQuote: maximumNotionalQuote,
             referencePriceDecimal: referencePriceDecimal,
           )),
       _runIntent = intentRunner ?? intentUseCase!.execute,
       _runExecution = executionRunner ?? executionUseCase!.execute,
       _strategyNaming = strategyNaming,
       _nowUtc = nowUtc ?? DateTime.now,
       _intentTimeout = intentTimeout;

  Future<BingxFuturesTradingCycleResult> run(
    BingxFuturesTradingCycleCommand command,
  ) async {
    final symbol = command.symbol.trim().toUpperCase();
    final preferredSide = command.preferredSide.trim().toLowerCase();
    if (symbol.isEmpty ||
        (preferredSide != 'buy' && preferredSide != 'sell') ||
        command.maximumNotionalQuote <= 0 ||
        command.stopLossPercent <= 0 ||
        command.takeProfitRiskReward <= 0) {
      return _blocked(
        BingxFuturesTradingCycleStatus.invalidInput,
        'trading_cycle_input_invalid',
        'Trading cycle input is invalid.',
      );
    }

    final initial = await _loadDecision(command, symbol, preferredSide);
    final decision = initial.decision;
    if (!initial.isSuccess || decision == null) {
      return _blocked(
        BingxFuturesTradingCycleStatus.marketUnavailable,
        initial.errorCode ?? 'market_analysis_unavailable',
        initial.errorMessage ?? 'Market analysis is unavailable.',
      );
    }
    final eventId = decision.liquidityEventId?.trim() ?? '';
    final closedBar = decision.latestClosedMicroBarAtUtc?.trim() ?? '';
    if (!decision.canPrepareIntent ||
        decision.side == null ||
        decision.zoneSide == null ||
        decision.zoneLowDecimal == null ||
        decision.zoneHighDecimal == null) {
      final blocker = _marketDecisionBlocker(decision);
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        blocker.code,
        blocker.message,
        decision: decision,
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(eventId) || closedBar.isEmpty) {
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        'liquidity_event_evidence_missing',
        'Liquidity event evidence is unavailable.',
        decision: decision,
      );
    }

    final zoneLow = num.tryParse(decision.zoneLowDecimal!);
    final zoneHigh = num.tryParse(decision.zoneHighDecimal!);
    if (zoneLow == null || zoneHigh == null || zoneLow <= 0 || zoneHigh <= 0) {
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        'liquidity_zone_invalid',
        'Liquidity zone is invalid.',
        decision: decision,
      );
    }
    final rules = await _loadContractRules(symbol);
    if (rules == null ||
        rules.symbol.trim().toUpperCase() != symbol ||
        rules.pricePrecision == null ||
        rules.pricePrecision! < 0 ||
        rules.pricePrecision! > 8) {
      return _blocked(
        BingxFuturesTradingCycleStatus.sizingBlocked,
        'contract_price_precision_unavailable',
        'Valid instrument price precision is required.',
        decision: decision,
      );
    }
    final precision = rules.pricePrecision!;
    final entryPrice = num.parse(
      bingxFuturesPriceDecimal((zoneLow + zoneHigh) / 2, precision: precision),
    );
    final triggerPrice = bingxFuturesPriceDecimal(
      decision.side == 'buy' ? zoneHigh : zoneLow,
      precision: precision,
      roundUp: decision.side == 'buy',
    );
    final targets = deriveBingxFuturesLiquidityTargets(
      side: decision.side!,
      entryPrice: entryPrice,
      zoneLow: zoneLow,
      zoneHigh: zoneHigh,
      atr14m5Decimal: decision.atr14m5Decimal,
      stopLossPercent: command.stopLossPercent,
      minimumRiskReward: command.takeProfitRiskReward,
      oppositeLiquidityTargetDecimal: decision.oppositeLiquidityTargetDecimal,
      pricePrecision: precision,
    );
    if (targets.blockerCode != null) {
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        targets.blockerCode!,
        targets.blockerMessage!,
        decision: decision,
        stopLossDecimal: targets.stopLossDecimal,
        takeProfitDecimal: targets.takeProfitDecimal,
      );
    }
    final sizing = await _runSizing(
      rules: rules,
      symbol: symbol,
      maximumNotionalQuote:
          command.maximumNotionalQuote * targets.notionalScale,
      referencePriceDecimal: _formatDecimal(entryPrice),
    );
    if (sizing.status != BingxFuturesOrderSizingStatus.sized ||
        sizing.quantityDecimal == null) {
      return _blocked(
        BingxFuturesTradingCycleStatus.sizingBlocked,
        sizing.reasonCode,
        sizing.reasonMessage,
        decision: decision,
        sizing: sizing,
      );
    }

    late final BingxFuturesIntentUseCaseResult intent;
    try {
      intent = await _runIntent(
        BingxFuturesIntentCommand(
          screen: command.screen,
          clientOrderId: 'hivra-${eventId.substring(0, 32)}',
          symbol: symbol,
          side: decision.side!,
          orderType: 'limit',
          quantityDecimal: sizing.quantityDecimal!,
          limitPriceDecimal: null,
          timeInForce: 'GTC',
          entryMode: 'zone_pending',
          zoneSide: decision.zoneSide!,
          zoneLowDecimal: decision.zoneLowDecimal!,
          zoneHighDecimal: decision.zoneHighDecimal!,
          zonePriceRule: 'manual',
          manualEntryPriceDecimal: _formatDecimal(entryPrice),
          triggerPriceDecimal: triggerPrice,
          stopLossDecimal: targets.stopLossDecimal,
          takeProfitDecimal: targets.takeProfitDecimal,
          createdAtUtc: _nowUtc().toUtc().toIso8601String(),
          strategyTag: _strategyNaming.tagForDecision(decision.decision),
          liveDecision: decision,
        ),
      ).timeout(_intentTimeout);
    } on TimeoutException {
      return _blocked(
        BingxFuturesTradingCycleStatus.intentBlocked,
        'host_intent_timeout',
        'Intent host timed out.',
        decision: decision,
        sizing: sizing,
        stopLossDecimal: targets.stopLossDecimal,
        takeProfitDecimal: targets.takeProfitDecimal,
      );
    }
    if (intent.response.status != PluginHostApiStatus.executed ||
        intent.response.result == null) {
      return _blocked(
        BingxFuturesTradingCycleStatus.intentBlocked,
        intent.response.errorCode ?? 'intent_not_prepared',
        intent.response.errorMessage ?? 'Intent was not prepared.',
        decision: decision,
        sizing: sizing,
        intent: intent,
        stopLossDecimal: targets.stopLossDecimal,
        takeProfitDecimal: targets.takeProfitDecimal,
      );
    }
    if (!command.executeEffect) {
      return BingxFuturesTradingCycleResult(
        status: BingxFuturesTradingCycleStatus.prepared,
        reasonCode: 'intent_prepared',
        reasonMessage: 'Trading intent prepared.',
        decision: decision,
        sizing: sizing,
        intent: intent,
        execution: null,
        stopLossDecimal: targets.stopLossDecimal,
        takeProfitDecimal: targets.takeProfitDecimal,
      );
    }
    final credentials = command.credentials;
    if (credentials == null) {
      return _blocked(
        BingxFuturesTradingCycleStatus.executionBlocked,
        'trading_credentials_required',
        'BingX credentials are required for execution.',
        decision: decision,
        sizing: sizing,
        intent: intent,
        stopLossDecimal: targets.stopLossDecimal,
        takeProfitDecimal: targets.takeProfitDecimal,
      );
    }

    final execution = await _runExecution(
      screen: command.screen,
      rawIntentResult: intent.response.result!,
      credentials: credentials,
      riskPolicy: command.riskPolicy,
      testOrder: command.testOrder,
      preparedDecision: decision,
      refreshDecision: () async {
        final refreshed = await _loadDecision(command, symbol, preferredSide);
        return refreshed.decision;
      },
    );
    final executionValidated =
        execution.status ==
            BingxFuturesExchangeExecutionUseCaseStatus.validated &&
        execution.queuedExecution?.execution.isSuccess == true;
    final executionSucceeded =
        execution.status ==
            BingxFuturesExchangeExecutionUseCaseStatus.executed &&
        execution.queuedExecution?.execution.isSuccess == true;
    return BingxFuturesTradingCycleResult(
      status:
          executionSucceeded
              ? BingxFuturesTradingCycleStatus.executed
              : executionValidated
              ? BingxFuturesTradingCycleStatus.validated
              : BingxFuturesTradingCycleStatus.executionBlocked,
      reasonCode:
          execution.errorCode ??
          (executionSucceeded
              ? 'effect_executed'
              : executionValidated
              ? 'request_validated'
              : execution.status ==
                      BingxFuturesExchangeExecutionUseCaseStatus.executed ||
                  execution.status ==
                      BingxFuturesExchangeExecutionUseCaseStatus.validated
              ? 'exchange_effect_failed'
              : execution.status.name),
      reasonMessage:
          execution.errorMessage ??
          (executionSucceeded
              ? 'Exchange effect executed.'
              : executionValidated
              ? 'Exact request validated; no exchange order was created.'
              : 'Exchange effect did not produce a success receipt.'),
      decision: decision,
      sizing: sizing,
      intent: intent,
      execution: execution,
      stopLossDecimal: targets.stopLossDecimal,
      takeProfitDecimal: targets.takeProfitDecimal,
    );
  }

  ({String code, String message}) _marketDecisionBlocker(
    BingxFuturesLiveDecisionResult decision,
  ) {
    final failedCodes =
        decision.reasons
            .where((reason) => !reason.passed)
            .map((reason) => reason.code)
            .toSet();
    if (failedCodes.contains('consensus_guard')) {
      return (
        code: 'market_consensus_guard_blocked',
        message: 'Pair-scoped consensus does not authorize this decision.',
      );
    }
    if (failedCodes.contains('funding_guard')) {
      return (
        code: 'market_funding_extreme',
        message: 'Funding is outside the configured trading boundary.',
      );
    }
    if (failedCodes.contains('zone_side_alignment') || decision.zoneConflict) {
      return (
        code: 'market_liquidity_zone_conflict',
        message: 'The liquidity zone conflicts with the activated side.',
      );
    }
    if (decision.trendGateBlocked) {
      return (
        code: decision.trendGateCode,
        message: switch (decision.trendGateCode) {
          'liquidity_anchor_unavailable' =>
            'No active 4h liquidity zone is ready now. Try again later or start a 24/7 session.',
          'momentum_gate_short_missed_retest' ||
          'momentum_gate_long_missed_retest' =>
            'The market has already moved beyond the bounded retest.',
          'trend_gate_short_far_retest' || 'trend_gate_long_far_retest' =>
            'The pending retest is too far for the current continuation.',
          _ => 'The structural market gate rejected this decision.',
        },
      );
    }
    final volumeUnavailable =
        failedCodes.contains('long_trade_imbalance') &&
        failedCodes.contains('short_trade_imbalance');
    if (volumeUnavailable || decision.side == null) {
      return (
        code: 'market_volume_activation_unavailable',
        message:
            'Buyers and sellers are still balanced. The drone will wait for a clearer move.',
      );
    }
    if (!decision.zoneAnchorExecutable) {
      return (
        code: 'liquidity_anchor_unavailable',
        message:
            'No active 4h liquidity zone is ready now. Try again later or start a 24/7 session.',
      );
    }
    return (
      code: 'market_decision_incomplete',
      message: 'The market decision is missing executable evidence.',
    );
  }

  Future<BingxFuturesLiveStrategyResult> _loadDecision(
    BingxFuturesTradingCycleCommand command,
    String symbol,
    String preferredSide,
  ) {
    return _runLiveStrategy(
      BingxFuturesLiveStrategyCommand(
        symbol: symbol,
        recentMicroBars: command.recentMicroBars,
        zoneNearBps: command.zoneNearBps,
        zoneFarBps: command.zoneFarBps,
        zoneEvaluationSide: preferredSide,
      ),
    );
  }

  String _formatDecimal(num value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');

  BingxFuturesTradingCycleResult _blocked(
    BingxFuturesTradingCycleStatus status,
    String reasonCode,
    String reasonMessage, {
    BingxFuturesLiveDecisionResult? decision,
    BingxFuturesOrderSizingResult? sizing,
    BingxFuturesIntentUseCaseResult? intent,
    String? stopLossDecimal,
    String? takeProfitDecimal,
  }) {
    return BingxFuturesTradingCycleResult(
      status: status,
      reasonCode: reasonCode,
      reasonMessage: reasonMessage,
      decision: decision,
      sizing: sizing,
      intent: intent,
      execution: null,
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: takeProfitDecimal,
    );
  }
}

({
  String? stopLossDecimal,
  String? takeProfitDecimal,
  double? actualRiskReward,
  String? blockerCode,
  String? blockerMessage,
  double notionalScale,
})
deriveBingxFuturesLiquidityTargets({
  required String side,
  required num entryPrice,
  required num zoneLow,
  required num zoneHigh,
  required String? atr14m5Decimal,
  required double stopLossPercent,
  required double minimumRiskReward,
  required String? oppositeLiquidityTargetDecimal,
  int pricePrecision = 8,
}) {
  final normalizedSide = side.trim().toLowerCase();
  final atr = num.tryParse(atr14m5Decimal ?? '');
  if (pricePrecision < 0 ||
      pricePrecision > 8 ||
      !['buy', 'sell'].contains(normalizedSide) ||
      !entryPrice.isFinite ||
      !zoneLow.isFinite ||
      !zoneHigh.isFinite ||
      zoneLow <= 0 ||
      zoneHigh <= zoneLow ||
      entryPrice <= zoneLow ||
      entryPrice >= zoneHigh ||
      atr == null ||
      !atr.isFinite ||
      atr <= 0 ||
      !stopLossPercent.isFinite ||
      stopLossPercent <= 0 ||
      stopLossPercent >= 100 ||
      !minimumRiskReward.isFinite ||
      minimumRiskReward <= 0) {
    return (
      stopLossDecimal: null,
      takeProfitDecimal: null,
      actualRiskReward: null,
      blockerCode: 'structural_stop_unavailable',
      blockerMessage: 'Valid entry structure and ATR are required.',
      notionalScale: 0,
    );
  }
  final buy = normalizedSide == 'buy';
  final structureDistance = buy ? entryPrice - zoneLow : zoneHigh - entryPrice;
  final distance =
      structureDistance > atr * 0.8 ? structureDistance : atr * 0.8;
  final stopLoss = buy ? entryPrice - distance : entryPrice + distance;
  final scaledStop = stopLoss * math.pow(10, pricePrecision);
  if (!scaledStop.isFinite) {
    return (
      stopLossDecimal: null,
      takeProfitDecimal: null,
      actualRiskReward: null,
      blockerCode: 'structural_stop_invalid',
      blockerMessage: 'Structural stop is not a valid price.',
      notionalScale: 0,
    );
  }
  final stopLossDecimal = bingxFuturesPriceDecimal(
    stopLoss,
    precision: pricePrecision,
    roundUp: !buy,
  );
  final roundedStop = num.parse(stopLossDecimal);
  final riskDistance = (roundedStop - entryPrice).abs();
  if (!roundedStop.isFinite ||
      roundedStop <= 0 ||
      riskDistance <= 0 ||
      (buy ? roundedStop >= entryPrice : roundedStop <= entryPrice)) {
    return (
      stopLossDecimal: null,
      takeProfitDecimal: null,
      actualRiskReward: null,
      blockerCode: 'structural_stop_invalid',
      blockerMessage: 'Structural stop is not a valid price.',
      notionalScale: 0,
    );
  }
  // The configured percentage bounds loss at maximum notional; a wider
  // structural stop reduces size, never moves the stop inside the structure.
  final notionalScale =
      (entryPrice * stopLossPercent / 100 / riskDistance)
          .clamp(0, 1)
          .toDouble();
  final target = num.tryParse(oppositeLiquidityTargetDecimal?.trim() ?? '');
  if (target == null || !target.isFinite || target <= 0) {
    return (
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: null,
      actualRiskReward: null,
      blockerCode: 'opposite_liquidity_target_unavailable',
      blockerMessage: 'Fresh opposite liquidity is unavailable.',
      notionalScale: notionalScale,
    );
  }
  final takeProfitDecimal = bingxFuturesPriceDecimal(
    target,
    precision: pricePrecision,
    roundUp: !buy,
  );
  final roundedTarget = num.parse(takeProfitDecimal);
  final profitDistance =
      buy ? roundedTarget - entryPrice : entryPrice - roundedTarget;
  if (profitDistance <= 0) {
    return (
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: null,
      actualRiskReward: null,
      blockerCode: 'opposite_liquidity_target_wrong_side',
      blockerMessage: 'Opposite liquidity is not on the profitable side.',
      notionalScale: notionalScale,
    );
  }
  final actualRiskReward = profitDistance / riskDistance;
  if (!actualRiskReward.isFinite || actualRiskReward < minimumRiskReward) {
    return (
      stopLossDecimal: stopLossDecimal,
      takeProfitDecimal: takeProfitDecimal,
      actualRiskReward: actualRiskReward,
      blockerCode: 'opposite_liquidity_risk_reward_insufficient',
      blockerMessage:
          'Opposite liquidity does not meet the minimum risk/reward.',
      notionalScale: notionalScale,
    );
  }
  return (
    stopLossDecimal: stopLossDecimal,
    takeProfitDecimal: takeProfitDecimal,
    actualRiskReward: actualRiskReward,
    blockerCode: null,
    blockerMessage: null,
    notionalScale: notionalScale,
  );
}

String bingxFuturesPriceDecimal(
  num value, {
  required int precision,
  bool? roundUp,
}) {
  if (!value.isFinite || precision < 0 || precision > 8) {
    throw const FormatException('Invalid instrument price');
  }
  final factor = math.pow(10, precision);
  final scaled = value * factor;
  final units =
      roundUp == null
          ? scaled.round()
          : roundUp
          ? scaled.ceil()
          : scaled.floor();
  final fixed = (units / factor).toStringAsFixed(precision);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}
