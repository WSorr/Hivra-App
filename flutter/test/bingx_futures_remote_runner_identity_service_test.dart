import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_remote_runner_identity_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  final service = BingxFuturesRemoteRunnerIdentityService();
  const publicKeyHex =
      '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
  const runnerKeyId =
      '56475aa75463474c0285df5dbf2bcab73da651358839e9b77481b2eab107708c';

  test('normalizes one lowercase runner key id', () {
    expect(service.normalizeRunnerKeyId('  $runnerKeyId\n'), runnerKeyId);
  });

  test('derives the canonical runner id from its public key file', () {
    expect(
      service.runnerKeyIdFromPublicKeyFile('$publicKeyHex\n'),
      runnerKeyId,
    );
  });

  test('rejects malformed and ambiguous runner identity input', () {
    expect(service.normalizeRunnerKeyId(runnerKeyId.toUpperCase()), isNull);
    expect(service.normalizeRunnerKeyId('${runnerKeyId}0'), isNull);
    expect(
      service.normalizeRunnerKeyId('g${runnerKeyId.substring(1)}'),
      isNull,
    );
    expect(
      service.runnerKeyIdFromPublicKeyFile('$publicKeyHex\n$publicKeyHex'),
      isNull,
    );
  });

  test(
    'verifies and persists one exact Capsule-scoped runner anchor',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'hivra-runner-anchor-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final anchor = Directory('${temp.path}/anchor')..createSync();
      File(
        '${anchor.path}/runner-public-key.ed25519.hex',
      ).writeAsStringSync('$publicKeyHex\n');
      File(
        '${anchor.path}/shadow-evidence.v1.json',
      ).writeAsStringSync(_goldenEvidenceWire());
      final capsuleHex = List<String>.filled(64, 'a').join();
      final boundService = BingxFuturesRemoteRunnerIdentityService(
        readActiveCapsuleRootHex: () => capsuleHex,
        files: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
        ),
      );

      final binding = await boundService.verifyAnchorDirectory(anchor.path);
      expect(binding.runnerKeyId, runnerKeyId);
      expect(binding.anchorSequence, 1);
      await boundService.saveVerifiedBinding(
        binding,
        expectedCapsuleRootHex: capsuleHex,
      );

      final restored = await boundService.loadVerifiedBinding();
      expect(restored?.canonicalJson, binding.canonicalJson);
      expect(_bindingFile(temp.path, capsuleHex).existsSync(), isTrue);
      final persisted = _bindingFile(temp.path, capsuleHex);
      final tampered = jsonDecode(persisted.readAsStringSync());
      tampered['runner_build_id'] = 'attacker-build';
      persisted.writeAsStringSync(jsonEncode(tampered));
      expect(await boundService.loadVerifiedBinding(), isNull);
    },
  );

  test('rejects tampered evidence and ambiguous anchor contents', () async {
    final temp = await Directory.systemTemp.createTemp('hivra-runner-anchor-');
    addTearDown(() => temp.delete(recursive: true));
    final anchor = Directory('${temp.path}/anchor')..createSync();
    File(
      '${anchor.path}/runner-public-key.ed25519.hex',
    ).writeAsStringSync('$publicKeyHex\n');
    final evidenceFile = File('${anchor.path}/shadow-evidence.v1.json');
    final evidence = jsonDecode(_goldenEvidenceWire()) as Map<String, dynamic>;
    final signature = evidence['signature_hex'] as String;
    evidence['signature_hex'] =
        '${signature[0] == '0' ? '1' : '0'}${signature.substring(1)}';
    evidenceFile.writeAsStringSync(jsonEncode(evidence));

    await expectLater(
      service.verifyAnchorDirectory(anchor.path),
      throwsFormatException,
    );

    evidenceFile.writeAsStringSync(_goldenEvidenceWire());
    File('${anchor.path}/unexpected.txt').writeAsStringSync('foreign');
    await expectLater(
      service.verifyAnchorDirectory(anchor.path),
      throwsFormatException,
    );
  });

  test('deletes the exact binding idempotently', () async {
    final temp = await Directory.systemTemp.createTemp('hivra-runner-delete-');
    addTearDown(() => temp.delete(recursive: true));
    final anchor = Directory('${temp.path}/anchor')..createSync();
    File(
      '${anchor.path}/runner-public-key.ed25519.hex',
    ).writeAsStringSync('$publicKeyHex\n');
    File(
      '${anchor.path}/shadow-evidence.v1.json',
    ).writeAsStringSync(_goldenEvidenceWire());
    final capsuleHex = List<String>.filled(64, 'a').join();
    final boundService = BingxFuturesRemoteRunnerIdentityService(
      readActiveCapsuleRootHex: () => capsuleHex,
      files: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
      ),
    );
    final binding = await boundService.verifyAnchorDirectory(anchor.path);
    await boundService.saveVerifiedBinding(
      binding,
      expectedCapsuleRootHex: capsuleHex,
    );

    await boundService.deleteVerifiedBinding(
      expectedRunnerKeyId: binding.runnerKeyId,
    );
    await boundService.deleteVerifiedBinding(
      expectedRunnerKeyId: binding.runnerKeyId,
    );

    expect(_bindingFile(temp.path, capsuleHex).existsSync(), isFalse);
  });

  test('refuses to persist a verified anchor after Capsule switch', () async {
    final temp = await Directory.systemTemp.createTemp('hivra-runner-owner-');
    addTearDown(() => temp.delete(recursive: true));
    var activeCapsule = List<String>.filled(64, 'a').join();
    final boundService = BingxFuturesRemoteRunnerIdentityService(
      readActiveCapsuleRootHex: () => activeCapsule,
      files: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
      ),
    );
    final binding = BingxFuturesRemoteRunnerBinding(
      runnerKeyId: runnerKeyId,
      publicKeyHex: publicKeyHex,
      runnerBuildId: 'runner-build',
      pluginVersion: 'plugin-version',
      packageDigestHex: List<String>.filled(64, 'b').join(),
      anchorSequence: 1,
      anchorEvidenceHashHex: List<String>.filled(64, 'c').join(),
      anchorEvidenceJson: _goldenEvidenceWire(),
    );
    final expectedCapsule = activeCapsule;
    activeCapsule = List<String>.filled(64, 'd').join();

    await expectLater(
      boundService.saveVerifiedBinding(
        binding,
        expectedCapsuleRootHex: expectedCapsule,
      ),
      throwsStateError,
    );
    expect(_bindingFile(temp.path, activeCapsule).existsSync(), isFalse);
  });

  test(
    'refuses direct persistence of unauthenticated binding fields',
    () async {
      final temp = await Directory.systemTemp.createTemp('hivra-runner-write-');
      addTearDown(() => temp.delete(recursive: true));
      final capsuleHex = List<String>.filled(64, 'a').join();
      final boundService = BingxFuturesRemoteRunnerIdentityService(
        readActiveCapsuleRootHex: () => capsuleHex,
        files: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
        ),
      );
      final binding = BingxFuturesRemoteRunnerBinding(
        runnerKeyId: runnerKeyId,
        publicKeyHex: publicKeyHex,
        runnerBuildId: 'attacker-build',
        pluginVersion: 'plugin-version',
        packageDigestHex: List<String>.filled(64, 'b').join(),
        anchorSequence: 1,
        anchorEvidenceHashHex: List<String>.filled(64, 'c').join(),
        anchorEvidenceJson: _goldenEvidenceWire(),
      );

      await expectLater(
        boundService.saveVerifiedBinding(
          binding,
          expectedCapsuleRootHex: capsuleHex,
        ),
        throwsFormatException,
      );
      expect(_bindingFile(temp.path, capsuleHex).existsSync(), isFalse);
    },
  );

  test('refuses a valid signed anchor for another plugin', () async {
    final temp = await Directory.systemTemp.createTemp('hivra-runner-plugin-');
    addTearDown(() => temp.delete(recursive: true));
    final capsuleHex = List<String>.filled(64, 'a').join();
    final boundService = BingxFuturesRemoteRunnerIdentityService(
      readActiveCapsuleRootHex: () => capsuleHex,
      files: CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
      ),
    );
    final evidence = await _signedEvidenceForPlugin('hivra.other-plugin');
    final binding = BingxFuturesRemoteRunnerBinding(
      runnerKeyId: evidence.runnerKeyId,
      publicKeyHex: publicKeyHex,
      runnerBuildId: evidence.runnerBuildId,
      pluginVersion: evidence.pluginVersion,
      packageDigestHex: evidence.packageDigestHex,
      anchorSequence: evidence.sequence,
      anchorEvidenceHashHex: evidence.evidenceHashHex,
      anchorEvidenceJson: utf8.decode(evidence.wireBytes),
    );

    await expectLater(
      boundService.saveVerifiedBinding(
        binding,
        expectedCapsuleRootHex: capsuleHex,
      ),
      throwsFormatException,
    );
  });
}

String _goldenEvidenceWire() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/trading_shadow_evidence_v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return fixture['expected_wire_utf8'] as String;
}

File _bindingFile(String home, String capsuleHex) => File(
  '$home/Library/Application Support/Hivra/capsules/'
  '$capsuleHex/plugin_state/hivra.contract.bingx-futures-trading.v1/'
  'remote_runner_binding.v1.json',
);

Future<BingxFuturesShadowEvidence> _signedEvidenceForPlugin(
  String pluginId,
) async {
  const harness = BingxFuturesDeterministicReplayHarnessService();
  final source = harness.parseShadowEvidence(
    utf8.encode(_goldenEvidenceWire()),
  );
  final unsigned = BingxFuturesShadowEvidence(
    contractVersion: source.contractVersion,
    runnerBuildId: source.runnerBuildId,
    pluginId: pluginId,
    pluginVersion: source.pluginVersion,
    packageDigestHex: source.packageDigestHex,
    hostAbi: source.hostAbi,
    policyHashHex: source.policyHashHex,
    marketSnapshotHashHex: source.marketSnapshotHashHex,
    featureHashHex: source.featureHashHex,
    decisionHashHex: source.decisionHashHex,
    decision: source.decision,
    marketSymbol: source.marketSymbol,
    marketProposalStatus: source.marketProposalStatus,
    marketProposalJson: source.marketProposalJson,
    observedAtEpochMs: source.observedAtEpochMs,
    validUntilEpochMs: source.validUntilEpochMs,
    sequence: source.sequence,
    previousEvidenceHashHex: source.previousEvidenceHashHex,
    runnerKeyId: source.runnerKeyId,
  );
  final keyPair = await Ed25519().newKeyPairFromSeed(
    List<int>.generate(32, (index) => index),
  );
  final signature = await Ed25519().sign(
    unsigned.signingPayload,
    keyPair: keyPair,
  );
  return unsigned.withSignature(
    signature.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
  );
}
