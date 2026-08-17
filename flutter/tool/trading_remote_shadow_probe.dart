import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_shadow_stream_store.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _parseArgs(args);
    final seedHex = Platform.environment['HIVRA_SHADOW_RUNNER_SEED_HEX'] ?? '';
    final signingKey = await Ed25519().newKeyPairFromSeed(_decodeSeed(seedHex));
    final publicKey = await signingKey.extractPublicKey();
    final stream = BingxFuturesShadowStreamStore(
      directory: Directory(_required(options, 'stream-dir')),
    );
    final evidence = await stream.append(
      trustedRunnerKey: publicKey,
      produce:
          (sequence, previousEvidenceHashHex) =>
              const BingxFuturesDeterministicReplayHarnessService()
                  .runLivePublicShadow(
                    marketData: BingxFuturesExchangeService(),
                    symbol: _required(options, 'symbol'),
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
      'evidence_hash=${evidence.evidenceHashHex}',
    );
  } on Object catch (error) {
    stderr.writeln('trading shadow probe failed: $error');
    exitCode = 1;
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
