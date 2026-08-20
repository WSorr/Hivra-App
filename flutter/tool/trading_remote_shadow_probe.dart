import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_live_snapshot_builder_service.dart';
import 'package:hivra_app/services/bingx_futures_public_session_accumulator.dart';
import 'package:hivra_app/services/bingx_futures_shadow_stream_store.dart';

const int maxScheduledRuns = 8928;
const int minScheduleIntervalSeconds = 60;
const int maxScheduleIntervalSeconds = 3600;
const String publicShadowMode = 'public-shadow';
const String accountReadMode = 'account-read';
const String accountReadEvidenceVersion =
    'hivra-trading-account-read-evidence-v2';
const String accountReadScopeWire = 'balance,positions,open_orders';
const List<String> accountReadScope = <String>[
  'balance',
  'positions',
  'open_orders',
];
const int accountReadMaxUses = 1;
const int maxCompressedTradeFrameBytes = 16384;
const String bingxPublicSwapWebSocket =
    'wss://open-api-swap.bingx.com/swap-market';

typedef TradingRemoteShadowCycle = Future<void> Function(int cycleNumber);
typedef TradingRemoteShadowDelay = Future<void> Function(Duration duration);

Future<void> main(List<String> args) async {
  final requestedMode = _requestedMode(args);
  try {
    final options = _parseArgs(args);
    final mode = options['mode'] ?? publicShadowMode;
    _validateModeOptions(options, mode);
    final seedBytes = await readRunnerSeedBytes(options);
    if (mode == accountReadMode) {
      stdout.writeln(
        await runMandateBoundAccountRead(
          options: options,
          runnerSeedBytes: seedBytes,
        ),
      );
      return;
    }
    final schedule = _parseSchedule(options);
    final signingKey = await Ed25519().newKeyPairFromSeed(seedBytes);
    final publicKey = await signingKey.extractPublicKey();
    final stream = BingxFuturesShadowStreamStore(
      directory: Directory(_required(options, 'stream-dir')),
    );
    final marketData = BingxFuturesExchangeService();
    final symbol = _required(options, 'symbol');
    final accumulator = BingxFuturesPublicSessionAccumulator(symbol: symbol);
    final socket = await WebSocket.connect(
      bingxPublicSwapWebSocket,
      headers: const <String, dynamic>{'X-SOURCE-KEY': 'BX-AI-SKILL'},
    );
    await runPublicShadowWithSessionStream(
      socket: socket,
      accumulator: accumulator,
      runCount: schedule.runCount,
      interval: schedule.interval,
      runOnce: (cycleNumber) async {
        if (!accumulator.isConnected) {
          throw StateError('public trade stream disconnected');
        }
        final evidenceOwner = BingxFuturesDeterministicReplayHarnessService(
          loadLiveSnapshot:
              ({required exchange, required symbol}) =>
                  const BingxFuturesLiveSnapshotBuilderService().fetchAndBuild(
                    exchange: exchange,
                    symbol: symbol,
                    sessionVolumes: accumulator.snapshot(),
                  ),
        );
        final evidence = await stream.append(
          trustedRunnerKey: publicKey,
          produce:
              (sequence, previousEvidenceHashHex) =>
                  evidenceOwner.runLivePublicShadow(
                    marketData: marketData,
                    symbol: symbol,
                    signingKey: signingKey,
                    runnerBuildId: _required(options, 'runner-build-id'),
                    pluginId: _required(options, 'plugin-id'),
                    pluginVersion: _required(options, 'plugin-version'),
                    packageDigestHex: _required(options, 'package-digest-hex'),
                    hostAbi: _required(options, 'host-abi'),
                    observedAtUtc: DateTime.now().toUtc(),
                    sequence: sequence,
                    previousEvidenceHashHex: previousEvidenceHashHex,
                  ),
        );
        stdout.writeln(
          'shadow_evidence_appended=${evidence.sequence} '
          'runner_key_id=${evidence.runnerKeyId} '
          'runner_public_key_hex=${_encodeHex(publicKey.bytes)} '
          'evidence_hash=${evidence.evidenceHashHex} '
          'cycle=$cycleNumber/${schedule.runCount}',
        );
      },
    );
  } on Object catch (error) {
    stderr.writeln(
      requestedMode == accountReadMode
          ? 'trading account read failed'
          : 'trading shadow probe failed: $error',
    );
    exitCode = 1;
  }
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}

Future<void> runPublicShadowWithSessionStream({
  required WebSocket socket,
  required BingxFuturesPublicSessionAccumulator accumulator,
  required int runCount,
  required Duration? interval,
  required TradingRemoteShadowCycle runOnce,
}) async {
  const subscriptionId = 'hivra-public-session-trade-v1';
  accumulator.beginConnection();
  socket.add(
    jsonEncode(<String, String>{
      'id': subscriptionId,
      'reqType': 'sub',
      'dataType': '${accumulator.symbol}@trade',
    }),
  );
  Object? streamError;
  StackTrace? streamStackTrace;
  final frameRelay = StreamController<dynamic>();
  final socketSubscription = socket.listen(
    frameRelay.add,
    onError: frameRelay.addError,
    onDone: frameRelay.close,
    cancelOnError: false,
  );
  final streamTask = consumeBingxPublicTradeFrames(
    frames: frameRelay.stream,
    send: socket.add,
    accumulator: accumulator,
    subscriptionId: subscriptionId,
  ).catchError((Object error, StackTrace stackTrace) {
    streamError = error;
    streamStackTrace = stackTrace;
  });
  void requireHealthyStream() {
    final error = streamError;
    if (error != null) {
      Error.throwWithStackTrace(error, streamStackTrace!);
    }
    if (!accumulator.isConnected) {
      throw StateError('public trade stream disconnected');
    }
  }

  try {
    await runBoundedShadowSchedule(
      runCount: runCount,
      interval: interval,
      runOnce: (cycleNumber) async {
        requireHealthyStream();
        await runOnce(cycleNumber);
        requireHealthyStream();
      },
      delay: (duration) async {
        await Future.any<void>(<Future<void>>[
          Future<void>.delayed(duration),
          streamTask,
        ]);
        requireHealthyStream();
      },
    );
  } finally {
    await socket
        .close(WebSocketStatus.normalClosure, 'bounded cycle complete')
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    await socketSubscription.cancel();
    if (!frameRelay.isClosed) await frameRelay.close();
    await streamTask;
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
      final message = decodeBingxPublicFrame(frame);
      if (message == 'Ping') {
        send('Pong');
        accumulator.acceptHeartbeat();
        continue;
      }
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic> &&
          decoded['id'] == subscriptionId &&
          decoded['data'] == null) {
        if (decoded['code'] != 0) {
          throw const FormatException('public trade subscription rejected');
        }
        accumulator.acceptHeartbeat();
        continue;
      }
      accumulator.acceptDecodedTradeMessage(message);
    }
  } finally {
    accumulator.markDisconnected();
  }
}

String decodeBingxPublicFrame(Object frame) {
  if (frame is String) {
    if (utf8.encode(frame).length >
        BingxFuturesPublicSessionAccumulator.maxDecodedMessageBytes) {
      throw const FormatException('public trade frame is oversized');
    }
    return frame;
  }
  if (frame is! List<int> || frame.length > maxCompressedTradeFrameBytes) {
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
  final decoded = output.takeBytes();
  return utf8.decode(decoded);
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

Future<String> runMandateBoundAccountRead({
  required Map<String, String> options,
  required List<int> runnerSeedBytes,
  BingxHttpRequestSender? requestSender,
  DateTime Function()? nowUtc,
  int Function()? clockMs,
}) async {
  _validateModeOptions(options, accountReadMode);
  final expectedRunnerKeyId = _requiredHex64(options, 'expected-runner-key-id');
  final expectedAccountBinding = _requiredHex64(
    options,
    'expected-account-binding-hash',
  );
  final accountReadOperationId = _requiredHex64(
    options,
    'account-read-operation-id',
  );
  if (_required(options, 'account-read-scope') != accountReadScopeWire ||
      _required(options, 'account-read-max-uses') != '$accountReadMaxUses') {
    throw const FormatException('account read authority is not exact');
  }
  final expiresRaw = _required(options, 'account-read-expires-at-utc');
  final expiresAtUtc = DateTime.tryParse(expiresRaw);
  if (expiresAtUtc == null ||
      !expiresAtUtc.isUtc ||
      !expiresRaw.endsWith('Z')) {
    throw const FormatException('mandate expiry must be UTC');
  }
  final observedAtUtc = (nowUtc ?? () => DateTime.now().toUtc())().toUtc();
  if (!observedAtUtc.isBefore(expiresAtUtc)) {
    throw const FormatException('mandate is expired');
  }

  final signingKey = await Ed25519().newKeyPairFromSeed(runnerSeedBytes);
  final publicKey = await signingKey.extractPublicKey();
  final actualRunnerKeyId = sha256.convert(publicKey.bytes).toString();
  if (actualRunnerKeyId != expectedRunnerKeyId) {
    throw const FormatException('runner identity mismatch');
  }

  final credentials = await readExchangeCredentialFile(
    _required(options, 'account-read-credential-file'),
  );
  final actualAccountBinding =
      sha256.convert(utf8.encode(credentials.apiKey)).toString();
  if (actualAccountBinding != expectedAccountBinding) {
    throw const FormatException('exchange account binding mismatch');
  }

  final exchange = BingxFuturesExchangeService(
    requestSender: requestSender,
    clockMs: clockMs,
  );
  final balance = await exchange.getUserBalance(credentials: credentials);
  if (!balance.isSuccess) throw StateError('balance read failed');
  final positions = await exchange.getUserPositions(credentials: credentials);
  if (!positions.isSuccess) throw StateError('positions read failed');
  final openOrders = await exchange.getOpenOrders(credentials: credentials);
  if (!openOrders.isSuccess) throw StateError('open orders read failed');

  return jsonEncode(<String, dynamic>{
    'contract_version': accountReadEvidenceVersion,
    'account_read_operation_id': accountReadOperationId,
    'runner_key_id': expectedRunnerKeyId,
    'account_binding_hash_hex': expectedAccountBinding,
    'read_scope': accountReadScope,
    'max_uses': accountReadMaxUses,
    'observed_at_utc': observedAtUtc.toIso8601String(),
    'checks': <Map<String, dynamic>>[
      <String, dynamic>{'name': 'balance', 'success': true},
      <String, dynamic>{'name': 'positions', 'success': true},
      <String, dynamic>{'name': 'open_orders', 'success': true},
    ],
    'effect': false,
  });
}

Future<BingxFuturesApiCredentials> readExchangeCredentialFile(
  String path,
) async {
  final file = File(path);
  if (!file.isAbsolute ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException(
      'exchange credential file must be one absolute regular file',
    );
  }
  final stat = await file.stat();
  if (stat.size < 1 || stat.size > 2048) {
    throw const FormatException('exchange credential file is not bounded');
  }
  if (!exchangeCredentialFilePermissionsAreSafe(path, stat.mode)) {
    throw const FormatException(
      'exchange credential file permissions are not private',
    );
  }
  final bytes = await file.readAsBytes();
  if (bytes.any((value) => value > 0x7f)) {
    throw const FormatException('exchange credential file must be ASCII');
  }
  final text = ascii.decode(bytes);
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('exchange credential file is not strict JSON');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded.keys.join(',') != 'contract_version,api_key,api_secret' ||
      decoded['contract_version'] != 'bingx-exchange-credential-v1' ||
      jsonEncode(decoded) != text) {
    throw const FormatException(
      'exchange credential file shape is not canonical',
    );
  }
  final apiKey = decoded['api_key'];
  final apiSecret = decoded['api_secret'];
  if (apiKey is! String ||
      apiSecret is! String ||
      apiKey.length > 512 ||
      apiSecret.length > 512) {
    throw const FormatException('exchange credential fields are invalid');
  }
  return BingxFuturesApiCredentials(
    apiKey: apiKey,
    apiSecret: apiSecret,
  ).normalized();
}

bool exchangeCredentialFilePermissionsAreSafe(String path, int mode) {
  final permissions = mode & 0x1ff;
  final systemdCredential = RegExp(
    r'^/run/credentials/[A-Za-z0-9_.@-]+\.service/bingx-exchange$',
  ).hasMatch(path);
  if (systemdCredential) return permissions == 0x120;
  return permissions & 0x3f == 0;
}

Future<void> runBoundedShadowSchedule({
  required int runCount,
  required Duration? interval,
  required TradingRemoteShadowCycle runOnce,
  required TradingRemoteShadowDelay delay,
}) async {
  _validateSchedule(runCount: runCount, interval: interval);
  for (var cycleNumber = 1; cycleNumber <= runCount; cycleNumber++) {
    await runOnce(cycleNumber);
    if (cycleNumber < runCount) {
      await delay(interval!);
    }
  }
}

Map<String, String> _parseArgs(List<String> args) {
  const allowed = <String>{
    'mode',
    'symbol',
    'runner-build-id',
    'plugin-id',
    'plugin-version',
    'package-digest-hex',
    'host-abi',
    'stream-dir',
    'runner-seed-file',
    'run-count',
    'interval-seconds',
    'account-read-credential-file',
    'expected-runner-key-id',
    'expected-account-binding-hash',
    'account-read-operation-id',
    'account-read-scope',
    'account-read-max-uses',
    'account-read-expires-at-utc',
  };
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--') ||
        index + 1 >= args.length ||
        args[index + 1].startsWith('--')) {
      throw FormatException('invalid argument: $argument');
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || parsed.containsKey(key)) {
      throw FormatException('unsupported or duplicate argument: $argument');
    }
    parsed[key] = args[++index];
  }
  return parsed;
}

String? _requestedMode(List<String> args) {
  for (var index = 0; index + 1 < args.length; index++) {
    if (args[index] == '--mode') return args[index + 1];
  }
  return null;
}

void _validateModeOptions(Map<String, String> options, String mode) {
  const publicOnly = <String>{
    'symbol',
    'runner-build-id',
    'plugin-id',
    'plugin-version',
    'package-digest-hex',
    'host-abi',
    'stream-dir',
    'run-count',
    'interval-seconds',
  };
  const accountOnly = <String>{
    'account-read-credential-file',
    'expected-account-binding-hash',
    'account-read-operation-id',
    'account-read-scope',
    'account-read-max-uses',
    'account-read-expires-at-utc',
  };
  if (mode != publicShadowMode && mode != accountReadMode) {
    throw const FormatException('unsupported runner mode');
  }
  final forbidden = switch (mode) {
    publicShadowMode => accountOnly,
    _ => publicOnly,
  };
  if (forbidden.any(options.containsKey)) {
    throw const FormatException('runner mode options are ambiguous');
  }
  if (mode == accountReadMode &&
      (accountOnly.any((key) => (options[key]?.trim() ?? '').isEmpty) ||
          (options['expected-runner-key-id']?.trim() ?? '').isEmpty)) {
    throw const FormatException('account read options are incomplete');
  }
}

Future<List<int>> readRunnerSeedBytes(
  Map<String, String> options, {
  Map<String, String>? environment,
}) async {
  final seedFilePath = options['runner-seed-file'];
  final seedFromEnvironment =
      (environment ?? Platform.environment)['HIVRA_SHADOW_RUNNER_SEED_HEX'];
  if (seedFilePath != null && seedFromEnvironment != null) {
    throw const FormatException('runner seed sources are ambiguous');
  }
  if (seedFilePath == null) {
    return _decodeSeed(seedFromEnvironment ?? '');
  }
  if (!File(seedFilePath).isAbsolute ||
      FileSystemEntity.typeSync(seedFilePath, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException(
      'runner seed file must be one absolute regular file',
    );
  }
  final stat = await File(seedFilePath).stat();
  if (!runnerSeedFilePermissionsAreSafe(seedFilePath, stat.mode)) {
    throw const FormatException('runner seed file permissions are not private');
  }
  return _decodeSeed(await File(seedFilePath).readAsString());
}

bool runnerSeedFilePermissionsAreSafe(String path, int mode) {
  final permissions = mode & 0x1ff;
  final systemdCredential = RegExp(
    r'^/run/credentials/[A-Za-z0-9_.@-]+\.service/runner-seed$',
  ).hasMatch(path);
  if (systemdCredential) return permissions == 0x120;
  return permissions & 0x3f == 0;
}

({int runCount, Duration? interval}) _parseSchedule(
  Map<String, String> options,
) {
  final runCount = _parseInteger(options['run-count'] ?? '1', 'run-count');
  final intervalSeconds = switch (options['interval-seconds']) {
    final value? => _parseInteger(value, 'interval-seconds'),
    null => null,
  };
  final interval =
      intervalSeconds == null ? null : Duration(seconds: intervalSeconds);
  _validateSchedule(runCount: runCount, interval: interval);
  return (runCount: runCount, interval: interval);
}

void _validateSchedule({required int runCount, required Duration? interval}) {
  if (runCount < 1 || runCount > maxScheduledRuns) {
    throw const FormatException('run-count is outside the bounded range');
  }
  if (runCount == 1 && interval != null) {
    throw const FormatException('interval-seconds requires multiple runs');
  }
  if (runCount > 1 && interval == null) {
    throw const FormatException('multiple runs require interval-seconds');
  }
  if (interval != null &&
      (interval.inSeconds < minScheduleIntervalSeconds ||
          interval.inSeconds > maxScheduleIntervalSeconds ||
          interval != Duration(seconds: interval.inSeconds))) {
    throw const FormatException(
      'interval-seconds is outside the bounded range',
    );
  }
}

int _parseInteger(String value, String label) {
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
    throw FormatException('$label must be a decimal integer');
  }
  return int.parse(value);
}

String _required(Map<String, String> options, String key) {
  final value = options[key]?.trim() ?? '';
  if (value.isEmpty) throw FormatException('missing --$key');
  return value;
}

String _requiredHex64(Map<String, String> options, String key) {
  final value = _required(options, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('--$key must be 64-character lowercase hex');
  }
  return value;
}

List<int> _decodeSeed(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException(
      'HIVRA_SHADOW_RUNNER_SEED_HEX must be 32-byte lowercase hex',
    );
  }
  return List<int>.generate(
    32,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}

String _encodeHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
