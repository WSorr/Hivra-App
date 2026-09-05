import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_exchange_execution_models.dart';
import '../models/bingx_futures_live_decision_models.dart';
import '../models/bingx_futures_live_strategy_models.dart';
import '../models/bingx_futures_order_sizing_models.dart';
import '../models/bingx_futures_order_tracking_models.dart';
import '../models/bingx_futures_order_replacement_models.dart';
import '../models/bingx_futures_risk_models.dart';
import '../models/bingx_futures_signal_rank_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import '../services/app_runtime_service.dart';
import '../services/trading_drone_module_service.dart';
import '../services/bingx_futures_trading_cycle_use_case_service.dart';
import '../services/bingx_futures_remote_runner_provisioning_service.dart';
import '../utils/bingx_futures_zone_evidence_formatter.dart';

part 'trading_drone_screen_remote_session.dart';
part 'trading_drone_screen_market_scan.dart';
part 'trading_drone_screen_execution.dart';
part 'trading_drone_screen_presentation.dart';

const String preparedTradingIntentTerminalOutcome = 'intent:prepared';
const List<int> tradingEffectBudgetOptions = <int>[1, 2, 4, 8, 16, 32];

@visibleForTesting
String? tradingReconciliationNotice(
  BingxFuturesManagedOrderReconciliationResult? result,
  String? activeCapsuleRootHex,
) {
  if (result == null || activeCapsuleRootHex == null ||
      result.capsuleRootHex != activeCapsuleRootHex || result.state == null) {
    return null;
  }
  final state = result.state!;
  String reason(String? diagnostic) {
    const prefix = 'provider_status_unknown:';
    if (diagnostic?.startsWith(prefix) == true) {
      return 'BingX reports ${diagnostic!.substring(prefix.length)}; final outcome unverified';
    }
    return diagnostic ?? 'Evidence unavailable';
  }
  final unresolved = <String, String>{
    for (final record in state.managedOrderProvenance.values)
      if (!record.testOrder && record.lifecycleStatus == BingxManagedOrderLifecycleStatus.unresolved)
        record.orderId: '${record.symbol} · ${record.orderId} · ${reason(record.lifecycleDiagnostic)}',
    for (final claim in state.liquidityEventEffectClaims.values)
      if (!claim.testOrder && claim.lifecycleStatus == BingxManagedOrderLifecycleStatus.unresolved)
        claim.orderId ?? claim.clientOrderId: '${claim.symbol} · ${claim.orderId ?? claim.clientOrderId} · ${reason(claim.lifecycleDiagnostic)}',
  };
  return <String>[
    'Last reconciliation · Active ${result.activeCount} · Completed ${result.terminalCount} · Needs review ${result.unresolvedCount}',
    'Completed means filled, cancelled, rejected or expired — not necessarily filled.',
    if (state.managedOrderProvenance.values.any((record) => record.testOrder) ||
        state.liquidityEventEffectClaims.values.any((claim) => claim.testOrder))
      'Test records are retained separately; they are not live orders.',
    if (result.unresolvedCount > 0)
      'Do not recreate these orders. Verify their outcome in BingX; missing evidence is not success or cancellation.',
    ...unresolved.values,
  ].join('\n');
}

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

@visibleForTesting
Future<void> restoreTradingDroneOrderState({
  required Future<bool> Function() restoreRemoteCompletedEffects,
  required Future<void> Function() restoreOpenOrdersTrackingState,
}) async {
  await restoreRemoteCompletedEffects();
  await restoreOpenOrdersTrackingState();
}

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
bool restoreTradingMandateSelection({
  required BingxFuturesTradingMandate? mandate,
  required DateTime nowUtc,
  required TextEditingController symbol,
  required TextEditingController maximumNotional,
}) {
  if (mandate == null || !mandate.isActiveAt(nowUtc)) return false;
  symbol.text = mandate.symbol;
  maximumNotional.text = mandate.maxOrderNotionalQuoteDecimal;
  return true;
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

  final TextEditingController _symbolController = TextEditingController(
    text: 'BTC-USDT',
  );
  final TextEditingController _maxNotionalUsdtController =
      TextEditingController(text: '100');
  final TextEditingController _quantityController = TextEditingController(
    text: '0.01',
  );
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
  bool _savingCredentials = false;
  bool _executing = false;
  bool _fetchingOpenOrders = false;
  bool _loadingPerpSymbols = false;
  bool _scanningSignals = false;
  bool _signalRankExpanded = true;
  bool _cancelingOrder = false;
  bool _fittingMaxNotional = false;
  bool _reviewingExposure = false;
  bool _useTestOrderEndpoint = false;
  bool _droneEnabled = false;
  BingxFuturesTradingMandate? _tradingMandate;
  bool _tradingControlLoaded = false;
  bool _savingTradingControl = false;
  bool _exportingRemoteMandate = false;
  bool _exportingRemoteRevocation = false;
  bool _provisioningRemoteRunner = false;
  double _stopLossPercent = _defaultStopLossPercent;
  double _takeProfitRiskReward = _defaultTakeProfitRiskReward;
  int _maxEffects = 1;

  String _side = 'buy';
  String _zoneSide = 'buyside';
  String _signalScanScope = _signalScanScopeCore;

  PluginHostApiResponse? _lastIntentResponse;
  BingxFuturesLiveDecisionResult? _lastPreparedLiveDecision;
  String? _intentBlockingMessage;
  BingxFuturesOrderExecutionResult? _lastExecution;
  BingxFuturesOpenOrdersResult? _lastOpenOrdersRead;
  BingxFuturesManagedOrderReconciliationResult? _lastReconciliation;
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
    unawaited(
      restoreTradingDroneOrderState(
        restoreRemoteCompletedEffects: _restoreRemoteCompletedEffects,
        restoreOpenOrdersTrackingState: _restoreOpenOrdersTrackingState,
      ),
    );
    _loadPerpetualSymbols(silent: true);
  }

  @override
  void dispose() {
    _openOrdersPollTimer?.cancel();
    unawaited(_module.publicSessionStream.disconnect());
    _symbolController.dispose();
    _maxNotionalUsdtController.dispose();
    _quantityController.dispose();
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
      final mandateActive = restoreTradingMandateSelection(
        mandate: _tradingMandate,
        nowUtc: DateTime.now().toUtc(),
        symbol: _symbolController,
        maximumNotional: _maxNotionalUsdtController,
      );
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
      if (!mandateActive && resumeSymbol != null) {
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

  String _formatDecimal(num value, {int scale = 8}) {
    final fixed = value.toStringAsFixed(scale);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  num? _toNum(String raw) => num.tryParse(raw.trim());

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
      );
      if (riskInput.accountEquityQuoteDecimal == null) {
        final reason = riskInput.firstUnavailableReason;
        await _module.uiLog.log(
          'bingx.risk.autofit.blocked',
          'reason=balance_unavailable exchange_reason=${reason ?? "-"}',
        );
        await _showSnack(
          reason == null
              ? 'Cannot auto-fit risk: BingX balance unavailable'
              : 'Cannot auto-fit risk: BingX futures access unavailable ($reason)',
          seconds: 4,
        );
        return;
      }
      final equity = _toNum(riskInput.accountEquityQuoteDecimal!);
      if (equity == null || equity <= 0) {
        await _showSnack('Cannot auto-fit risk: invalid equity');
        return;
      }
      final symbol = _symbolController.text.trim();
      final fit = await _module.orderSizing.fitMaximumNotional(
        symbol: symbol,
        accountEquityQuote: equity,
        maximumRiskPercent: _executionRiskPolicy.maxRiskPerTradePercent,
        stopLossPercent: _stopLossPercent,
      );
      final safeNotional = fit.safeNotionalQuote;
      final fittedNotional = fit.fittedNotionalQuote;
      final sizing = fit.sizing;
      String? sizingBlockMessage;
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
          sizingBlockMessage = sizing.reasonMessage;
          await _module.uiLog.log(
            'bingx.risk.autofit.blocked',
            'symbol=${symbol.toUpperCase()} max_notional=$fitted '
                'safe_notional=${_formatDecimal(safeNotional, scale: 4)} '
                'code=${sizing.reasonCode}',
          );
        } else {
          _quantityController.text = sizing.quantityDecimal!;
          await _module.uiLog.log(
            'bingx.risk.quantity',
            'symbol=${symbol.toUpperCase()} '
                'max_notional_usdt=$fitted '
                'order_notional_usdt=${sizing.orderNotionalQuoteDecimal} '
                'quantity=${sizing.quantityDecimal}',
          );
        }
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
        sizingBlockMessage != null
            ? 'Max notional auto-fit: $fitted USDT. '
                '${symbol.toUpperCase()} remains blocked: $sizingBlockMessage'
            : mandateNeedsReauthorization
            ? 'Max notional auto-fit: $fitted USDT. Trading paused; Resume to authorize this limit.'
            : 'Max notional auto-fit: $fitted USDT',
        seconds:
            sizingBlockMessage != null || mandateNeedsReauthorization ? 5 : 2,
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

  Future<BingxFuturesLiveDecisionResult?> _computeLiveDecision({
    required String symbol,
    bool silent = false,
    String? zoneEvaluationSide,
  }) async {
    final result = await _module.liveStrategyUseCase.execute(
      BingxFuturesLiveStrategyCommand(
        symbol: symbol,
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
          _displayedZoneDecision = decision;
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
    final symbol = _symbolController.text.trim();
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return 'blocked:symbol_required';
    }
    if (!await _primePublicSessionEvidence(symbol, reportFailure: true)) {
      return 'blocked:session_stream_unavailable';
    }
    return _runCanonicalSoloCycle(symbol: symbol);
  }

  String _formatOrderTime(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return '-';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
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
