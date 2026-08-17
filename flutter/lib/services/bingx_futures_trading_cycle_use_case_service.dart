import 'dart:async';

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
  final double fallbackEquityQuote;
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
    required this.fallbackEquityQuote,
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
      required double fallbackEquityQuote,
      required bool testOrder,
      BingxFuturesLiveDecisionResult? preparedDecision,
      Future<BingxFuturesLiveDecisionResult?> Function()? refreshDecision,
    });

class BingxFuturesTradingCycleUseCaseService {
  final BingxFuturesLiveStrategyCycleRunner _runLiveStrategy;
  final BingxFuturesOrderSizingCycleRunner _runSizing;
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
    BingxFuturesIntentCycleRunner? intentRunner,
    BingxFuturesExecutionCycleRunner? executionRunner,
    DateTime Function()? nowUtc,
    Duration intentTimeout = const Duration(seconds: 20),
  }) : assert(liveStrategyRunner != null || liveStrategy != null),
       assert(sizingRunner != null || orderSizing != null),
       assert(intentRunner != null || intentUseCase != null),
       assert(executionRunner != null || executionUseCase != null),
       _runLiveStrategy = liveStrategyRunner ?? liveStrategy!.execute,
       _runSizing = sizingRunner ?? orderSizing!.size,
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
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        'market_decision_blocked',
        'No executable market decision is available.',
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

    final sizing = await _runSizing(
      symbol: symbol,
      maximumNotionalQuote: command.maximumNotionalQuote,
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

    final zoneLow = num.tryParse(decision.zoneLowDecimal!);
    final zoneHigh = num.tryParse(decision.zoneHighDecimal!);
    if (zoneLow == null || zoneHigh == null || zoneLow <= 0 || zoneHigh <= 0) {
      return _blocked(
        BingxFuturesTradingCycleStatus.marketBlocked,
        'liquidity_zone_invalid',
        'Liquidity zone is invalid.',
        decision: decision,
        sizing: sizing,
      );
    }
    final entryPrice = (zoneLow + zoneHigh) / 2;
    final targets = _riskTargets(
      side: decision.side!,
      entryPrice: entryPrice,
      stopLossPercent: command.stopLossPercent,
      riskReward: command.takeProfitRiskReward,
    );
    late final BingxFuturesIntentUseCaseResult intent;
    try {
      intent = await _runIntent(
        BingxFuturesIntentCommand(
          screen: command.screen,
          peerHex: '',
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
          zonePriceRule: 'zone_mid',
          manualEntryPriceDecimal: null,
          triggerPriceDecimal:
              decision.side == 'buy'
                  ? decision.zoneHighDecimal!
                  : decision.zoneLowDecimal!,
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
      fallbackEquityQuote: command.fallbackEquityQuote,
      testOrder: command.testOrder,
      preparedDecision: decision,
      refreshDecision: () async {
        final refreshed = await _loadDecision(command, symbol, preferredSide);
        return refreshed.decision;
      },
    );
    return BingxFuturesTradingCycleResult(
      status:
          execution.status ==
                  BingxFuturesExchangeExecutionUseCaseStatus.executed
              ? BingxFuturesTradingCycleStatus.executed
              : BingxFuturesTradingCycleStatus.executionBlocked,
      reasonCode:
          execution.errorCode ??
          (execution.status ==
                  BingxFuturesExchangeExecutionUseCaseStatus.executed
              ? 'effect_executed'
              : execution.status.name),
      reasonMessage:
          execution.errorMessage ??
          (execution.status ==
                  BingxFuturesExchangeExecutionUseCaseStatus.executed
              ? 'Exchange effect executed.'
              : 'Exchange effect was blocked.'),
      decision: decision,
      sizing: sizing,
      intent: intent,
      execution: execution,
      stopLossDecimal: targets.stopLossDecimal,
      takeProfitDecimal: targets.takeProfitDecimal,
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
        isConsensusSignable: true,
        blockingFactCodes: const <String>[],
        recentMicroBars: command.recentMicroBars,
        zoneNearBps: command.zoneNearBps,
        zoneFarBps: command.zoneFarBps,
        zoneEvaluationSide: preferredSide,
      ),
    );
  }

  ({String stopLossDecimal, String takeProfitDecimal}) _riskTargets({
    required String side,
    required num entryPrice,
    required double stopLossPercent,
    required double riskReward,
  }) {
    final stopFactor = stopLossPercent / 100;
    final buy = side == 'buy';
    final stopLoss =
        buy ? entryPrice * (1 - stopFactor) : entryPrice * (1 + stopFactor);
    final risk = (stopLoss - entryPrice).abs();
    final takeProfit =
        buy
            ? entryPrice + (risk * riskReward)
            : entryPrice - (risk * riskReward);
    return (
      stopLossDecimal: _formatDecimal(stopLoss),
      takeProfitDecimal: _formatDecimal(takeProfit),
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
