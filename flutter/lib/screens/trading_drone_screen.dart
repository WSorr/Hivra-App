import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/bingx_futures_order_tracking_models.dart';
import '../models/capsule_chat_models.dart';
import '../models/plugin_contract_ids.dart';
import '../services/bingx_futures_live_decision_service.dart';
import '../services/bingx_futures_intent_use_case_service.dart';
import '../services/bingx_futures_live_strategy_use_case_service.dart';
import '../services/bingx_futures_exchange_service.dart';
import '../services/bingx_futures_exchange_execution_use_case_service.dart';
import '../services/bingx_futures_order_sizing_service.dart';
import '../services/bingx_futures_order_replacement_service.dart';
import '../services/bingx_futures_risk_governor_service.dart';
import '../services/bingx_futures_signal_rank_use_case_service.dart';
import '../services/plugin_host_api_service.dart';
import '../services/app_runtime_service.dart';
import '../services/trading_drone_module_service.dart';

class TradingDroneScreen extends StatefulWidget {
  const TradingDroneScreen({super.key});

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

  late final TradingDroneModule _module;

  final TextEditingController _peerController = TextEditingController();
  final TextEditingController _symbolController =
      TextEditingController(text: 'BTC-USDT');
  final TextEditingController _maxNotionalUsdtController =
      TextEditingController(text: '100');
  final TextEditingController _quantityController =
      TextEditingController(text: '0.01');
  final TextEditingController _limitPriceController = TextEditingController();
  final TextEditingController _zoneLowController = TextEditingController();
  final TextEditingController _zoneHighController = TextEditingController();
  final TextEditingController _triggerPriceController = TextEditingController();
  final TextEditingController _stopLossController = TextEditingController();
  final TextEditingController _takeProfitController = TextEditingController();
  final TextEditingController _strategyTagController =
      TextEditingController(text: 'demo');
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiSecretController = TextEditingController();
  final TextEditingController _cancelOrderIdController =
      TextEditingController();

  bool _runningIntent = false;
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
  bool _obscureApiSecret = true;
  bool _droneEnabled = true;
  double _stopLossPercent = _defaultStopLossPercent;
  double _takeProfitRiskReward = _defaultTakeProfitRiskReward;

  String _side = 'buy';
  String _orderType = 'limit';
  String _timeInForce = 'GTC';
  String _entryMode = 'direct';
  String _zoneSide = 'buyside';
  String _zonePriceRule = 'zone_mid';

  PluginHostApiResponse? _lastIntentResponse;
  BingxFuturesOrderExecutionResult? _lastExecution;
  BingxFuturesOpenOrdersResult? _lastOpenOrdersRead;
  BingxFuturesCancelOrderResult? _lastCancelOrder;
  List<BingxFuturesOpenOrder> _openOrders = const <BingxFuturesOpenOrder>[];
  final Set<String> _managedOrderIds = <String>{};
  final Map<String, String> _managedOrderSymbols = <String, String>{};
  final Map<String, BingxManagedOrderProvenance> _managedOrderProvenance =
      <String, BingxManagedOrderProvenance>{};
  int _managedOrderLifecycleRevision = 0;
  int _lastOpenOrdersTotalCount = 0;
  Timer? _openOrdersPollTimer;
  String? _trackedOrdersSymbol;
  String? _trackedOrderId;
  int _lastExecutionAttempts = 0;
  bool _lastExecutionFromCache = false;
  List<CapsuleTradeSignalInboxMessage> _signalInbox =
      const <CapsuleTradeSignalInboxMessage>[];
  List<String> _availablePerpSymbols = const <String>[];
  List<BingxFuturesSignalRankEntry> _signalRankEntries =
      const <BingxFuturesSignalRankEntry>[];

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
    _module = TradingDroneModuleService(
      runtime: AppRuntimeService(),
    ).build();
    _loadCredentials();
    unawaited(_restoreOpenOrdersTrackingState());
    _loadPerpetualSymbols(silent: true);
    _signalInbox = _module.chatDelivery.loadCachedTradeSignals();
    _refreshSignalInbox(silentWhenEmpty: true);
  }

  @override
  void dispose() {
    _openOrdersPollTimer?.cancel();
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

  bool get _isTrackingOpenOrders => _openOrdersPollTimer != null;

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
  }) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    final normalizedOrderId = orderId?.trim();
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
      unawaited(
        _fetchOpenOrders(
          silent: true,
          symbolOverride: _trackedOrdersSymbol,
        ),
      );
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
    await _fetchOpenOrders(
      silent: true,
      symbolOverride: normalizedSymbol,
    );
  }

  Future<void> _persistOpenOrdersTrackingState({
    required String source,
  }) async {
    try {
      final state = BingxFuturesOrderTrackingState(
        trackedSymbol: _trackedOrdersSymbol,
        trackedOrderId: _trackedOrderId,
        managedOrderIds: _managedOrderIds.toList(growable: false),
        managedOrderSymbols:
            Map<String, String>.unmodifiable(_managedOrderSymbols),
        managedOrderProvenance:
            Map<String, BingxManagedOrderProvenance>.unmodifiable(
          _managedOrderProvenance,
        ),
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
      await _fetchOpenOrders(
        silent: true,
        symbolOverride: trackedSymbol,
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.exchange.tracking.restore.error',
        '$error',
      );
    }
  }

  Future<void> _showSnack(String message, {int seconds = 2}) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: seconds),
      ),
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

  Future<void> _loadCredentials() async {
    try {
      final credentials = await _module.credentialStore.load();
      if (!mounted || credentials == null) return;
      setState(() {
        _apiKeyController.text = credentials.apiKey;
        _apiSecretController.text = credentials.apiSecret;
      });
      await _module.uiLog.log(
        'bingx.credentials.load',
        'ok keyLen=${credentials.apiKey.length} secretLen=${credentials.apiSecret.length}',
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.credentials.load.error',
        '$error',
      );
      await _showSnack('Failed to load BingX credentials: $error', seconds: 3);
    }
  }

  Future<String?> _selectConsensusPeer({
    required String hint,
  }) async {
    final checks = _module.manualChecks.loadChecks().toList()
      ..sort(
        (a, b) => a.peerLabel.toLowerCase().compareTo(
              b.peerLabel.toLowerCase(),
            ),
      );
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
                  title: Text(check.peerLabel),
                  subtitle: Text(
                    check.peerHex,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: check.isSignable
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
            final filtered = _availablePerpSymbols.where((symbol) {
              if (query.isEmpty) return true;
              return symbol.toLowerCase().contains(query.toLowerCase());
            }).toList(growable: false);
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
                      child: filtered.isEmpty
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
                                  onTap: () =>
                                      Navigator.of(sheetContext).pop(symbol),
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
    });
    await _module.uiLog
        .log('bingx.symbols.select', 'symbol=$selected source=picker');
    await _maybeRetargetOpenOrdersTracking(
      symbol: selected,
      source: 'picker',
      force: true,
    );
  }

  Future<void> _scanSignalWatchlist() async {
    if (_scanningSignals) return;
    if (_signalRankEntries.isNotEmpty && _signalRankExpanded) {
      setState(() {
        _signalRankExpanded = false;
      });
      return;
    }
    final currentSymbol = _symbolController.text.trim().toUpperCase();
    final peerHex = _peerController.text.trim().toLowerCase();
    final symbols = <String>{
      ..._shortBreakdownSymbols,
      if (currentSymbol.isNotEmpty) currentSymbol,
    }.toList()
      ..sort();
    if (symbols.isEmpty) {
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
          BingxFuturesSignalRankCandidate(
            symbol: symbol,
            decision: decision,
          ),
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
        _signalRankExpanded = true;
      });
      final top = ranked.entries.isEmpty ? null : ranked.entries.first;
      await _module.uiLog.log(
        'bingx.signal.rank',
        'symbols=${symbols.length} candidates=${candidates.length} '
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

  Future<void> _applySignalRankEntry(BingxFuturesSignalRankEntry entry) async {
    if (!mounted) return;
    setState(() {
      _symbolController.text = entry.symbol;
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

  Future<void> _applyShortBreakdownPlaybook({
    required String symbol,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) return;
    if (mounted) {
      setState(() {
        _symbolController.text = normalizedSymbol;
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
        BingxFuturesApiCredentials(
          apiKey: apiKey,
          apiSecret: apiSecret,
        ),
      );
      await _module.uiLog.log(
        'bingx.credentials.save',
        'ok keyLen=${apiKey.length} secretLen=${apiSecret.length}',
      );
      await _showSnack('BingX credentials saved for active capsule');
    } catch (error) {
      await _module.uiLog.log(
        'bingx.credentials.save.error',
        '$error',
      );
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
    return BingxFuturesApiCredentials(
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
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
    final takeProfit = buy
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
    final zone = live.zoneLowDecimal != null && live.zoneHighDecimal != null
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

    final failed = live.reasons
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
    final credentials = _resolveCredentials();
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
      final fallbackEquity =
          double.tryParse(_maxNotionalUsdtController.text.trim()) ?? 100.0;
      final riskInput = await _module.exchangeRiskInput.read(
        exchangeService: _module.exchangeService,
        credentials: credentials,
        fallbackEquityQuote: fallbackEquity,
      );
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
          final minimumNotional =
              _toNum(sizing.minimumNotionalQuoteDecimal ?? '');
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
          final codes = check.blockingFacts
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
    final consensus = forceConsensusSignable
        ? (isSignable: true, blockingCodes: const <String>[])
        : _consensusDecisionContext(peerHex);
    final result = await _module.liveStrategyUseCase.execute(
      BingxFuturesLiveStrategyCommand(
        symbol: symbol,
        credentials: _resolveCredentials(),
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
    if (!_droneEnabled) {
      await _showSnack('Drone is paused. Resume before running strategy.');
      return;
    }
    final peerHex = _peerController.text.trim().toLowerCase();
    final symbol = _symbolController.text.trim();
    var strategyTag = _strategyTagController.text.trim();
    var triggerPriceDecimal = _triggerPriceController.text.trim();
    var stopLossDecimal = _stopLossController.text.trim();
    var takeProfitDecimal = _takeProfitController.text.trim();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final clientOrderId = 'ui-ord-${DateTime.now().microsecondsSinceEpoch}';
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return;
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

    final isZonePending = _entryMode == 'zone_pending';
    BingxFuturesLiveDecisionResult? liveDecision;

    if (_orderType == 'limit') {
      liveDecision =
          await _computeLiveDecision(symbol: symbol, peerHex: peerHex);
      if (liveDecision == null) return;
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
        await _module.uiLog.log(
          'bingx.strategy.live_decision.blocked',
          'symbol=$symbol message=$message '
              'decision=${live.decision.name} side=${live.side ?? "-"} '
              'zone=${live.zoneLowDecimal ?? "-"}-${live.zoneHighDecimal ?? "-"} '
              'trend_gate=${live.trendGateCode} '
              'live_hash=${live.liveDecisionHashHex.substring(0, 12)}',
        );
        await _showSnack(message, seconds: 4);
        return;
      }
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
    final riskReady = await _applyRiskBudgetQuantity(symbol: symbol);
    if (!riskReady) {
      return;
    }
    final quantityDecimal = _quantityController.text.trim();

    final zoneLowDecimal = _zoneLowController.text.trim();
    final zoneHighDecimal = _zoneHighController.text.trim();
    String? limitPriceDecimal = _orderType == 'limit' && !isZonePending
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

    setState(() {
      _runningIntent = true;
    });
    final stopwatch = Stopwatch()..start();
    PluginHostApiStatus? finalStatus;
    try {
      await _module.uiLog.log(
        'bingx.intent.request',
        'peer=${peerHex.isEmpty ? "empty" : "${peerHex.substring(0, 8)}.."} symbol=$symbol side=$_side type=$_orderType entry=$_entryMode qty=$quantityDecimal',
      );

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
      if (!mounted) return;
      setState(() {
        _lastIntentResponse = response;
      });
      finalStatus = response.status;
      final decisionEnvelope = useCaseResult.decisionEnvelope;
      await _module.uiLog.log(
        'bingx.intent.response',
        'status=${response.status.name} '
            'elapsedMs=${stopwatch.elapsedMilliseconds} '
            'source=${response.executionSource}',
      );
      if (response.status == PluginHostApiStatus.rejected) {
        final code = response.errorCode?.trim().isNotEmpty == true
            ? response.errorCode!.trim()
            : 'none';
        final msg = response.errorMessage?.trim().isNotEmpty == true
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
          final reason = response.blockingFacts.isEmpty
              ? 'Consensus guard blocked execution.'
              : response.blockingFacts.first.label;
          await _showSnack(reason);
          break;
        case PluginHostApiStatus.rejected:
          final message = _resolveIntentRejectedMessage(response);
          await _showSnack(message, seconds: 4);
          break;
      }
    } on TimeoutException {
      await _module.uiLog.log(
        'bingx.intent.timeout',
        'elapsedMs=${stopwatch.elapsedMilliseconds} timeoutMs=${_hostIntentTimeout.inMilliseconds}',
      );
      await _showSnack(
        'Intent host timeout (${_hostIntentTimeout.inSeconds}s)',
        seconds: 3,
      );
    } catch (error) {
      await _module.uiLog.log(
        'bingx.intent.error',
        '$error elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      await _showSnack('Intent failed: $error', seconds: 3);
    } finally {
      await _module.uiLog.log(
        'bingx.intent.finally',
        'elapsedMs=${stopwatch.elapsedMilliseconds} status=${finalStatus?.name ?? "none"}',
      );
      if (mounted) {
        setState(() {
          _runningIntent = false;
        });
      }
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

    final peers = _module.manualChecks
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
      final result = await _module.chatDelivery.receiveAndFilter();
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
        final merged = byId.values.toList()
          ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
        _signalInbox =
            List<CapsuleTradeSignalInboxMessage>.unmodifiable(merged);
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
      CapsuleTradeSignalInboxMessage signal) async {
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
      _quantityController.text =
          decoded['quantity_decimal']?.toString() ?? signal.quantityDecimal;
      _side = decoded['side']?.toString() ?? signal.side;
      _orderType = decoded['order_type']?.toString() ?? signal.orderType;
      _timeInForce = decoded['time_in_force']?.toString() ?? 'GTC';
      _entryMode = decoded['entry_mode']?.toString() ?? signal.entryMode;
      _strategyTagController.text = decoded['strategy_tag']?.toString() ?? '';
      _lastIntentResponse = null;

      if (_entryMode == 'zone_pending') {
        _zoneSide = decoded['zone_side']?.toString() ??
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

    final shortSignal = signal.signalId.length <= 12
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

    final credentials = _resolveCredentials();
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
      final equityProxy =
          double.tryParse(_maxNotionalUsdtController.text.trim()) ?? 100.0;
      final useCaseResult = await _module.executionUseCase.execute(
        screen: 'trading_drone',
        rawIntentResult: result,
        credentials: credentials,
        riskPolicy: _executionRiskPolicy,
        fallbackEquityQuote: equityProxy,
        testOrder: _useTestOrderEndpoint,
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
          provenance: orderId == null || orderId.isEmpty
              ? null
              : _buildManagedOrderProvenance(
                  orderId: orderId,
                  payload: payload,
                  result: result,
                  testOrder: _useTestOrderEndpoint,
                ),
        );
        _startOpenOrdersAutoTracking(
          symbol: payload.symbol,
          orderId: queued.execution.orderId,
        );
        unawaited(
          _fetchOpenOrders(
            silent: true,
            symbolOverride: payload.symbol,
          ),
        );
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
    final credentials = _resolveCredentials();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return null;
    }
    final equityProxy =
        double.tryParse(_maxNotionalUsdtController.text.trim()) ?? 100.0;
    final evaluation = await _module.executionUseCase.evaluateRisk(
      payload: payload,
      rawIntentResult: rawIntentResult,
      credentials: credentials,
      riskPolicy: _executionRiskPolicy,
      fallbackEquityQuote: equityProxy,
    );
    for (final diagnostic in evaluation.diagnostics) {
      await _module.uiLog.log('bingx.exchange.risk_detail', diagnostic);
    }
    if (evaluation.decision == null) {
      await _module.uiLog.log(
        'bingx.exchange.risk_error',
        evaluation.errorCode ?? 'risk_unavailable',
      );
      await _showSnack(
        evaluation.errorMessage ?? 'Risk check unavailable',
      );
    }
    return evaluation.decision;
  }

  Future<void> _fetchOpenOrders({
    bool silent = false,
    String? symbolOverride,
  }) async {
    if (_fetchingOpenOrders) return;
    final credentials = _resolveCredentials();
    if (credentials == null) {
      if (!silent) {
        await _showSnack('Save BingX API credentials first');
      }
      return;
    }
    final symbol = (symbolOverride ?? _symbolController.text).trim();

    setState(() {
      _fetchingOpenOrders = true;
    });
    try {
      final result = await _module.exchangeService.getOpenOrders(
        credentials: credentials,
        symbol: symbol.isEmpty ? null : symbol,
      );
      final message =
          result.exchangeMessage.replaceAll('\n', ' ').replaceAll('\r', ' ');
      await _module.uiLog.log(
        'bingx.exchange.open_orders',
        'symbol=${result.symbol} success=${result.isSuccess} '
            'http=${result.httpStatusCode} code=${result.exchangeCode} '
            'count=${result.orders.length} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      final allOrders = result.orders;
      final triggerOrders = allOrders
          .where((order) => _isDroneTriggerOrder(order.orderType))
          .toList(growable: false);
      for (final order in triggerOrders) {
        if (_managedOrderIds.contains(order.orderId)) {
          _managedOrderSymbols[order.orderId] = order.symbol.toUpperCase();
        }
      }
      final managedOrders = triggerOrders.where((order) {
        if (!_managedOrderIds.contains(order.orderId)) {
          return false;
        }
        final trackedSymbol =
            _managedOrderSymbols[order.orderId]?.toUpperCase();
        if (trackedSymbol == null || trackedSymbol.isEmpty) {
          return true;
        }
        return trackedSymbol == result.symbol.toUpperCase();
      }).toList(growable: false);
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
        _lastOpenOrdersTotalCount = triggerOrders.length;
        if (result.isSuccess) {
          _openOrders = triggerOrders
              .where((order) => _managedOrderIds.contains(order.orderId))
              .toList(growable: false);
        }
        if (result.isSuccess && _openOrders.isNotEmpty) {
          _cancelOrderIdController.text = _openOrders.first.orderId;
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
          final trackedStillOpen =
              triggerOrders.any((order) => order.orderId == trackedOrderId);
          await _module.uiLog.log(
            'bingx.exchange.tracking.check',
            'symbol=${result.symbol} orderId=$trackedOrderId '
                'open=${trackedStillOpen ? "yes" : "no"} '
                'managedCount=${managedOrders.length} totalCount=${triggerOrders.length}',
          );
          if (!trackedStillOpen) {
            _managedOrderIds.remove(trackedOrderId);
            _managedOrderSymbols.remove(trackedOrderId);
            _managedOrderProvenance.remove(trackedOrderId);
            _managedOrderLifecycleRevision += 1;
            if (triggerOrders.isNotEmpty) {
              final nextTrackedOrderId = triggerOrders.first.orderId;
              _trackedOrderId = nextTrackedOrderId;
              _cancelOrderIdController.text = nextTrackedOrderId;
              await _persistOpenOrdersTrackingState(
                source: 'tracked_order_closed_rotate',
              );
              await _module.uiLog.log(
                'bingx.exchange.tracking.rotate',
                'symbol=${result.symbol} previous=$trackedOrderId next=$nextTrackedOrderId '
                    'managedCount=${triggerOrders.length}',
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
              ? 'Drone trigger orders: ${triggerOrders.length}'
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

    final runtime = await _module.orderReplacement.execute(
      provenance: provenance,
      liveDecision: liveDecision,
      cancellationReasonCode: cancellationReasonCode,
      cycleAtUtc: cycleAtUtc,
      prepareIntent: (hostArgs) {
        return _module.pluginHostApi
            .executeWithRuntimeHook(
              PluginHostApiRequest(
                schemaVersion: PluginHostApiService.schemaVersion,
                pluginId: bingxFuturesTradingPluginId,
                method: placeBingxFuturesOrderIntentMethod,
                args: hostArgs,
              ),
            )
            .timeout(_hostIntentTimeout);
      },
      evaluateRisk: (payload, rawIntentResult) {
        return _evaluateExecutionRisk(
          payload: payload,
          rawIntentResult: rawIntentResult,
        );
      },
      executeOrder: (payload, testOrder) {
        return _module.executionQueue.enqueueOrderExecution(
          credentials: credentials,
          intent: payload,
          testOrder: testOrder,
        );
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
      ),
    );
    _startOpenOrdersAutoTracking(
      symbol: payload.symbol,
      orderId: newOrderId,
    );
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

  Future<void> _cancelOrder() async {
    if (_cancelingOrder) return;
    final credentials = _resolveCredentials();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }
    final symbol = _symbolController.text.trim();
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return;
    }
    final orderId = _cancelOrderIdController.text.trim();
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
      final message =
          result.exchangeMessage.replaceAll('\n', ' ').replaceAll('\r', ' ');
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

  bool _isDroneTriggerOrder(String orderType) {
    final normalized = orderType.trim().toUpperCase();
    return normalized.startsWith('TRIGGER');
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
        for (final entry in _signalRankEntries.take(8))
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
                      color: _signalBucketColor(entry.bucket).withValues(
                        alpha: 0.15,
                      ),
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
    final canBroadcast =
        _lastIntentResponse?.status == PluginHostApiStatus.executed;
    final shortIntentHash =
        _lastIntentResponse?.result?['intent_hash_hex']?.toString() ?? '';
    final intentHashLabel = shortIntentHash.isEmpty
        ? 'none'
        : (shortIntentHash.length > 12
            ? '${shortIntentHash.substring(0, 12)}..'
            : shortIntentHash);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trading Drone'),
      ),
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
                      onPressed: _runningIntent
                          ? null
                          : () => _applyShortBreakdownPlaybook(symbol: symbol),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _peerController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Peer hex (64 lowercase chars)',
                  hintText: 'bbbb...bbbb',
                  filled: true,
                  fillColor: const Color(0xFF0F141C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
                              _symbolController.text = symbol;
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
                          onPressed: _runningIntent
                              ? null
                              : _loadingPerpSymbols
                                  ? null
                                  : _openPerpetualSymbolPicker,
                          icon: _loadingPerpSymbols
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.tune_rounded),
                          label: const Text('Perp'),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: _loadingPerpSymbols
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
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _runningIntent || _scanningSignals
                        ? null
                        : _scanSignalWatchlist,
                    icon: _scanningSignals
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _signalRankEntries.isNotEmpty && _signalRankExpanded
                                ? Icons.unfold_less_rounded
                                : Icons.radar_rounded,
                          ),
                    label: Text(
                      _scanningSignals
                          ? 'Scanning'
                          : (_signalRankEntries.isNotEmpty &&
                                  _signalRankExpanded
                              ? 'Hide Watchlist'
                              : 'Scan Watchlist'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _signalRankEntries.isEmpty
                        ? 'Signals not ranked'
                        : 'Ranked ${_signalRankEntries.length}',
                    style: const TextStyle(
                      color: Color(0xFF97A3B5),
                      fontSize: 12,
                    ),
                  ),
                  if (_signalRankEntries.isNotEmpty) ...[
                    const SizedBox(width: 6),
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
              const SizedBox(height: 8),
              _signalRankList(),
              const SizedBox(height: 8),
              Text(
                'Estimated order quantity: ${_quantityController.text}',
                style: const TextStyle(color: Color(0xFF97A3B5), fontSize: 12),
              ),
              SwitchListTile.adaptive(
                value: _droneEnabled,
                onChanged: _runningIntent
                    ? null
                    : (value) {
                        setState(() {
                          _droneEnabled = value;
                        });
                      },
                title: const Text('Drone enabled'),
                subtitle: Text(
                  _droneEnabled
                      ? 'Strategy can prepare and execute orders.'
                      : 'Paused. New strategy runs are blocked.',
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
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
                    onChanged: _runningIntent
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
                    onChanged: _runningIntent
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
                    onPressed: _runningIntent || _fittingMaxNotional
                        ? null
                        : _autoFitMaxNotionalToRisk,
                    icon: _fittingMaxNotional
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
                        labelText: 'Zone Low',
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
                        labelText: 'Zone High',
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _runningIntent ? null : _choosePeer,
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Choose Consensus Peer'),
                  ),
                  FilledButton.icon(
                    onPressed: _runningIntent ? null : _runIntent,
                    icon: _runningIntent
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(_runningIntent ? 'Preparing' : 'Run Intent'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _runningIntent
                        ? null
                        : () {
                            setState(() {
                              _droneEnabled = !_droneEnabled;
                            });
                          },
                    icon: Icon(
                      _droneEnabled
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(_droneEnabled ? 'Emergency Pause' : 'Resume'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _runningIntent || _broadcastingSignal || !canBroadcast
                            ? null
                            : _broadcastLastIntent,
                    icon: _broadcastingSignal
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
            ],
          ),
          const SizedBox(height: 14),
          _panel(
            title: 'Exchange Execution',
            subtitle:
                'Credentialed execution queue with retry + idempotency cache.',
            children: [
              TextField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'BingX API Key',
                  filled: true,
                  fillColor: const Color(0xFF0F141C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiSecretController,
                obscureText: _obscureApiSecret,
                decoration: InputDecoration(
                  labelText: 'BingX API Secret',
                  filled: true,
                  fillColor: const Color(0xFF0F141C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureApiSecret = !_obscureApiSecret;
                      });
                    },
                    icon: Icon(
                      _obscureApiSecret
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    tooltip: _obscureApiSecret ? 'Show secret' : 'Hide secret',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                value: _useTestOrderEndpoint,
                onChanged: _executing
                    ? null
                    : (value) {
                        setState(() {
                          _useTestOrderEndpoint = value;
                        });
                      },
                title: const Text('Use test order endpoint'),
                subtitle: Text(
                  _useTestOrderEndpoint
                      ? '/openApi/swap/v2/trade/order/test'
                      : '/openApi/swap/v2/trade/order',
                  style: const TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _executing ? null : _executeLastIntent,
                    icon: _executing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _executing
                          ? 'Sending to BingX'
                          : _useTestOrderEndpoint
                              ? 'Send Test Order to BingX'
                              : 'Send Live Order to BingX',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _savingCredentials ? null : _saveCredentials,
                    icon: _savingCredentials
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.key_rounded),
                    label: Text(
                        _savingCredentials ? 'Saving' : 'Save Credentials'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _fetchingOpenOrders ? null : () => _fetchOpenOrders(),
                    icon: _fetchingOpenOrders
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
                    icon: _cancelingOrder
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_presentation_rounded),
                    label: Text(
                      _cancelingOrder ? 'Canceling' : 'Cancel Order',
                    ),
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
                      accent: _lastExecution!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastExecution != null)
                    _statusChip('HTTP ${_lastExecution!.httpStatusCode}'),
                  if (_lastExecutionAttempts > 0)
                    _statusChip('Attempts $_lastExecutionAttempts'),
                  if (_lastExecutionFromCache)
                    _statusChip('Idempotent cache',
                        accent: const Color(0xFFFFC76A)),
                  if (_lastOpenOrdersRead != null)
                    _statusChip(
                      'Drone Open: ${_openOrders.length}/$_lastOpenOrdersTotalCount (${_lastOpenOrdersRead!.exchangeCode})',
                      accent: _lastOpenOrdersRead!.isSuccess
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
                      accent: _lastCancelOrder!.isSuccess
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
                    'Managed Drone Orders',
                    style: TextStyle(
                      color: Color(0xFF9FAAC0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final order in _openOrders.take(12))
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1322),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF2D3550),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.symbol} · ${order.side} · ${order.orderType}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE6EBFF),
                          ),
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
                        Text(
                          'updated ${_formatOrderTime(order.createdAtMs)}',
                          style: const TextStyle(color: Color(0xFF8D97AE)),
                        ),
                      ],
                    ),
                  ),
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
                    onPressed: _refreshingSignals
                        ? null
                        : () => _refreshSignalInbox(silentWhenEmpty: false),
                    icon: _refreshingSignals
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
                ..._signalInbox.reversed.take(10).map(
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty ${signal.quantityDecimal} · mode ${signal.entryMode} · from ${signal.fromHex.substring(0, 8)}..',
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
