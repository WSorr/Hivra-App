import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../services/atomic_file_write_service.dart';
import '../services/capsule_passive_receive_coordinator.dart';
import '../services/consensus_attestation_exchange_service.dart';
import '../services/trading_drone_module_service.dart';
import '../services/bingx_futures_trading_cycle_use_case_service.dart';
import '../services/hivra_file_picker_service.dart';
import '../utils/bingx_futures_zone_evidence_formatter.dart';
import '../utils/peer_identity_format.dart';

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
bool tradingMandateMatchesSelection({
  required BingxFuturesTradingMandate? mandate,
  required bool droneEnabled,
  required String selectedSymbol,
  required bool testOrder,
  required DateTime nowUtc,
}) {
  if (!droneEnabled || mandate == null || !mandate.isActiveAt(nowUtc)) {
    return false;
  }
  final normalizedSymbol = selectedSymbol.trim().toUpperCase();
  return mandate.symbol == normalizedSymbol && mandate.testOrder == testOrder;
}

@visibleForTesting
String? tradingMandateSelectionNotice({
  required BingxFuturesTradingMandate? mandate,
  required bool droneEnabled,
  required String selectedSymbol,
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
    testOrder: testOrder,
    nowUtc: nowUtc,
  )) {
    return null;
  }
  final authorizedMode = mandate.testOrder ? 'TEST' : 'LIVE';
  final selectedMode = testOrder ? 'TEST' : 'LIVE';
  return 'Authorized for ${mandate.symbol} $authorizedMode. '
      'Selected $normalizedSymbol $selectedMode. Re-authorize before exact export.';
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
  bool _useTestOrderEndpoint = true;
  bool _droneEnabled = false;
  BingxFuturesTradingMandate? _tradingMandate;
  bool _tradingControlLoaded = false;
  bool _savingTradingControl = false;
  bool _exportingRemoteMandate = false;
  double _stopLossPercent = _defaultStopLossPercent;
  double _takeProfitRiskReward = _defaultTakeProfitRiskReward;

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

  void _startOpenOrdersAutoTracking({required String symbol, String? orderId}) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    final normalizedOrderId = orderId?.trim();
    if ((normalizedOrderId == null || normalizedOrderId.isEmpty) &&
        _managedOrderIds.isEmpty) {
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

  Future<void> _persistOpenOrdersTrackingState({required String source}) async {
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
    }
  }

  Future<void> _changeDroneEnabled(bool value) async {
    if (!_tradingControlLoaded || _savingTradingControl) return;
    BingxFuturesTradingMandate? nextMandate = _tradingMandate;
    if (value) {
      if (_orderType != 'limit') {
        await _showSnack(
          'Bounded trading currently requires the Limit strategy path.',
        );
        return;
      }
      final credentials = await _ensureCredentialsLoaded();
      final capsuleRootHex = _module.orderTrackingStore.activeCapsuleRootHex;
      final symbol = _symbolController.text.trim().toUpperCase();
      final maxNotional = double.tryParse(
        _maxNotionalUsdtController.text.trim(),
      );
      if (credentials == null || capsuleRootHex == null) {
        await _showSnack('Capsule and BingX credentials are required.');
        return;
      }
      if (symbol.isEmpty || maxNotional == null || maxNotional <= 0) {
        await _showSnack('Symbol and positive max notional are required.');
        return;
      }
      final confirmed = await _confirmTradingMandate(
        symbol: symbol,
        maxNotional: maxNotional,
      );
      if (!confirmed) return;
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
        maxEffects: 32,
      );
    } else {
      nextMandate = nextMandate?.revoke(DateTime.now().toUtc());
    }
    setState(() {
      _droneEnabled = value;
      _tradingMandate = nextMandate;
      _savingTradingControl = true;
    });
    await _persistOpenOrdersTrackingState(source: 'drone_control_changed');
    if (mounted) {
      setState(() {
        _savingTradingControl = false;
      });
    }
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
              'Maximum effects: 32\n'
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

  Future<void> _exportSignedRemoteMandate() async {
    if (_exportingRemoteMandate) return;
    final mandate = _tradingMandate;
    if (!_droneEnabled ||
        mandate == null ||
        !mandate.isActiveAt(DateTime.now().toUtc())) {
      await _showSnack('An active bounded trading mandate is required.');
      return;
    }
    if (!Platform.isMacOS) {
      await _showSnack(
        'Remote mandate export is currently available on macOS.',
      );
      return;
    }
    final runnerKeyController = TextEditingController();
    final runnerKeyId = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Prepare remote mandate'),
            content: TextField(
              controller: runnerKeyController,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Runner key id',
                hintText: '64 lowercase hex characters',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(runnerKeyController.text.trim()),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    runnerKeyController.dispose();
    if (runnerKeyId == null) return;
    final admission = BingxFuturesRemoteMandateAdmission.issue(
      mandate: mandate,
      runnerKeyId: runnerKeyId,
      signCommitment: _module.signRootCommitment,
    );
    if (admission == null ||
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
              untrustedWireBytes: utf8.encode(admission.canonicalJson),
              verifySignature:
                  ({
                    required messageHashHex,
                    required participantIdHex,
                    required signatureHex,
                  }) => _module.verifyRootCommitmentSignature(
                    commitmentHashHex: messageHashHex,
                    capsuleRootHex: participantIdHex,
                    signatureHex: signatureHex,
                  ),
            ) ==
            null) {
      await _showSnack('Capsule could not sign the exact remote mandate.');
      return;
    }
    final directory = await HivraFilePickerService.selectDirectory(
      confirmButtonText: 'Export mandate',
    );
    if (directory == null || directory.trim().isEmpty) return;
    final target = File(
      '${directory.trim()}/trading-remote-mandate-${admission.operationId.substring(0, 16)}.json',
    );
    if (await target.exists()) {
      await _showSnack('The exact remote mandate artifact already exists.');
      return;
    }
    setState(() {
      _exportingRemoteMandate = true;
    });
    try {
      await const AtomicFileWriteService().writeString(
        target,
        admission.canonicalJson,
      );
      await _module.uiLog.log(
        'bingx.remote_mandate.exported',
        'operation_id=${admission.operationId} '
            'runner_key_id=${admission.runnerKeyId} effect=false',
      );
      await _showSnack('Signed remote mandate exported.');
    } catch (error) {
      await _module.uiLog.log(
        'bingx.remote_mandate.export.error',
        'operation_id=${admission.operationId} error=$error effect=false',
      );
      await _showSnack('Remote mandate export failed.');
    } finally {
      if (mounted) {
        setState(() {
          _exportingRemoteMandate = false;
        });
      }
    }
  }

  Future<void> _exportSignedRemoteExactOrder() async {
    if (_exportingRemoteMandate) return;
    final mandate = _tradingMandate;
    final result = _lastIntentResponse?.result;
    if (!_droneEnabled ||
        mandate == null ||
        !mandate.isActiveAt(DateTime.now().toUtc()) ||
        result == null) {
      await _showSnack('An active mandate and fresh intent are required.');
      return;
    }
    if (!Platform.isMacOS) {
      await _showSnack('Remote order export is currently available on macOS.');
      return;
    }
    final intent = BingxFuturesIntentPayload.fromPluginResult(result);
    final mandateMismatch = tradingMandateSelectionNotice(
      mandate: mandate,
      droneEnabled: _droneEnabled,
      selectedSymbol: intent.symbol,
      testOrder: _useTestOrderEndpoint,
      nowUtc: DateTime.now().toUtc(),
    );
    if (mandateMismatch != null) {
      await _showSnack(mandateMismatch, seconds: 4);
      return;
    }
    final fresh = await _module.executionUseCase
        .isPreparedLiquidityDecisionFresh(
          payload: intent,
          rawIntentResult: result,
          preparedDecision: _lastPreparedLiveDecision,
          refreshDecision:
              () => _computeLiveDecision(
                symbol: intent.symbol,
                peerHex: result['peer_hex']?.toString().trim() ?? '',
                silent: true,
                forceConsensusSignable: true,
                zoneEvaluationSide: intent.side,
              ),
        );
    if (!fresh) {
      await _showSnack('Market structure changed. Run a fresh intent first.');
      return;
    }
    if (!mounted) return;
    final runnerKeyController = TextEditingController();
    final runnerKeyId = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Prepare one exact remote order'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${intent.symbol} · ${intent.side.toUpperCase()} · '
                  '${intent.quantityDecimal} · '
                  '${mandate.testOrder ? "TEST" : "LIVE"}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: runnerKeyController,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Runner key id',
                    hintText: '64 lowercase hex characters',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(runnerKeyController.text.trim()),
                child: const Text('Sign exact order'),
              ),
            ],
          ),
    );
    runnerKeyController.dispose();
    if (runnerKeyId == null) return;
    final admission = BingxFuturesRemoteMandateAdmission.issueExactOrder(
      mandate: mandate,
      runnerKeyId: runnerKeyId,
      exactOrder: intent.toExactOrderJson(testOrder: mandate.testOrder),
      signCommitment: _module.signRootCommitment,
    );
    if (admission == null ||
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
              untrustedWireBytes: utf8.encode(admission.canonicalJson),
              verifySignature:
                  ({
                    required messageHashHex,
                    required participantIdHex,
                    required signatureHex,
                  }) => _module.verifyRootCommitmentSignature(
                    commitmentHashHex: messageHashHex,
                    capsuleRootHex: participantIdHex,
                    signatureHex: signatureHex,
                  ),
            ) ==
            null) {
      await _showSnack('Capsule could not sign the exact remote order.');
      return;
    }
    final directory = await HivraFilePickerService.selectDirectory(
      confirmButtonText: 'Export exact order',
    );
    if (directory == null || directory.trim().isEmpty) return;
    final target = File(
      '${directory.trim()}/trading-remote-order-${admission.operationId.substring(0, 16)}.json',
    );
    if (await target.exists()) {
      await _showSnack('The exact remote order artifact already exists.');
      return;
    }
    setState(() => _exportingRemoteMandate = true);
    try {
      await const AtomicFileWriteService().writeString(
        target,
        admission.canonicalJson,
      );
      await _module.uiLog.log(
        'bingx.remote_order.exported',
        'operation_id=${admission.operationId} '
            'runner_key_id=${admission.runnerKeyId} effect=false',
      );
      await _showSnack('Signed exact remote order exported.');
    } finally {
      if (mounted) setState(() => _exportingRemoteMandate = false);
    }
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
      if (_tradingMandate?.isActiveAt(DateTime.now().toUtc()) != true) {
        _droneEnabled = false;
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
      final trackedSymbol = state.trackedSymbol?.trim().toUpperCase();
      final trackedOrderId = state.trackedOrderId?.trim();
      if (trackedSymbol == null || trackedSymbol.isEmpty) {
        String? managedSymbol;
        for (final value in _managedOrderSymbols.values) {
          final normalized = value.trim().toUpperCase();
          if (normalized.isNotEmpty) {
            managedSymbol = normalized;
            break;
          }
        }
        final credentials = await _ensureCredentialsLoaded(silent: true);
        if (managedSymbol != null && credentials != null) {
          _startOpenOrdersAutoTracking(symbol: managedSymbol);
          await _fetchOpenOrders(silent: true);
        }
        if (mounted) {
          setState(() {});
        }
        await _module.uiLog.log(
          'bingx.exchange.tracking.restore',
          'tracked=no managedCount=${_managedOrderIds.length} '
              'symbolCount=${_managedOrderSymbols.length} '
              'provenanceCount=${_managedOrderProvenance.length} '
              'slPct=${_stopLossPercent.toStringAsFixed(2)} '
              'rr=${_takeProfitRiskReward.toStringAsFixed(2)}',
        );
        return;
      }
      _symbolController.text = trackedSymbol;
      if (await _ensureCredentialsLoaded(silent: true) == null) {
        if (mounted) {
          setState(() {});
        }
        await _module.uiLog.log(
          'bingx.exchange.tracking.restore',
          'tracked=deferred symbol=$trackedSymbol '
              'orderId=${trackedOrderId ?? "-"} reason=credentials_not_loaded '
              'managedCount=${_managedOrderIds.length} '
              'symbolCount=${_managedOrderSymbols.length} '
              'provenanceCount=${_managedOrderProvenance.length} '
              'slPct=${_stopLossPercent.toStringAsFixed(2)} '
              'rr=${_takeProfitRiskReward.toStringAsFixed(2)}',
        );
        return;
      }
      _startOpenOrdersAutoTracking(
        symbol: trackedSymbol,
        orderId: trackedOrderId,
      );
      await _module.uiLog.log(
        'bingx.exchange.tracking.restore',
        'tracked=yes symbol=$trackedSymbol '
            'orderId=${trackedOrderId ?? "-"} managedCount=${_managedOrderIds.length} '
            'symbolCount=${_managedOrderSymbols.length} '
            'provenanceCount=${_managedOrderProvenance.length} '
            'slPct=${_stopLossPercent.toStringAsFixed(2)} '
            'rr=${_takeProfitRiskReward.toStringAsFixed(2)}',
      );
      await _fetchOpenOrders(silent: true);
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

  Future<void> _loadPerpetualSymbols({required bool silent}) async {
    if (_loadingPerpSymbols) return;
    if (mounted) {
      setState(() {
        _loadingPerpSymbols = true;
      });
    } else {
      _loadingPerpSymbols = true;
    }
    try {
      final result = await _module.exchangeService.getPerpetualSymbols();
      await _module.uiLog.log(
        'bingx.symbols.perp',
        'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} count=${result.symbols.length} '
            'endpoint=${result.endpointPath}',
      );
      if (!result.isSuccess || result.symbols.isEmpty) {
        if (!silent) {
          await _showSnack(
            'Perp symbols failed: ${result.exchangeCode}',
            seconds: 3,
          );
        }
        return;
      }
      final merged = <String>{...result.symbols, ..._shortBreakdownSymbols};
      final sorted = merged.toList()..sort();
      if (!mounted) return;
      setState(() {
        _availablePerpSymbols = List<String>.unmodifiable(sorted);
      });
      if (!silent) {
        await _showSnack('Perp symbols loaded: ${sorted.length}');
      }
    } catch (error) {
      await _module.uiLog.log('bingx.symbols.perp.error', '$error');
      if (!silent) {
        await _showSnack('Perp symbols failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPerpSymbols = false;
        });
      } else {
        _loadingPerpSymbols = false;
      }
    }
  }

  Future<void> _openPerpetualSymbolPicker() async {
    if (_availablePerpSymbols.isEmpty) {
      await _loadPerpetualSymbols(silent: false);
      if (!mounted) return;
      if (_availablePerpSymbols.isEmpty) return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _availablePerpSymbols
                .where((symbol) {
                  if (query.isEmpty) return true;
                  return symbol.toLowerCase().contains(query.toLowerCase());
                })
                .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Search perpetual symbol',
                        hintText: 'BTC-USDT',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 420,
                      child:
                          filtered.isEmpty
                              ? const Center(
                                child: Text(
                                  'No symbols',
                                  style: TextStyle(color: Color(0xFF97A3B5)),
                                ),
                              )
                              : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final symbol = filtered[index];
                                  return ListTile(
                                    title: Text(symbol),
                                    onTap:
                                        () => Navigator.of(
                                          sheetContext,
                                        ).pop(symbol),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    setState(() {
      _symbolController.text = selected;
      _displayedZoneDecision = null;
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;
    });
    await _module.uiLog.log(
      'bingx.symbols.select',
      'symbol=$selected source=picker',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: selected,
      source: 'picker',
      force: true,
    );
  }

  Future<void> _scanSignalWatchlist() async {
    if (_scanningSignals) return;
    final currentSymbol = _symbolController.text.trim().toUpperCase();
    final peerHex = _peerController.text.trim().toLowerCase();
    if (_signalScanScope == _signalScanScopeAllPerps &&
        _availablePerpSymbols.isEmpty) {
      await _loadPerpetualSymbols(silent: false);
      if (!mounted) return;
    }
    final rawSymbols = _signalScanSymbols(currentSymbol);
    if (rawSymbols.isEmpty) {
      await _showSnack('No symbols to scan');
      return;
    }
    if (mounted) {
      setState(() {
        _scanningSignals = true;
      });
    } else {
      _scanningSignals = true;
    }
    try {
      await _module.uiLog.log(
        'bingx.signal.scan.start',
        'scope=$_signalScanScope symbols=${rawSymbols.length} '
            'prefilter=5m_volume_growth',
      );
      final scanObservedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final symbols = await _filterVolumeGrowthSymbols(
        rawSymbols,
        observedAtMs: scanObservedAtMs,
      );
      if (symbols.isEmpty) {
        await _module.uiLog.log(
          'bingx.signal.scan.empty',
          'scope=$_signalScanScope source_symbols=${rawSymbols.length} '
              'prefilter=5m_volume_growth observed_at_ms=$scanObservedAtMs',
        );
        await _showSnack(
          'Signal scan: no symbols with rising 5m volume',
          seconds: 3,
        );
        return;
      }
      final candidates = <BingxFuturesSignalRankCandidate>[];
      var skipped = 0;
      for (final symbol in symbols) {
        BingxFuturesLiveDecisionResult? decision;
        try {
          decision = await _computeLiveDecision(
            symbol: symbol,
            peerHex: peerHex,
            silent: true,
            forceConsensusSignable: peerHex.isEmpty,
          );
        } catch (error) {
          skipped += 1;
          await _module.uiLog.log(
            'bingx.signal.rank.candidate_error',
            'symbol=$symbol error=$error',
          );
          continue;
        }
        if (decision == null) continue;
        candidates.add(
          BingxFuturesSignalRankCandidate(symbol: symbol, decision: decision),
        );
      }
      if (candidates.isEmpty) {
        await _showSnack('Signal scan failed: no live decisions', seconds: 3);
        return;
      }
      final ranked = await _module.signalRankUseCase.execute(
        BingxFuturesSignalRankCommand(candidates: candidates),
      );
      if (!ranked.isSuccess) {
        await _module.uiLog.log(
          'bingx.signal.rank.rejected',
          'status=${ranked.response.status.name} code=${ranked.response.errorCode ?? "-"} '
              'message=${ranked.response.errorMessage ?? "-"}',
        );
        await _showSnack(
          'Signal rank failed: ${ranked.response.errorCode ?? ranked.response.status.name}',
          seconds: 4,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _signalRankEntries = ranked.entries;
        _signalScanCompletedAtUtc = DateTime.now().toUtc();
        _signalDecisionByHash = <String, BingxFuturesLiveDecisionResult>{
          for (final candidate in candidates)
            candidate.decision.liveDecisionHashHex: candidate.decision,
        };
        _signalRankExpanded = true;
      });
      final top = ranked.entries.isEmpty ? null : ranked.entries.first;
      await _module.uiLog.log(
        'bingx.signal.rank',
        'scope=$_signalScanScope source_symbols=${rawSymbols.length} '
            'volume_growth_symbols=${symbols.length} '
            'candidates=${candidates.length} '
            'skipped=$skipped '
            'entries=${ranked.entries.length} scan_hash=${_shortHash(ranked.scanHashHex)} '
            'top=${top == null ? "-" : "${top.symbol}:${top.bucket}:${top.score}"}',
      );
      await _showSnack(
        ranked.entries.any((entry) => entry.bucket == 'ready')
            ? 'Signal scan complete: ready found'
            : skipped > 0
            ? 'Signal scan partial: no ready signals, skipped $skipped'
            : 'Signal scan complete: no ready signals',
        seconds: 2,
      );
    } catch (error) {
      await _module.uiLog.log('bingx.signal.rank.error', '$error');
      if (mounted) {
        await _showSnack('Signal scan failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanningSignals = false;
        });
      } else {
        _scanningSignals = false;
      }
    }
  }

  List<String> _signalScanSymbols(String currentSymbol) {
    final source =
        _signalScanScope == _signalScanScopeAllPerps
            ? _availablePerpSymbols
            : _shortBreakdownSymbols;
    final symbols =
        <String>{
              ...source.map((symbol) => symbol.trim().toUpperCase()),
              if (currentSymbol.isNotEmpty) currentSymbol,
            }
            .where(
              (symbol) =>
                  symbol.isNotEmpty && _isNormalCryptoPerpSymbol(symbol),
            )
            .toList()
          ..sort();
    return symbols;
  }

  bool _isNormalCryptoPerpSymbol(String symbol) {
    final parts = symbol.trim().toUpperCase().split('-');
    if (parts.length != 2) return false;
    final base = parts[0];
    final quote = parts[1];
    if (quote != 'USDT' && quote != 'USDC') return false;
    if (!RegExp(r'^[A-Z][A-Z0-9]{1,14}$').hasMatch(base)) return false;
    if (base.startsWith('NC')) return false;
    if (RegExp(r'^\d').hasMatch(base)) return false;
    return true;
  }

  Future<List<String>> _filterVolumeGrowthSymbols(
    List<String> symbols, {
    required int observedAtMs,
  }) async {
    if (_signalScanScope == _signalScanScopeCore) {
      await _module.uiLog.log(
        'bingx.signal.volume_prefilter.skip',
        'scope=$_signalScanScope source=${symbols.length} reason=core_watchlist',
      );
      return symbols;
    }
    final tickerFiltered = await _prefilterLiquidTickerSymbols(symbols);
    final accepted = <String>[];
    var insufficient = 0;
    var flatOrFalling = 0;
    var failed = 0;
    for (final symbol in tickerFiltered) {
      try {
        final result = await _module.exchangeService.getPublicKlines(
          symbol: symbol,
          interval: '5m',
          limit: _signalVolumeGrowthKlineLimit,
        );
        if (!result.isSuccess || result.klines.length < 3) {
          insufficient += 1;
          continue;
        }
        final grows = _module.volumeGrowthFilter.hasStrictlyRisingClosedVolume(
          klines: result.klines,
          observedAtMs: observedAtMs,
        );
        if (grows) {
          accepted.add(symbol);
        } else {
          flatOrFalling += 1;
        }
      } catch (error) {
        failed += 1;
        await _module.uiLog.log(
          'bingx.signal.volume_prefilter.error',
          'symbol=$symbol error=$error',
        );
      }
    }
    await _module.uiLog.log(
      'bingx.signal.volume_prefilter',
      'scope=$_signalScanScope source=${symbols.length} '
          'ticker_filtered=${tickerFiltered.length} accepted=${accepted.length} '
          'flat_or_falling=$flatOrFalling insufficient=$insufficient failed=$failed '
          'observed_at_ms=$observedAtMs candles=closed',
    );
    return accepted;
  }

  Future<List<String>> _prefilterLiquidTickerSymbols(
    List<String> symbols,
  ) async {
    if (_signalScanScope != _signalScanScopeAllPerps ||
        symbols.length <= _signalTickerPrefilterLimit) {
      return symbols;
    }
    try {
      final tickers = await _module.exchangeService.getPublicTickers();
      if (!tickers.isSuccess || tickers.tickers.isEmpty) {
        await _module.uiLog.log(
          'bingx.signal.ticker_prefilter.skip',
          'reason=ticker_unavailable code=${tickers.exchangeCode} '
              'message=${tickers.exchangeMessage}',
        );
        return symbols;
      }
      final allowed = symbols.toSet();
      final currentSymbol = _symbolController.text.trim().toUpperCase();
      final selected =
          tickers.tickers
              .where(
                (ticker) =>
                    allowed.contains(ticker.symbol) &&
                    _isNormalCryptoPerpSymbol(ticker.symbol),
              )
              .take(_signalTickerPrefilterLimit)
              .map((ticker) => ticker.symbol)
              .toSet();
      if (currentSymbol.isNotEmpty && allowed.contains(currentSymbol)) {
        selected.add(currentSymbol);
      }
      final out = selected.toList()..sort();
      await _module.uiLog.log(
        'bingx.signal.ticker_prefilter',
        'source=${symbols.length} selected=${out.length} '
            'limit=$_signalTickerPrefilterLimit sort=quote_volume_desc',
      );
      return out;
    } catch (error) {
      await _module.uiLog.log('bingx.signal.ticker_prefilter.error', '$error');
      return symbols;
    }
  }

  String _signalScanScopeLabel() {
    if (_signalScanScope == _signalScanScopeAllPerps) {
      final count = _availablePerpSymbols.length;
      return count > 0
          ? 'All Perps ($count, top $_signalTickerPrefilterLimit volume)'
          : 'All Perps';
    }
    return 'Core Watchlist (${_shortBreakdownSymbols.length})';
  }

  Future<void> _applySignalRankEntry(BingxFuturesSignalRankEntry entry) async {
    if (!mounted) return;
    final decision = _signalDecisionByHash[entry.liveDecisionHashHex];
    setState(() {
      _symbolController.text = entry.symbol;
      _displayedZoneDecision = decision;
      _lastIntentResponse = null;
      _lastPreparedLiveDecision = null;
      _intentBlockingMessage = null;
      if (entry.side != null) {
        _side = entry.side!;
        _zoneSide = entry.side == 'buy' ? 'sellside' : 'buyside';
      }
      if (entry.zoneLowDecimal != null && entry.zoneHighDecimal != null) {
        _entryMode = 'zone_pending';
        _zonePriceRule = 'zone_mid';
        _zoneLowController.text = entry.zoneLowDecimal!;
        _zoneHighController.text = entry.zoneHighDecimal!;
      }
      _signalRankExpanded = false;
    });
    await _module.uiLog.log(
      'bingx.signal.rank.select',
      'symbol=${entry.symbol} bucket=${entry.bucket} score=${entry.score} '
          'side=${entry.side ?? "-"} live_hash=${_shortHash(entry.liveDecisionHashHex)}',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: entry.symbol,
      source: 'signal_rank',
      force: true,
    );
  }

  String _playbookQtyForSymbol(String symbol) {
    return switch (symbol.toUpperCase()) {
      'BTC-USDT' => '0.001',
      'ETH-USDT' => '0.01',
      'SOL-USDT' => '0.10',
      'BNB-USDT' => '0.01',
      'XRP-USDT' => '10',
      'DOGE-USDT' => '50',
      _ => '0.01',
    };
  }

  Future<void> _applyShortBreakdownPlaybook({required String symbol}) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    if (mounted) {
      setState(() {
        _symbolController.text = normalizedSymbol;
        _displayedZoneDecision = null;
        _lastIntentResponse = null;
        _lastPreparedLiveDecision = null;
        _intentBlockingMessage = null;
        _quantityController.text = _playbookQtyForSymbol(normalizedSymbol);
        _side = 'sell';
        _orderType = 'limit';
        _entryMode = 'zone_pending';
        _zoneSide = 'sellside';
        _zonePriceRule = 'zone_mid';
        _timeInForce = 'GTC';
        _strategyTagController.text = 'tvh_short_breakdown_v1';
        _limitPriceController.clear();
        _zoneLowController.clear();
        _zoneHighController.clear();
        _triggerPriceController.clear();
        _stopLossController.clear();
        _takeProfitController.clear();
      });
    }
    await _module.uiLog.log(
      'bingx.playbook.apply',
      'name=short_breakdown_v1 symbol=$normalizedSymbol side=sell mode=zone_pending',
    );
    await _maybeRetargetOpenOrdersTracking(
      symbol: normalizedSymbol,
      source: 'playbook',
      force: true,
    );
    await _showSnack('Playbook applied: short breakdown · $normalizedSymbol');
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

  ({String stopLossDecimal, String takeProfitDecimal}) _deriveRiskTargets({
    required String side,
    required num entryPrice,
    required double stopLossPercent,
    required double riskReward,
  }) {
    final slFactor = stopLossPercent / 100;
    final buy = side.trim().toLowerCase() == 'buy';
    final stopLoss =
        buy ? entryPrice * (1 - slFactor) : entryPrice * (1 + slFactor);
    final risk = (stopLoss - entryPrice).abs();
    final takeProfit =
        buy
            ? entryPrice + (risk * riskReward)
            : entryPrice - (risk * riskReward);
    return (
      stopLossDecimal: _formatDecimal(stopLoss, scale: 8),
      takeProfitDecimal: _formatDecimal(takeProfit, scale: 8),
    );
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
      _maxNotionalUsdtController.text = fitted;
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
      await _module.uiLog.log(
        'bingx.risk.autofit',
        'equity=${riskInput.accountEquityQuoteDecimal} '
            'risk_pct=${_executionRiskPolicy.maxRiskPerTradePercent.toStringAsFixed(2)} '
            'sl_pct=${_stopLossPercent.toStringAsFixed(2)} '
            'max_notional=$fitted '
            'safe_notional=${_formatDecimal(safeNotional, scale: 4)}',
      );
      await _showSnack('Max notional auto-fit: $fitted USDT');
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
    if (mounted) {
      setState(() {
        if (decision != null) {
          _displayedZoneDecision = decision;
          _lastPreparedLiveDecision = cycle.isPrepared ? decision : null;
          _side = decision.side ?? _side;
          _zoneSide = decision.zoneSide ?? _zoneSide;
          _entryMode = 'zone_pending';
          _zonePriceRule = 'zone_mid';
          _zoneLowController.text = decision.zoneLowDecimal ?? '';
          _zoneHighController.text = decision.zoneHighDecimal ?? '';
          _triggerPriceController.text =
              decision.side == 'buy'
                  ? decision.zoneHighDecimal ?? ''
                  : decision.zoneLowDecimal ?? '';
          _strategyTagController.text =
              _module.strategyNaming.tagForDecision(decision.decision) ?? '';
        }
        if (cycle.sizing?.quantityDecimal != null) {
          _quantityController.text = cycle.sizing!.quantityDecimal!;
        }
        if (cycle.stopLossDecimal != null) {
          _stopLossController.text = cycle.stopLossDecimal!;
        }
        if (cycle.takeProfitDecimal != null) {
          _takeProfitController.text = cycle.takeProfitDecimal!;
        }
        _lastIntentResponse = response;
        _intentBlockingMessage = cycle.isPrepared ? null : cycle.reasonMessage;
      });
    }
    await _module.uiLog.log(
      'bingx.trading_cycle.result',
      'status=${cycle.status.name} code=${cycle.reasonCode} '
          'symbol=$symbol effect=false '
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
      return 'response:${response.status.name}';
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
        final derived = _deriveRiskTargets(
          side: _side,
          entryPrice: entryPrice,
          stopLossPercent: _stopLossPercent,
          riskReward: _takeProfitRiskReward,
        );
        stopLossDecimal = derived.stopLossDecimal;
        _stopLossController.text = stopLossDecimal;
        takeProfitDecimal = derived.takeProfitDecimal;
        _takeProfitController.text = takeProfitDecimal;
        await _module.uiLog.log(
          'bingx.intent.risk_targets.auto',
          'entry=$entryPrice side=$_side '
              'sl=$stopLossDecimal tp=$takeProfitDecimal '
              'slPct=${_stopLossPercent.toStringAsFixed(2)} '
              'rr=${_takeProfitRiskReward.toStringAsFixed(2)}',
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
      return 'response:${response.status.name}';
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

  Future<void> _executeLastIntent() async {
    await _module.uiLog.log(
      'bingx.exchange.execute.tap',
      'running=$_executing hasIntent=${_lastIntentResponse?.status == PluginHostApiStatus.executed}',
    );
    if (_executing) return;
    final response = _lastIntentResponse;
    final result = response?.result;
    if (response?.status != PluginHostApiStatus.executed || result == null) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_intent status=${response?.status.name ?? "none"}',
      );
      await _showSnack('Run a BingX intent first');
      return;
    }
    final currentSymbol = _symbolController.text.trim().toUpperCase();
    final intentSymbol = result['symbol']?.toString().trim().toUpperCase();
    if (currentSymbol.isNotEmpty &&
        intentSymbol != null &&
        intentSymbol.isNotEmpty &&
        currentSymbol != intentSymbol) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=stale_intent current_symbol=$currentSymbol intent_symbol=$intentSymbol',
      );
      await _showSnack('Run a fresh intent for $currentSymbol first');
      return;
    }

    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _module.uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_credentials',
      );
      await _showSnack('Save BingX API credentials first');
      return;
    }

    setState(() {
      _executing = true;
    });
    try {
      final useCaseResult = await _module.executionUseCase.execute(
        screen: 'trading_drone',
        rawIntentResult: result,
        credentials: credentials,
        riskPolicy: _executionRiskPolicy,
        fallbackEquityQuote: _fallbackRiskEquityQuote,
        testOrder: _useTestOrderEndpoint,
        preparedDecision: _lastPreparedLiveDecision,
        refreshDecision:
            () => _computeLiveDecision(
              symbol: intentSymbol ?? currentSymbol,
              peerHex: result['peer_hex']?.toString().trim() ?? '',
              silent: true,
              forceConsensusSignable:
                  (result['peer_hex']?.toString().trim() ?? '').isEmpty,
              zoneEvaluationSide: result['side']?.toString(),
            ),
      );
      for (final diagnostic in useCaseResult.diagnostics) {
        await _module.uiLog.log('bingx.exchange.risk_detail', diagnostic);
      }
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.invalidIntent) {
        await _module.uiLog.log(
          'bingx.exchange.execute.parse_error',
          useCaseResult.errorMessage ?? 'invalid intent',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Invalid intent',
          seconds: 3,
        );
        return;
      }
      if (useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.staleIntent ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.executionPaused ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus.mandateBlocked ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus
                  .duplicateLiquidityEvent ||
          useCaseResult.status ==
              BingxFuturesExchangeExecutionUseCaseStatus
                  .effectClaimUnavailable) {
        await _module.uiLog.log(
          'bingx.exchange.execute.guard',
          'blocked=${useCaseResult.errorCode ?? useCaseResult.status.name}',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Execution blocked',
          seconds: 4,
        );
        return;
      }
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.riskUnavailable) {
        await _module.uiLog.log(
          'bingx.exchange.risk_error',
          useCaseResult.errorCode ?? 'risk_unavailable',
        );
        await _showSnack(
          useCaseResult.errorMessage ?? 'Risk check unavailable',
        );
        return;
      }
      final riskDecision = useCaseResult.riskDecision!;
      if (useCaseResult.status ==
          BingxFuturesExchangeExecutionUseCaseStatus.riskBlocked) {
        final shortHash = riskDecision.decisionHashHex.substring(0, 12);
        final executionEnvelope = useCaseResult.executionEnvelope;
        await _module.uiLog.log(
          'bingx.exchange.risk_blocked',
          'code=${riskDecision.reasonCode} hash=$shortHash '
              'risk=${riskDecision.tradeRiskQuoteDecimal} '
              'limit=${riskDecision.tradeRiskLimitQuoteDecimal}',
        );
        if (executionEnvelope != null) {
          await _module.uiLog.log(
            'drone.execution.envelope',
            'hash=${executionEnvelope.envelopeHashHex} '
                'kind=execution screen=trading_drone risk=blocked',
          );
        }
        await _showSnack(
          '${riskDecision.reasonMessage} ($shortHash)',
          seconds: 4,
        );
        return;
      }
      await _module.uiLog.log(
        'bingx.exchange.risk_allowed',
        'hash=${riskDecision.decisionHashHex.substring(0, 12)} '
            'max_qty=${riskDecision.maxAllowedQuantityDecimal} '
            'risk=${riskDecision.tradeRiskQuoteDecimal}',
      );
      final payload = useCaseResult.payload!;
      await _module.uiLog.log(
        'bingx.exchange.execute.intent',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'entry=${payload.entryMode} limit=${payload.limitPriceDecimal ?? "-"} '
            'trigger=${payload.triggerPriceDecimal ?? "-"} '
            'sl=${payload.stopLossDecimal ?? "-"} '
            'tp=${payload.takeProfitDecimal ?? "-"} '
            'tif=${payload.timeInForce ?? "-"}',
      );
      final queued = useCaseResult.queuedExecution!;
      final executionEnvelope = useCaseResult.executionEnvelope!;
      final safeMessage = queued.execution.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.execute',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'test=${_useTestOrderEndpoint ? "yes" : "no"} attempts=${queued.attempts} '
            'cache=${queued.fromIdempotentCache ? "hit" : "miss"} '
            'success=${queued.execution.isSuccess} http=${queued.execution.httpStatusCode} '
            'code=${queued.execution.exchangeCode} endpoint=${queued.execution.endpointPath} '
            'orderId=${queued.execution.orderId ?? "-"} msg=$safeMessage',
      );
      await _module.uiLog.log(
        'drone.execution.envelope',
        'hash=${executionEnvelope.envelopeHashHex} '
            'kind=execution screen=trading_drone',
      );
      if (!mounted) return;
      setState(() {
        _lastExecution = queued.execution;
        _lastExecutionAttempts = queued.attempts;
        _lastExecutionFromCache = queued.fromIdempotentCache;
      });

      if (queued.execution.isSuccess) {
        final orderId = queued.execution.orderId?.trim();
        _registerManagedOrderId(
          orderId,
          symbol: payload.symbol,
          provenance:
              orderId == null || orderId.isEmpty
                  ? null
                  : _buildManagedOrderProvenance(
                    orderId: orderId,
                    payload: payload,
                    result: result,
                    testOrder: _useTestOrderEndpoint,
                    credentials: credentials,
                  ),
        );
        _startOpenOrdersAutoTracking(
          symbol: payload.symbol,
          orderId: queued.execution.orderId,
        );
        unawaited(_fetchOpenOrders(silent: true));
        await _showSnack(
          'Order sent${queued.execution.orderId == null ? '' : ' · id ${queued.execution.orderId}'}'
          '${queued.fromIdempotentCache ? ' · idempotent cache' : ''}',
        );
      } else {
        await _showSnack(
          'Order failed: ${queued.execution.exchangeCode} ${queued.execution.exchangeMessage}',
          seconds: 4,
        );
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.error', '$error');
      await _showSnack('BingX execution failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _executing = false;
        });
      }
    }
  }

  Future<BingxFuturesRiskDecision?> _evaluateExecutionRisk({
    required BingxFuturesIntentPayload payload,
    required Map<String, dynamic> rawIntentResult,
  }) async {
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return null;
    }
    final evaluation = await _module.executionUseCase.evaluateRisk(
      payload: payload,
      rawIntentResult: rawIntentResult,
      credentials: credentials,
      riskPolicy: _executionRiskPolicy,
      fallbackEquityQuote: _fallbackRiskEquityQuote,
    );
    for (final diagnostic in evaluation.diagnostics) {
      await _module.uiLog.log('bingx.exchange.risk_detail', diagnostic);
    }
    if (evaluation.decision == null) {
      await _module.uiLog.log(
        'bingx.exchange.risk_error',
        evaluation.errorCode ?? 'risk_unavailable',
      );
      await _showSnack(evaluation.errorMessage ?? 'Risk check unavailable');
    }
    return evaluation.decision;
  }

  Future<void> _fetchOpenOrders({bool silent = false}) async {
    if (_fetchingOpenOrders) return;
    final credentials = await _ensureCredentialsLoaded(silent: silent);
    if (credentials == null) {
      if (!silent) {
        await _showSnack('Save BingX API credentials first');
      }
      return;
    }
    setState(() {
      _fetchingOpenOrders = true;
    });
    try {
      final result = await _module.exchangeService.getOpenOrders(
        credentials: credentials,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.open_orders',
        'symbol=${result.symbol} success=${result.isSuccess} '
            'http=${result.httpStatusCode} code=${result.exchangeCode} '
            'count=${result.orders.length} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      final allOrders = result.orders;
      final reconciliation = await _module.executionUseCase
          .reconcileManagedOrders(credentials: credentials, openOrders: result);
      if (!mounted) return;
      _applyManagedOrderReconciliation(reconciliation);
      for (final order in allOrders) {
        if (_managedOrderIds.contains(order.orderId)) {
          _managedOrderSymbols[order.orderId] = order.symbol.toUpperCase();
        }
      }
      final managedOrders = allOrders
          .where((order) => _managedOrderIds.contains(order.orderId))
          .toList(growable: false);
      final lifecycleRevisionBeforeRevalidation =
          _managedOrderLifecycleRevision;
      if (result.isSuccess && managedOrders.isNotEmpty) {
        await _revalidateManagedOpenOrders(
          credentials: credentials,
          managedOrders: managedOrders,
          silent: silent,
        );
      }
      final snapshotInvalidatedByLifecycle =
          lifecycleRevisionBeforeRevalidation != _managedOrderLifecycleRevision;
      setState(() {
        _lastOpenOrdersRead = result;
        if (result.isSuccess) {
          _openOrders = allOrders;
        }
        if (result.isSuccess && managedOrders.isNotEmpty) {
          _cancelOrderIdController.text = managedOrders.first.orderId;
        }
      });
      final trackedOrderId = _trackedOrderId;
      if (trackedOrderId != null && trackedOrderId.isNotEmpty) {
        if (result.isSuccess) {
          if (snapshotInvalidatedByLifecycle) {
            await _module.uiLog.log(
              'bingx.exchange.tracking.skip',
              'symbol=${result.symbol} orderId=$trackedOrderId '
                  'reason=stale_snapshot_after_lifecycle_change',
            );
            return;
          }
          final trackedStillOpen = allOrders.any(
            (order) => order.orderId == trackedOrderId,
          );
          await _module.uiLog.log(
            'bingx.exchange.tracking.check',
            'symbol=${result.symbol} orderId=$trackedOrderId '
                'open=${trackedStillOpen ? "yes" : "no"} '
                'managedCount=${managedOrders.length} totalCount=${allOrders.length}',
          );
          if (!trackedStillOpen) {
            _managedOrderIds.remove(trackedOrderId);
            _managedOrderSymbols.remove(trackedOrderId);
            _managedOrderProvenance.remove(trackedOrderId);
            _managedOrderLifecycleRevision += 1;
            final remainingManagedOrders = allOrders
                .where((order) => _managedOrderIds.contains(order.orderId))
                .toList(growable: false);
            if (remainingManagedOrders.isNotEmpty) {
              final nextTrackedOrderId = remainingManagedOrders.first.orderId;
              _trackedOrderId = nextTrackedOrderId;
              _cancelOrderIdController.text = nextTrackedOrderId;
              await _persistOpenOrdersTrackingState(
                source: 'tracked_order_closed_rotate',
              );
              await _module.uiLog.log(
                'bingx.exchange.tracking.rotate',
                'symbol=${result.symbol} previous=$trackedOrderId next=$nextTrackedOrderId '
                    'managedCount=${remainingManagedOrders.length}',
              );
            } else {
              _stopOpenOrdersAutoTracking(reason: 'order_closed');
              if (!silent) {
                await _showSnack('Tracked order is no longer open');
              }
            }
          }
        } else {
          await _module.uiLog.log(
            'bingx.exchange.tracking.skip',
            'symbol=${result.symbol} orderId=$trackedOrderId '
                'reason=open_orders_failed code=${result.exchangeCode} '
                'http=${result.httpStatusCode}',
          );
        }
      }
      if (!silent) {
        await _showSnack(
          result.isSuccess
              ? 'Open orders: ${allOrders.length} · drone: ${managedOrders.length}'
              : 'Open orders failed: ${result.exchangeCode}',
          seconds: result.isSuccess ? 2 : 4,
        );
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.open_orders.error', '$error');
      if (!silent) {
        await _showSnack('Fetch open orders failed: $error', seconds: 3);
      }
    } finally {
      if (mounted) {
        setState(() {
          _fetchingOpenOrders = false;
        });
      }
    }
  }

  void _applyManagedOrderReconciliation(
    BingxFuturesManagedOrderReconciliationResult reconciliation,
  ) {
    final state = reconciliation.state;
    if (state == null ||
        reconciliation.capsuleRootHex != _module.activeCapsuleRootHex()) {
      return;
    }
    _managedOrderIds
      ..clear()
      ..addAll(state.managedOrderIds);
    _managedOrderSymbols
      ..clear()
      ..addAll(state.managedOrderSymbols);
    _managedOrderProvenance
      ..clear()
      ..addAll(state.managedOrderProvenance);
    _trackedOrdersSymbol = state.trackedSymbol;
    _trackedOrderId = state.trackedOrderId;
    _cancelOrderIdController.text = state.trackedOrderId ?? '';
    _managedOrderLifecycleRevision += 1;
    unawaited(
      _module.uiLog.log(
        'bingx.exchange.tracking.reconcile',
        'active=${reconciliation.activeCount} '
            'terminal=${reconciliation.terminalCount} '
            'unresolved=${reconciliation.unresolvedCount} '
            'trackedOrderId=${state.trackedOrderId ?? "-"}',
      ),
    );
    if (state.managedOrderIds.isEmpty) {
      _stopOpenOrdersAutoTracking(reason: 'no_managed_open_orders');
    }
  }

  Future<void> _revalidateManagedOpenOrders({
    required BingxFuturesApiCredentials credentials,
    required List<BingxFuturesOpenOrder> managedOrders,
    required bool silent,
  }) async {
    final bySymbol = <String, List<BingxFuturesOpenOrder>>{};
    for (final order in managedOrders) {
      final symbol = order.symbol.trim().toUpperCase();
      if (symbol.isEmpty) continue;
      bySymbol.putIfAbsent(symbol, () => <BingxFuturesOpenOrder>[]).add(order);
    }

    var canceled = 0;
    final replacementLifecycleKeys = <String>{};
    for (final entry in bySymbol.entries) {
      final actionableDecision = await _computeLiveDecision(
        symbol: entry.key,
        peerHex: '',
        silent: true,
        forceConsensusSignable: true,
      );
      if (actionableDecision == null) {
        await _module.uiLog.log(
          'bingx.exchange.revalidate.skip',
          'symbol=${entry.key} reason=live_decision_unavailable '
              'orders=${entry.value.length}',
        );
        continue;
      }
      final structuralDecisions = <String, BingxFuturesLiveDecisionResult?>{};

      for (final order in entry.value) {
        if (!_managedOrderIds.contains(order.orderId)) continue;
        final orderSide = switch (order.side.trim().toLowerCase()) {
          'buy' => 'buy',
          'sell' => 'sell',
          _ => null,
        };
        var revalidationDecision = actionableDecision;
        if (!actionableDecision.canPrepareIntent && orderSide != null) {
          if (!structuralDecisions.containsKey(orderSide)) {
            structuralDecisions[orderSide] = await _computeLiveDecision(
              symbol: entry.key,
              peerHex: '',
              silent: true,
              forceConsensusSignable: true,
              zoneEvaluationSide: orderSide,
            );
          }
          final structuralDecision = structuralDecisions[orderSide];
          if (structuralDecision == null) {
            await _module.uiLog.log(
              'bingx.exchange.revalidate.skip',
              'symbol=${entry.key} orderId=${order.orderId} '
                  'reason=structural_decision_unavailable side=$orderSide',
            );
            continue;
          }
          revalidationDecision = structuralDecision;
        }
        final provenance = _managedOrderProvenance[order.orderId];
        final verdict = _module.orderRevalidation.revalidate(
          order: order,
          liveDecision: revalidationDecision,
        );
        await _module.uiLog.log(
          'bingx.exchange.revalidate',
          'symbol=${order.symbol} orderId=${order.orderId} '
              'action=${verdict.action.name} reason=${verdict.reasonCode} '
              'live_hash=${revalidationDecision.liveDecisionHashHex.substring(0, 12)}',
        );
        if (!verdict.shouldCancel) continue;

        final cancel = await _module.exchangeService.cancelOrder(
          credentials: credentials,
          symbol: order.symbol,
          orderId: order.orderId,
        );
        await _module.uiLog.log(
          'bingx.exchange.revalidate.cancel',
          'symbol=${order.symbol} orderId=${order.orderId} '
              'success=${cancel.isSuccess} code=${cancel.exchangeCode} '
              'reason=${verdict.reasonCode}',
        );
        if (!cancel.isSuccess) continue;
        canceled += 1;
        _managedOrderIds.remove(order.orderId);
        _managedOrderSymbols.remove(order.orderId);
        _managedOrderProvenance.remove(order.orderId);
        _managedOrderLifecycleRevision += 1;
        if (_trackedOrderId == order.orderId) {
          _trackedOrderId = null;
        }
        if (provenance == null) {
          await _module.uiLog.log(
            'bingx.exchange.replace.skip',
            'symbol=${order.symbol} orderId=${order.orderId} '
                'reason=replacement_provenance_missing',
          );
          continue;
        }
        if (!actionableDecision.canPrepareIntent) {
          await _module.uiLog.log(
            'bingx.exchange.replace.skip',
            'symbol=${order.symbol} orderId=${order.orderId} '
                'reason=structural_revalidation_cancel_only',
          );
          continue;
        }
        try {
          await _replaceCanceledManagedOrder(
            credentials: credentials,
            provenance: provenance,
            liveDecision: actionableDecision,
            cancellationReasonCode: verdict.reasonCode,
            replacementLifecycleKeys: replacementLifecycleKeys,
          );
        } catch (error) {
          await _module.uiLog.log(
            'bingx.exchange.replace.error',
            'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
                'error=$error',
          );
        }
      }
    }

    if (canceled > 0) {
      await _persistOpenOrdersTrackingState(source: 'revalidate_cancel');
      if (!silent && mounted) {
        await _showSnack('Canceled stale drone orders: $canceled');
      }
    }
  }

  Future<void> _replaceCanceledManagedOrder({
    required BingxFuturesApiCredentials credentials,
    required BingxManagedOrderProvenance provenance,
    required BingxFuturesLiveDecisionResult liveDecision,
    required String cancellationReasonCode,
    required Set<String> replacementLifecycleKeys,
  }) async {
    final cycleAtUtc = DateTime.now().toUtc().toIso8601String();
    final plan = _module.orderReplacement.plan(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
    );
    await _module.uiLog.log(
      'bingx.exchange.replace.plan',
      'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
          'status=${plan.status.name} reason=${plan.reasonCode} '
          'liveHash=${liveDecision.liveDecisionHashHex.substring(0, 12)}',
    );
    if (!plan.isReady) return;
    final peerHex = plan.hostArgs!['peer_hex']?.toString().trim() ?? '';
    final lifecycleKey =
        '$peerHex|${provenance.symbol.toUpperCase()}|${provenance.side}';
    if (!replacementLifecycleKeys.add(lifecycleKey)) {
      await _module.uiLog.log(
        'bingx.exchange.replace.skip',
        'oldOrderId=${provenance.orderId} symbol=${provenance.symbol} '
            'reason=replacement_lifecycle_duplicate key=$lifecycleKey',
      );
      return;
    }

    Map<String, dynamic>? replacementIntentResult;
    final runtime = await _module.orderReplacement.execute(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
      prepareIntent: (hostArgs) async {
        final response = await _module.pluginHostApi
            .executeWithRuntimeHook(
              PluginHostApiRequest(
                schemaVersion: pluginHostApiSchemaVersion,
                pluginId: bingxFuturesTradingPluginId,
                method: placeBingxFuturesOrderIntentMethod,
                args: hostArgs,
              ),
            )
            .timeout(_hostIntentTimeout);
        replacementIntentResult = response.result;
        return response;
      },
      evaluateRisk: (payload, rawIntentResult) {
        return _evaluateExecutionRisk(
          payload: payload,
          rawIntentResult: rawIntentResult,
        );
      },
      executeOrder: (payload, testOrder) async {
        final rawIntentResult = replacementIntentResult;
        if (rawIntentResult == null) return null;
        final execution = await _module.executionUseCase.execute(
          screen: 'trading_drone_replacement',
          rawIntentResult: rawIntentResult,
          credentials: credentials,
          riskPolicy: _executionRiskPolicy,
          fallbackEquityQuote: _fallbackRiskEquityQuote,
          testOrder: testOrder,
          preparedDecision: liveDecision,
          refreshDecision:
              () => _computeLiveDecision(
                symbol: payload.symbol,
                peerHex: '',
                silent: true,
                forceConsensusSignable: true,
                zoneEvaluationSide: payload.side,
              ),
        );
        return execution.queuedExecution;
      },
    );
    final response = runtime.hostResponse;
    await _module.uiLog.log(
      'bingx.exchange.replace.intent',
      'oldOrderId=${provenance.orderId} runtime=${runtime.status.name} '
          'status=${response?.status.name ?? "-"} '
          'source=${response?.executionSource ?? "-"} '
          'code=${response?.errorCode ?? "-"}',
    );
    final riskDecision = runtime.riskDecision;
    if (runtime.status == BingxFuturesReplacementRuntimeStatus.riskBlocked ||
        runtime.status ==
            BingxFuturesReplacementRuntimeStatus.riskUnavailable) {
      await _module.uiLog.log(
        'bingx.exchange.replace.risk_blocked',
        'oldOrderId=${provenance.orderId} '
            'code=${riskDecision?.reasonCode ?? "risk_unavailable"}',
      );
    }
    final payload = runtime.payload;
    final queued = runtime.queuedExecution;
    final result = response?.result;
    if (payload == null ||
        queued == null ||
        riskDecision == null ||
        result == null) {
      return;
    }

    final executionEnvelope = _module.observability.buildExecutionEnvelope(
      screen: 'trading_drone_replacement',
      symbol: payload.symbol,
      side: payload.side,
      orderType: payload.orderType,
      idempotencyKey: queued.idempotencyKey,
      attempts: queued.attempts,
      fromIdempotentCache: queued.fromIdempotentCache,
      isSuccess: queued.execution.isSuccess,
      httpStatusCode: queued.execution.httpStatusCode,
      exchangeCode: queued.execution.exchangeCode,
      endpointPath: queued.execution.endpointPath,
      orderId: queued.execution.orderId,
      intentHashHex: payload.intentHashHex,
      riskDecisionCode: riskDecision.reasonCode,
      riskDecisionHashHex: riskDecision.decisionHashHex,
      marketSnapshotHashHex:
          result['market_snapshot_hash_hex']?.toString().trim(),
      featureHashHex: result['feature_hash_hex']?.toString().trim(),
      tvhDecisionHashHex: result['tvh_decision_hash_hex']?.toString().trim(),
      liveDecisionHashHex: result['live_decision_hash_hex']?.toString().trim(),
    );
    await _module.uiLog.log(
      'bingx.exchange.replace.execute',
      'oldOrderId=${provenance.orderId} '
          'success=${queued.execution.isSuccess} '
          'newOrderId=${queued.execution.orderId ?? "-"} '
          'attempts=${queued.attempts} code=${queued.execution.exchangeCode}',
    );
    await _module.uiLog.log(
      'drone.execution.envelope',
      'hash=${executionEnvelope.envelopeHashHex} '
          'kind=execution screen=trading_drone_replacement',
    );
    if (!queued.execution.isSuccess) return;

    final newOrderId = queued.execution.orderId?.trim();
    if (newOrderId == null || newOrderId.isEmpty) {
      await _module.uiLog.log(
        'bingx.exchange.replace.skip',
        'oldOrderId=${provenance.orderId} '
            'reason=replacement_receipt_missing_order_id',
      );
      return;
    }
    _registerManagedOrderId(
      newOrderId,
      symbol: payload.symbol,
      provenance: _buildManagedOrderProvenance(
        orderId: newOrderId,
        payload: payload,
        result: result,
        testOrder: provenance.testOrder,
        credentials: credentials,
      ),
    );
    _startOpenOrdersAutoTracking(symbol: payload.symbol, orderId: newOrderId);
    await _module.uiLog.log(
      'bingx.exchange.replace.complete',
      'oldOrderId=${provenance.orderId} newOrderId=$newOrderId '
          'intentHash=${_shortHash(payload.intentHashHex)}',
    );
  }

  String _shortHash(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '-';
    return normalized.length <= 12 ? normalized : normalized.substring(0, 12);
  }

  Future<void> _cancelOrder({BingxFuturesOpenOrder? order}) async {
    if (_cancelingOrder) return;
    final credentials = await _ensureCredentialsLoaded();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }
    final symbol = order?.symbol.trim() ?? _symbolController.text.trim();
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return;
    }
    final orderId =
        order?.orderId.trim() ?? _cancelOrderIdController.text.trim();
    if (orderId.isEmpty) {
      await _showSnack('Order ID is required');
      return;
    }

    setState(() {
      _cancelingOrder = true;
    });
    try {
      final result = await _module.exchangeService.cancelOrder(
        credentials: credentials,
        symbol: symbol,
        orderId: orderId,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.cancel_order',
        'symbol=${result.symbol} requestOrderId=${result.requestedOrderId} '
            'canceledOrderId=${result.canceledOrderId ?? "-"} '
            'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      setState(() {
        _lastCancelOrder = result;
        if (result.isSuccess) {
          final canceled = result.canceledOrderId ?? result.requestedOrderId;
          _managedOrderIds.remove(canceled);
          _managedOrderSymbols.remove(canceled);
          _managedOrderProvenance.remove(canceled);
          _managedOrderLifecycleRevision += 1;
          _openOrders =
              _openOrders.where((order) => order.orderId != canceled).toList();
        }
      });
      if (result.isSuccess) {
        await _persistOpenOrdersTrackingState(source: 'cancel_order');
      }
      await _showSnack(
        result.isSuccess
            ? 'Order canceled: ${result.canceledOrderId ?? result.requestedOrderId}'
            : 'Cancel failed: ${result.exchangeCode}',
        seconds: result.isSuccess ? 2 : 4,
      );
      if (result.isSuccess) {
        await _fetchOpenOrders(silent: true);
      }
    } catch (error) {
      await _module.uiLog.log('bingx.exchange.cancel_order.error', '$error');
      await _showSnack('Cancel order failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _cancelingOrder = false;
        });
      }
    }
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

  Widget _statusChip(String label, {Color? accent}) {
    final color = accent ?? const Color(0xFFAEB9C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent == null ? const Color(0xFF10161D) : color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              accent == null ? const Color(0xFF29313D) : color.withAlpha(120),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _openOrderCard(BingxFuturesOpenOrder order) {
    final isManaged = _managedOrderIds.contains(order.orderId);
    final badgeColor =
        isManaged ? const Color(0xFF75D98A) : const Color(0xFFFFC76A);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1322),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D3550), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.symbol} · ${order.side} · ${order.orderType}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE6EBFF),
                  ),
                ),
              ),
              _statusChip(
                isManaged ? 'Drone' : 'Exchange only',
                accent: badgeColor,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'id ${order.orderId}',
            style: const TextStyle(
              color: Color(0xFF9FAAC0),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'status ${order.status.isEmpty ? "-" : order.status} · '
            'price ${order.priceDecimal ?? "-"} · '
            'trigger ${order.triggerPriceDecimal ?? "-"} · '
            'qty ${order.quantityDecimal ?? "-"}',
            style: const TextStyle(color: Color(0xFFC4CCE0)),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'created ${_formatOrderTime(order.createdAtMs)}',
                  style: const TextStyle(color: Color(0xFF8D97AE)),
                ),
              ),
              TextButton.icon(
                onPressed:
                    _cancelingOrder ? null : () => _cancelOrder(order: order),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF97A3B5), height: 1.35),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Color _signalBucketColor(String bucket) {
    return switch (bucket) {
      'ready' => Colors.green,
      'near' => Colors.amber,
      'blocked' => Colors.orange,
      'no_signal' => const Color(0xFF97A3B5),
      _ => Colors.redAccent,
    };
  }

  String _signalBucketLabel(String bucket) {
    return switch (bucket) {
      'ready' => 'READY',
      'near' => 'NEAR',
      'blocked' => 'BLOCKED',
      'no_signal' => 'NO SIGNAL',
      _ => 'ERROR',
    };
  }

  Widget _signalRankList() {
    if (_signalRankEntries.isEmpty) {
      return const Text(
        'No scan yet. Host computes live summaries; plugin ranks signals.',
        style: TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
      );
    }
    final top = _signalRankEntries.first;
    if (!_signalRankExpanded) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _signalRankExpanded = true),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F141C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF263343)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: _signalBucketColor(top.bucket),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Top ${top.symbol} · ${_signalBucketLabel(top.bucket)} · score ${top.score}',
                  style: const TextStyle(
                    color: Color(0xFFCAD2E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                'Show',
                style: TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in _signalRankEntries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF263343)),
            ),
            child: ListTile(
              dense: true,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.symbol,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _signalBucketColor(
                        entry.bucket,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _signalBucketLabel(entry.bucket),
                      style: TextStyle(
                        color: _signalBucketColor(entry.bucket),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                'score ${entry.score} · side ${entry.side ?? "-"} · '
                'zone ${entry.zoneLowDecimal ?? "-"}-${entry.zoneHighDecimal ?? "-"} · '
                'gate ${entry.trendGateCode}'
                '${entry.failedReasonCodes.isEmpty ? "" : " · failed ${entry.failedReasonCodes.join(",")}"}',
                style: const TextStyle(color: Color(0xFF97A3B5)),
              ),
              onTap: () => _applySignalRankEntry(entry),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExecutableIntent =
        _lastIntentResponse?.status == PluginHostApiStatus.executed &&
        _lastIntentResponse?.result != null;
    final selectedSymbol = _symbolController.text.trim().toUpperCase();
    final mandateSelectionNotice = tradingMandateSelectionNotice(
      mandate: _tradingMandate,
      droneEnabled: _droneEnabled,
      selectedSymbol: selectedSymbol,
      testOrder: _useTestOrderEndpoint,
      nowUtc: DateTime.now().toUtc(),
    );
    final tradingControlSubtitle =
        !_tradingControlLoaded || _savingTradingControl
            ? 'Loading Capsule trading control.'
            : mandateSelectionNotice ??
                (_droneEnabled
                    ? 'Strategy can prepare and execute orders.'
                    : 'Paused. New strategy runs are blocked.');
    final preparedSymbol =
        _lastIntentResponse?.result?['symbol']?.toString().trim().toUpperCase();
    final exactOrderMandateMatches =
        hasExecutableIntent &&
        preparedSymbol != null &&
        tradingMandateMatchesSelection(
          mandate: _tradingMandate,
          droneEnabled: _droneEnabled,
          selectedSymbol: preparedSymbol,
          testOrder: _useTestOrderEndpoint,
          nowUtc: DateTime.now().toUtc(),
        );
    final canBroadcast = hasExecutableIntent;
    final shortIntentHash =
        _lastIntentResponse?.result?['intent_hash_hex']?.toString() ?? '';
    final intentHashLabel =
        shortIntentHash.isEmpty
            ? 'none'
            : (shortIntentHash.length > 12
                ? '${shortIntentHash.substring(0, 12)}..'
                : shortIntentHash);

    return Scaffold(
      appBar: AppBar(title: const Text('Trading Drone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            title: 'Intent Builder',
            subtitle:
                'Deterministic futures intent for plugin host and broadcast.',
            children: [
              const Text(
                'Playbook · Short Breakdown v1',
                style: TextStyle(
                  color: Color(0xFF97A3B5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final symbol in _shortBreakdownSymbols)
                    ActionChip(
                      label: Text(symbol),
                      onPressed:
                          _runningIntent
                              ? null
                              : () =>
                                  _applyShortBreakdownPlaybook(symbol: symbol),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _TradingPeerScopeCard(
                peerHex: _peerController.text,
                onClear:
                    _peerController.text.trim().isEmpty
                        ? null
                        : () {
                          setState(_peerController.clear);
                        },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 320,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _symbolController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Perp Symbol',
                              hintText: 'BTC-USDT',
                              filled: true,
                              fillColor: const Color(0xFF0F141C),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (value) {
                              final symbol = value.trim().toUpperCase();
                              if (symbol.isEmpty) return;
                              setState(() {
                                _symbolController.text = symbol;
                                _displayedZoneDecision = null;
                                _lastIntentResponse = null;
                                _lastPreparedLiveDecision = null;
                                _intentBlockingMessage = null;
                              });
                              unawaited(
                                _maybeRetargetOpenOrdersTracking(
                                  symbol: symbol,
                                  source: 'manual_input',
                                  force: true,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _runningIntent
                                  ? null
                                  : _loadingPerpSymbols
                                  ? null
                                  : _openPerpetualSymbolPicker,
                          icon:
                              _loadingPerpSymbols
                                  ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.tune_rounded),
                          label: const Text('Perp'),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed:
                              _loadingPerpSymbols
                                  ? null
                                  : () => _loadPerpetualSymbols(silent: false),
                          tooltip: 'Refresh symbols',
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _maxNotionalUsdtController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Max Notional (USDT)',
                        hintText: '100',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _availablePerpSymbols.isEmpty
                    ? 'Perp symbols: not loaded (manual input available)'
                    : 'Perp symbols loaded: ${_availablePerpSymbols.length}',
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _signalScanScope,
                    dropdownColor: const Color(0xFF121821),
                    items: const [
                      DropdownMenuItem<String>(
                        value: _signalScanScopeCore,
                        child: Text('Core Watchlist'),
                      ),
                      DropdownMenuItem<String>(
                        value: _signalScanScopeAllPerps,
                        child: Text('All Perps'),
                      ),
                    ],
                    onChanged:
                        _scanningSignals
                            ? null
                            : (value) {
                              if (value == null) return;
                              setState(() {
                                _signalScanScope = value;
                                _signalRankEntries =
                                    const <BingxFuturesSignalRankEntry>[];
                                _signalScanCompletedAtUtc = null;
                                _signalDecisionByHash =
                                    const <
                                      String,
                                      BingxFuturesLiveDecisionResult
                                    >{};
                                _signalRankExpanded = true;
                              });
                            },
                  ),
                  FilledButton.icon(
                    onPressed:
                        _runningIntent || _scanningSignals
                            ? null
                            : _scanSignalWatchlist,
                    icon:
                        _scanningSignals
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Icon(
                              _signalRankEntries.isEmpty
                                  ? Icons.radar_rounded
                                  : Icons.refresh_rounded,
                            ),
                    label: Text(
                      tradingSignalScanActionLabel(scanning: _scanningSignals),
                    ),
                  ),
                  Text(
                    _signalRankEntries.isEmpty
                        ? '${_signalScanScopeLabel()} · not ranked'
                        : 'Ranked ${_signalRankEntries.length}',
                    style: const TextStyle(
                      color: Color(0xFF97A3B5),
                      fontSize: 12,
                    ),
                  ),
                  if (_signalRankEntries.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _signalRankExpanded = !_signalRankExpanded;
                        });
                      },
                      icon: Icon(
                        _signalRankExpanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        size: 16,
                      ),
                      label: Text(_signalRankExpanded ? 'Collapse' : 'Show'),
                    ),
                  ],
                ],
              ),
              if (_signalScanCompletedAtUtc != null) ...[
                const SizedBox(height: 8),
                Text(
                  tradingSignalSnapshotLabel(_signalScanCompletedAtUtc!),
                  style: const TextStyle(
                    color: Color(0xFF97A3B5),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _signalRankList(),
              const SizedBox(height: 8),
              Text(
                'Estimated order quantity: ${_quantityController.text}',
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              SwitchListTile.adaptive(
                value: _droneEnabled,
                onChanged:
                    _runningIntent ||
                            !_tradingControlLoaded ||
                            _savingTradingControl
                        ? null
                        : (value) {
                          unawaited(_changeDroneEnabled(value));
                        },
                title: const Text('Drone enabled'),
                subtitle: Text(
                  tradingControlSubtitle,
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (mandateSelectionNotice != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed:
                        _runningIntent || _savingTradingControl
                            ? null
                            : () => unawaited(_changeDroneEnabled(true)),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text('Re-authorize $selectedSymbol'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Auto risk',
                    style: TextStyle(
                      color: Color(0xFF97A3B5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DropdownButton<double>(
                    value: _stopLossPercent,
                    dropdownColor: const Color(0xFF121821),
                    items: _stopLossPercentOptions
                        .map(
                          (value) => DropdownMenuItem<double>(
                            value: value,
                            child: Text('SL ${value.toStringAsFixed(0)}%'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged:
                        _runningIntent
                            ? null
                            : (value) {
                              if (value == null) return;
                              setState(() {
                                _stopLossPercent = value;
                              });
                              unawaited(
                                _persistOpenOrdersTrackingState(
                                  source: 'risk_settings_sl_change',
                                ),
                              );
                            },
                  ),
                  DropdownButton<double>(
                    value: _takeProfitRiskReward,
                    dropdownColor: const Color(0xFF121821),
                    items: _takeProfitRiskRewardOptions
                        .map(
                          (value) => DropdownMenuItem<double>(
                            value: value,
                            child: Text(
                              'TP ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}R',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged:
                        _runningIntent
                            ? null
                            : (value) {
                              if (value == null) return;
                              setState(() {
                                _takeProfitRiskReward = value;
                              });
                              unawaited(
                                _persistOpenOrdersTrackingState(
                                  source: 'risk_settings_rr_change',
                                ),
                              );
                            },
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent || _fittingMaxNotional
                            ? null
                            : _autoFitMaxNotionalToRisk,
                    icon:
                        _fittingMaxNotional
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.auto_fix_high_rounded),
                    label: Text(
                      _fittingMaxNotional ? 'Fitting' : 'Auto-fit Notional',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent ||
                                _savingTradingControl ||
                                _exportingRemoteMandate ||
                                !_droneEnabled ||
                                !exactOrderMandateMatches
                            ? null
                            : _exportSignedRemoteExactOrder,
                    icon: const Icon(Icons.outbox_outlined),
                    label: const Text('Export Exact Order'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _zoneLowController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Pending Zone Low',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _zoneHighController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Pending Zone High',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _displayedZoneDecision == null
                    ? 'Pending liquidity zone — not current market price. Run Intent revalidates it.'
                    : formatBingxFuturesZoneEvidence(_displayedZoneDecision!),
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _runningIntent ? null : _choosePeer,
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Choose Trusted Capsule'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _runningIntent ||
                                !_tradingControlLoaded ||
                                _savingTradingControl
                            ? null
                            : _runIntent,
                    icon:
                        _runningIntent
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.bolt_rounded),
                    label: Text(
                      _runningIntent ? _intentProgressLabel : 'Run Intent',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _runningIntent ||
                                !_tradingControlLoaded ||
                                _savingTradingControl
                            ? null
                            : () =>
                                unawaited(_changeDroneEnabled(!_droneEnabled)),
                    icon: Icon(
                      _droneEnabled
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(_droneEnabled ? 'Emergency Pause' : 'Resume'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _runningIntent ||
                                _savingTradingControl ||
                                _exportingRemoteMandate ||
                                !_droneEnabled
                            ? null
                            : _exportSignedRemoteMandate,
                    icon:
                        _exportingRemoteMandate
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.verified_user_outlined),
                    label: Text(
                      _exportingRemoteMandate
                          ? 'Exporting mandate'
                          : 'Export Remote Mandate',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _runningIntent || _broadcastingSignal || !canBroadcast
                            ? null
                            : _broadcastLastIntent,
                    icon:
                        _broadcastingSignal
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.campaign_outlined),
                    label: Text(
                      _broadcastingSignal ? 'Broadcasting' : 'Broadcast',
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child:
                    _runningIntent
                        ? Container(
                          key: const ValueKey<String>('intent-progress'),
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF172033),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFF8DC2FF,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _intentProgressLabel,
                                style: const TextStyle(
                                  color: Color(0xFFC9DEFF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const LinearProgressIndicator(minHeight: 3),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(
                          key: ValueKey<String>('intent-idle'),
                        ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    'Status: ${_lastIntentResponse?.status.name ?? "idle"}',
                  ),
                  _statusChip('Intent: $intentHashLabel'),
                  if (_lastIntentResponse?.errorCode != null &&
                      _lastIntentResponse!.errorCode!.trim().isNotEmpty)
                    _statusChip(
                      'Code: ${_lastIntentResponse!.errorCode!.trim()}',
                      accent: const Color(0xFFFF8A7A),
                    ),
                ],
              ),
              if (_intentBlockingMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2418),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB86B35)),
                  ),
                  child: Text(
                    _intentBlockingMessage!,
                    style: const TextStyle(color: Color(0xFFFFC58F)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _panel(
            title: 'Exchange Execution',
            subtitle:
                'Credentialed execution queue with retry + idempotency cache.',
            children: [
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-key-field'),
                controller: _apiKeyController,
                label: 'BingX API Key',
                showTooltip: 'Show API key',
                hideTooltip: 'Hide API key',
              ),
              const SizedBox(height: 10),
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-secret-field'),
                controller: _apiSecretController,
                label: 'BingX API Secret',
                showTooltip: 'Show secret',
                hideTooltip: 'Hide secret',
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                value: _useTestOrderEndpoint,
                onChanged:
                    _executing
                        ? null
                        : (value) {
                          setState(() {
                            _useTestOrderEndpoint = value;
                            _lastIntentResponse = null;
                            _lastPreparedLiveDecision = null;
                            _intentBlockingMessage = null;
                          });
                        },
                title: Text(
                  _useTestOrderEndpoint
                      ? 'Simulation endpoint (no exchange order)'
                      : 'Live endpoint (creates exchange order)',
                ),
                subtitle: Text(
                  _useTestOrderEndpoint
                      ? 'Validates one exact request without placing it on BingX.'
                      : 'Places the exact authorized order on BingX.',
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _executing || !hasExecutableIntent
                            ? null
                            : _executeLastIntent,
                    icon:
                        _executing
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.send_rounded),
                    label: Text(
                      _executing
                          ? 'Sending to BingX'
                          : !hasExecutableIntent
                          ? 'Run Intent to Enable Order'
                          : _useTestOrderEndpoint
                          ? 'Send Test Order to BingX'
                          : 'Send Live Order to BingX',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _savingCredentials ? null : _saveCredentials,
                    icon:
                        _savingCredentials
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.key_rounded),
                    label: Text(
                      _savingCredentials ? 'Saving' : 'Save Credentials',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _fetchingOpenOrders ? null : () => _fetchOpenOrders(),
                    icon:
                        _fetchingOpenOrders
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.list_alt_rounded),
                    label: Text(
                      _fetchingOpenOrders ? 'Fetching Orders' : 'Open Orders',
                    ),
                  ),
                ],
              ),
              if (_isTrackingOpenOrders) ...[
                const SizedBox(height: 8),
                Text(
                  'Managed order tracking is active and stops automatically '
                  'when the order closes.',
                  style: const TextStyle(
                    color: Color(0xFF97A3B5),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _cancelOrderIdController,
                      decoration: InputDecoration(
                        labelText: 'Order ID to cancel',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _cancelingOrder ? null : _cancelOrder,
                    icon:
                        _cancelingOrder
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.cancel_presentation_rounded),
                    label: Text(_cancelingOrder ? 'Canceling' : 'Cancel Order'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_lastExecution != null)
                    _statusChip(
                      _lastExecution!.isSuccess
                          ? 'Order OK · ${_lastExecution!.exchangeCode}'
                          : 'Order FAIL · ${_lastExecution!.exchangeCode}',
                      accent:
                          _lastExecution!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                  if (_lastExecution != null)
                    _statusChip('HTTP ${_lastExecution!.httpStatusCode}'),
                  if (_lastExecutionAttempts > 0)
                    _statusChip('Attempts $_lastExecutionAttempts'),
                  if (_lastExecutionFromCache)
                    _statusChip(
                      'Idempotent cache',
                      accent: const Color(0xFFFFC76A),
                    ),
                  if (_lastOpenOrdersRead != null)
                    _statusChip(
                      'Open: ${_openOrders.length} · Drone: $_managedOpenOrderCount '
                      '(${_lastOpenOrdersRead!.exchangeCode})',
                      accent:
                          _lastOpenOrdersRead!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                  if (_isTrackingOpenOrders)
                    _statusChip(
                      'Tracking ${_trackedOrdersSymbol ?? "-"}'
                      '${_trackedOrderId == null ? '' : ' · id ${_trackedOrderId!}'}',
                      accent: const Color(0xFF8DC2FF),
                    ),
                  if (_lastCancelOrder != null)
                    _statusChip(
                      'Cancel: ${_lastCancelOrder!.exchangeCode}',
                      accent:
                          _lastCancelOrder!.isSuccess
                              ? const Color(0xFF75D98A)
                              : const Color(0xFFFF8A7A),
                    ),
                ],
              ),
              if (_openOrders.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Open Exchange Orders',
                    style: TextStyle(
                      color: Color(0xFF9FAAC0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final order in _openOrders.take(12)) _openOrderCard(order),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _panel(
            title: 'Signal Inbox',
            subtitle: 'Broadcasted intents from trusted consensus peers.',
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _refreshingSignals
                            ? null
                            : () => _refreshSignalInbox(silentWhenEmpty: false),
                    icon:
                        _refreshingSignals
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _refreshingSignals ? 'Refreshing' : 'Fetch Signals',
                    ),
                  ),
                  _statusChip('Inbox ${_signalInbox.length}'),
                ],
              ),
              if (_signalInbox.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'No trade signals yet.',
                    style: TextStyle(color: Color(0xFF97A3B5)),
                  ),
                )
              else
                ..._signalInbox.reversed
                    .take(10)
                    .map(
                      (signal) => Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D131C),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF263244)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${signal.symbol} · ${signal.side.toUpperCase()} · ${signal.orderType.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty ${signal.quantityDecimal} · mode ${signal.entryMode} · from ${PeerIdentityFormat.capsuleLabelFromRootHex(signal.fromHex)}',
                              style: const TextStyle(
                                color: Color(0xFF9AA7BA),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: () => _repeatSignalAsDraft(signal),
                                icon: const Icon(Icons.copy_all_rounded),
                                label: const Text('Repeat as draft'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
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
