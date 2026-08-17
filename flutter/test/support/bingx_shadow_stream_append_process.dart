import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_shadow_stream_store.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) exit(64);
  final signingKey = await Ed25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  final publicKey = await signingKey.extractPublicKey();
  final store = BingxFuturesShadowStreamStore(
    directory: Directory(arguments.single),
  );
  await store.append(
    trustedRunnerKey: publicKey,
    produce:
        (sequence, previousHash) =>
            _evidence(sequence, previousHash, signingKey, publicKey),
  );
}

Future<BingxFuturesShadowEvidence> _evidence(
  int sequence,
  String previousEvidenceHashHex,
  SimpleKeyPair signingKey,
  SimplePublicKey publicKey,
) async {
  const owner = BingxFuturesDeterministicReplayHarnessService();
  final unsigned = BingxFuturesShadowEvidence(
    runnerBuildId: 'runner-build-process-test',
    pluginId: 'hivra.bingx-futures-trading',
    pluginVersion: '0.2.7-plugins',
    packageDigestHex: '1' * 64,
    hostAbi: 'dart-headless-v1',
    policyHashHex: '2' * 64,
    marketSnapshotHashHex: '3' * 64,
    featureHashHex: '4' * 64,
    decisionHashHex: '5' * 64,
    decision: 'long',
    observedAtEpochMs: 1770000000000 + sequence,
    validUntilEpochMs: 1770000060000 + sequence,
    sequence: sequence,
    previousEvidenceHashHex: previousEvidenceHashHex,
    runnerKeyId: owner.runnerKeyId(publicKey),
  );
  final signature = await Ed25519().sign(
    unsigned.signingPayload,
    keyPair: signingKey,
  );
  return unsigned.withSignature(
    signature.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join(),
  );
}
