import '../models/bingx_futures_exchange_models.dart';
import 'app_runtime_service.dart';
import 'bingx_futures_credential_store.dart';
import 'bingx_futures_exchange_execution_use_case_service.dart';
import 'bingx_futures_exchange_risk_input_service.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_execution_queue_service.dart';
import 'bingx_futures_intent_use_case_service.dart';
import 'bingx_futures_live_strategy_use_case_service.dart';
import 'bingx_futures_live_snapshot_builder_service.dart';
import 'bingx_futures_observability_envelope_service.dart';
import 'bingx_futures_order_replacement_service.dart';
import 'bingx_futures_order_revalidation_service.dart';
import 'bingx_futures_order_sizing_service.dart';
import 'bingx_futures_order_tracking_store.dart';
import 'bingx_futures_public_session_stream_service.dart';
import 'bingx_futures_remote_runner_identity_service.dart';
import 'bingx_futures_remote_runner_provisioning_service.dart';
import 'bingx_futures_risk_governor_service.dart';
import 'bingx_futures_risk_history_service.dart';
import 'bingx_futures_signal_rank_use_case_service.dart';
import 'bingx_futures_strategy_naming_service.dart';
import 'bingx_futures_trading_cycle_use_case_service.dart';
import 'bingx_futures_volume_growth_filter_service.dart';
import 'capsule_chat_delivery_service.dart';
import 'capsule_contact_label_store.dart';
import 'capsule_passive_receive_coordinator.dart';
import 'consensus_attestation_exchange_service.dart';
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
  final BingxFuturesRiskHistoryService riskHistory;
  final BingxFuturesObservabilityEnvelopeService observability;
  final BingxFuturesIntentUseCaseService intentUseCase;
  final BingxFuturesExchangeExecutionUseCaseService executionUseCase;
  final BingxFuturesSignalRankUseCaseService signalRankUseCase;
  final BingxFuturesOrderRevalidationService orderRevalidation;
  final BingxFuturesOrderReplacementService orderReplacement;
  final BingxFuturesPublicSessionStreamService publicSessionStream;
  final BingxFuturesRemoteRunnerIdentityService remoteRunnerIdentity;
  final BingxFuturesRemoteRunnerProvisioningService remoteRunnerProvisioning;
  final BingxFuturesLiveStrategyUseCaseService liveStrategyUseCase;
  final BingxFuturesStrategyNamingService strategyNaming;
  final BingxFuturesVolumeGrowthFilterService volumeGrowthFilter;
  final BingxFuturesTradingCycleUseCaseService cycleUseCase;
  final CapsuleChatDeliveryService chatDelivery;
  final CapsulePassiveReceivePort passiveReceive;
  final CapsuleContactLabelStore contactLabels;
  final ConsensusAttestationExchangeService attestationExchange;
  final UiEventLogService uiLog;
  final String? Function() activeCapsuleRootHex;
  final String? Function(String commitmentHashHex) signRootCommitment;
  final bool Function({
    required String commitmentHashHex,
    required String capsuleRootHex,
    required String signatureHex,
  })
  verifyRootCommitmentSignature;

  const TradingDroneModule({
    required this.pluginHostApi,
    required this.manualChecks,
    required this.credentialStore,
    required this.exchangeService,
    required this.orderTrackingStore,
    required this.exchangeRiskInput,
    required this.orderSizing,
    required this.riskGovernor,
    required this.riskHistory,
    required this.observability,
    required this.intentUseCase,
    required this.executionUseCase,
    required this.signalRankUseCase,
    required this.orderRevalidation,
    required this.orderReplacement,
    required this.publicSessionStream,
    required this.remoteRunnerIdentity,
    required this.remoteRunnerProvisioning,
    required this.liveStrategyUseCase,
    required this.strategyNaming,
    required this.volumeGrowthFilter,
    required this.cycleUseCase,
    required this.chatDelivery,
    required this.passiveReceive,
    required this.contactLabels,
    required this.attestationExchange,
    required this.uiLog,
    required this.activeCapsuleRootHex,
    required this.signRootCommitment,
    required this.verifyRootCommitmentSignature,
  });

  String accountBindingHashHex(BingxFuturesApiCredentials credentials) =>
      BingxFuturesExchangeExecutionUseCaseService.accountBindingHashHex(
        credentials,
      );
}

class TradingDroneModuleService {
  final AppRuntimeService runtime;

  const TradingDroneModuleService({required this.runtime});

  TradingDroneModule build() {
    final pluginHostApi = runtime.buildPluginHostApiService();
    final exchangeService = runtime.buildBingxFuturesExchangeService();
    final observability = const BingxFuturesObservabilityEnvelopeService();
    final executionQueue = BingxFuturesExecutionQueueService(
      exchangeService: exchangeService,
    );
    final exchangeRiskInput = const BingxFuturesExchangeRiskInputService();
    final riskGovernor = const BingxFuturesRiskGovernorService();
    final riskHistory = runtime.buildBingxFuturesRiskHistoryService();
    final orderTrackingStore = runtime.buildBingxFuturesOrderTrackingStore();
    final orderSizing = BingxFuturesOrderSizingService(
      exchange: exchangeService,
    );
    final intentUseCase = BingxFuturesIntentUseCaseService(
      hostApi: pluginHostApi,
      observability: observability,
    );
    final executionUseCase = BingxFuturesExchangeExecutionUseCaseService(
      exchange: exchangeService,
      queue: executionQueue,
      riskInput: exchangeRiskInput,
      riskGovernor: riskGovernor,
      riskHistory: riskHistory,
      orderTrackingStore: orderTrackingStore,
      observability: observability,
    );
    final publicSessionStream = BingxFuturesPublicSessionStreamService();
    final remoteRunnerIdentity = BingxFuturesRemoteRunnerIdentityService(
      readActiveCapsuleRootHex: runtime.activeCapsuleRootHex,
    );
    final snapshotBuilder = const BingxFuturesLiveSnapshotBuilderService();
    final liveStrategyUseCase = BingxFuturesLiveStrategyUseCaseService(
      exchange: exchangeService,
      loadSnapshot:
          ({required exchange, required symbol}) =>
              snapshotBuilder.fetchAndBuild(
                exchange: exchange,
                symbol: symbol,
                sessionVolumes: publicSessionStream.snapshotFor(symbol),
              ),
    );
    return TradingDroneModule(
      pluginHostApi: pluginHostApi,
      manualChecks: runtime.buildManualConsensusCheckService(),
      credentialStore: runtime.buildBingxFuturesCredentialStore(),
      exchangeService: exchangeService,
      orderTrackingStore: orderTrackingStore,
      exchangeRiskInput: exchangeRiskInput,
      orderSizing: orderSizing,
      riskGovernor: riskGovernor,
      riskHistory: riskHistory,
      observability: observability,
      intentUseCase: intentUseCase,
      executionUseCase: executionUseCase,
      signalRankUseCase: BingxFuturesSignalRankUseCaseService(
        hostApi: pluginHostApi,
      ),
      orderRevalidation: const BingxFuturesOrderRevalidationService(),
      orderReplacement: const BingxFuturesOrderReplacementService(),
      publicSessionStream: publicSessionStream,
      remoteRunnerIdentity: remoteRunnerIdentity,
      remoteRunnerProvisioning: BingxFuturesRemoteRunnerProvisioningService(
        activeCapsuleRootHex: runtime.activeCapsuleRootHex,
        identity: remoteRunnerIdentity,
      ),
      liveStrategyUseCase: liveStrategyUseCase,
      strategyNaming: const BingxFuturesStrategyNamingService(),
      volumeGrowthFilter: const BingxFuturesVolumeGrowthFilterService(),
      cycleUseCase: BingxFuturesTradingCycleUseCaseService(
        liveStrategy: liveStrategyUseCase,
        orderSizing: orderSizing,
        intentUseCase: intentUseCase,
        executionUseCase: executionUseCase,
      ),
      chatDelivery: runtime.buildCapsuleChatDeliveryService(),
      passiveReceive: runtime.passiveReceive,
      contactLabels: runtime.buildCapsuleContactLabelStore(),
      attestationExchange: runtime.buildConsensusAttestationExchangeService(),
      uiLog: const UiEventLogService(),
      activeCapsuleRootHex: runtime.activeCapsuleRootHex,
      signRootCommitment: runtime.signRootCommitment,
      verifyRootCommitmentSignature: runtime.verifyRootCommitmentSignature,
    );
  }
}
