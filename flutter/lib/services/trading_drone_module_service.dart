import 'app_runtime_service.dart';
import 'bingx_futures_credential_store.dart';
import 'bingx_futures_exchange_execution_use_case_service.dart';
import 'bingx_futures_exchange_risk_input_service.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_execution_queue_service.dart';
import 'bingx_futures_intent_use_case_service.dart';
import 'bingx_futures_live_strategy_use_case_service.dart';
import 'bingx_futures_observability_envelope_service.dart';
import 'bingx_futures_order_replacement_service.dart';
import 'bingx_futures_order_revalidation_service.dart';
import 'bingx_futures_order_sizing_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_signal_rank_use_case_service.dart';
import 'bingx_futures_strategy_naming_service.dart';
import 'capsule_chat_delivery_service.dart';
import 'manual_consensus_check_service.dart';
import 'plugin_host_api_service.dart';
import 'ui_event_log_service.dart';

class TradingDroneModule {
  final PluginHostApiService pluginHostApi;
  final ManualConsensusCheckService manualChecks;
  final BingxFuturesCredentialStore credentialStore;
  final BingxFuturesExchangeService exchangeService;
  final BingxFuturesOrderTrackingStore orderTrackingStore;
  final BingxFuturesExchangeRiskInputService exchangeRiskInput;
  final BingxFuturesOrderSizingService orderSizing;
  final BingxFuturesRiskGovernorService riskGovernor;
  final BingxFuturesObservabilityEnvelopeService observability;
  final BingxFuturesIntentUseCaseService intentUseCase;
  final BingxFuturesExchangeExecutionUseCaseService executionUseCase;
  final BingxFuturesSignalRankUseCaseService signalRankUseCase;
  final BingxFuturesOrderRevalidationService orderRevalidation;
  final BingxFuturesOrderReplacementService orderReplacement;
  final BingxFuturesLiveStrategyUseCaseService liveStrategyUseCase;
  final BingxFuturesStrategyNamingService strategyNaming;
  final CapsuleChatDeliveryService chatDelivery;
  final UiEventLogService uiLog;
  final BingxFuturesExecutionQueueService executionQueue;

  const TradingDroneModule({
    required this.pluginHostApi,
    required this.manualChecks,
    required this.credentialStore,
    required this.exchangeService,
    required this.orderTrackingStore,
    required this.exchangeRiskInput,
    required this.orderSizing,
    required this.riskGovernor,
    required this.observability,
    required this.intentUseCase,
    required this.executionUseCase,
    required this.signalRankUseCase,
    required this.orderRevalidation,
    required this.orderReplacement,
    required this.liveStrategyUseCase,
    required this.strategyNaming,
    required this.chatDelivery,
    required this.uiLog,
    required this.executionQueue,
  });
}

class TradingDroneModuleService {
  final AppRuntimeService runtime;

  const TradingDroneModuleService({
    required this.runtime,
  });

  TradingDroneModule build() {
    final pluginHostApi = runtime.buildPluginHostApiService();
    final exchangeService = runtime.buildBingxFuturesExchangeService();
    final observability = const BingxFuturesObservabilityEnvelopeService();
    final executionQueue = BingxFuturesExecutionQueueService(
      exchangeService: exchangeService,
    );
    final exchangeRiskInput = const BingxFuturesExchangeRiskInputService();
    final riskGovernor = const BingxFuturesRiskGovernorService();
    return TradingDroneModule(
      pluginHostApi: pluginHostApi,
      manualChecks: runtime.buildManualConsensusCheckService(),
      credentialStore: runtime.buildBingxFuturesCredentialStore(),
      exchangeService: exchangeService,
      orderTrackingStore: runtime.buildBingxFuturesOrderTrackingStore(),
      exchangeRiskInput: exchangeRiskInput,
      orderSizing: BingxFuturesOrderSizingService(exchange: exchangeService),
      riskGovernor: riskGovernor,
      observability: observability,
      intentUseCase: BingxFuturesIntentUseCaseService(
        hostApi: pluginHostApi,
        observability: observability,
      ),
      executionUseCase: BingxFuturesExchangeExecutionUseCaseService(
        exchange: exchangeService,
        queue: executionQueue,
        riskInput: exchangeRiskInput,
        riskGovernor: riskGovernor,
        observability: observability,
      ),
      signalRankUseCase: BingxFuturesSignalRankUseCaseService(
        hostApi: pluginHostApi,
      ),
      orderRevalidation: const BingxFuturesOrderRevalidationService(),
      orderReplacement: const BingxFuturesOrderReplacementService(),
      liveStrategyUseCase: BingxFuturesLiveStrategyUseCaseService(
        exchange: exchangeService,
      ),
      strategyNaming: const BingxFuturesStrategyNamingService(),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      uiLog: const UiEventLogService(),
      executionQueue: executionQueue,
    );
  }
}
