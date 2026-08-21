import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/bingx_futures_market_snapshot_models.dart';
import 'bingx_futures_public_session_accumulator.dart';

const int bingxPublicSessionMaxCompressedFrameBytes = 16384;
const String bingxPublicSwapWebSocket =
    'wss://open-api-swap.bingx.com/swap-market';

typedef BingxPublicWebSocketConnector = Future<WebSocket> Function();

class BingxFuturesPublicSessionStreamService {
  final BingxPublicWebSocketConnector _connect;

  BingxFuturesPublicSessionAccumulator? _accumulator;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Future<void> _connectionSerial = Future<void>.value();
  Object? _terminalError;

  BingxFuturesPublicSessionStreamService({
    BingxPublicWebSocketConnector? connect,
  }) : _connect =
           connect ??
           (() => WebSocket.connect(
             bingxPublicSwapWebSocket,
             headers: const <String, dynamic>{'X-SOURCE-KEY': 'BX-AI-SKILL'},
           ));

  bool get isConnected => _accumulator?.hasHealthyConnection == true;
  String? get symbol => _accumulator?.symbol;
  Object? get terminalError => _terminalError;

  Future<void> ensureConnected(String requestedSymbol) async {
    final normalized = requestedSymbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,20}-USDT$').hasMatch(normalized)) {
      throw const FormatException('invalid public session symbol');
    }
    final operation = _connectionSerial.then<void>((_) async {
      if (_accumulator?.symbol == normalized && isConnected) return;
      await _replaceConnection(normalized);
    });
    _connectionSerial = operation.then<void>((_) {}, onError: (_) {});
    await operation;
  }

  List<BingxFuturesSessionVolumePoint>? snapshotFor(String requestedSymbol) {
    final normalized = requestedSymbol.trim().toUpperCase();
    final accumulator = _accumulator;
    if (accumulator == null || accumulator.symbol != normalized) return null;
    return accumulator.snapshot();
  }

  Future<void> _replaceConnection(String symbol) async {
    await disconnect();
    final accumulator = BingxFuturesPublicSessionAccumulator(symbol: symbol);
    final socket = await _connect();
    const subscriptionId = 'hivra-public-session-trade-v1';
    _terminalError = null;
    _accumulator = accumulator;
    _socket = socket;
    accumulator.beginConnection();
    socket.add(
      jsonEncode(<String, String>{
        'id': subscriptionId,
        'reqType': 'sub',
        'dataType': '$symbol@trade',
      }),
    );
    _subscription = socket.listen(
      (frame) {
        try {
          consumeBingxPublicTradeFrame(
            frame: frame,
            send: socket.add,
            accumulator: accumulator,
            subscriptionId: subscriptionId,
          );
        } on Object catch (error) {
          _terminalError = error;
          accumulator.markDisconnected();
          unawaited(socket.close(WebSocketStatus.policyViolation));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _terminalError = error;
        accumulator.markDisconnected();
      },
      onDone: accumulator.markDisconnected,
      cancelOnError: false,
    );
  }

  Future<void> disconnect() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _accumulator?.markDisconnected();
    if (subscription != null) await subscription.cancel();
    if (socket != null) {
      await socket
          .close(WebSocketStatus.normalClosure, 'session evidence stopped')
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }
  }
}

Future<void> consumeBingxPublicTradeFrames({
  required Stream<dynamic> frames,
  required void Function(Object frame) send,
  required BingxFuturesPublicSessionAccumulator accumulator,
  required String subscriptionId,
}) async {
  try {
    await for (final frame in frames) {
      consumeBingxPublicTradeFrame(
        frame: frame,
        send: send,
        accumulator: accumulator,
        subscriptionId: subscriptionId,
      );
    }
  } finally {
    accumulator.markDisconnected();
  }
}

void consumeBingxPublicTradeFrame({
  required Object frame,
  required void Function(Object frame) send,
  required BingxFuturesPublicSessionAccumulator accumulator,
  required String subscriptionId,
}) {
  final message = decodeBingxPublicFrame(frame);
  if (message == 'Ping') {
    send('Pong');
    accumulator.acceptHeartbeat();
    return;
  }
  final decoded = jsonDecode(message);
  if (decoded is Map<String, dynamic> &&
      decoded['id'] == subscriptionId &&
      decoded['data'] == null) {
    if (decoded['code'] != 0) {
      throw const FormatException('public trade subscription rejected');
    }
    accumulator.acceptHeartbeat();
    return;
  }
  accumulator.acceptDecodedTradeMessage(message);
}

String decodeBingxPublicFrame(Object frame) {
  if (frame is String) {
    if (utf8.encode(frame).length >
        BingxFuturesPublicSessionAccumulator.maxDecodedMessageBytes) {
      throw const FormatException('public trade frame is oversized');
    }
    return frame;
  }
  if (frame is! List<int> ||
      frame.length > bingxPublicSessionMaxCompressedFrameBytes) {
    throw const FormatException('public trade frame is invalid');
  }
  final output = BytesBuilder(copy: false);
  final decodedSink = ByteConversionSink.from(
    _BoundedBytesSink(
      output: output,
      maxBytes: BingxFuturesPublicSessionAccumulator.maxDecodedMessageBytes,
    ),
  );
  final decoder = gzip.decoder.startChunkedConversion(decodedSink);
  decoder.add(frame);
  decoder.close();
  return utf8.decode(output.takeBytes());
}

class _BoundedBytesSink implements Sink<List<int>> {
  final BytesBuilder output;
  final int maxBytes;
  int _length = 0;

  _BoundedBytesSink({required this.output, required this.maxBytes});

  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > maxBytes) {
      throw const FormatException('public trade frame expands beyond limit');
    }
    output.add(data);
  }

  @override
  void close() {}
}
