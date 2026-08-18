import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_shadow_stream_store.dart';

const int maxScheduledRuns = 288;
const int minScheduleIntervalSeconds = 60;
const int maxScheduleIntervalSeconds = 3600;

typedef TradingRemoteShadowCycle = Future<void> Function(int cycleNumber);
typedef TradingRemoteShadowDelay = Future<void> Function(Duration duration);

Future<void> main(List<String> args) async {
  try {
    final options = _parseArgs(args);
    final schedule = _parseSchedule(options);
    final signingKey = await Ed25519().newKeyPairFromSeed(
      await readRunnerSeedBytes(options),
    );
    final publicKey = await signingKey.extractPublicKey();
    final stream = BingxFuturesShadowStreamStore(
      directory: Directory(_required(options, 'stream-dir')),
    );
    final marketData = BingxFuturesExchangeService();
    await runBoundedShadowSchedule(
      runCount: schedule.runCount,
      interval: schedule.interval,
      runOnce: (cycleNumber) async {
        final evidence = await stream.append(
          trustedRunnerKey: publicKey,
          produce:
              (sequence, previousEvidenceHashHex) =>
                  const BingxFuturesDeterministicReplayHarnessService()
                      .runLivePublicShadow(
                        marketData: marketData,
                        symbol: _required(options, 'symbol'),
                        signingKey: signingKey,
                        runnerBuildId: _required(options, 'runner-build-id'),
                        pluginId: _required(options, 'plugin-id'),
                        pluginVersion: _required(options, 'plugin-version'),
                        packageDigestHex: _required(
                          options,
                          'package-digest-hex',
                        ),
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
      delay: Future<void>.delayed,
    );
  } on Object catch (error) {
    stderr.writeln('trading shadow probe failed: $error');
    exitCode = 1;
  }
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
