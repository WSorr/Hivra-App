import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_runtime_service.dart';
import '../services/bingx_futures_credential_store.dart';
import '../services/bingx_futures_exchange_service.dart';
import '../services/bingx_futures_observability_envelope_service.dart';
import '../services/bingx_futures_execution_queue_service.dart';
import '../services/bingx_futures_risk_governor_service.dart';
import '../services/capsule_chat_delivery_service.dart';
import '../services/manual_consensus_check_service.dart';
import '../services/plugin_host_api_service.dart';
import '../services/ui_event_log_service.dart';

class TradingDroneScreen extends StatefulWidget {
  const TradingDroneScreen({super.key});

  @override
  State<TradingDroneScreen> createState() => _TradingDroneScreenState();
}

class _TradingDroneScreenState extends State<TradingDroneScreen> {
  static const Duration _hostIntentTimeout = Duration(seconds: 20);
  static const double _zoneNearBps = 15.0;
  static const double _zoneFarBps = 35.0;
  static const String _microInterval = '5m';
  static const String _macroInterval = '1h';
  static const int _microLimit = 72;
  static const int _macroLimit = 96;
  static const int _recentMicroBars = 8;
  static const List<String> _shortBreakdownSymbols = <String>[
    'BTC-USDT',
    'ETH-USDT',
    'SOL-USDT',
    'XRP-USDT',
    'BNB-USDT',
    'DOGE-USDT',
  ];

  final PluginHostApiService _pluginHostApi =
      AppRuntimeService().buildPluginHostApiService();
  final ManualConsensusCheckService _manualChecks =
      AppRuntimeService().buildManualConsensusCheckService();
  final BingxFuturesCredentialStore _bingxCredentialStore =
      AppRuntimeService().buildBingxFuturesCredentialStore();
  final BingxFuturesExchangeService _bingxExchangeService =
      AppRuntimeService().buildBingxFuturesExchangeService();
  final BingxFuturesRiskGovernorService _riskGovernor =
      const BingxFuturesRiskGovernorService();
  final BingxFuturesObservabilityEnvelopeService _observability =
      const BingxFuturesObservabilityEnvelopeService();
  final CapsuleChatDeliveryService _chatDelivery =
      AppRuntimeService().buildCapsuleChatDeliveryService();
  final UiEventLogService _uiLog = const UiEventLogService();
  late final BingxFuturesExecutionQueueService _bingxExecutionQueue;

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
  final TextEditingController _leverageController =
      TextEditingController(text: '3');
  final TextEditingController _cancelOrderIdController = TextEditingController();

  bool _runningIntent = false;
  bool _broadcastingSignal = false;
  bool _savingCredentials = false;
  bool _readingCurrentSettings = false;
  bool _executing = false;
  bool _switchingLeverage = false;
  bool _switchingMarginType = false;
  bool _refreshingSignals = false;
  bool _fetchingOpenOrders = false;
  bool _cancelingOrder = false;
  bool _useTestOrderEndpoint = true;
  bool _obscureApiSecret = true;
  bool _droneEnabled = true;
  bool _advancedControlsEnabled = false;

  String _side = 'buy';
  String _orderType = 'limit';
  String _timeInForce = 'GTC';
  String _entryMode = 'direct';
  String _zoneSide = 'buyside';
  String _zonePriceRule = 'zone_mid';
  String _leverageSide = 'LONG';
  String _marginType = 'CROSSED';

  PluginHostApiResponse? _lastIntentResponse;
  BingxFuturesOrderExecutionResult? _lastExecution;
  BingxFuturesControlActionResult? _lastLeverageSwitch;
  BingxFuturesControlActionResult? _lastMarginSwitch;
  BingxFuturesLeverageReadResult? _lastLeverageRead;
  BingxFuturesMarginTypeReadResult? _lastMarginRead;
  BingxFuturesOpenOrdersResult? _lastOpenOrdersRead;
  BingxFuturesCancelOrderResult? _lastCancelOrder;
  List<BingxFuturesOpenOrder> _openOrders = const <BingxFuturesOpenOrder>[];
  int _lastExecutionAttempts = 0;
  bool _lastExecutionFromCache = false;
  List<CapsuleTradeSignalInboxMessage> _signalInbox =
      const <CapsuleTradeSignalInboxMessage>[];

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
    _bingxExecutionQueue = BingxFuturesExecutionQueueService(
      exchangeService: _bingxExchangeService,
    );
    _loadCredentials();
    _refreshSignalInbox(silentWhenEmpty: true);
  }

  @override
  void dispose() {
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
    _leverageController.dispose();
    _cancelOrderIdController.dispose();
    super.dispose();
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

  Future<void> _loadCredentials() async {
    try {
      final credentials = await _bingxCredentialStore.load();
      if (!mounted || credentials == null) return;
      setState(() {
        _apiKeyController.text = credentials.apiKey;
        _apiSecretController.text = credentials.apiSecret;
      });
      await _uiLog.log(
        'bingx.credentials.load',
        'ok keyLen=${credentials.apiKey.length} secretLen=${credentials.apiSecret.length}',
      );
    } catch (error) {
      await _uiLog.log(
        'bingx.credentials.load.error',
        '$error',
      );
      await _showSnack('Failed to load BingX credentials: $error', seconds: 3);
    }
  }

  Future<String?> _selectConsensusPeer({
    required String hint,
  }) async {
    final checks = _manualChecks.loadChecks().toList()
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
    await _uiLog.log(
      'bingx.playbook.apply',
      'name=short_breakdown_v1 symbol=$normalizedSymbol side=sell mode=zone_pending',
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
      await _bingxCredentialStore.save(
        BingxFuturesApiCredentials(
          apiKey: apiKey,
          apiSecret: apiSecret,
        ),
      );
      await _uiLog.log(
        'bingx.credentials.save',
        'ok keyLen=${apiKey.length} secretLen=${apiSecret.length}',
      );
      await _showSnack('BingX credentials saved for active capsule');
    } catch (error) {
      await _uiLog.log(
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

  String _formatDecimal(num value, {int scale = 8}) {
    final fixed = value.toStringAsFixed(scale);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  num _clamp(num value, num min, num max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  num? _toNum(String raw) => num.tryParse(raw.trim());

  Future<bool> _applyRiskBudgetQuantity({required String symbol}) async {
    final maxNotional = _toNum(_maxNotionalUsdtController.text);
    if (maxNotional == null || maxNotional <= 0) {
      await _showSnack('Max notional must be a positive number');
      return false;
    }

    final quote = await _bingxExchangeService.getPublicPrice(symbol: symbol);
    if (!quote.isSuccess || quote.priceDecimal == null) {
      await _showSnack(
        'Cannot compute quantity: quote unavailable (${quote.exchangeCode})',
        seconds: 3,
      );
      return false;
    }
    final mid = _toNum(quote.priceDecimal!);
    if (mid == null || mid <= 0) {
      await _showSnack('Cannot compute quantity: invalid quote price',
          seconds: 3);
      return false;
    }

    final quantity = maxNotional / mid;
    if (quantity <= 0) {
      await _showSnack('Cannot compute quantity: max notional too small');
      return false;
    }
    final quantityDecimal = _formatDecimal(quantity, scale: 6);
    if (mounted) {
      setState(() {
        _quantityController.text = quantityDecimal;
      });
    } else {
      _quantityController.text = quantityDecimal;
    }
    await _uiLog.log(
      'bingx.risk.quantity',
      'symbol=${quote.symbol} max_notional_usdt=$maxNotional mid=${quote.priceDecimal} quantity=$quantityDecimal',
    );
    return true;
  }

  num _fallbackZoneWidth(num mid) =>
      mid * ((_zoneFarBps - _zoneNearBps) / 10000.0);

  Future<void> _applyZone({
    required num zoneLow,
    required num zoneHigh,
  }) async {
    final normalizedLow = zoneLow <= zoneHigh ? zoneLow : zoneHigh;
    final normalizedHigh = zoneLow <= zoneHigh ? zoneHigh : zoneLow;
    if (normalizedLow <= 0 || normalizedHigh <= 0) {
      return;
    }
    final zoneLowDecimal = _formatDecimal(normalizedLow);
    final zoneHighDecimal = _formatDecimal(normalizedHigh);
    if (mounted) {
      setState(() {
        _zoneLowController.text = zoneLowDecimal;
        _zoneHighController.text = zoneHighDecimal;
      });
    } else {
      _zoneLowController.text = zoneLowDecimal;
      _zoneHighController.text = zoneHighDecimal;
    }
  }

  Future<bool> _computeZoneFromMarketStructure({required String symbol}) async {
    final quote = await _bingxExchangeService.getPublicPrice(symbol: symbol);
    if (!quote.isSuccess || quote.priceDecimal == null) {
      final message =
          quote.exchangeMessage.replaceAll('\n', ' ').replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.strategy.zone.error',
        'symbol=${quote.symbol} code=${quote.exchangeCode} '
            'http=${quote.httpStatusCode} endpoint=${quote.endpointPath} msg=$message',
      );
      await _showSnack(
        'Strategy failed: quote unavailable (${quote.exchangeCode})',
        seconds: 3,
      );
      return false;
    }

    final mid = _toNum(quote.priceDecimal!);
    if (mid == null || mid <= 0) {
      await _uiLog.log(
        'bingx.strategy.zone.error',
        'symbol=${quote.symbol} code=invalid_quote price=${quote.priceDecimal}',
      );
      await _showSnack('Strategy failed: invalid quote price', seconds: 3);
      return false;
    }

    final micro = await _bingxExchangeService.getPublicKlines(
      symbol: symbol,
      interval: _microInterval,
      limit: _microLimit,
    );
    final macro = await _bingxExchangeService.getPublicKlines(
      symbol: symbol,
      interval: _macroInterval,
      limit: _macroLimit,
    );

    if (!micro.isSuccess ||
        !macro.isSuccess ||
        micro.klines.length < 20 ||
        macro.klines.length < 20) {
      final nearDelta = mid * (_zoneNearBps / 10000.0);
      final farDelta = mid * (_zoneFarBps / 10000.0);
      final zoneLow = _side == 'buy' ? mid - farDelta : mid + nearDelta;
      final zoneHigh = _side == 'buy' ? mid - nearDelta : mid + farDelta;
      await _applyZone(zoneLow: zoneLow, zoneHigh: zoneHigh);
      await _uiLog.log(
        'bingx.strategy.zone',
        'symbol=${quote.symbol} side=$_side source=fallback_quote '
            'mid=${quote.priceDecimal} low=${_zoneLowController.text} high=${_zoneHighController.text} '
            'microOk=${micro.isSuccess} macroOk=${macro.isSuccess}',
      );
      return true;
    }

    final microHighs = <num>[];
    final microLows = <num>[];
    for (final candle in micro.klines) {
      final high = _toNum(candle.highDecimal);
      final low = _toNum(candle.lowDecimal);
      if (high != null) microHighs.add(high);
      if (low != null) microLows.add(low);
    }
    final macroHighs = <num>[];
    final macroLows = <num>[];
    for (final candle in macro.klines) {
      final high = _toNum(candle.highDecimal);
      final low = _toNum(candle.lowDecimal);
      if (high != null) macroHighs.add(high);
      if (low != null) macroLows.add(low);
    }
    if (microHighs.length < 20 ||
        microLows.length < 20 ||
        macroHighs.length < 20 ||
        macroLows.length < 20) {
      await _showSnack('Strategy failed: malformed kline data', seconds: 3);
      return false;
    }

    final microSplit = microHighs.length - _recentMicroBars;
    if (microSplit < 5) {
      await _showSnack('Strategy failed: not enough structure bars',
          seconds: 3);
      return false;
    }

    final olderMicroHighs = microHighs.sublist(0, microSplit);
    final olderMicroLows = microLows.sublist(0, microSplit);
    final recentMicroHighs = microHighs.sublist(microSplit);
    final recentMicroLows = microLows.sublist(microSplit);

    final olderHigh = olderMicroHighs.reduce((a, b) => a > b ? a : b);
    final olderLow = olderMicroLows.reduce((a, b) => a < b ? a : b);
    final recentHigh = recentMicroHighs.reduce((a, b) => a > b ? a : b);
    final recentLow = recentMicroLows.reduce((a, b) => a < b ? a : b);

    final macroHigh = macroHighs.reduce((a, b) => a > b ? a : b);
    final macroLow = macroLows.reduce((a, b) => a < b ? a : b);
    final macroRange = macroHigh - macroLow;

    final minWidth = mid * 0.0010; // 10 bps
    final maxWidth = mid * 0.0040; // 40 bps
    final widthFromMacro = macroRange * 0.08;
    final width = _clamp(widthFromMacro, minWidth, maxWidth);
    final fallbackWidth = _fallbackZoneWidth(mid);

    final sweepUp = recentHigh > olderHigh;
    final sweepDown = recentLow < olderLow;

    num zoneLow;
    num zoneHigh;
    if (_side == 'sell') {
      final anchorHigh = sweepUp ? recentHigh : olderHigh;
      zoneLow = anchorHigh - width * 0.65;
      zoneHigh = anchorHigh - width * 0.20;
      if (zoneHigh <= 0 || zoneLow <= 0 || zoneHigh <= zoneLow) {
        zoneLow = mid + (fallbackWidth * 0.40);
        zoneHigh = mid + (fallbackWidth * 1.00);
      }
    } else {
      final anchorLow = sweepDown ? recentLow : olderLow;
      zoneLow = anchorLow + width * 0.20;
      zoneHigh = anchorLow + width * 0.65;
      if (zoneHigh <= 0 || zoneLow <= 0 || zoneHigh <= zoneLow) {
        zoneLow = mid - (fallbackWidth * 1.00);
        zoneHigh = mid - (fallbackWidth * 0.40);
      }
    }

    await _applyZone(zoneLow: zoneLow, zoneHigh: zoneHigh);
    await _uiLog.log(
      'bingx.strategy.zone',
      'symbol=${quote.symbol} side=$_side source=mtf_sweep_retest '
          'mid=${quote.priceDecimal} low=${_zoneLowController.text} high=${_zoneHighController.text} '
          'micro=$_microInterval/${micro.klines.length} macro=$_macroInterval/${macro.klines.length} '
          'olderHigh=${_formatDecimal(olderHigh)} olderLow=${_formatDecimal(olderLow)} '
          'recentHigh=${_formatDecimal(recentHigh)} recentLow=${_formatDecimal(recentLow)} '
          'sweepUp=$sweepUp sweepDown=$sweepDown',
    );
    return true;
  }

  Future<void> _runIntent() async {
    if (_runningIntent) return;
    if (!_droneEnabled) {
      await _showSnack('Drone is paused. Resume before running strategy.');
      return;
    }
    final peerHex = _peerController.text.trim().toLowerCase();
    final symbol = _symbolController.text.trim();
    final strategyTag = _strategyTagController.text.trim();
    final triggerPriceDecimal = _triggerPriceController.text.trim();
    final stopLossDecimal = _stopLossController.text.trim();
    final takeProfitDecimal = _takeProfitController.text.trim();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final clientOrderId = 'ui-ord-${DateTime.now().microsecondsSinceEpoch}';
    if (symbol.isEmpty) {
      await _showSnack('Symbol is required');
      return;
    }
    final riskReady = await _applyRiskBudgetQuantity(symbol: symbol);
    if (!riskReady) {
      return;
    }
    final quantityDecimal = _quantityController.text.trim();

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
      await _uiLog.log(
        'bingx.strategy.entry_mode.auto',
        'forced=zone_pending rule=zone_mid side=$_zoneSide order_type=$_orderType',
      );
    }

    final isZonePending = _entryMode == 'zone_pending';

    if (_orderType == 'limit') {
      final zoneReady = await _computeZoneFromMarketStructure(symbol: symbol);
      if (!zoneReady) {
        return;
      }
    }
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
        await _uiLog.log(
          'bingx.intent.autofill_limit',
          'mode=direct source=zone side=$_side value=$derived',
        );
      }
    }
    final timeInForce = _orderType == 'limit' ? _timeInForce : null;

    setState(() {
      _runningIntent = true;
    });
    final stopwatch = Stopwatch()..start();
    PluginHostApiStatus? finalStatus;
    try {
      await _uiLog.log(
        'bingx.intent.request',
        'peer=${peerHex.isEmpty ? "empty" : "${peerHex.substring(0, 8)}.."} symbol=$symbol side=$_side type=$_orderType entry=$_entryMode qty=$quantityDecimal',
      );

      final response = await _pluginHostApi
          .executeWithRuntimeHook(
            PluginHostApiRequest(
              schemaVersion: PluginHostApiService.schemaVersion,
              pluginId: PluginHostApiService.bingxFuturesTradingPluginId,
              method: PluginHostApiService.placeBingxFuturesOrderIntentMethod,
              args: <String, dynamic>{
                'peer_hex': peerHex,
                'client_order_id': clientOrderId,
                'symbol': symbol,
                'side': _side,
                'order_type': _orderType,
                'quantity_decimal': quantityDecimal,
                'limit_price_decimal': limitPriceDecimal,
                'time_in_force': timeInForce,
                'entry_mode': _entryMode,
                'zone_side': isZonePending ? _zoneSide : null,
                'zone_low_decimal': isZonePending && zoneLowDecimal.isNotEmpty
                    ? zoneLowDecimal
                    : null,
                'zone_high_decimal': isZonePending && zoneHighDecimal.isNotEmpty
                    ? zoneHighDecimal
                    : null,
                'zone_price_rule': isZonePending ? _zonePriceRule : null,
                'trigger_price_decimal':
                    isZonePending && triggerPriceDecimal.isNotEmpty
                        ? triggerPriceDecimal
                        : null,
                'stop_loss_decimal': isZonePending && stopLossDecimal.isNotEmpty
                    ? stopLossDecimal
                    : null,
                'take_profit_decimal':
                    isZonePending && takeProfitDecimal.isNotEmpty
                        ? takeProfitDecimal
                        : null,
                'created_at_utc': nowUtc,
                'strategy_tag': strategyTag.isEmpty ? null : strategyTag,
              },
            ),
          )
          .timeout(_hostIntentTimeout);
      if (!mounted) return;
      setState(() {
        _lastIntentResponse = response;
      });
      finalStatus = response.status;
      final decisionEnvelope = _observability.buildDecisionEnvelope(
        screen: 'trading_drone',
        pluginId: PluginHostApiService.bingxFuturesTradingPluginId,
        method: PluginHostApiService.placeBingxFuturesOrderIntentMethod,
        status: response.status.name,
        symbol: symbol,
        side: _side,
        orderType: _orderType,
        entryMode: _entryMode,
        executionSource: response.executionSource,
        intentHashHex: response.result?['intent_hash_hex']?.toString(),
        errorCode: response.errorCode,
        blockingFactCodes: response.blockingFacts.map((f) => f.key).toList(),
      );
      await _uiLog.log(
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
        await _uiLog.log(
          'bingx.intent.rejected.detail',
          'code=$code message=$msg source=${response.executionSource}',
        );
      }
      await _uiLog.log(
        'drone.decision.envelope',
        'hash=${decisionEnvelope.envelopeHashHex.substring(0, 12)} '
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
          final message = response.errorMessage?.trim().isNotEmpty == true
              ? response.errorMessage!.trim()
              : 'BingX futures request rejected';
          await _showSnack(message);
          break;
      }
    } on TimeoutException {
      await _uiLog.log(
        'bingx.intent.timeout',
        'elapsedMs=${stopwatch.elapsedMilliseconds} timeoutMs=${_hostIntentTimeout.inMilliseconds}',
      );
      await _showSnack(
        'Intent host timeout (${_hostIntentTimeout.inSeconds}s)',
        seconds: 3,
      );
    } catch (error) {
      await _uiLog.log(
        'bingx.intent.error',
        '$error elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      await _showSnack('Intent failed: $error', seconds: 3);
    } finally {
      await _uiLog.log(
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

    final peers = _manualChecks
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
      'plugin_id': PluginHostApiService.bingxFuturesTradingPluginId,
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
    try {
      for (final peerHex in peers) {
        final sendResult = await _chatDelivery.sendCanonicalEnvelope(
          peerHex: peerHex,
          canonicalEnvelopeJson: payloadJson,
        );
        if (sendResult.isSuccess) {
          sent += 1;
        } else if (sendResult.blockedByConsensus) {
          blocked += 1;
        } else {
          failed += 1;
        }
      }
      await _uiLog.log(
        'bingx.signal.broadcast',
        'signal=$signalId peers=${peers.length} sent=$sent blocked=$blocked failed=$failed',
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
      final result = await _chatDelivery.receiveAndFilter();
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
    await _showSnack('Draft loaded from signal $shortSignal');
  }

  Future<void> _executeLastIntent() async {
    await _uiLog.log(
      'bingx.exchange.execute.tap',
      'running=$_executing hasIntent=${_lastIntentResponse?.status == PluginHostApiStatus.executed}',
    );
    if (_executing) return;
    final response = _lastIntentResponse;
    final result = response?.result;
    if (response?.status != PluginHostApiStatus.executed || result == null) {
      await _uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_intent status=${response?.status.name ?? "none"}',
      );
      await _showSnack('Run a BingX intent first');
      return;
    }

    final credentials = _resolveCredentials();
    if (credentials == null) {
      await _uiLog.log(
        'bingx.exchange.execute.guard',
        'blocked=no_credentials',
      );
      await _showSnack('Save BingX API credentials first');
      return;
    }

    late final BingxFuturesIntentPayload payload;
    try {
      payload = BingxFuturesIntentPayload.fromPluginResult(result);
    } on FormatException catch (error) {
      await _uiLog.log(
        'bingx.exchange.execute.parse_error',
        error.message,
      );
      await _showSnack(error.message, seconds: 3);
      return;
    }

    final riskDecision = await _evaluateExecutionRisk(
      payload: payload,
      rawIntentResult: result,
    );
    if (riskDecision == null) {
      return;
    }
    if (riskDecision.status == BingxFuturesRiskDecisionStatus.blocked) {
      final shortHash = riskDecision.decisionHashHex.substring(0, 12);
      await _uiLog.log(
        'bingx.exchange.risk_blocked',
        'code=${riskDecision.reasonCode} hash=$shortHash '
            'risk=${riskDecision.tradeRiskQuoteDecimal} '
            'limit=${riskDecision.dailyLossLimitQuoteDecimal}',
      );
      await _showSnack(
        'Risk blocked: ${riskDecision.reasonCode} ($shortHash)',
        seconds: 3,
      );
      return;
    }
    await _uiLog.log(
      'bingx.exchange.risk_allowed',
      'hash=${riskDecision.decisionHashHex.substring(0, 12)} '
          'max_qty=${riskDecision.maxAllowedQuantityDecimal} '
          'risk=${riskDecision.tradeRiskQuoteDecimal}',
    );

    setState(() {
      _executing = true;
    });
    try {
      await _uiLog.log(
        'bingx.exchange.execute.intent',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'entry=${payload.entryMode} limit=${payload.limitPriceDecimal ?? "-"} '
            'trigger=${payload.triggerPriceDecimal ?? "-"} tif=${payload.timeInForce ?? "-"}',
      );
      final queued = await _bingxExecutionQueue.enqueueOrderExecution(
        credentials: credentials,
        intent: payload,
        testOrder: _useTestOrderEndpoint,
      );
      final executionEnvelope = _observability.buildExecutionEnvelope(
        screen: 'trading_drone',
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
      );
      final safeMessage = queued.execution.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.exchange.execute',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'test=${_useTestOrderEndpoint ? "yes" : "no"} attempts=${queued.attempts} '
            'cache=${queued.fromIdempotentCache ? "hit" : "miss"} '
            'success=${queued.execution.isSuccess} http=${queued.execution.httpStatusCode} '
            'code=${queued.execution.exchangeCode} endpoint=${queued.execution.endpointPath} '
            'orderId=${queued.execution.orderId ?? "-"} msg=$safeMessage',
      );
      await _uiLog.log(
        'drone.execution.envelope',
        'hash=${executionEnvelope.envelopeHashHex.substring(0, 12)} '
            'kind=execution screen=trading_drone',
      );
      if (!mounted) return;
      setState(() {
        _lastExecution = queued.execution;
        _lastExecutionAttempts = queued.attempts;
        _lastExecutionFromCache = queued.fromIdempotentCache;
      });

      if (queued.execution.isSuccess) {
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
      await _uiLog.log('bingx.exchange.error', '$error');
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
    String? entryPriceDecimal = payload.limitPriceDecimal;
    entryPriceDecimal ??= payload.triggerPriceDecimal;
    if (entryPriceDecimal == null || entryPriceDecimal.trim().isEmpty) {
      final quote = await _bingxExchangeService.getPublicPrice(
        symbol: payload.symbol,
      );
      if (quote.isSuccess &&
          quote.priceDecimal != null &&
          quote.priceDecimal!.trim().isNotEmpty) {
        entryPriceDecimal = quote.priceDecimal!.trim();
      }
    }
    if (entryPriceDecimal == null || entryPriceDecimal.trim().isEmpty) {
      await _uiLog.log(
        'bingx.exchange.risk_error',
        'entry_price_unavailable symbol=${payload.symbol}',
      );
      await _showSnack('Risk check failed: entry price unavailable');
      return null;
    }

    var stopLossDecimal =
        rawIntentResult['stop_loss_decimal']?.toString().trim() ?? '';
    if (stopLossDecimal.isEmpty) {
      if (payload.side == 'buy') {
        stopLossDecimal =
            rawIntentResult['zone_low_decimal']?.toString().trim() ?? '';
      } else {
        stopLossDecimal =
            rawIntentResult['zone_high_decimal']?.toString().trim() ?? '';
      }
    }
    if (stopLossDecimal.isEmpty) {
      stopLossDecimal = entryPriceDecimal;
    }

    final equityProxy =
        double.tryParse(_maxNotionalUsdtController.text.trim()) ?? 100.0;
    final decision = _riskGovernor.evaluate(
      input: BingxFuturesRiskGovernorInput(
        symbol: payload.symbol,
        quantityDecimal: payload.quantityDecimal,
        entryPriceDecimal: entryPriceDecimal,
        stopLossDecimal: stopLossDecimal,
        accountEquityQuoteDecimal:
            equityProxy <= 0 ? '100' : equityProxy.toStringAsFixed(8),
        realizedDailyPnlQuoteDecimal: '0',
        concurrentPositions: 0,
        lossStreakCount: 0,
        lastLossAtUtc: null,
        nowUtc: DateTime.now().toUtc().toIso8601String(),
      ),
      policy: _executionRiskPolicy,
    );
    return decision;
  }

  Future<void> _switchLeverage() async {
    if (_switchingLeverage) return;
    final credentials = _resolveCredentials();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }
    final symbol = _symbolController.text.trim();
    final leverage = int.tryParse(_leverageController.text.trim());
    if (symbol.isEmpty || leverage == null) {
      await _showSnack('Symbol and integer leverage are required');
      return;
    }

    setState(() {
      _switchingLeverage = true;
    });
    try {
      final result = await _bingxExchangeService.switchLeverage(
        credentials: credentials,
        symbol: symbol,
        side: _leverageSide == 'LONG'
            ? BingxFuturesLeverageSide.long
            : BingxFuturesLeverageSide.short,
        leverage: leverage,
      );
      final safeMessage =
          result.exchangeMessage.replaceAll('\n', ' ').replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.exchange.switch_leverage',
        'symbol=${result.symbol} side=$_leverageSide leverage=$leverage '
            'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} endpoint=${result.endpointPath} msg=$safeMessage',
      );
      if (!mounted) return;
      setState(() {
        _lastLeverageSwitch = result;
      });
      await _showSnack(
        result.isSuccess
            ? 'Leverage switched: $_leverageSide x$leverage'
            : 'Switch leverage failed: ${result.exchangeCode} ${result.exchangeMessage}',
        seconds: result.isSuccess ? 2 : 4,
      );
    } catch (error) {
      await _showSnack('Switch leverage failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _switchingLeverage = false;
        });
      }
    }
  }

  Future<void> _switchMarginType() async {
    if (_switchingMarginType) return;
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

    setState(() {
      _switchingMarginType = true;
    });
    try {
      final result = await _bingxExchangeService.switchMarginType(
        credentials: credentials,
        symbol: symbol,
        marginType: _marginType == 'ISOLATED'
            ? BingxFuturesMarginType.isolated
            : BingxFuturesMarginType.crossed,
      );
      final safeMessage =
          result.exchangeMessage.replaceAll('\n', ' ').replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.exchange.switch_margin_type',
        'symbol=${result.symbol} margin=$_marginType '
            'success=${result.isSuccess} http=${result.httpStatusCode} '
            'code=${result.exchangeCode} endpoint=${result.endpointPath} msg=$safeMessage',
      );
      if (!mounted) return;
      setState(() {
        _lastMarginSwitch = result;
      });
      await _showSnack(
        result.isSuccess
            ? 'Margin mode switched: $_marginType'
            : 'Switch margin mode failed: ${result.exchangeCode} ${result.exchangeMessage}',
        seconds: result.isSuccess ? 2 : 4,
      );
    } catch (error) {
      await _showSnack('Switch margin mode failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _switchingMarginType = false;
        });
      }
    }
  }

  Future<void> _fetchCurrent() async {
    if (_readingCurrentSettings) return;
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

    setState(() {
      _readingCurrentSettings = true;
    });
    try {
      final leverageResult = await _bingxExchangeService.getLeverage(
        credentials: credentials,
        symbol: symbol,
      );
      final marginResult = await _bingxExchangeService.getMarginType(
        credentials: credentials,
        symbol: symbol,
      );
      final levMsg = leverageResult.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      final marginMsg = marginResult.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.exchange.fetch_current',
        'symbol=${symbol.toUpperCase()} '
            'lev=${leverageResult.exchangeCode} levEndpoint=${leverageResult.endpointPath} levMsg=$levMsg '
            'margin=${marginResult.exchangeCode} marginEndpoint=${marginResult.endpointPath} marginMsg=$marginMsg',
      );
      if (!mounted) return;
      setState(() {
        _lastLeverageRead = leverageResult;
        _lastMarginRead = marginResult;
        if (marginResult.isSuccess &&
            marginResult.marginType != null &&
            (marginResult.marginType == 'CROSSED' ||
                marginResult.marginType == 'ISOLATED')) {
          _marginType = marginResult.marginType!;
        }
        if (leverageResult.isSuccess) {
          final selected = _leverageSide == 'LONG'
              ? leverageResult.longLeverage
              : leverageResult.shortLeverage;
          if (selected != null && selected > 0) {
            _leverageController.text = selected.toString();
          }
        }
      });
      final levSummary = leverageResult.isSuccess
          ? 'L:${leverageResult.longLeverage ?? "-"} / S:${leverageResult.shortLeverage ?? "-"}'
          : 'err ${leverageResult.exchangeCode}';
      final marginSummary = marginResult.isSuccess
          ? (marginResult.marginType ?? '-')
          : 'err ${marginResult.exchangeCode}';
      await _showSnack(
        'Current fetched · leverage $levSummary · margin $marginSummary',
        seconds: 3,
      );
    } catch (error) {
      await _showSnack('Fetch current failed: $error', seconds: 3);
    } finally {
      if (mounted) {
        setState(() {
          _readingCurrentSettings = false;
        });
      }
    }
  }

  Future<void> _fetchOpenOrders({bool silent = false}) async {
    if (_fetchingOpenOrders) return;
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

    setState(() {
      _fetchingOpenOrders = true;
    });
    try {
      final result = await _bingxExchangeService.getOpenOrders(
        credentials: credentials,
        symbol: symbol,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _uiLog.log(
        'bingx.exchange.open_orders',
        'symbol=${result.symbol} success=${result.isSuccess} '
            'http=${result.httpStatusCode} code=${result.exchangeCode} '
            'count=${result.orders.length} endpoint=${result.endpointPath} msg=$message',
      );
      if (!mounted) return;
      setState(() {
        _lastOpenOrdersRead = result;
        _openOrders = result.orders;
        if (result.orders.isNotEmpty) {
          _cancelOrderIdController.text = result.orders.first.orderId;
        }
      });
      if (!silent) {
        await _showSnack(
          result.isSuccess
              ? 'Open orders: ${result.orders.length}'
              : 'Open orders failed: ${result.exchangeCode}',
          seconds: result.isSuccess ? 2 : 4,
        );
      }
    } catch (error) {
      await _uiLog.log('bingx.exchange.open_orders.error', '$error');
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
      final result = await _bingxExchangeService.cancelOrder(
        credentials: credentials,
        symbol: symbol,
        orderId: orderId,
      );
      final message = result.exchangeMessage
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      await _uiLog.log(
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
          _openOrders =
              _openOrders.where((order) => order.orderId != canceled).toList();
        }
      });
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
      await _uiLog.log('bingx.exchange.cancel_order.error', '$error');
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
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true)
        .toLocal();
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

  @override
  Widget build(BuildContext context) {
    final isZonePending = _entryMode == 'zone_pending';
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
                    width: 180,
                    child: TextField(
                      controller: _symbolController,
                      decoration: InputDecoration(
                        labelText: 'Symbol',
                        hintText: 'BTC-USDT',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
              SwitchListTile.adaptive(
                value: _advancedControlsEnabled,
                onChanged: (value) {
                  setState(() {
                    _advancedControlsEnabled = value;
                  });
                },
                title: const Text('Advanced controls (dev only)'),
                subtitle: const Text(
                  'Manual parameters for debugging. Keep OFF for normal use.',
                  style: TextStyle(color: Color(0xFF97A3B5)),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_advancedControlsEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-entry-mode-$_entryMode'),
                        initialValue: _entryMode,
                        decoration: InputDecoration(
                          labelText: 'Entry Mode',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: 'direct', child: Text('Direct')),
                          DropdownMenuItem(
                            value: 'zone_pending',
                            child: Text('Zone Pending'),
                          ),
                        ],
                        onChanged: _runningIntent
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _entryMode = value;
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-side-$_side'),
                        initialValue: _side,
                        decoration: InputDecoration(
                          labelText: 'Side',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'buy', child: Text('Buy')),
                          DropdownMenuItem(value: 'sell', child: Text('Sell')),
                        ],
                        onChanged: _runningIntent
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _side = value;
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-order-$_orderType'),
                        initialValue: _orderType,
                        decoration: InputDecoration(
                          labelText: 'Order Type',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: 'limit', child: Text('Limit')),
                          DropdownMenuItem(
                              value: 'market', child: Text('Market')),
                        ],
                        onChanged: _runningIntent || isZonePending
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _orderType = value;
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-tif-$_timeInForce'),
                        initialValue: _timeInForce,
                        decoration: InputDecoration(
                          labelText: 'TIF',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'GTC', child: Text('GTC')),
                          DropdownMenuItem(value: 'IOC', child: Text('IOC')),
                          DropdownMenuItem(value: 'FOK', child: Text('FOK')),
                        ],
                        onChanged: _runningIntent
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _timeInForce = value;
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Manual Quantity',
                          hintText: 'overridden by risk budget',
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
                if (isZonePending) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String>('drone-zone-side-$_zoneSide'),
                          initialValue: _zoneSide,
                          decoration: InputDecoration(
                            labelText: 'Zone Side',
                            filled: true,
                            fillColor: const Color(0xFF0F141C),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'buyside',
                              child: Text('Buyside'),
                            ),
                            DropdownMenuItem(
                              value: 'sellside',
                              child: Text('Sellside'),
                            ),
                          ],
                          onChanged: _runningIntent
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _zoneSide = value;
                                  });
                                },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                              'drone-zone-rule-$_zonePriceRule'),
                          initialValue: _zonePriceRule,
                          decoration: InputDecoration(
                            labelText: 'Zone Price Rule',
                            filled: true,
                            fillColor: const Color(0xFF0F141C),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'zone_low',
                              child: Text('Zone Low'),
                            ),
                            DropdownMenuItem(
                              value: 'zone_mid',
                              child: Text('Zone Mid'),
                            ),
                            DropdownMenuItem(
                              value: 'zone_high',
                              child: Text('Zone High'),
                            ),
                          ],
                          onChanged: _runningIntent
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _zonePriceRule = value;
                                  });
                                },
                        ),
                      ),
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _triggerPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Trigger (opt)',
                            filled: true,
                            fillColor: const Color(0xFF0F141C),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _stopLossController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Stop Loss (opt)',
                            filled: true,
                            fillColor: const Color(0xFF0F141C),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _takeProfitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Take Profit (opt)',
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
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _strategyTagController,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: 'Strategy Tag (opt)',
                    filled: true,
                    fillColor: const Color(0xFF0F141C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
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
                  if (_advancedControlsEnabled)
                    OutlinedButton.icon(
                      onPressed: _readingCurrentSettings ? null : _fetchCurrent,
                      icon: _readingCurrentSettings
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _readingCurrentSettings ? 'Fetching' : 'Fetch Current',
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _fetchingOpenOrders
                        ? null
                        : () => _fetchOpenOrders(),
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
                          ? 'Executing'
                          : _useTestOrderEndpoint
                              ? 'Execute Test Order'
                              : 'Execute Live Order',
                    ),
                  ),
                ],
              ),
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
              if (_advancedControlsEnabled) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _leverageController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Leverage',
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
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-lev-side-$_leverageSide'),
                        initialValue: _leverageSide,
                        decoration: InputDecoration(
                          labelText: 'Lev Side',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'LONG', child: Text('LONG')),
                          DropdownMenuItem(
                              value: 'SHORT', child: Text('SHORT')),
                        ],
                        onChanged: _switchingLeverage
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _leverageSide = value;
                                });
                              },
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _switchingLeverage ? null : _switchLeverage,
                      icon: _switchingLeverage
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.tune_rounded),
                      label: Text(
                        _switchingLeverage ? 'Switching' : 'Switch Leverage',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>('drone-margin-$_marginType'),
                        initialValue: _marginType,
                        decoration: InputDecoration(
                          labelText: 'Margin Type',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: 'CROSSED', child: Text('CROSSED')),
                          DropdownMenuItem(
                            value: 'ISOLATED',
                            child: Text('ISOLATED'),
                          ),
                        ],
                        onChanged: _switchingMarginType
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _marginType = value;
                                });
                              },
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _switchingMarginType ? null : _switchMarginType,
                      icon: _switchingMarginType
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz_rounded),
                      label: Text(
                        _switchingMarginType ? 'Switching' : 'Switch Margin',
                      ),
                    ),
                  ],
                ),
              ],
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
                      'Open: ${_openOrders.length} (${_lastOpenOrdersRead!.exchangeCode})',
                      accent: _lastOpenOrdersRead!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastCancelOrder != null)
                    _statusChip(
                      'Cancel: ${_lastCancelOrder!.exchangeCode}',
                      accent: _lastCancelOrder!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastLeverageSwitch != null)
                    _statusChip(
                      'Lev: ${_lastLeverageSwitch!.exchangeCode}',
                      accent: _lastLeverageSwitch!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastMarginSwitch != null)
                    _statusChip(
                      'Margin: ${_lastMarginSwitch!.exchangeCode}',
                      accent: _lastMarginSwitch!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastLeverageRead != null)
                    _statusChip(
                      _lastLeverageRead!.isSuccess
                          ? 'Current L:${_lastLeverageRead!.longLeverage ?? "-"} S:${_lastLeverageRead!.shortLeverage ?? "-"}'
                          : 'Current lev err ${_lastLeverageRead!.exchangeCode}',
                      accent: _lastLeverageRead!.isSuccess
                          ? const Color(0xFF75D98A)
                          : const Color(0xFFFF8A7A),
                    ),
                  if (_lastMarginRead != null)
                    _statusChip(
                      _lastMarginRead!.isSuccess
                          ? 'Current margin ${_lastMarginRead!.marginType ?? "-"}'
                          : 'Current margin err ${_lastMarginRead!.exchangeCode}',
                      accent: _lastMarginRead!.isSuccess
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
                    'Active Orders',
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
