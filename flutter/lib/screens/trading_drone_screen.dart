import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_runtime_service.dart';
import '../services/bingx_futures_credential_store.dart';
import '../services/bingx_futures_exchange_service.dart';
import '../services/bingx_futures_execution_queue_service.dart';
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
  final PluginHostApiService _pluginHostApi =
      AppRuntimeService().buildPluginHostApiService();
  final ManualConsensusCheckService _manualChecks =
      AppRuntimeService().buildManualConsensusCheckService();
  final BingxFuturesCredentialStore _bingxCredentialStore =
      AppRuntimeService().buildBingxFuturesCredentialStore();
  final BingxFuturesExchangeService _bingxExchangeService =
      AppRuntimeService().buildBingxFuturesExchangeService();
  final CapsuleChatDeliveryService _chatDelivery =
      AppRuntimeService().buildCapsuleChatDeliveryService();
  final UiEventLogService _uiLog = const UiEventLogService();
  late final BingxFuturesExecutionQueueService _bingxExecutionQueue;

  final TextEditingController _peerController = TextEditingController();
  final TextEditingController _symbolController =
      TextEditingController(text: 'BTC-USDT');
  final TextEditingController _quantityController =
      TextEditingController(text: '0.01');
  final TextEditingController _limitPriceController =
      TextEditingController(text: '60000');
  final TextEditingController _zoneLowController =
      TextEditingController(text: '58000');
  final TextEditingController _zoneHighController =
      TextEditingController(text: '60000');
  final TextEditingController _manualEntryPriceController =
      TextEditingController();
  final TextEditingController _triggerPriceController = TextEditingController();
  final TextEditingController _stopLossController = TextEditingController();
  final TextEditingController _takeProfitController = TextEditingController();
  final TextEditingController _strategyTagController =
      TextEditingController(text: 'demo');
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiSecretController = TextEditingController();
  final TextEditingController _leverageController =
      TextEditingController(text: '3');

  bool _runningIntent = false;
  bool _broadcastingSignal = false;
  bool _savingCredentials = false;
  bool _readingCurrentSettings = false;
  bool _executing = false;
  bool _switchingLeverage = false;
  bool _switchingMarginType = false;
  bool _refreshingSignals = false;
  bool _useTestOrderEndpoint = true;

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
  int _lastExecutionAttempts = 0;
  bool _lastExecutionFromCache = false;
  List<CapsuleTradeSignalInboxMessage> _signalInbox =
      const <CapsuleTradeSignalInboxMessage>[];

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
    _quantityController.dispose();
    _limitPriceController.dispose();
    _zoneLowController.dispose();
    _zoneHighController.dispose();
    _manualEntryPriceController.dispose();
    _triggerPriceController.dispose();
    _stopLossController.dispose();
    _takeProfitController.dispose();
    _strategyTagController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _leverageController.dispose();
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
    } catch (_) {
      await _showSnack('Failed to load BingX credentials');
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
      await _showSnack('BingX credentials saved for active capsule');
    } catch (_) {
      await _showSnack('Failed to save BingX credentials');
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

  Future<void> _runIntent() async {
    if (_runningIntent) return;
    final peerHex = _peerController.text.trim().toLowerCase();
    final symbol = _symbolController.text.trim();
    final quantityDecimal = _quantityController.text.trim();
    final strategyTag = _strategyTagController.text.trim();
    final zoneLowDecimal = _zoneLowController.text.trim();
    final zoneHighDecimal = _zoneHighController.text.trim();
    final manualEntryPriceDecimal = _manualEntryPriceController.text.trim();
    final triggerPriceDecimal = _triggerPriceController.text.trim();
    final stopLossDecimal = _stopLossController.text.trim();
    final takeProfitDecimal = _takeProfitController.text.trim();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final clientOrderId = 'ui-ord-${DateTime.now().microsecondsSinceEpoch}';
    final isZonePending = _entryMode == 'zone_pending';
    final limitPriceDecimal = _orderType == 'limit' && !isZonePending
        ? _limitPriceController.text.trim()
        : null;
    final timeInForce = _orderType == 'limit' ? _timeInForce : null;

    setState(() {
      _runningIntent = true;
    });
    try {
      await _uiLog.log(
        'bingx.intent.request',
        'peer=${peerHex.isEmpty ? "empty" : "${peerHex.substring(0, 8)}.."} symbol=$symbol side=$_side type=$_orderType entry=$_entryMode qty=$quantityDecimal',
      );

      final response = await _pluginHostApi.executeWithRuntimeHook(
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
            'manual_entry_price_decimal': isZonePending &&
                    _zonePriceRule == 'manual' &&
                    manualEntryPriceDecimal.isNotEmpty
                ? manualEntryPriceDecimal
                : null,
            'trigger_price_decimal':
                isZonePending && triggerPriceDecimal.isNotEmpty
                    ? triggerPriceDecimal
                    : null,
            'stop_loss_decimal': isZonePending && stopLossDecimal.isNotEmpty
                ? stopLossDecimal
                : null,
            'take_profit_decimal': isZonePending && takeProfitDecimal.isNotEmpty
                ? takeProfitDecimal
                : null,
            'created_at_utc': nowUtc,
            'strategy_tag': strategyTag.isEmpty ? null : strategyTag,
          },
        ),
      );
      if (!mounted) return;
      setState(() {
        _lastIntentResponse = response;
      });

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
    } finally {
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
        _zonePriceRule = decoded['zone_price_rule']?.toString() ?? 'zone_mid';
        _manualEntryPriceController.text =
            decoded['manual_entry_price_decimal']?.toString() ?? '';
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
    if (_executing) return;
    final response = _lastIntentResponse;
    final result = response?.result;
    if (response?.status != PluginHostApiStatus.executed || result == null) {
      await _showSnack('Run a BingX intent first');
      return;
    }

    final credentials = _resolveCredentials();
    if (credentials == null) {
      await _showSnack('Save BingX API credentials first');
      return;
    }

    late final BingxFuturesIntentPayload payload;
    try {
      payload = BingxFuturesIntentPayload.fromPluginResult(result);
    } on FormatException catch (error) {
      await _showSnack(error.message, seconds: 3);
      return;
    }

    setState(() {
      _executing = true;
    });
    try {
      final queued = await _bingxExecutionQueue.enqueueOrderExecution(
        credentials: credentials,
        intent: payload,
        testOrder: _useTestOrderEndpoint,
      );
      await _uiLog.log(
        'bingx.exchange.execute',
        'symbol=${payload.symbol} side=${payload.side} type=${payload.orderType} '
            'test=${_useTestOrderEndpoint ? "yes" : "no"} attempts=${queued.attempts} '
            'cache=${queued.fromIdempotentCache ? "hit" : "miss"} '
            'success=${queued.execution.isSuccess} http=${queued.execution.httpStatusCode} '
            'code=${queued.execution.exchangeCode}',
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
      await _uiLog.log(
        'bingx.exchange.switch_leverage',
        'symbol=${result.symbol} side=$_leverageSide leverage=$leverage '
            'success=${result.isSuccess} http=${result.httpStatusCode} code=${result.exchangeCode}',
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
      await _uiLog.log(
        'bingx.exchange.switch_margin_type',
        'symbol=${result.symbol} margin=$_marginType '
            'success=${result.isSuccess} http=${result.httpStatusCode} code=${result.exchangeCode}',
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
      await _uiLog.log(
        'bingx.exchange.fetch_current',
        'symbol=${symbol.toUpperCase()} lev=${leverageResult.exchangeCode} margin=${marginResult.exchangeCode}',
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
    final isZoneManual = _zonePriceRule == 'manual';
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
                                if (_entryMode == 'zone_pending') {
                                  _orderType = 'limit';
                                  _zoneSide =
                                      _side == 'buy' ? 'buyside' : 'sellside';
                                }
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
                                if (_entryMode == 'zone_pending') {
                                  _zoneSide =
                                      _side == 'buy' ? 'buyside' : 'sellside';
                                }
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
                        DropdownMenuItem(value: 'limit', child: Text('Limit')),
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
                ],
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
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        hintText: '0.01',
                        filled: true,
                        fillColor: const Color(0xFF0F141C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_orderType == 'limit' && !isZonePending)
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _limitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Limit Price',
                          hintText: '60000',
                          filled: true,
                          fillColor: const Color(0xFF0F141C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (_orderType == 'limit')
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
                ],
              ),
              if (isZonePending) ...[
                const SizedBox(height: 10),
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
                        key:
                            ValueKey<String>('drone-zone-rule-$_zonePriceRule'),
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
                          DropdownMenuItem(
                            value: 'manual',
                            child: Text('Manual'),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                    if (isZoneManual)
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _manualEntryPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Manual Entry',
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
              const SizedBox(height: 10),
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
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'BingX API Secret',
                  filled: true,
                  fillColor: const Color(0xFF0F141C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                        DropdownMenuItem(value: 'SHORT', child: Text('SHORT')),
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
                    onPressed: _switchingMarginType ? null : _switchMarginType,
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
