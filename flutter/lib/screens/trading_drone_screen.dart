import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_exchange_execution_models.dart';
import '../models/bingx_futures_intent_models.dart';
import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_live_strategy_models.dart';
import '../models/bingx_futures_order_sizing_models.dart';
import '../models/bingx_futures_order_tracking_models.dart';
import '../models/bingx_futures_order_replacement_models.dart';
import '../models/bingx_futures_risk_models.dart';
import '../models/bingx_futures_signal_rank_models.dart';
import '../models/capsule_chat_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../services/app_runtime_service.dart';
import '../services/capsule_passive_receive_coordinator.dart';
import '../services/consensus_attestation_exchange_service.dart';
import '../services/trading_drone_module_service.dart';
import '../services/bingx_futures_trading_cycle_use_case_service.dart';
import '../services/bingx_futures_remote_runner_provisioning_service.dart';
import '../utils/bingx_futures_zone_evidence_formatter.dart';
import '../utils/peer_identity_format.dart';

part 'trading_drone_screen_remote_session.dart';
part 'trading_drone_screen_market_scan.dart';
part 'trading_drone_screen_execution.dart';
part 'trading_drone_screen_presentation.dart';

const String preparedTradingIntentTerminalOutcome = 'intent:prepared';
const List<int> tradingEffectBudgetOptions = <int>[1, 2, 4, 8, 16, 32];

@visibleForTesting
String tradingPreparedSessionApplyCommand({
  required String runnerKeyId,
  required String mandateFileName,
}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(runnerKeyId)) {
    throw const FormatException('Invalid prepared-session command input.');
  }
  final safeFileName =
      mandateFileName.isNotEmpty &&
              utf8.encode(mandateFileName).length <= 255 &&
              !mandateFileName.contains('/') &&
              !mandateFileName.contains('\\') &&
              !mandateFileName.contains('\n') &&
              !mandateFileName.contains('\r')
          ? mandateFileName
          : 'signed-session.json';
  final quotedRemotePath =
      "'/path/to/${safeFileName.replaceAll("'", "'\"'\"'")}'";
  return 'sudo ./public_shadow_runner_artifact.sh '
      '--apply-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runnerKeyId '
      '--mandate-artifact $quotedRemotePath';
}

@visibleForTesting
String tradingPreparedSessionActivationCommand({required String runnerKeyId}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(runnerKeyId)) {
    throw const FormatException('Invalid prepared-session command input.');
  }
  return 'sudo ./public_shadow_runner_artifact.sh '
      '--activate-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runnerKeyId';
}

@visibleForTesting
String tradingPreparedSessionRunCommand({required String runnerKeyId}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(runnerKeyId)) {
    throw const FormatException('Invalid prepared-session command input.');
  }
  return 'sudo ./public_shadow_runner_artifact.sh '
      '--run-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runnerKeyId';
}

@visibleForTesting
String tradingPreparedSessionServiceEnableCommand({
  required String runnerKeyId,
}) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(runnerKeyId)) {
    throw const FormatException('Invalid prepared-session command input.');
  }
  return 'sudo ./public_shadow_runner_artifact.sh '
      '--enable-prepared-session-service /path/to/runner-bundle '
      '--expected-runner-key-id $runnerKeyId';
}

@visibleForTesting
String tradingPreparedSessionServicePauseCommand() =>
    'sudo ./public_shadow_runner_artifact.sh '
    '--pause-prepared-session-service /path/to/runner-bundle';

@visibleForTesting
String tradingPreparedSessionServiceStatusCommand() =>
    'sudo ./public_shadow_runner_artifact.sh '
    '--prepared-session-service-status /path/to/runner-bundle';

const int tradingRemoteSessionIntervalSeconds = 300;
const Duration tradingRemoteSessionProvisioningLeadTime = Duration(minutes: 15);

@visibleForTesting
DateTime tradingRemoteSessionFirstCycleStart(DateTime nowUtc) {
  final earliest = nowUtc.toUtc().add(tradingRemoteSessionProvisioningLeadTime);
  final seconds = earliest.millisecondsSinceEpoch ~/ 1000;
  final alignedSeconds =
      ((seconds + tradingRemoteSessionIntervalSeconds - 1) ~/
          tradingRemoteSessionIntervalSeconds) *
      tradingRemoteSessionIntervalSeconds;
  return DateTime.fromMillisecondsSinceEpoch(
    alignedSeconds * 1000,
    isUtc: true,
  );
}

@visibleForTesting
Future<String> runTradingIntentWithTerminalEvidence({
  required Future<String> Function() pipeline,
  required Future<void> Function(String source, String message) log,
}) async {
  final stopwatch = Stopwatch()..start();
  var outcome = 'error:unhandled';
  try {
    await log('bingx.intent.tap', 'accepted=true');
    outcome = await pipeline();
    return outcome;
  } catch (error) {
    await log(
      'bingx.intent.error',
      '$error elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    rethrow;
  } finally {
    await log(
      'bingx.intent.finally',
      'outcome=$outcome elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
  }
}

@visibleForTesting
String tradingSignalScanActionLabel({required bool scanning}) =>
    scanning ? 'Scanning' : 'Refresh Scan';

@visibleForTesting
String tradingOrderBudgetLabel(int value) =>
    '$value exchange order${value == 1 ? '' : 's'}';

@visibleForTesting
int tradingRestoredEffectBudget(BingxFuturesTradingMandate mandate) =>
    tradingEffectBudgetOptions.contains(mandate.maxEffects)
        ? mandate.maxEffects
        : tradingEffectBudgetOptions.first;

@visibleForTesting
String tradingIntentStatusLabel(PluginHostApiStatus? status) {
  if (status == null) return 'idle';
  return status == PluginHostApiStatus.executed ? 'prepared' : status.name;
}

@visibleForTesting
bool tradingUsesTestEndpointAfterRestore({
  required BingxFuturesTradingMandate? mandate,
  required DateTime nowUtc,
}) =>
    mandate == null || !mandate.isActiveAt(nowUtc.toUtc())
        ? false
        : mandate.testOrder;

String tradingPreferredSideForCycle({
  required String symbol,
  required String currentSide,
  required List<BingxFuturesSignalRankEntry> rankedEntries,
}) {
  final normalizedSymbol = symbol.trim().toUpperCase();
  for (final entry in rankedEntries) {
    if (entry.symbol.trim().toUpperCase() != normalizedSymbol ||
        entry.bucket != 'ready' ||
        !entry.canPrepareIntent) {
      continue;
    }
    final rankedSide = entry.side?.trim().toLowerCase();
    if (rankedSide == 'buy' || rankedSide == 'sell') {
      return rankedSide!;
    }
  }
  return currentSide;
}

String tradingSideAfterCycle({
  required String currentSide,
  required bool cyclePrepared,
  required String? decisionSide,
}) {
  if (!cyclePrepared) return currentSide;
  final normalizedSide = decisionSide?.trim().toLowerCase();
  return normalizedSide == 'buy' || normalizedSide == 'sell'
      ? normalizedSide!
      : currentSide;
}

String tradingZoneSideForOrderSide(String orderSide) =>
    orderSide.trim().toLowerCase() == 'buy' ? 'buyside' : 'sellside';

@visibleForTesting
String? tradingManagedOrderStructuralSide(String orderSide) {
  final normalized = orderSide.trim().toLowerCase();
  return normalized == 'buy' || normalized == 'sell' ? normalized : null;
}

String tradingZoneSideAfterCycle({
  required String currentZoneSide,
  required bool cyclePrepared,
  required String? decisionZoneSide,
}) {
  if (!cyclePrepared) return currentZoneSide;
  final normalizedZoneSide = decisionZoneSide?.trim().toLowerCase();
  return normalizedZoneSide == 'buyside' || normalizedZoneSide == 'sellside'
      ? normalizedZoneSide!
      : currentZoneSide;
}

@visibleForTesting
bool tradingCycleProjectsExecutableZone({
  required bool cyclePrepared,
  required bool decisionCanPrepareIntent,
}) => cyclePrepared && decisionCanPrepareIntent;

@visibleForTesting
String? tradingReconciliationResumeSymbol(
  BingxFuturesOrderTrackingState state,
) {
  String? normalize(String? value) {
    final symbol = value?.trim().toUpperCase() ?? '';
    return symbol.isEmpty ? null : symbol;
  }

  bool isTerminal(BingxManagedOrderLifecycleStatus status) =>
      status == BingxManagedOrderLifecycleStatus.filled ||
      status == BingxManagedOrderLifecycleStatus.cancelled ||
      status == BingxManagedOrderLifecycleStatus.rejected ||
      status == BingxManagedOrderLifecycleStatus.expired;

  final tracked = normalize(state.trackedSymbol);
  if (tracked != null) return tracked;

  final managedIds = state.managedOrderIds.toList()..sort();
  for (final orderId in managedIds) {
    final symbol = normalize(state.managedOrderSymbols[orderId]);
    if (symbol != null) return symbol;
  }

  final provenance =
      state.managedOrderProvenance.values.toList()
        ..sort((a, b) => a.orderId.compareTo(b.orderId));
  for (final record in provenance) {
    if (record.testOrder || isTerminal(record.lifecycleStatus)) continue;
    final symbol = normalize(record.symbol);
    if (symbol != null) return symbol;
  }

  final claims =
      state.liquidityEventEffectClaims.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in claims) {
    final claim = entry.value;
    if (claim.testOrder || isTerminal(claim.lifecycleStatus)) continue;
    final symbol = normalize(claim.symbol);
    if (symbol != null) return symbol;
  }
  return null;
}

@visibleForTesting
bool tradingMandateMaxNotionalMatches({
  required BingxFuturesTradingMandate mandate,
  required String selectedMaxNotional,
}) {
  final authorizedMax = num.tryParse(
    mandate.maxOrderNotionalQuoteDecimal.trim(),
  );
  final selectedMax = num.tryParse(selectedMaxNotional.trim());
  return authorizedMax != null &&
      authorizedMax.isFinite &&
      selectedMax != null &&
      selectedMax.isFinite &&
      authorizedMax == selectedMax;
}

@visibleForTesting
bool tradingMandateMatchesSelection({
  required BingxFuturesTradingMandate? mandate,
  required bool droneEnabled,
  required String selectedSymbol,
  required String selectedMaxNotional,
  required int selectedMaxEffects,
  required bool testOrder,
  required DateTime nowUtc,
}) {
  if (!droneEnabled || mandate == null || !mandate.isActiveAt(nowUtc)) {
    return false;
  }
  final normalizedSymbol = selectedSymbol.trim().toUpperCase();
  return mandate.symbol == normalizedSymbol &&
      mandate.testOrder == testOrder &&
      mandate.maxEffects == selectedMaxEffects &&
      tradingMandateMaxNotionalMatches(
        mandate: mandate,
        selectedMaxNotional: selectedMaxNotional,
      );
}

@visibleForTesting
bool tradingHasExecutableIntent({
  required PluginHostApiStatus? status,
  required bool hasResult,
  required BingxFuturesTradingMandate? mandate,
  required bool droneEnabled,
  required String selectedSymbol,
  required String selectedMaxNotional,
  required int selectedMaxEffects,
  required bool testOrder,
  required DateTime nowUtc,
}) =>
    status == PluginHostApiStatus.executed &&
    hasResult &&
    tradingMandateMatchesSelection(
      mandate: mandate,
      droneEnabled: droneEnabled,
      selectedSymbol: selectedSymbol,
      selectedMaxNotional: selectedMaxNotional,
      selectedMaxEffects: selectedMaxEffects,
      testOrder: testOrder,
      nowUtc: nowUtc,
    );

@visibleForTesting
String? tradingMandateSelectionNotice({
  required BingxFuturesTradingMandate? mandate,
  required bool droneEnabled,
  required String selectedSymbol,
  required String selectedMaxNotional,
  required int selectedMaxEffects,
  required bool testOrder,
  required DateTime nowUtc,
}) {
  if (!droneEnabled || mandate == null) return null;
  if (!mandate.isActiveAt(nowUtc)) {
    return 'Trading mandate expired. Re-authorize before exact export.';
  }
  final normalizedSymbol = selectedSymbol.trim().toUpperCase();
  if (tradingMandateMatchesSelection(
    mandate: mandate,
    droneEnabled: droneEnabled,
    selectedSymbol: selectedSymbol,
    selectedMaxNotional: selectedMaxNotional,
    selectedMaxEffects: selectedMaxEffects,
    testOrder: testOrder,
    nowUtc: nowUtc,
  )) {
    return null;
  }
  final authorizedMode = mandate.testOrder ? 'TEST' : 'LIVE';
  final selectedMode = testOrder ? 'TEST' : 'LIVE';
  return 'Authorized for ${mandate.symbol} $authorizedMode at max '
      '${mandate.maxOrderNotionalQuoteDecimal} USDT and '
      '${tradingOrderBudgetLabel(mandate.maxEffects)}. Selected '
      '$normalizedSymbol $selectedMode at max '
      '${selectedMaxNotional.trim()} USDT and '
      '${tradingOrderBudgetLabel(selectedMaxEffects)}. '
      'Re-authorize before remote export.';
}

@visibleForTesting
String tradingSignalSnapshotLabel(DateTime observedAtUtc) {
  final observed = observedAtUtc.toUtc().toIso8601String();
  return 'Snapshot $observed. READY is observational; Run Intent revalidates current market.';
}

class TradingDroneScreen extends StatefulWidget {
  final AppRuntimeService? runtime;

  const TradingDroneScreen({super.key, this.runtime});

  @override
  State<TradingDroneScreen> createState() => _TradingDroneScreenState();
}

class _TradingDroneScreenState extends State<TradingDroneScreen> {
  static const Duration _hostIntentTimeout = Duration(seconds: 20);
  static const Duration _openOrdersPollInterval = Duration(seconds: 12);
  static const double _zoneNearBps = 15.0;
  static const double _zoneFarBps = 35.0;
  static const double _fallbackRiskEquityQuote = 100.0;
  static const double _defaultStopLossPercent = 10.0;
  static const List<double> _stopLossPercentOptions = <double>[
    5.0,
    7.0,
    10.0,
    12.0,
  ];
  static const double _defaultTakeProfitRiskReward = 2.0;
  static const List<double> _takeProfitRiskRewardOptions = <double>[
    1.5,
    2.0,
    3.0,
  ];
  static const int _recentMicroBars = 8;
  static const List<String> _shortBreakdownSymbols = <String>[
    'BTC-USDT',
    'ETH-USDT',
    'SOL-USDT',
    'XRP-USDT',
    'BNB-USDT',
    'DOGE-USDT',
  ];
  static const String _signalScanScopeCore = 'core_watchlist';
  static const String _signalScanScopeAllPerps = 'all_perps';
  static const int _signalTickerPrefilterLimit = 80;
  static const int _signalVolumeGrowthKlineLimit = 10;

  late final TradingDroneModule _module;

  final TextEditingController _peerController = TextEditingController();
  final TextEditingController _symbolController = TextEditingController(
    text: 'BTC-USDT',
  );
  final TextEditingController _maxNotionalUsdtController =
      TextEditingController(text: '100');
  final TextEditingController _quantityController = TextEditingController(
    text: '0.01',
  );
  final TextEditingController _limitPriceController = TextEditingController();
  final TextEditingController _zoneLowController = TextEditingController();
  final TextEditingController _zoneHighController = TextEditingController();
  final TextEditingController _triggerPriceController = TextEditingController();
  final TextEditingController _stopLossController = TextEditingController();
  final TextEditingController _takeProfitController = TextEditingController();
  final TextEditingController _strategyTagController = TextEditingController(
    text: 'demo',
  );
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiSecretController = TextEditingController();
  final TextEditingController _cancelOrderIdController =
      TextEditingController();

  bool _runningIntent = false;
  String _intentProgressLabel = 'Starting';
  bool _broadcastingSignal = false;
  bool _savingCredentials = false;
  bool _executing = false;
  bool _refreshingSignals = false;
  bool _fetchingOpenOrders = false;
  bool _loadingPerpSymbols = false;
  bool _scanningSignals = false;
  bool _signalRankExpanded = true;
  bool _cancelingOrder = false;
  bool _fittingMaxNotional = false;
  bool _useTestOrderEndpoint = false;
  bool _droneEnabled = false;
  BingxFuturesTradingMandate? _tradingMandate;
  bool _tradingControlLoaded = false;
  bool _savingTradingControl = false;
  bool _exportingRemoteMandate = false;
  bool _exportingRemoteRevocation = false;
  double _stopLossPercent = _defaultStopLossPercent;
  double _takeProfitRiskReward = _defaultTakeProfitRiskReward;
  int _maxEffects = 1;

  String _side = 'buy';
  String _orderType = 'limit';
  String _timeInForce = 'GTC';
  String _entryMode = 'direct';
  String _zoneSide = 'buyside';
  String _zonePriceRule = 'zone_mid';
  String _signalScanScope = _signalScanScopeCore;

  PluginHostApiResponse? _lastIntentResponse;
  BingxFuturesLiveDecisionResult? _lastPreparedLiveDecision;
  String? _intentBlockingMessage;
  BingxFuturesOrderExecutionResult? _lastExecution;
  BingxFuturesOpenOrdersResult? _lastOpenOrdersRead;
  BingxFuturesCancelOrderResult? _lastCancelOrder;
  List<BingxFuturesOpenOrder> _openOrders = const <BingxFuturesOpenOrder>[];
  final Set<String> _managedOrderIds = <String>{};
  final Map<String, String> _managedOrderSymbols = <String, String>{};
  final Map<String, BingxManagedOrderProvenance> _managedOrderProvenance =
      <String, BingxManagedOrderProvenance>{};
  int _managedOrderLifecycleRevision = 0;
  Timer? _openOrdersPollTimer;
  String? _trackedOrdersSymbol;
  String? _trackedOrderId;
  Future<BingxFuturesApiCredentials?>? _credentialsLoadFuture;
  int _lastExecutionAttempts = 0;
  bool _lastExecutionFromCache = false;
  List<CapsuleTradeSignalInboxMessage> _signalInbox =
      const <CapsuleTradeSignalInboxMessage>[];
  List<String> _availablePerpSymbols = const <String>[];
  List<BingxFuturesSignalRankEntry> _signalRankEntries =
      const <BingxFuturesSignalRankEntry>[];
  DateTime? _signalScanCompletedAtUtc;
  Map<String, BingxFuturesLiveDecisionResult> _signalDecisionByHash =
      const <String, BingxFuturesLiveDecisionResult>{};
  BingxFuturesLiveDecisionResult? _displayedZoneDecision;

  static const BingxFuturesRiskPolicy _executionRiskPolicy =
      BingxFuturesRiskPolicy(
        maxRiskPerTradePercent: 2.0,
        maxDailyLossPercent: 5.0,
        maxConcurrentPositions: 3,
        cooldownAfterLossStreak: 2,
        cooldownMinutes: 60,
      );

  void _updateState(VoidCallback mutation) => setState(mutation);

  @override
  void initState() {
    super.initState();
    _module =
        TradingDroneModuleService(
          runtime: widget.runtime ?? AppRuntimeService(),
        ).build();
    unawaited(_primePublicSessionEvidence(_symbolController.text));
    unawaited(_restoreOpenOrdersTrackingState());
    _loadPerpetualSymbols(silent: true);
    _signalInbox = _module.chatDelivery.loadCachedTradeSignals();
    _refreshSignalInbox(silentWhenEmpty: true);
  }

  @override
  void dispose() {
    _openOrdersPollTimer?.cancel();
    unawaited(_module.publicSessionStream.disconnect());
    _peerController.dispose();
    _symbolController.dispose();
    _maxNotionalUsdtController.dispose();
    _quantityController.dispose();
    _limitPriceController.dispose();
    _zoneLowController.dispose();
    _zoneHighController.dispose();
    _triggerPriceController.dispose();
    _stopLossController.dispose();
    _takeProfitController.dispose();
    _strategyTagController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _cancelOrderIdController.dispose();
    super.dispose();
  }

  Future<bool> _primePublicSessionEvidence(
    String symbol, {
    bool reportFailure = false,
  }) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    try {
      await _module.publicSessionStream.ensureConnected(normalized);
      await _module.uiLog.log(
        'bingx.market.session_stream',
        'status=connected symbol=$normalized effect=false',
      );
      return true;
    } catch (error) {
      await _module.uiLog.log(
        'bingx.market.session_stream.error',
        'symbol=$normalized error=$error effect=false',
      );
      if (reportFailure) {
        await _showSnack(
          'Live session evidence is unavailable. No order can be prepared.',
          seconds: 4,
        );
      }
      return false;
    }
  }

  bool get _isTrackingOpenOrders => _openOrdersPollTimer != null;

  int get _managedOpenOrderCount =>
      _openOrders
          .where((order) => _managedOrderIds.contains(order.orderId))
          .length;

  void _registerManagedOrderId(
    String? orderId, {
    String? symbol,
    BingxManagedOrderProvenance? provenance,
  }) {
    final normalized = orderId?.trim() ?? '';
    if (normalized.isEmpty) return;
    final normalizedSymbol = symbol?.trim().toUpperCase();
    final added = _managedOrderIds.add(normalized);
    var updated = added;
    if (normalizedSymbol != null && normalizedSymbol.isNotEmpty) {
      if (_managedOrderSymbols[normalized] != normalizedSymbol) {
        _managedOrderSymbols[normalized] = normalizedSymbol;
        updated = true;
      }
    }
    if (provenance != null && provenance.orderId == normalized) {
      _managedOrderProvenance[normalized] = provenance;
      updated = true;
    }
    if (updated) {
      _managedOrderLifecycleRevision += 1;
      unawaited(_persistOpenOrdersTrackingState(source: 'register_order_id'));
    }
  }

  BingxManagedOrderProvenance? _buildManagedOrderProvenance({
    required String orderId,
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> result,
    required bool testOrder,
    required BingxFuturesApiCredentials credentials,
  }) {
    final intentHash = payload.intentHashHex?.trim() ?? '';
    final canonicalIntent = result['canonical_intent_json']?.toString() ?? '';
    if (intentHash.isEmpty || canonicalIntent.trim().isEmpty) {
      unawaited(
        _module.uiLog.log(
          'bingx.exchange.provenance.skip',
          'orderId=$orderId symbol=${payload.symbol} '
              'reason=missing_intent_lineage',
        ),
      );
      return null;
    }
    return BingxManagedOrderProvenance(
      orderId: orderId,
      symbol: payload.symbol,
      side: payload.side,
      testOrder: testOrder,
      intentHashHex: intentHash,
      canonicalIntentJson: canonicalIntent,
      clientOrderId: payload.clientOrderId,
      accountBindingHashHex: _module.accountBindingHashHex(credentials),
      lifecycleStatus: BingxManagedOrderLifecycleStatus.active,
      lifecycleEvidenceAtUtc: DateTime.now().toUtc().toIso8601String(),
      marketSnapshotHashHex: result['market_snapshot_hash_hex']?.toString(),
      featureHashHex: result['feature_hash_hex']?.toString(),
      tvhDecisionHashHex: result['tvh_decision_hash_hex']?.toString(),
      liveDecisionHashHex: result['live_decision_hash_hex']?.toString(),
      recordedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
  }

  void _startOpenOrdersAutoTracking({
    required String symbol,
    String? orderId,
    bool allowReconciliationWithoutManagedOrder = false,
  }) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    final normalizedOrderId = orderId?.trim();
    if ((normalizedOrderId == null || normalizedOrderId.isEmpty) &&
        _managedOrderIds.isEmpty &&
        !allowReconciliationWithoutManagedOrder) {
      unawaited(
        _module.uiLog.log(
          'bingx.exchange.tracking.skip',
          'symbol=$normalizedSymbol reason=no_tracked_or_managed_orders',
        ),
      );
      return;
    }
    _openOrdersPollTimer?.cancel();
    _trackedOrdersSymbol = normalizedSymbol;
    if (normalizedOrderId != null && normalizedOrderId.isNotEmpty) {
      _trackedOrderId = normalizedOrderId;
      _registerManagedOrderId(normalizedOrderId, symbol: normalizedSymbol);
      _cancelOrderIdController.text = normalizedOrderId;
    } else {
      _trackedOrderId = null;
    }
    _openOrdersPollTimer = Timer.periodic(_openOrdersPollInterval, (_) {
      if (!mounted) return;
      unawaited(_fetchOpenOrders(silent: true));
    });
    unawaited(
      _module.uiLog.log(
        'bingx.exchange.tracking',
        'enabled symbol=$normalizedSymbol orderId=${_trackedOrderId ?? "-"} '
            'intervalSec=${_openOrdersPollInterval.inSeconds}',
      ),
    );
    if (mounted) {
      setState(() {});
    }
    unawaited(_persistOpenOrdersTrackingState(source: 'tracking_enabled'));
  }

  Future<bool> _resumeManagedOrderReconciliation({
    required String source,
  }) async {
    final state = await _module.orderTrackingStore.load();
    if (state == null) return false;
    final symbol = tradingReconciliationResumeSymbol(state);
    if (symbol == null) {
      await _module.uiLog.log(
        'bingx.exchange.tracking.resume.skip',
        'source=$source reason=no_unresolved_live_effect',
      );
      return false;
    }
    if (await _ensureCredentialsLoaded(silent: true) == null) {
      await _module.uiLog.log(
        'bingx.exchange.tracking.resume.deferred',
        'source=$source symbol=$symbol reason=credentials_not_loaded',
      );
      return false;
    }
    if (!_isTrackingOpenOrders) {
      _startOpenOrdersAutoTracking(
        symbol: symbol,
        orderId: state.trackedOrderId,
        allowReconciliationWithoutManagedOrder: true,
      );
    }
    await _module.uiLog.log(
      'bingx.exchange.tracking.resume',
      'source=$source symbol=$symbol orderId=${state.trackedOrderId ?? "-"}',
    );
    await _fetchOpenOrders(silent: true);
    return true;
  }

  void _stopOpenOrdersAutoTracking({String reason = 'manual'}) {
    if (_openOrdersPollTimer == null) return;
    _openOrdersPollTimer?.cancel();
    _openOrdersPollTimer = null;
    final symbol = _trackedOrdersSymbol ?? '-';
    final orderId = _trackedOrderId ?? '-';
    _trackedOrdersSymbol = null;
    _trackedOrderId = null;
    unawaited(
      _module.uiLog.log(
        'bingx.exchange.tracking',
        'disabled reason=$reason symbol=$symbol orderId=$orderId',
      ),
    );
    if (mounted) {
      setState(() {});
    }
    unawaited(_persistOpenOrdersTrackingState(source: 'tracking_disabled'));
  }

  Future<void> _maybeRetargetOpenOrdersTracking({
    required String symbol,
    required String source,
    bool force = false,
  }) async {
    if (!_isTrackingOpenOrders) return;
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    final trackedOrderId = _trackedOrderId?.trim() ?? '';
    if (trackedOrderId.isNotEmpty) {
      if (!force) {
        await _module.uiLog.log(
          'bingx.exchange.tracking.retarget.skip',
          'source=$source symbol=$normalizedSymbol reason=tracked_order orderId=$trackedOrderId',
        );
        return;
      }
      final previousOrderId = trackedOrderId;
      _trackedOrderId = null;
      _cancelOrderIdController.clear();
      await _module.uiLog.log(
        'bingx.exchange.tracking.retarget.force',
        'source=$source symbol=$normalizedSymbol previousOrderId=$previousOrderId',
      );
    }
    if (_trackedOrdersSymbol?.trim().toUpperCase() == normalizedSymbol) {
      return;
    }
    _startOpenOrdersAutoTracking(symbol: normalizedSymbol);
    await _module.uiLog.log(
      'bingx.exchange.tracking.retarget',
      'source=$source symbol=$normalizedSymbol',
    );
    await _fetchOpenOrders(silent: true);
  }

  Future<void> _persistOpenOrdersTrackingState({
    required String source,
    bool propagateError = false,
  }) async {
    try {
      final state = BingxFuturesOrderTrackingState(
        trackedSymbol: _trackedOrdersSymbol,
        trackedOrderId: _trackedOrderId,
        managedOrderIds: _managedOrderIds.toList(growable: false),
        managedOrderSymbols: Map<String, String>.unmodifiable(
          _managedOrderSymbols,
        ),
        managedOrderProvenance:
            Map<String, BingxManagedOrderProvenance>.unmodifiable(
              _managedOrderProvenance,
            ),
        droneEnabled: _droneEnabled,
        tradingMandate: _tradingMandate,
        stopLossPercent: _stopLossPercent,
        takeProfitRiskReward: _takeProfitRiskReward,
      );
      await _module.orderTrackingStore.save(state);
      await _module.uiLog.log(
        'bingx.exchange.tracking.persist',
        'source=$source trackedSymbol=${state.trackedSymbol ?? "-"} '
            'trackedOrderId=${state.trackedOrderId ?? "-"} '
            'managedCount=${state.managedOrderIds.length} '
            'symbolCount=${state.managedOrderSymbols.length} '
            'provenanceCount=${state.managedOrderProvenance.length}',
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.exchange.tracking.persist.error',
        'source=$source error=$error',
      );
      if (propagateError) rethrow;
    }
  }

  Future<bool> _changeDroneEnabled(
    bool value, {
    bool requirePersistence = false,
  }) async {
    if (!_tradingControlLoaded || _savingTradingControl) return false;
    BingxFuturesTradingMandate? nextMandate = _tradingMandate;
    if (value) {
      if (_orderType != 'limit') {
        await _showSnack(
          'Bounded trading currently requires the Limit strategy path.',
        );
        return false;
      }
      final credentials = await _ensureCredentialsLoaded();
      final capsuleRootHex = _module.orderTrackingStore.activeCapsuleRootHex;
      final symbol = _symbolController.text.trim().toUpperCase();
      final maxNotional = double.tryParse(
        _maxNotionalUsdtController.text.trim(),
      );
      if (credentials == null || capsuleRootHex == null) {
        await _showSnack('Capsule and BingX credentials are required.');
        return false;
      }
      if (symbol.isEmpty || maxNotional == null || maxNotional <= 0) {
        await _showSnack('Symbol and positive max notional are required.');
        return false;
      }
      final confirmed = await _confirmTradingMandate(
        symbol: symbol,
        maxNotional: maxNotional,
      );
      if (!confirmed) return false;
      final now = DateTime.now().toUtc();
      nextMandate = BingxFuturesTradingMandate.issue(
        capsuleRootHex: capsuleRootHex,
        accountBindingHashHex: _module.accountBindingHashHex(credentials),
        symbol: symbol,
        testOrder: _useTestOrderEndpoint,
        issuedAtUtc: now,
        expiresAtUtc: now.add(const Duration(hours: 24)),
        maxOrderNotionalQuoteDecimal: maxNotional.toString(),
        maxRiskPerTradePercent: _executionRiskPolicy.maxRiskPerTradePercent,
        maxDailyLossPercent: _executionRiskPolicy.maxDailyLossPercent,
        maxConcurrentPositions: _executionRiskPolicy.maxConcurrentPositions,
        cooldownAfterLossStreak: _executionRiskPolicy.cooldownAfterLossStreak,
        cooldownMinutes: _executionRiskPolicy.cooldownMinutes,
        maxEffects: _maxEffects,
      );
    } else {
      nextMandate = nextMandate?.revoke(DateTime.now().toUtc());
    }
    setState(() {
      _droneEnabled = value;
      _tradingMandate = nextMandate;
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;
      _savingTradingControl = true;
    });
    try {
      await _persistOpenOrdersTrackingState(
        source: 'drone_control_changed',
        propagateError: requirePersistence,
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingTradingControl = false;
        });
      }
    }
    return true;
  }

  Future<bool> _confirmTradingMandate({
    required String symbol,
    required double maxNotional,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Authorize bounded trading'),
            content: Text(
              'Capsule: ${_module.orderTrackingStore.activeCapsuleRootHex!.substring(0, 12)}…\n'
              'Account: current BingX credential\n'
              'Symbol: $symbol\n'
              'Mode: ${_useTestOrderEndpoint ? "test" : "live"}\n'
              'Max order: ${maxNotional.toStringAsFixed(2)} USDT\n'
              'Risk: ${_executionRiskPolicy.maxRiskPerTradePercent}% per trade, '
              '${_executionRiskPolicy.maxDailyLossPercent}% daily\n'
              'Maximum orders: ${tradingOrderBudgetLabel(_maxEffects)}\n'
              'Expires: 24 hours\n\n'
              'Emergency Pause revokes this mandate.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Authorize'),
              ),
            ],
          ),
    );
    return result == true;
  }

  Future<void> _restoreOpenOrdersTrackingState() async {
    try {
      final state = await _module.orderTrackingStore.load();
      if (state == null) return;
      _managedOrderIds
        ..clear()
        ..addAll(state.managedOrderIds);
      _managedOrderSymbols
        ..clear()
        ..addAll(state.managedOrderSymbols);
      _managedOrderProvenance
        ..clear()
        ..addAll(state.managedOrderProvenance);
      _droneEnabled = state.droneEnabled == true;
      _tradingMandate = state.tradingMandate;
      final mandateActive =
          _tradingMandate?.isActiveAt(DateTime.now().toUtc()) == true;
      if (mandateActive) {
        _maxEffects = tradingRestoredEffectBudget(_tradingMandate!);
        _useTestOrderEndpoint = tradingUsesTestEndpointAfterRestore(
          mandate: _tradingMandate,
          nowUtc: DateTime.now().toUtc(),
        );
      } else {
        _droneEnabled = false;
        _useTestOrderEndpoint = false;
      }
      final restoredStopLossPercent = state.stopLossPercent;
      if (restoredStopLossPercent != null &&
          _stopLossPercentOptions.contains(restoredStopLossPercent)) {
        _stopLossPercent = restoredStopLossPercent;
      }
      final restoredRiskReward = state.takeProfitRiskReward;
      if (restoredRiskReward != null &&
          _takeProfitRiskRewardOptions.contains(restoredRiskReward)) {
        _takeProfitRiskReward = restoredRiskReward;
      }
      final resumeSymbol = tradingReconciliationResumeSymbol(state);
      if (resumeSymbol != null) {
        _symbolController.text = resumeSymbol;
      }
      final resumed = await _resumeManagedOrderReconciliation(
        source: 'state_restored',
      );
      await _module.uiLog.log(
        'bingx.exchange.tracking.restore',
        'tracked=${resumed ? "yes" : "deferred_or_idle"} '
            'symbol=${resumeSymbol ?? "-"} '
            'orderId=${state.trackedOrderId ?? "-"} '
            'managedCount=${_managedOrderIds.length} '
            'symbolCount=${_managedOrderSymbols.length} '
            'provenanceCount=${_managedOrderProvenance.length} '
            'mandateActive=$mandateActive '
            'endpoint=${_useTestOrderEndpoint ? "test" : "live"} '
            'slPct=${_stopLossPercent.toStringAsFixed(2)} '
            'rr=${_takeProfitRiskReward.toStringAsFixed(2)}',
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.exchange.tracking.restore.error',
        '$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _tradingControlLoaded = true;
        });
      }
    }
  }

  Future<void> _showSnack(String message, {int seconds = 2}) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: seconds)),
    );
  }

  String _resolveIntentRejectedMessage(PluginHostApiResponse response) {
    final code = response.errorCode?.trim() ?? '';
    if (code == 'runtime_invoke_unavailable') {
      return 'Futures runtime package is missing. Install/reinstall BingX Futures plugin in Plugins and retry.';
    }
    if (code == 'runtime_invoke_invalid') {
      return 'Futures plugin package is invalid. Reinstall BingX Futures plugin.';
    }
    if (code == 'runtime_invoke_failed') {
      return 'Futures runtime invoke failed. Reinstall plugin and retry.';
    }
    final message = response.errorMessage?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'BingX futures request rejected';
  }

  Future<BingxFuturesApiCredentials?> _loadCredentials({
    bool showError = true,
  }) async {
    try {
      final credentials = await _module.credentialStore.load();
      if (!mounted || credentials == null) return credentials;
      setState(() {
        _apiKeyController.text = credentials.apiKey;
        _apiSecretController.text = credentials.apiSecret;
      });
      await _module.uiLog.log(
        'bingx.credentials.load',
        'ok keyLen=${credentials.apiKey.length} secretLen=${credentials.apiSecret.length}',
      );
      return credentials;
    } catch (error) {
      await _module.uiLog.log('bingx.credentials.load.error', '$error');
      if (showError) {
        await _showSnack(
          'Failed to load BingX credentials: $error',
          seconds: 3,
        );
      }
      return null;
    }
  }

  Future<String?> _selectConsensusPeer({required String hint}) async {
    final labels = await _module.contactLabels.load();
    if (!mounted) return null;
    final checks =
        (await _module.manualChecks.loadAttestedChecks()).toList()..sort(
          (a, b) =>
              a.peerLabel.toLowerCase().compareTo(b.peerLabel.toLowerCase()),
        );
    if (!mounted) return null;
    if (checks.isEmpty) return null;
    final selectedPeerHex = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text(
                  'Select consensus peer',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(hint),
              ),
              for (final check in checks)
                ListTile(
                  leading: Icon(
                    check.isSignable ? Icons.verified_rounded : Icons.warning,
                    color: check.isSignable ? Colors.green : Colors.orange,
                  ),
                  title: Text(
                    PeerIdentityFormat.capsuleLabelFromRootHex(
                      check.peerHex,
                      localLabel:
                          labels[PeerIdentityFormat.capsuleKeyFromRootHex(
                            check.peerHex,
                          )],
                    ),
                  ),
                  subtitle: Text(
                    '${check.isSignable ? 'Pair consensus verified' : 'Pair consensus needs attention'}\n'
                    '${PeerIdentityFormat.capsuleIdentityHintFromRootHex(check.peerHex)}',
                  ),
                  trailing:
                      check.isSignable
                          ? const Text(
                            'Signable',
                            style: TextStyle(color: Colors.green),
                          )
                          : const Text(
                            'Blocked',
                            style: TextStyle(color: Colors.orange),
                          ),
                  onTap: () => Navigator.of(sheetContext).pop(check.peerHex),
                ),
            ],
          ),
        );
      },
    );
    return selectedPeerHex;
  }

  Future<void> _choosePeer() async {
    final selectedPeerHex = await _selectConsensusPeer(
      hint: 'Choose consensus peer for BingX intent routing.',
    );
    if (!mounted || selectedPeerHex == null || selectedPeerHex.isEmpty) return;
    setState(() {
      _peerController.text = selectedPeerHex;
    });
  }

  Future<void> _saveCredentials() async {
    if (_savingCredentials) return;
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      await _showSnack('BingX API key and secret are required');
      return;
    }

    setState(() {
      _savingCredentials = true;
    });
    try {
      await _module.credentialStore.save(
        BingxFuturesApiCredentials(apiKey: apiKey, apiSecret: apiSecret),
      );
      await _module.uiLog.log(
        'bingx.credentials.save',
        'ok keyLen=${apiKey.length} secretLen=${apiSecret.length}',
      );
      await _resumeManagedOrderReconciliation(source: 'credentials_saved');
      await _showSnack('BingX credentials saved for active capsule');
    } catch (error) {
      await _module.uiLog.log('bingx.credentials.save.error', '$error');
      await _showSnack('Failed to save BingX credentials: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _savingCredentials = false;
        });
      }
    }
  }

  BingxFuturesApiCredentials? _resolveCredentials() {
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      return null;
    }
    return BingxFuturesApiCredentials(apiKey: apiKey, apiSecret: apiSecret);
  }

  Future<BingxFuturesApiCredentials?> _ensureCredentialsLoaded({
    bool silent = false,
  }) async {
    final current = _resolveCredentials();
    if (current != null) return current;
    final pending = _credentialsLoadFuture;
    if (pending != null) {
      final loaded = await pending;
      return loaded ?? _resolveCredentials();
    }
    final loadFuture = _loadCredentials(showError: !silent);
    _credentialsLoadFuture = loadFuture;
    final loaded = await loadFuture;
    if (identical(_credentialsLoadFuture, loadFuture)) {
      _credentialsLoadFuture = null;
    }
    return loaded ?? _resolveCredentials();
  }

  String? _deriveDirectLimitFromZone() {
    final lowRaw = _zoneLowController.text.trim();
    final highRaw = _zoneHighController.text.trim();
    if (lowRaw.isEmpty || highRaw.isEmpty) return null;
    final low = num.tryParse(lowRaw);
    final high = num.tryParse(highRaw);
    if (low == null || high == null || low <= 0 || high <= 0 || low >= high) {
      return null;
    }
    return _side == 'buy' ? lowRaw : highRaw;
  }

  num? _deriveZoneEntryPrice({
    required String zonePriceRule,
    required String zoneLowDecimal,
    required String zoneHighDecimal,
    String? manualLimitPriceDecimal,
  }) {
    final low = _toNum(zoneLowDecimal);
    final high = _toNum(zoneHighDecimal);
    if (low == null || high == null || low <= 0 || high <= 0 || low >= high) {
      return null;
    }
    switch (zonePriceRule.trim().toLowerCase()) {
      case 'zone_low':
        return low;
      case 'zone_high':
        return high;
      case 'manual':
        final manual = _toNum(manualLimitPriceDecimal ?? '');
        if (manual == null || manual <= 0) return null;
        return manual;
      case 'zone_mid':
      default:
        return (low + high) / 2;
    }
  }

  String _formatDecimal(num value, {int scale = 8}) {
    final fixed = value.toStringAsFixed(scale);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatLiveDecisionBlockedMessage(
    BingxFuturesLiveDecisionResult live,
  ) {
    final zone =
        live.zoneLowDecimal != null && live.zoneHighDecimal != null
            ? ' zone ${live.zoneLowDecimal}-${live.zoneHighDecimal}'
            : '';
    if (live.trendGateBlocked) {
      return switch (live.trendGateCode) {
        'momentum_gate_short_missed_retest' =>
          'Short blocked: retest already missed.$zone',
        'momentum_gate_long_missed_retest' =>
          'Long blocked: retest already missed.$zone',
        'trend_gate_short_far_retest' =>
          'Short blocked: retest is too far.$zone',
        'trend_gate_long_far_retest' => 'Long blocked: retest is too far.$zone',
        'liquidity_anchor_unavailable' =>
          'No executable liquidity anchor for this symbol.',
        _ => 'Signal blocked: ${live.trendGateCode}.$zone',
      };
    }

    final failed =
        live.reasons
            .where((reason) => !reason.passed)
            .map((reason) => reason.code)
            .where((code) => code.isNotEmpty)
            .toList();
    if (failed.isEmpty) {
      return 'No executable signal for current market state.';
    }
    return 'No executable signal: ${failed.join(', ')}.';
  }

  num? _toNum(String raw) => num.tryParse(raw.trim());

  Future<bool> _applyRiskBudgetQuantity({required String symbol}) async {
    final maxNotional = _toNum(_maxNotionalUsdtController.text);
    if (maxNotional == null || maxNotional <= 0) {
      await _showSnack('Max notional must be a positive number');
      return false;
    }

    final sizing = await _module.orderSizing.size(
      symbol: symbol,
      maximumNotionalQuote: maxNotional,
    );
    await _module.uiLog.log(
      'bingx.risk.sizing',
      'symbol=${symbol.trim().toUpperCase()} '
          'status=${sizing.status.name} code=${sizing.reasonCode} '
          'risk_notional=$maxNotional '
          'quantity=${sizing.quantityDecimal ?? "-"} '
          'order_notional=${sizing.orderNotionalQuoteDecimal ?? "-"} '
          'min_quantity=${sizing.minimumQuantityDecimal ?? "-"} '
          'min_notional=${sizing.minimumNotionalQuoteDecimal ?? "-"}',
    );
    if (sizing.status != BingxFuturesOrderSizingStatus.sized ||
        sizing.quantityDecimal == null) {
      _quantityController.clear();
      await _showSnack(sizing.reasonMessage, seconds: 4);
      return false;
    }

    final quantityDecimal = sizing.quantityDecimal!;
    if (mounted) {
      setState(() {
        _quantityController.text = quantityDecimal;
      });
    } else {
      _quantityController.text = quantityDecimal;
    }
    await _module.uiLog.log(
      'bingx.risk.quantity',
      'symbol=${symbol.trim().toUpperCase()} '
          'max_notional_usdt=$maxNotional '
          'order_notional_usdt=${sizing.orderNotionalQuoteDecimal} '
          'quantity=$quantityDecimal',
    );
    return true;
  }

  Future<void> _autoFitMaxNotionalToRisk() async {
    if (_fittingMaxNotional) return;
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }
    final slFactor = _stopLossPercent / 100;
    if (slFactor <= 0) {
      await _showSnack('SL% must be greater than 0');
      return;
    }
    setState(() {
      _fittingMaxNotional = true;
    });
    try {
      final riskInput = await _module.exchangeRiskInput.read(
        exchangeService: _module.exchangeService,
        riskHistoryService: _module.riskHistory,
        credentials: credentials,
        nowUtc: DateTime.now().toUtc(),
        fallbackEquityQuote: _fallbackRiskEquityQuote,
      );
      if (riskInput.usedBalanceFallback) {
        final reason = riskInput.firstUnavailableReason;
        await _module.uiLog.log(
          'bingx.risk.autofit.blocked',
          'reason=balance_unavailable fallback_equity='
              '${riskInput.accountEquityQuoteDecimal} '
              'exchange_reason=${reason ?? "-"}',
        );
        await _showSnack(
          reason == null
              ? 'Cannot auto-fit risk: BingX balance unavailable'
              : 'Cannot auto-fit risk: BingX futures access unavailable ($reason)',
          seconds: 4,
        );
        return;
      }
      final equity = _toNum(riskInput.accountEquityQuoteDecimal);
      if (equity == null || equity <= 0) {
        await _showSnack('Cannot auto-fit risk: invalid equity');
        return;
      }
      final riskQuoteLimit =
          equity * (_executionRiskPolicy.maxRiskPerTradePercent / 100.0);
      final safeNotional = riskQuoteLimit / slFactor;
      final conservativeNotional = safeNotional * 0.98;
      if (conservativeNotional <= 0) {
        await _showSnack('Cannot auto-fit risk: limit too small');
        return;
      }
      final symbol = _symbolController.text.trim();
      num fittedNotional = conservativeNotional;
      BingxFuturesOrderSizingResult? sizing;
      if (symbol.isNotEmpty) {
        sizing = await _module.orderSizing.size(
          symbol: symbol,
          maximumNotionalQuote: fittedNotional,
        );
        if (sizing.status == BingxFuturesOrderSizingStatus.blocked &&
            sizing.reasonCode == 'exchange_minimum_exceeds_risk_budget') {
          final minimumNotional = _toNum(
            sizing.minimumNotionalQuoteDecimal ?? '',
          );
          if (minimumNotional != null &&
              minimumNotional > fittedNotional &&
              minimumNotional <= safeNotional) {
            fittedNotional = minimumNotional;
            sizing = await _module.orderSizing.size(
              symbol: symbol,
              maximumNotionalQuote: fittedNotional,
            );
          }
        }
      }
      final fitted = _formatDecimal(fittedNotional, scale: 4);
      if (symbol.isNotEmpty && sizing != null) {
        await _module.uiLog.log(
          'bingx.risk.sizing',
          'symbol=${symbol.toUpperCase()} '
              'status=${sizing.status.name} code=${sizing.reasonCode} '
              'risk_notional=$fitted '
              'quantity=${sizing.quantityDecimal ?? "-"} '
              'order_notional=${sizing.orderNotionalQuoteDecimal ?? "-"} '
              'min_quantity=${sizing.minimumQuantityDecimal ?? "-"} '
              'min_notional=${sizing.minimumNotionalQuoteDecimal ?? "-"}',
        );
        if (sizing.status != BingxFuturesOrderSizingStatus.sized ||
            sizing.quantityDecimal == null) {
          _quantityController.clear();
          await _module.uiLog.log(
            'bingx.risk.autofit.blocked',
            'symbol=${symbol.toUpperCase()} max_notional=$fitted '
                'safe_notional=${_formatDecimal(safeNotional, scale: 4)} '
                'code=${sizing.reasonCode}',
          );
          await _showSnack(sizing.reasonMessage, seconds: 4);
          return;
        }
        _quantityController.text = sizing.quantityDecimal!;
        await _module.uiLog.log(
          'bingx.risk.quantity',
          'symbol=${symbol.toUpperCase()} '
              'max_notional_usdt=$fitted '
              'order_notional_usdt=${sizing.orderNotionalQuoteDecimal} '
              'quantity=${sizing.quantityDecimal}',
        );
      }
      _maxNotionalUsdtController.text = fitted;
      final mandate = _tradingMandate;
      final mandateNeedsReauthorization =
          _droneEnabled &&
          mandate != null &&
          mandate.isActiveAt(DateTime.now().toUtc()) &&
          !tradingMandateMaxNotionalMatches(
            mandate: mandate,
            selectedMaxNotional: fitted,
          );
      if (mandateNeedsReauthorization) {
        final revokedAt = DateTime.now().toUtc();
        setState(() {
          _droneEnabled = false;
          _tradingMandate = mandate.revoke(revokedAt);
        });
        await _persistOpenOrdersTrackingState(
          source: 'risk_autofit_mandate_revoked',
        );
        await _module.uiLog.log(
          'bingx.risk.autofit.mandate_revoked',
          'previous_max_notional=${mandate.maxOrderNotionalQuoteDecimal} '
              'fitted_max_notional=$fitted effect=false',
        );
      }
      await _module.uiLog.log(
        'bingx.risk.autofit',
        'equity=${riskInput.accountEquityQuoteDecimal} '
            'risk_pct=${_executionRiskPolicy.maxRiskPerTradePercent.toStringAsFixed(2)} '
            'sl_pct=${_stopLossPercent.toStringAsFixed(2)} '
            'max_notional=$fitted '
            'safe_notional=${_formatDecimal(safeNotional, scale: 4)}',
      );
      await _showSnack(
        mandateNeedsReauthorization
            ? 'Max notional auto-fit: $fitted USDT. Trading paused; Resume to authorize this limit.'
            : 'Max notional auto-fit: $fitted USDT',
        seconds: mandateNeedsReauthorization ? 5 : 2,
      );
    } catch (error) {
      await _module.uiLog.log('bingx.risk.autofit.error', '$error');
      await _showSnack('Auto-fit failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _fittingMaxNotional = false;
        });
      }
    }
  }

  ({bool isSignable, List<String> blockingCodes}) _consensusDecisionContext(
    String peerHex,
  ) {
    final checks = _module.manualChecks.loadChecks();
    final normalizedPeer = peerHex.trim().toLowerCase();
    if (checks.isEmpty) {
      return (isSignable: false, blockingCodes: const <String>[]);
    }

    if (normalizedPeer.isEmpty) {
      return (
        isSignable: false,
        blockingCodes: const <String>['consensus_peer_not_selected'],
      );
    }

    if (normalizedPeer.isNotEmpty) {
      for (final check in checks) {
        if (check.peerHex.trim().toLowerCase() == normalizedPeer) {
          final codes =
              check.blockingFacts
                  .map((fact) => fact.code.trim())
                  .where((code) => code.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          return (isSignable: check.isSignable, blockingCodes: codes);
        }
      }
    }

    return (
      isSignable: false,
      blockingCodes: const <String>['consensus_peer_not_found'],
    );
  }

  Future<BingxFuturesLiveDecisionResult?> _computeLiveDecision({
    required String symbol,
    required String peerHex,
    bool silent = false,
    bool forceConsensusSignable = false,
    String? zoneEvaluationSide,
  }) async {
    final consensus =
        forceConsensusSignable
            ? (isSignable: true, blockingCodes: const <String>[])
            : _consensusDecisionContext(peerHex);
    final result = await _module.liveStrategyUseCase.execute(
      BingxFuturesLiveStrategyCommand(
        symbol: symbol,
        isConsensusSignable: consensus.isSignable,
        blockingFactCodes: consensus.blockingCodes,
        recentMicroBars: _recentMicroBars,
        zoneNearBps: _zoneNearBps,
        zoneFarBps: _zoneFarBps,
        zoneEvaluationSide: zoneEvaluationSide,
      ),
    );
    if (!result.isSuccess) {
      await _module.uiLog.log(
        'bingx.strategy.live_decision.error',
        result.diagnostic,
      );
      if (!silent) {
        await _showSnack(
          'Strategy failed: ${result.errorCode} ${result.errorMessage}',
          seconds: 3,
        );
      }
      return null;
    }

    await _module.uiLog.log('bingx.strategy.live_decision', result.diagnostic);
    return result.decision;
  }

  Future<void> _runIntent() async {
    if (_runningIntent) return;
    if (mounted) {
      setState(() {
        _runningIntent = true;
        _intentProgressLabel = 'Starting';
        _lastIntentResponse = null;
        _lastPreparedLiveDecision = null;
        _intentBlockingMessage = null;
      });
    }
    try {
      await runTradingIntentWithTerminalEvidence(
        pipeline: _runIntentPipeline,
        log: _module.uiLog.log,
      );
    } catch (error) {
      await _showSnack('Intent failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _runningIntent = false;
          _intentProgressLabel = 'Starting';
        });
      }
    }
  }

  void _setIntentProgress(String label) {
    if (!mounted || !_runningIntent || _intentProgressLabel == label) return;
    setState(() {
      _intentProgressLabel = label;
    });
  }

  Future<String> _runCanonicalSoloCycle({required String symbol}) async {
    final maximumNotional = num.tryParse(
      _maxNotionalUsdtController.text.trim(),
    );
    if (maximumNotional == null || maximumNotional <= 0) {
      await _showSnack('Max notional must be a positive number');
      return 'blocked:risk_notional_invalid';
    }
    _setIntentProgress('Analyzing market');
    final cycle = await _module.cycleUseCase.run(
      BingxFuturesTradingCycleCommand(
        screen: 'trading_drone',
        symbol: symbol,
        preferredSide: _side,
        maximumNotionalQuote: maximumNotional,
        stopLossPercent: _stopLossPercent,
        takeProfitRiskReward: _takeProfitRiskReward,
        credentials: _resolveCredentials(),
        riskPolicy: _executionRiskPolicy,
        fallbackEquityQuote: _fallbackRiskEquityQuote,
        testOrder: _useTestOrderEndpoint,
        executeEffect: false,
        recentMicroBars: _recentMicroBars,
        zoneNearBps: _zoneNearBps,
        zoneFarBps: _zoneFarBps,
      ),
    );
    final decision = cycle.decision;
    final response = cycle.intent?.response;
    final projectsExecutableZone =
        decision != null &&
        tradingCycleProjectsExecutableZone(
          cyclePrepared: cycle.isPrepared,
          decisionCanPrepareIntent: decision.canPrepareIntent,
        );
    final executableDecision = projectsExecutableZone ? decision : null;
    if (mounted) {
      setState(() {
        if (executableDecision != null) {
          _displayedZoneDecision = executableDecision;
          _lastPreparedLiveDecision = executableDecision;
          _side = tradingSideAfterCycle(
            currentSide: _side,
            cyclePrepared: true,
            decisionSide: executableDecision.side,
          );
          _zoneSide = tradingZoneSideAfterCycle(
            currentZoneSide: _zoneSide,
            cyclePrepared: true,
            decisionZoneSide: executableDecision.zoneSide,
          );
          _entryMode = 'zone_pending';
          _zonePriceRule = 'zone_mid';
          _zoneLowController.text = executableDecision.zoneLowDecimal ?? '';
          _zoneHighController.text = executableDecision.zoneHighDecimal ?? '';
          _triggerPriceController.text =
              executableDecision.side == 'buy'
                  ? executableDecision.zoneHighDecimal ?? ''
                  : executableDecision.zoneLowDecimal ?? '';
          _strategyTagController.text =
              _module.strategyNaming.tagForDecision(
                executableDecision.decision,
              ) ??
              '';
          _quantityController.text = cycle.sizing?.quantityDecimal ?? '';
          _stopLossController.text = cycle.stopLossDecimal ?? '';
          _takeProfitController.text = cycle.takeProfitDecimal ?? '';
        } else {
          _displayedZoneDecision = null;
          _lastPreparedLiveDecision = null;
          _zoneLowController.clear();
          _zoneHighController.clear();
          _triggerPriceController.clear();
          _quantityController.clear();
          _stopLossController.clear();
          _takeProfitController.clear();
          _strategyTagController.clear();
        }
        _lastIntentResponse = response;
        _intentBlockingMessage = cycle.isPrepared ? null : cycle.reasonMessage;
      });
    }
    await _module.uiLog.log(
      'bingx.trading_cycle.result',
      'status=${cycle.status.name} code=${cycle.reasonCode} '
          'symbol=$symbol effect=false '
          'decision=${decision?.decision.name ?? "-"} '
          'side=${decision?.side ?? "-"} '
          'zone_side=${decision?.zoneSide ?? "-"} '
          'zone_evaluation_side=${decision?.zoneEvaluationSide ?? "-"} '
          'zone_anchor=${decision?.zoneAnchorSource ?? "-"} '
          'zone_conflict=${decision?.zoneConflict ?? false} '
          'opposite_target=${decision?.oppositeLiquidityTargetDecimal ?? "-"} '
          'opposite_source=${decision?.oppositeLiquidityTargetSource ?? "-"} '
          'failed=${decision == null ? "-" : decision.reasons.where((reason) => !reason.passed).map((reason) => "${reason.code}:${reason.detail}").join("|")} '
          'live_hash=${decision?.liveDecisionHashHex ?? "-"}',
    );
    final envelope = cycle.intent?.decisionEnvelope;
    if (envelope != null) {
      await _module.uiLog.log(
        'drone.decision.envelope',
        'hash=${envelope.envelopeHashHex} kind=decision screen=trading_drone',
      );
    }
    if (cycle.isPrepared && response != null) {
      final hash = response.result?['intent_hash_hex']?.toString() ?? '';
      final shortHash = hash.length >= 12 ? '${hash.substring(0, 12)}..' : hash;
      await _showSnack('BingX intent prepared: $shortHash');
      return preparedTradingIntentTerminalOutcome;
    }
    await _showSnack(cycle.reasonMessage, seconds: 4);
    return 'blocked:${cycle.reasonCode}';
  }

  Future<String> _runIntentPipeline() async {
    if (!_tradingControlLoaded || _savingTradingControl) {
      await _showSnack('Trading control is not ready yet.');
      return 'blocked:trading_control_unavailable';
    }
    if (!_droneEnabled) {
      await _showSnack('Drone is paused. Resume before running strategy.');
      return 'blocked:drone_paused';
    }
    final peerHex = _peerController.text.trim().toLowerCase();
    final symbol = _symbolController.text.trim();
    var strategyTag = _strategyTagController.text.trim();
    var triggerPriceDecimal = _triggerPriceController.text.trim();
    var stopLossDecimal = _stopLossController.text.trim();
    var takeProfitDecimal = _takeProfitController.text.trim();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    var clientOrderId = 'ui-ord-${DateTime.now().microsecondsSinceEpoch}';
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return 'blocked:symbol_required';
    }
    if (!await _primePublicSessionEvidence(symbol, reportFailure: true)) {
      return 'blocked:session_stream_unavailable';
    }
    final forceAutoZonePending = _orderType == 'limit';
    if (forceAutoZonePending &&
        (_entryMode != 'zone_pending' ||
            _zonePriceRule == 'manual' ||
            _zoneSide != (_side == 'buy' ? 'buyside' : 'sellside'))) {
      if (mounted) {
        setState(() {
          _entryMode = 'zone_pending';
          _zonePriceRule = 'zone_mid';
          _zoneSide = _side == 'buy' ? 'buyside' : 'sellside';
        });
      } else {
        _entryMode = 'zone_pending';
        _zonePriceRule = 'zone_mid';
        _zoneSide = _side == 'buy' ? 'buyside' : 'sellside';
      }
      await _module.uiLog.log(
        'bingx.strategy.entry_mode.auto',
        'forced=zone_pending rule=zone_mid side=$_zoneSide order_type=$_orderType',
      );
    }

    if (peerHex.isEmpty && _orderType == 'limit') {
      return _runCanonicalSoloCycle(symbol: symbol);
    }

    final isZonePending = _entryMode == 'zone_pending';
    BingxFuturesLiveDecisionResult? liveDecision;

    if (_orderType == 'limit') {
      _setIntentProgress('Analyzing market');
      liveDecision = await _computeLiveDecision(
        symbol: symbol,
        peerHex: peerHex,
        forceConsensusSignable: peerHex.isEmpty,
        zoneEvaluationSide: _side,
      );
      if (liveDecision == null) return 'blocked:market_analysis_unavailable';
      final live = liveDecision;
      if (live.zoneLowDecimal != null && live.zoneHighDecimal != null) {
        if (mounted) {
          setState(() {
            _zoneLowController.text = live.zoneLowDecimal!;
            _zoneHighController.text = live.zoneHighDecimal!;
            if (live.zoneSide != null) {
              _zoneSide = live.zoneSide!;
            }
            if (live.side != null) {
              _side = live.side!;
            }
          });
        } else {
          _zoneLowController.text = live.zoneLowDecimal!;
          _zoneHighController.text = live.zoneHighDecimal!;
          if (live.zoneSide != null) {
            _zoneSide = live.zoneSide!;
          }
          if (live.side != null) {
            _side = live.side!;
          }
        }
      }
      if (!live.canPrepareIntent ||
          live.side == null ||
          live.zoneSide == null ||
          live.zoneLowDecimal == null ||
          live.zoneHighDecimal == null) {
        final message = _formatLiveDecisionBlockedMessage(live);
        if (mounted) {
          setState(() {
            _intentBlockingMessage = message;
          });
        }
        await _module.uiLog.log(
          'bingx.strategy.live_decision.blocked',
          'symbol=$symbol message=$message '
              'decision=${live.decision.name} side=${live.side ?? "-"} '
              'zone=${live.zoneLowDecimal ?? "-"}-${live.zoneHighDecimal ?? "-"} '
              'trend_gate=${live.trendGateCode} '
              'live_hash=${live.liveDecisionHashHex.substring(0, 12)}',
        );
        await _showSnack(message, seconds: 4);
        return 'blocked:market_decision';
      }
      final liquidityEventId = live.liquidityEventId?.trim() ?? '';
      final latestClosedBar = live.latestClosedMicroBarAtUtc?.trim() ?? '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(liquidityEventId) ||
          latestClosedBar.isEmpty) {
        await _module.uiLog.log(
          'bingx.strategy.live_decision.blocked',
          'symbol=$symbol message=liquidity_event_evidence_missing',
        );
        await _showSnack('Liquidity event evidence is unavailable', seconds: 4);
        return 'blocked:liquidity_event_evidence_missing';
      }
      clientOrderId = 'hivra-${liquidityEventId.substring(0, 32)}';
      if (mounted) {
        setState(() {
          _side = live.side!;
          _zoneSide = live.zoneSide!;
          _entryMode = 'zone_pending';
          _zonePriceRule = 'zone_mid';
          _zoneLowController.text = live.zoneLowDecimal!;
          _zoneHighController.text = live.zoneHighDecimal!;
        });
      } else {
        _side = live.side!;
        _zoneSide = live.zoneSide!;
        _entryMode = 'zone_pending';
        _zonePriceRule = 'zone_mid';
        _zoneLowController.text = live.zoneLowDecimal!;
        _zoneHighController.text = live.zoneHighDecimal!;
      }
      strategyTag = _module.strategyNaming.tagForDecision(live.decision) ?? '';
      _strategyTagController.text = strategyTag;
      triggerPriceDecimal =
          live.side == 'buy' ? live.zoneHighDecimal! : live.zoneLowDecimal!;
      _triggerPriceController.text = triggerPriceDecimal;
    }

    // Market analysis is independent from exchange sizing. A valid setup must
    // remain observable even when the account cannot safely meet minQty.
    _setIntentProgress('Sizing risk');
    final riskReady = await _applyRiskBudgetQuantity(symbol: symbol);
    if (!riskReady) {
      return 'blocked:risk_sizing';
    }
    final quantityDecimal = _quantityController.text.trim();

    final zoneLowDecimal = _zoneLowController.text.trim();
    final zoneHighDecimal = _zoneHighController.text.trim();
    String? limitPriceDecimal =
        _orderType == 'limit' && !isZonePending
            ? _limitPriceController.text.trim()
            : null;
    if (_orderType == 'limit' &&
        !isZonePending &&
        (limitPriceDecimal == null || limitPriceDecimal.isEmpty)) {
      final derived = _deriveDirectLimitFromZone();
      if (derived != null && derived.isNotEmpty) {
        limitPriceDecimal = derived;
        _limitPriceController.text = derived;
        await _module.uiLog.log(
          'bingx.intent.autofill_limit',
          'mode=direct source=zone side=$_side value=$derived',
        );
      }
    }
    final timeInForce = _orderType == 'limit' ? _timeInForce : null;
    if (isZonePending) {
      final entryPrice = _deriveZoneEntryPrice(
        zonePriceRule: _zonePriceRule,
        zoneLowDecimal: zoneLowDecimal,
        zoneHighDecimal: zoneHighDecimal,
        manualLimitPriceDecimal:
            limitPriceDecimal ?? _limitPriceController.text,
      );
      if (entryPrice != null && entryPrice > 0) {
        final derived = deriveBingxFuturesLiquidityTargets(
          side: _side,
          entryPrice: entryPrice,
          stopLossPercent: _stopLossPercent,
          minimumRiskReward: _takeProfitRiskReward,
          oppositeLiquidityTargetDecimal:
              liveDecision?.oppositeLiquidityTargetDecimal,
        );
        if (derived.blockerCode != null) {
          await _module.uiLog.log(
            'bingx.intent.risk_targets.blocked',
            'code=${derived.blockerCode} entry=$entryPrice side=$_side '
                'target=${liveDecision?.oppositeLiquidityTargetDecimal ?? "-"}',
          );
          await _showSnack(derived.blockerMessage!, seconds: 4);
          return 'blocked:${derived.blockerCode}';
        }
        stopLossDecimal = derived.stopLossDecimal!;
        _stopLossController.text = stopLossDecimal;
        takeProfitDecimal = derived.takeProfitDecimal!;
        _takeProfitController.text = takeProfitDecimal;
        await _module.uiLog.log(
          'bingx.intent.risk_targets.auto',
          'entry=$entryPrice side=$_side '
              'sl=$stopLossDecimal tp=$takeProfitDecimal '
              'slPct=${_stopLossPercent.toStringAsFixed(2)} '
              'minRr=${_takeProfitRiskReward.toStringAsFixed(2)} '
              'actualRr=${derived.actualRiskReward!.toStringAsFixed(3)} '
              'targetSource=${liveDecision?.oppositeLiquidityTargetSource ?? "-"}',
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    try {
      await _module.uiLog.log(
        'bingx.intent.request',
        'peer=${peerHex.isEmpty ? "empty" : "${peerHex.substring(0, 8)}.."} symbol=$symbol side=$_side type=$_orderType entry=$_entryMode qty=$quantityDecimal',
      );
      if (peerHex.isNotEmpty) {
        _setIntentProgress('Checking consensus');
        final attestation = await _module.attestationExchange.ensureForPeer(
          peerHex,
        );
        await _module.uiLog.log(
          'bingx.attestation.ensure',
          'peer=${peerHex.substring(0, 8)}.. status=${attestation.status.name} '
              'receive=${attestation.receiveCode}/${attestation.receivedCount}/${attestation.storedCount} '
              'mismatch=${attestation.mismatchedEvidenceCount} '
              'sent=${attestation.localEvidenceSent} send=${attestation.sendCode ?? "-"}',
        );
        if (!attestation.isReady) {
          await _showSnack(
            attestation.message ??
                (attestation.status ==
                        ConsensusAttestationExchangeStatus.syncing
                    ? 'Pair consensus attestation syncing'
                    : 'Pair consensus attestation blocked'),
            seconds: 3,
          );
          return 'blocked:consensus_attestation';
        }
      }

      _setIntentProgress('Preparing intent');
      final useCaseResult = await _module.intentUseCase
          .execute(
            BingxFuturesIntentCommand(
              screen: 'trading_drone',
              peerHex: peerHex,
              clientOrderId: clientOrderId,
              symbol: symbol,
              side: _side,
              orderType: _orderType,
              quantityDecimal: quantityDecimal,
              limitPriceDecimal: limitPriceDecimal,
              timeInForce: timeInForce,
              entryMode: _entryMode,
              zoneSide: _zoneSide,
              zoneLowDecimal: zoneLowDecimal,
              zoneHighDecimal: zoneHighDecimal,
              zonePriceRule: _zonePriceRule,
              manualEntryPriceDecimal: null,
              triggerPriceDecimal: triggerPriceDecimal,
              stopLossDecimal: stopLossDecimal,
              takeProfitDecimal: takeProfitDecimal,
              createdAtUtc: nowUtc,
              strategyTag: strategyTag,
              liveDecision: liveDecision,
            ),
          )
          .timeout(_hostIntentTimeout);
      final response = useCaseResult.response;
      if (!mounted) return 'cancelled:screen_disposed';
      setState(() {
        _lastIntentResponse = response;
        _lastPreparedLiveDecision =
            response.status == PluginHostApiStatus.executed
                ? liveDecision
                : null;
        _intentBlockingMessage =
            response.status == PluginHostApiStatus.executed
                ? null
                : response.errorMessage ?? 'Intent was not prepared.';
      });
      final decisionEnvelope = useCaseResult.decisionEnvelope;
      await _module.uiLog.log(
        'bingx.intent.response',
        'status=${response.status.name} '
            'elapsedMs=${stopwatch.elapsedMilliseconds} '
            'source=${response.executionSource}',
      );
      if (response.status == PluginHostApiStatus.rejected) {
        final code =
            response.errorCode?.trim().isNotEmpty == true
                ? response.errorCode!.trim()
                : 'none';
        final msg =
            response.errorMessage?.trim().isNotEmpty == true
                ? response.errorMessage!.trim()
                : 'none';
        await _module.uiLog.log(
          'bingx.intent.rejected.detail',
          'code=$code message=$msg source=${response.executionSource}',
        );
      }
      await _module.uiLog.log(
        'drone.decision.envelope',
        'hash=${decisionEnvelope.envelopeHashHex} '
            'kind=decision screen=trading_drone',
      );

      switch (response.status) {
        case PluginHostApiStatus.executed:
          final hash = response.result?['intent_hash_hex']?.toString() ?? '';
          final shortHash =
              hash.length >= 12 ? '${hash.substring(0, 12)}..' : hash;
          await _showSnack('BingX intent prepared: $shortHash');
          break;
        case PluginHostApiStatus.blocked:
          final reason =
              response.blockingFacts.isEmpty
                  ? 'Consensus guard blocked execution.'
                  : response.blockingFacts.first.label;
          await _showSnack(reason);
          break;
        case PluginHostApiStatus.rejected:
          final message = _resolveIntentRejectedMessage(response);
          await _showSnack(message, seconds: 4);
          break;
      }
      return switch (response.status) {
        PluginHostApiStatus.executed => preparedTradingIntentTerminalOutcome,
        PluginHostApiStatus.blocked => 'blocked:intent_guard',
        PluginHostApiStatus.rejected =>
          'rejected:${response.errorCode ?? "intent_rejected"}',
      };
    } on TimeoutException {
      await _module.uiLog.log(
        'bingx.intent.timeout',
        'elapsedMs=${stopwatch.elapsedMilliseconds} timeoutMs=${_hostIntentTimeout.inMilliseconds}',
      );
      await _showSnack(
        'Intent host timeout (${_hostIntentTimeout.inSeconds}s)',
        seconds: 3,
      );
      return 'timeout:host_intent';
    }
  }

  Future<void> _broadcastLastIntent() async {
    if (_broadcastingSignal) return;
    final response = _lastIntentResponse;
    final result = response?.result;
    if (response?.status != PluginHostApiStatus.executed || result == null) {
      await _showSnack('Run a BingX intent first, then broadcast it');
      return;
    }

    final peers =
        _module.manualChecks
            .loadChecks()
            .where((check) => check.isSignable)
            .map((check) => check.peerHex)
            .toSet()
            .toList()
          ..sort();
    if (peers.isEmpty) {
      await _showSnack('No signable consensus peers available');
      return;
    }

    final signalId = 'sig-${DateTime.now().microsecondsSinceEpoch}';
    final payloadJson = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plugin_id': bingxFuturesTradingPluginId,
      'contract_kind': 'bingx_trade_signal_v1',
      'signal_type': 'intent_prepared',
      'signal_id': signalId,
      'intent_hash_hex': result['intent_hash_hex']?.toString(),
      'canonical_intent_json': result['canonical_intent_json']?.toString(),
      'symbol': result['symbol']?.toString(),
      'side': result['side']?.toString(),
      'order_type': result['order_type']?.toString(),
      'quantity_decimal': result['quantity_decimal']?.toString(),
      'entry_mode': result['entry_mode']?.toString() ?? 'direct',
      'strategy_tag': result['strategy_tag']?.toString(),
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
    });

    setState(() {
      _broadcastingSignal = true;
    });
    var sent = 0;
    var blocked = 0;
    var failed = 0;
    var receipts = 0;
    try {
      for (final peerHex in peers) {
        final sendResult = await _module.chatDelivery.sendCanonicalEnvelope(
          peerHex: peerHex,
          canonicalEnvelopeJson: payloadJson,
        );
        receipts += sendResult.deliveryReceiptCount;
        if (sendResult.isSuccess) {
          sent += 1;
        } else if (sendResult.blockedByConsensus) {
          blocked += 1;
        } else {
          failed += 1;
        }
      }
      await _module.uiLog.log(
        'bingx.signal.broadcast',
        'signal=$signalId peers=${peers.length} sent=$sent blocked=$blocked failed=$failed receipts=$receipts',
      );
      await _refreshSignalInbox(silentWhenEmpty: true);
      await _showSnack(
        'Signal broadcast: sent $sent/${peers.length}'
        '${blocked > 0 ? ' · blocked $blocked' : ''}'
        '${failed > 0 ? ' · failed $failed' : ''}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _broadcastingSignal = false;
        });
      }
    }
  }

  Future<void> _refreshSignalInbox({required bool silentWhenEmpty}) async {
    if (_refreshingSignals) return;
    _refreshingSignals = true;
    try {
      final capsuleHex = _module.activeCapsuleRootHex();
      if (capsuleHex == null) {
        if (!silentWhenEmpty) {
          await _showSnack('Active capsule identity is unavailable');
        }
        return;
      }
      final receive = await _module.passiveReceive.trigger(
        capsuleHex: capsuleHex,
        reason:
            silentWhenEmpty
                ? CapsulePassiveReceiveReason.screenActivation
                : CapsulePassiveReceiveReason.manual,
        quick: silentWhenEmpty,
        manualRetry: !silentWhenEmpty,
      );
      final result = receive.chat;
      if (result.code < 0) {
        if (!silentWhenEmpty) {
          await _showSnack(
            result.errorMessage ?? 'Inbox fetch failed (code ${result.code})',
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        final byId = <String, CapsuleTradeSignalInboxMessage>{
          for (final signal in _signalInbox) signal.id: signal,
          for (final signal in _module.chatDelivery.loadCachedTradeSignals())
            signal.id: signal,
        };
        for (final signal in result.tradeSignals) {
          byId[signal.id] = signal;
        }
        final merged =
            byId.values.toList()
              ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
        _signalInbox = List<CapsuleTradeSignalInboxMessage>.unmodifiable(
          merged,
        );
      });

      if (result.tradeSignals.isEmpty && silentWhenEmpty) return;
      await _showSnack(
        'Signal inbox: +${result.tradeSignals.length}'
        '${result.droppedByConsensus > 0 ? ' · dropped ${result.droppedByConsensus}' : ''}',
      );
    } finally {
      _refreshingSignals = false;
    }
  }

  Future<void> _repeatSignalAsDraft(
    CapsuleTradeSignalInboxMessage signal,
  ) async {
    final decoded = _tryDecodeJsonMap(signal.canonicalIntentJson);
    if (decoded == null) {
      await _module.uiLog.log(
        'bingx.signal.draft.rejected',
        'signal=${signal.signalId} reason=invalid_canonical_intent',
      );
      await _showSnack('Signal intent payload is invalid');
      return;
    }

    if (!mounted) return;
    setState(() {
      _peerController.text = signal.fromHex;
      _symbolController.text = decoded['symbol']?.toString() ?? signal.symbol;
      _displayedZoneDecision = null;
      _quantityController.text =
          decoded['quantity_decimal']?.toString() ?? signal.quantityDecimal;
      _side = decoded['side']?.toString() ?? signal.side;
      _orderType = decoded['order_type']?.toString() ?? signal.orderType;
      _timeInForce = decoded['time_in_force']?.toString() ?? 'GTC';
      _entryMode = decoded['entry_mode']?.toString() ?? signal.entryMode;
      _strategyTagController.text = decoded['strategy_tag']?.toString() ?? '';
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;

      if (_entryMode == 'zone_pending') {
        _zoneSide =
            decoded['zone_side']?.toString() ??
            (_side == 'buy' ? 'buyside' : 'sellside');
        _zoneLowController.text = decoded['zone_low_decimal']?.toString() ?? '';
        _zoneHighController.text =
            decoded['zone_high_decimal']?.toString() ?? '';
        final decodedRule =
            decoded['zone_price_rule']?.toString() ?? 'zone_mid';
        _zonePriceRule = decodedRule == 'manual' ? 'zone_mid' : decodedRule;
        _triggerPriceController.text =
            decoded['trigger_price_decimal']?.toString() ?? '';
        _stopLossController.text =
            decoded['stop_loss_decimal']?.toString() ?? '';
        _takeProfitController.text =
            decoded['take_profit_decimal']?.toString() ?? '';
        _limitPriceController.text =
            decoded['limit_price_decimal']?.toString() ?? '';
      } else {
        _limitPriceController.text =
            decoded['limit_price_decimal']?.toString() ?? '';
      }
    });

    final shortSignal =
        signal.signalId.length <= 12
            ? signal.signalId
            : '${signal.signalId.substring(0, 12)}..';
    await _module.uiLog.log(
      'bingx.signal.draft.loaded',
      'signal=${signal.signalId} from=${signal.fromHex} '
          'symbol=${_symbolController.text} side=$_side '
          'type=$_orderType mode=$_entryMode qty=${_quantityController.text}',
    );
    await _showSnack(
      'Draft loaded: ${_symbolController.text} · ${_side.toUpperCase()} · '
      '${_quantityController.text} ($shortSignal)',
      seconds: 3,
    );
  }

  String _formatOrderTime(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return '-';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}

class TradingDroneCredentialField extends StatefulWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String showTooltip;
  final String hideTooltip;

  const TradingDroneCredentialField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.showTooltip,
    required this.hideTooltip,
  });

  @override
  State<TradingDroneCredentialField> createState() =>
      _TradingDroneCredentialFieldState();
}

class _TradingDroneCredentialFieldState
    extends State<TradingDroneCredentialField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      obscureText: _obscureText,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.label,
        filled: true,
        fillColor: const Color(0xFF0F141C),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
          icon: Icon(
            _obscureText
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          tooltip: _obscureText ? widget.showTooltip : widget.hideTooltip,
        ),
      ),
    );
  }
}

class _TradingPeerScopeCard extends StatelessWidget {
  final String peerHex;
  final VoidCallback? onClear;

  const _TradingPeerScopeCard({required this.peerHex, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final hasPeer = peerHex.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B4657)),
      ),
      child: ListTile(
        leading: Icon(
          hasPeer ? Icons.group_outlined : Icons.person_outline_rounded,
          color: hasPeer ? const Color(0xFFC9B2FF) : const Color(0xFF9FAABA),
        ),
        title: const Text('Intent scope'),
        subtitle: Text(
          hasPeer
              ? 'Shared with ${PeerIdentityFormat.capsuleLabelFromRootHex(peerHex)}'
              : 'Solo trading. No trusted capsule is selected.',
        ),
        trailing:
            onClear == null
                ? null
                : IconButton(
                  tooltip: 'Use solo trading',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
      ),
    );
  }
}
