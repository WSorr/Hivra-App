import 'dart:convert';

import '../models/bingx_futures_market_snapshot_models.dart';

class BingxFuturesPublicSessionAccumulator {
  static const Duration maxMessageSilence = Duration(seconds: 90);
  static const int maxDecodedMessageBytes = 32768;
  static const int maxTradesPerMessage = 256;

  final String symbol;
  final DateTime Function() _clockUtc;
  final Map<String, _SessionAggregate> _latestBySession =
      <String, _SessionAggregate>{};

  DateTime? _connectedAtUtc;
  DateTime? _lastMessageAtUtc;
  bool _connected = false;

  bool get isConnected => _connected;

  bool get hasHealthyConnection {
    final now = _clockUtc().toUtc();
    final lastMessageAt = _lastMessageAtUtc;
    return _connected &&
        lastMessageAt != null &&
        !now.isBefore(lastMessageAt) &&
        now.difference(lastMessageAt) <= maxMessageSilence;
  }

  BingxFuturesPublicSessionAccumulator({
    required this.symbol,
    DateTime Function()? clockUtc,
  }) : _clockUtc = clockUtc ?? (() => DateTime.now().toUtc()) {
    if (!RegExp(r'^[A-Z0-9]{2,20}-USDT$').hasMatch(symbol)) {
      throw const FormatException('invalid public session symbol');
    }
  }

  void beginConnection() {
    final now = _clockUtc().toUtc();
    _latestBySession.clear();
    _connectedAtUtc = now;
    _lastMessageAtUtc = now;
    _connected = true;
  }

  void markDisconnected() {
    _connected = false;
    _connectedAtUtc = null;
    _lastMessageAtUtc = null;
  }

  void acceptHeartbeat() {
    _requireConnected();
    _lastMessageAtUtc = _clockUtc().toUtc();
  }

  void acceptDecodedTradeMessage(String message) {
    _requireConnected();
    if (utf8.encode(message).length > maxDecodedMessageBytes) {
      throw const FormatException('public trade message is oversized');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      throw const FormatException('public trade message is not JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['dataType'] != '$symbol@trade') {
      throw const FormatException('public trade channel mismatch');
    }
    final now = _clockUtc().toUtc();
    final payload = decoded['data'];
    final rows = switch (payload) {
      Map<String, dynamic>() => <Map<String, dynamic>>[payload],
      List<dynamic>()
          when payload.isNotEmpty &&
              payload.length <= maxTradesPerMessage &&
              payload.every((row) => row is Map<String, dynamic>) =>
        payload.cast<Map<String, dynamic>>(),
      _ => throw const FormatException('public trade payload is invalid'),
    };
    final trades = rows
        .map((row) => _parseTrade(row, now: now))
        .toList(growable: false);

    for (final trade in trades) {
      final bucket = _bucketFor(trade.timestampUtc);
      final previous = _latestBySession[bucket.session];
      final aggregate =
          previous == null || previous.bucketStartUtc != bucket.bucketStartUtc
              ? _SessionAggregate(bucketStartUtc: bucket.bucketStartUtc)
              : previous;
      aggregate.volumeNotional += trade.notional;
      aggregate.deltaNotional +=
          trade.buyerIsMaker ? -trade.notional : trade.notional;
      _latestBySession[bucket.session] = aggregate;
    }
    _lastMessageAtUtc = now;
  }

  _ParsedTrade _parseTrade(Map<String, dynamic> data, {required DateTime now}) {
    if (data['s'] != symbol) {
      throw const FormatException('public trade symbol mismatch');
    }
    final timestampMs = _parseTimestamp(data['T']);
    final price = _parsePositiveDecimal(data['p'], field: 'price');
    final quantity = _parsePositiveDecimal(data['q'], field: 'quantity');
    final buyerIsMaker = data['m'];
    if (buyerIsMaker is! bool) {
      throw const FormatException('public trade maker flag is invalid');
    }
    final timestampUtc = DateTime.fromMillisecondsSinceEpoch(
      timestampMs,
      isUtc: true,
    );
    if (timestampUtc.isAfter(now.add(const Duration(minutes: 1))) ||
        timestampUtc.isBefore(now.subtract(const Duration(minutes: 5)))) {
      throw const FormatException('public trade timestamp is outside bounds');
    }
    return _ParsedTrade(
      timestampUtc: timestampUtc,
      notional: price * quantity,
      buyerIsMaker: buyerIsMaker,
    );
  }

  List<BingxFuturesSessionVolumePoint> snapshot() {
    final now = _clockUtc().toUtc();
    final connectedAt = _connectedAtUtc;
    final lastMessageAt = _lastMessageAtUtc;
    final healthy =
        connectedAt != null && lastMessageAt != null && hasHealthyConnection;
    return <String>['asia', 'london', 'newyork']
        .map((session) {
          final aggregate = _latestBySession[session];
          final fallbackStart = _latestBucketStart(session, now);
          final bucketStart = aggregate?.bucketStartUtc ?? fallbackStart;
          final complete =
              healthy &&
              aggregate != null &&
              !bucketStart.isBefore(connectedAt);
          return BingxFuturesSessionVolumePoint(
            session: session,
            bucketStartUtc: bucketStart.toIso8601String(),
            volumeDecimal: _format(aggregate?.volumeNotional ?? 0),
            deltaDecimal: _format(aggregate?.deltaNotional ?? 0),
            evidenceSource: 'public_trade_stream',
            coverageComplete: complete,
          );
        })
        .toList(growable: false);
  }

  void _requireConnected() {
    if (!_connected) {
      throw StateError('public trade stream is not connected');
    }
  }

  int _parseTimestamp(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 1) {
      throw const FormatException('public trade timestamp is invalid');
    }
    return parsed;
  }

  double _parsePositiveDecimal(Object? value, {required String field}) {
    final text = value?.toString() ?? '';
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw FormatException('public trade $field is invalid');
    }
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw FormatException('public trade $field is invalid');
    }
    return parsed;
  }

  ({String session, DateTime bucketStartUtc}) _bucketFor(DateTime value) {
    final utc = value.toUtc();
    if (utc.hour < 8) {
      return (
        session: 'asia',
        bucketStartUtc: DateTime.utc(utc.year, utc.month, utc.day),
      );
    }
    if (utc.hour < 16) {
      return (
        session: 'london',
        bucketStartUtc: DateTime.utc(utc.year, utc.month, utc.day, 8),
      );
    }
    return (
      session: 'newyork',
      bucketStartUtc: DateTime.utc(utc.year, utc.month, utc.day, 16),
    );
  }

  DateTime _latestBucketStart(String session, DateTime now) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final hour =
        session == 'asia'
            ? 0
            : session == 'london'
            ? 8
            : 16;
    final candidate = today.add(Duration(hours: hour));
    return candidate.isAfter(now)
        ? candidate.subtract(const Duration(days: 1))
        : candidate;
  }

  String _format(double value) {
    final normalized = value.abs() < 0.000000005 ? 0.0 : value;
    return normalized.toStringAsFixed(8);
  }
}

class _SessionAggregate {
  final DateTime bucketStartUtc;
  double volumeNotional = 0;
  double deltaNotional = 0;

  _SessionAggregate({required this.bucketStartUtc});
}

class _ParsedTrade {
  final DateTime timestampUtc;
  final double notional;
  final bool buyerIsMaker;

  const _ParsedTrade({
    required this.timestampUtc,
    required this.notional,
    required this.buyerIsMaker,
  });
}
