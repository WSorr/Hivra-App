import 'dart:async';
import 'dart:io';

import 'package:hivra_app/models/bingx_futures_live_strategy_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_live_strategy_use_case_service.dart';

const int _recentMicroBars = 8;
const double _zoneNearBps = 15.0;
const double _zoneFarBps = 35.0;

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final limit = int.parse(options['limit'] ?? '0');
  final top = int.parse(options['top'] ?? '20');
  final concurrency = int.parse(options['concurrency'] ?? '4');
  final contains = options['contains']?.trim().toUpperCase();
  final symbolsArg = options['symbols']?.trim();
  final includeNoSignal = options['include-no-signal'] == 'true';
  final side = options['side']?.trim().toLowerCase();

  if (concurrency < 1 || concurrency > 16) {
    throw const FormatException('--concurrency must be in 1..16');
  }

  final exchange = BingxFuturesExchangeService();
  final strategy = BingxFuturesLiveStrategyUseCaseService(exchange: exchange);

  final symbols =
      symbolsArg == null || symbolsArg.isEmpty
          ? await _loadSymbols(exchange, contains: contains)
          : symbolsArg
              .split(',')
              .map((value) => value.trim().toUpperCase())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
  final scanSymbols = limit > 0 ? symbols.take(limit).toList() : symbols;

  stdout.writeln(
    'Scanning ${scanSymbols.length} BingX perpetual symbols '
    '(concurrency=$concurrency, top=$top)...',
  );

  final results = <_SignalProbe>[];
  var index = 0;
  var completed = 0;

  Future<void> worker() async {
    while (true) {
      final currentIndex = index++;
      if (currentIndex >= scanSymbols.length) return;
      final symbol = scanSymbols[currentIndex];
      final result = await _probe(strategy, symbol: symbol, side: side);
      results.add(result);
      completed += 1;
      if (completed % 10 == 0 || completed == scanSymbols.length) {
        stdout.writeln('progress=$completed/${scanSymbols.length}');
      }
    }
  }

  await Future.wait(List<Future<void>>.generate(concurrency, (_) => worker()));

  final actionable = results.where((item) => item.ready).toList(growable: false)
    ..sort(_compareProbe);
  final blocked = results
    .where((item) => !item.ready && item.decision != null)
    .toList(growable: false)..sort(_compareProbe);
  final errors = results.where((item) => item.errorCode != null).length;

  stdout.writeln('');
  stdout.writeln(
    'Summary: ready=${actionable.length} evaluated=${blocked.length} '
    'errors=$errors total=${results.length}',
  );
  stdout.writeln('');

  if (actionable.isEmpty) {
    stdout.writeln('No READY signals found.');
  } else {
    stdout.writeln('READY signals:');
    for (final item in actionable.take(top)) {
      stdout.writeln(item.describe());
    }
  }

  if (includeNoSignal) {
    stdout.writeln('');
    stdout.writeln('Best non-ready candidates:');
    for (final item in blocked.take(top)) {
      stdout.writeln(item.describe());
    }
  }

  if (errors > 0) {
    stdout.writeln('');
    stdout.writeln('Errors:');
    for (final item in results
        .where((item) => item.errorCode != null)
        .take(10)) {
      stdout.writeln(
        '${item.symbol} error=${item.errorCode} ${item.errorMessage ?? ""}',
      );
    }
  }
}

Future<List<String>> _loadSymbols(
  BingxFuturesExchangeService exchange, {
  String? contains,
}) async {
  final result = await exchange.getPerpetualSymbols();
  if (!result.isSuccess || result.symbols.isEmpty) {
    throw StateError(
      'Failed to load perpetual symbols: ${result.exchangeCode} '
      '${result.exchangeMessage}',
    );
  }
  final symbols =
      result.symbols
          .map((value) => value.trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .where((value) => contains == null || value.contains(contains))
          .toSet()
          .toList()
        ..sort();
  return symbols;
}

Future<_SignalProbe> _probe(
  BingxFuturesLiveStrategyUseCaseService strategy, {
  required String symbol,
  required String? side,
}) async {
  try {
    final result = await strategy.execute(
      BingxFuturesLiveStrategyCommand(
        symbol: symbol,
        credentials: null,
        isConsensusSignable: true,
        blockingFactCodes: const <String>[],
        recentMicroBars: _recentMicroBars,
        zoneNearBps: _zoneNearBps,
        zoneFarBps: _zoneFarBps,
        zoneEvaluationSide: side,
      ),
    );
    final decision = result.decision;
    if (decision == null) {
      return _SignalProbe(
        symbol: symbol,
        errorCode: result.errorCode ?? 'strategy_failed',
        errorMessage: result.errorMessage,
      );
    }
    return _SignalProbe(
      symbol: symbol,
      decision: decision.decision.name,
      ready:
          decision.canPrepareIntent &&
          decision.decision != BingxTvhDecisionKind.noSignal,
      side: decision.side,
      zoneLow: decision.zoneLowDecimal,
      zoneHigh: decision.zoneHighDecimal,
      trend15m: decision.trend15m,
      trend4h: decision.trend4h,
      trend1d: decision.trend1d,
      trendGate: decision.trendGateCode,
      anchorSource: decision.zoneAnchorSource,
      anchorLifecycle: decision.zoneAnchorLifecycle,
      anchorExecutable: decision.zoneAnchorExecutable,
      liveHash: decision.liveDecisionHashHex,
      failedCodes: decision.reasons
          .where((reason) => !reason.passed)
          .map((reason) => reason.code)
          .where((code) => code.isNotEmpty)
          .toList(growable: false),
    );
  } catch (error) {
    return _SignalProbe(
      symbol: symbol,
      errorCode: 'exception',
      errorMessage: error.toString(),
    );
  }
}

int _compareProbe(_SignalProbe a, _SignalProbe b) {
  final scoreCompare = b.score.compareTo(a.score);
  if (scoreCompare != 0) return scoreCompare;
  return a.symbol.compareTo(b.symbol);
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    final key = arg.substring(2);
    if (key == 'include-no-signal') {
      parsed[key] = 'true';
      continue;
    }
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      throw FormatException('Missing value for: $arg');
    }
    parsed[key] = args[++i];
  }
  return parsed;
}

class _SignalProbe {
  final String symbol;
  final String? decision;
  final bool ready;
  final String? side;
  final String? zoneLow;
  final String? zoneHigh;
  final String? trend15m;
  final String? trend4h;
  final String? trend1d;
  final String? trendGate;
  final String? anchorSource;
  final String? anchorLifecycle;
  final bool anchorExecutable;
  final String? liveHash;
  final List<String> failedCodes;
  final String? errorCode;
  final String? errorMessage;

  const _SignalProbe({
    required this.symbol,
    this.decision,
    this.ready = false,
    this.side,
    this.zoneLow,
    this.zoneHigh,
    this.trend15m,
    this.trend4h,
    this.trend1d,
    this.trendGate,
    this.anchorSource,
    this.anchorLifecycle,
    this.anchorExecutable = false,
    this.liveHash,
    this.failedCodes = const <String>[],
    this.errorCode,
    this.errorMessage,
  });

  int get score {
    var value = 0;
    if (ready) value += 100000;
    if (anchorExecutable) value += 10000;
    if (anchorLifecycle == 'fresh') value += 1000;
    if (trendGate == 'ok') value += 500;
    if (decision == 'short' || decision == 'long') value += 250;
    value -= failedCodes.length * 25;
    return value;
  }

  String describe() {
    final zone =
        zoneLow != null && zoneHigh != null ? '$zoneLow-$zoneHigh' : '-';
    final hash =
        liveHash == null || liveHash!.length < 12
            ? '-'
            : liveHash!.substring(0, 12);
    final failed = failedCodes.isEmpty ? '-' : failedCodes.join(',');
    return '$symbol score=$score decision=${decision ?? "-"} side=${side ?? "-"} '
        'zone=$zone trend15m=${trend15m ?? "-"} trend4h=${trend4h ?? "-"} '
        'trend1d=${trend1d ?? "-"} gate=${trendGate ?? "-"} '
        'anchor=${anchorSource ?? "-"}/${anchorLifecycle ?? "-"} '
        'exec=$anchorExecutable live=$hash failed=$failed';
  }
}
