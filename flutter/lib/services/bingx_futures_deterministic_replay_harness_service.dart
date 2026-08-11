import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/bingx_futures_market_snapshot_models.dart';
import '../models/bingx_futures_tvh_rule_models.dart';
import 'bingx_futures_feature_extractor_service.dart';
import 'bingx_futures_market_snapshot_service.dart';
import 'bingx_futures_tvh_rule_engine_service.dart';

const _shadowEvidenceDomain = 'hivra:trading-shadow-evidence:v1\n';
const _emptyShadowEvidenceHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

enum BingxFuturesShadowEvidenceVerdict {
  accepted,
  exactReplay,
  malformed,
  oversized,
  unsupportedContract,
  unsupportedSignatureSuite,
  wrongRunner,
  buildDrift,
  pluginDrift,
  policyDrift,
  localParityMismatch,
  stale,
  notYetValid,
  sequenceConflict,
  chainFork,
  invalidSignature,
}

class BingxFuturesShadowEvidence {
  final String contractVersion;
  final String runnerBuildId;
  final String pluginId;
  final String pluginVersion;
  final String packageDigestHex;
  final String hostAbi;
  final String policyHashHex;
  final String marketSnapshotHashHex;
  final String featureHashHex;
  final String decisionHashHex;
  final String decision;
  final int observedAtEpochMs;
  final int validUntilEpochMs;
  final int sequence;
  final String previousEvidenceHashHex;
  final String runnerKeyId;
  final String signatureSuite;
  final String signatureHex;

  const BingxFuturesShadowEvidence({
    this.contractVersion = 'trading-shadow-evidence-v1',
    required this.runnerBuildId,
    required this.pluginId,
    required this.pluginVersion,
    required this.packageDigestHex,
    required this.hostAbi,
    required this.policyHashHex,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.decisionHashHex,
    required this.decision,
    required this.observedAtEpochMs,
    required this.validUntilEpochMs,
    required this.sequence,
    required this.previousEvidenceHashHex,
    required this.runnerKeyId,
    this.signatureSuite = 'ed25519-v1',
    this.signatureHex = '',
  });

  Map<String, dynamic> get semanticMap => <String, dynamic>{
    'contract_version': contractVersion,
    'runner_build_id': runnerBuildId,
    'plugin_id': pluginId,
    'plugin_version': pluginVersion,
    'package_digest_hex': packageDigestHex,
    'host_abi': hostAbi,
    'policy_hash_hex': policyHashHex,
    'market_snapshot_hash_hex': marketSnapshotHashHex,
    'feature_hash_hex': featureHashHex,
    'decision_hash_hex': decisionHashHex,
    'decision': decision,
    'observed_at_epoch_ms': observedAtEpochMs,
    'valid_until_epoch_ms': validUntilEpochMs,
    'sequence': sequence,
    'previous_evidence_hash_hex': previousEvidenceHashHex,
    'runner_key_id': runnerKeyId,
    'signature_suite': signatureSuite,
  };

  String get semanticJson => jsonEncode(semanticMap);

  List<int> get signingPayload =>
      utf8.encode('$_shadowEvidenceDomain$semanticJson');

  String get evidenceHashHex => sha256.convert(signingPayload).toString();

  int get encodedLength =>
      utf8
          .encode(
            jsonEncode(<String, dynamic>{
              ...semanticMap,
              'signature_hex': signatureHex,
            }),
          )
          .length;

  BingxFuturesShadowEvidence withSignature(String value) {
    return BingxFuturesShadowEvidence(
      contractVersion: contractVersion,
      runnerBuildId: runnerBuildId,
      pluginId: pluginId,
      pluginVersion: pluginVersion,
      packageDigestHex: packageDigestHex,
      hostAbi: hostAbi,
      policyHashHex: policyHashHex,
      marketSnapshotHashHex: marketSnapshotHashHex,
      featureHashHex: featureHashHex,
      decisionHashHex: decisionHashHex,
      decision: decision,
      observedAtEpochMs: observedAtEpochMs,
      validUntilEpochMs: validUntilEpochMs,
      sequence: sequence,
      previousEvidenceHashHex: previousEvidenceHashHex,
      runnerKeyId: runnerKeyId,
      signatureSuite: signatureSuite,
      signatureHex: value,
    );
  }
}

class BingxFuturesReplayFixture {
  final String id;
  final BingxFuturesMarketSnapshotInput snapshotInput;
  final String fundingRateDecimal;
  final bool isConsensusSignable;
  final List<String> blockingFactCodes;
  final BingxTvhDecisionKind expectedDecision;
  final String expectedReasonCode;

  const BingxFuturesReplayFixture({
    required this.id,
    required this.snapshotInput,
    required this.fundingRateDecimal,
    required this.isConsensusSignable,
    this.blockingFactCodes = const <String>[],
    required this.expectedDecision,
    required this.expectedReasonCode,
  });
}

class BingxFuturesReplayRunResult {
  final String fixtureId;
  final String marketSnapshotHashHex;
  final String featureHashHex;
  final String decisionHashHex;
  final BingxTvhDecisionKind decision;
  final String topReasonCode;

  const BingxFuturesReplayRunResult({
    required this.fixtureId,
    required this.marketSnapshotHashHex,
    required this.featureHashHex,
    required this.decisionHashHex,
    required this.decision,
    required this.topReasonCode,
  });
}

class BingxFuturesDeterministicReplayHarnessService {
  final BingxFuturesMarketSnapshotService _snapshotService;
  final BingxFuturesFeatureExtractorService _featureExtractor;
  final BingxFuturesTvhRuleEngineService _ruleEngine;
  final BingxTvhPolicy _policy;

  const BingxFuturesDeterministicReplayHarnessService({
    BingxFuturesMarketSnapshotService snapshotService =
        const BingxFuturesMarketSnapshotService(),
    BingxFuturesFeatureExtractorService featureExtractor =
        const BingxFuturesFeatureExtractorService(),
    BingxFuturesTvhRuleEngineService ruleEngine =
        const BingxFuturesTvhRuleEngineService(),
    BingxTvhPolicy policy = const BingxTvhPolicy(),
  }) : _snapshotService = snapshotService,
       _featureExtractor = featureExtractor,
       _ruleEngine = ruleEngine,
       _policy = policy;

  BingxFuturesReplayRunResult runFixture(BingxFuturesReplayFixture fixture) {
    final snapshotDigest = _snapshotService.build(fixture.snapshotInput);
    final featureResult = _featureExtractor.extract(snapshotDigest);
    final decision = _ruleEngine.evaluate(
      features: featureResult,
      fundingRateDecimal: fixture.fundingRateDecimal,
      isConsensusSignable: fixture.isConsensusSignable,
      blockingFactCodes: fixture.blockingFactCodes,
      policy: _policy,
    );
    final topReasonCode =
        decision.reasons.isNotEmpty ? decision.reasons.first.code : '';
    return BingxFuturesReplayRunResult(
      fixtureId: fixture.id,
      marketSnapshotHashHex: snapshotDigest.marketSnapshotHashHex,
      featureHashHex: featureResult.featureHashHex,
      decisionHashHex: decision.decisionHashHex,
      decision: decision.decision,
      topReasonCode: topReasonCode,
    );
  }

  List<BingxFuturesReplayRunResult> runMany({
    required List<BingxFuturesReplayFixture> fixtures,
    int repeat = 1,
  }) {
    if (repeat < 1) {
      throw const FormatException('repeat must be >= 1');
    }
    final results = <BingxFuturesReplayRunResult>[];
    for (var round = 0; round < repeat; round++) {
      for (final fixture in fixtures) {
        results.add(runFixture(fixture));
      }
    }
    return results;
  }

  String policyHashHex() {
    final canonical = jsonEncode(<String, dynamic>{
      'min_abs_trade_delta': _policy.minAbsTradeDelta,
      'min_abs_session_net_delta': _policy.minAbsSessionNetDelta,
      'max_abs_funding_rate': _policy.maxAbsFundingRate,
      'require_whale_activation': _policy.requireWhaleActivation,
      'require_consensus_signable': _policy.requireConsensusSignable,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  BingxFuturesShadowEvidence buildShadowEvidence({
    required BingxFuturesReplayRunResult localRun,
    required String runnerBuildId,
    required String pluginId,
    required String pluginVersion,
    required String packageDigestHex,
    required String hostAbi,
    required int observedAtEpochMs,
    required int validUntilEpochMs,
    required int sequence,
    required String previousEvidenceHashHex,
    required String runnerKeyId,
  }) {
    return BingxFuturesShadowEvidence(
      runnerBuildId: runnerBuildId,
      pluginId: pluginId,
      pluginVersion: pluginVersion,
      packageDigestHex: packageDigestHex,
      hostAbi: hostAbi,
      policyHashHex: policyHashHex(),
      marketSnapshotHashHex: localRun.marketSnapshotHashHex,
      featureHashHex: localRun.featureHashHex,
      decisionHashHex: localRun.decisionHashHex,
      decision: localRun.decision.name,
      observedAtEpochMs: observedAtEpochMs,
      validUntilEpochMs: validUntilEpochMs,
      sequence: sequence,
      previousEvidenceHashHex: previousEvidenceHashHex,
      runnerKeyId: runnerKeyId,
    );
  }

  Future<BingxFuturesShadowEvidenceVerdict> verifyShadowEvidence({
    required BingxFuturesShadowEvidence evidence,
    required BingxFuturesReplayRunResult localRun,
    required SimplePublicKey trustedRunnerKey,
    required String expectedRunnerBuildId,
    required String expectedPluginId,
    required String expectedPluginVersion,
    required String expectedPackageDigestHex,
    required String expectedHostAbi,
    required int receivedAtEpochMs,
    required int lastAcceptedSequence,
    required String lastAcceptedEvidenceHashHex,
    int maxEncodedBytes = 8192,
    int maxValidityMs = 60000,
  }) async {
    if (evidence.encodedLength > maxEncodedBytes) {
      return BingxFuturesShadowEvidenceVerdict.oversized;
    }
    if (evidence.contractVersion != 'trading-shadow-evidence-v1') {
      return BingxFuturesShadowEvidenceVerdict.unsupportedContract;
    }
    if (evidence.signatureSuite != 'ed25519-v1') {
      return BingxFuturesShadowEvidenceVerdict.unsupportedSignatureSuite;
    }
    if (!_isSha256(evidence.packageDigestHex) ||
        !_isSha256(evidence.policyHashHex) ||
        !_isSha256(evidence.marketSnapshotHashHex) ||
        !_isSha256(evidence.featureHashHex) ||
        !_isSha256(evidence.decisionHashHex) ||
        !_isSha256(evidence.previousEvidenceHashHex) ||
        evidence.sequence < 1 ||
        evidence.validUntilEpochMs < evidence.observedAtEpochMs ||
        evidence.validUntilEpochMs - evidence.observedAtEpochMs >
            maxValidityMs) {
      return BingxFuturesShadowEvidenceVerdict.malformed;
    }
    final trustedKeyId = sha256.convert(trustedRunnerKey.bytes).toString();
    if (evidence.runnerKeyId != trustedKeyId) {
      return BingxFuturesShadowEvidenceVerdict.wrongRunner;
    }
    try {
      final signatureBytes = _decodeHex(evidence.signatureHex);
      final isValid = await Ed25519().verify(
        evidence.signingPayload,
        signature: Signature(signatureBytes, publicKey: trustedRunnerKey),
      );
      if (!isValid) {
        return BingxFuturesShadowEvidenceVerdict.invalidSignature;
      }
    } on Object {
      return BingxFuturesShadowEvidenceVerdict.invalidSignature;
    }
    if (evidence.runnerBuildId != expectedRunnerBuildId ||
        evidence.hostAbi != expectedHostAbi) {
      return BingxFuturesShadowEvidenceVerdict.buildDrift;
    }
    if (evidence.pluginId != expectedPluginId ||
        evidence.pluginVersion != expectedPluginVersion ||
        evidence.packageDigestHex != expectedPackageDigestHex) {
      return BingxFuturesShadowEvidenceVerdict.pluginDrift;
    }
    if (evidence.policyHashHex != policyHashHex()) {
      return BingxFuturesShadowEvidenceVerdict.policyDrift;
    }
    if (evidence.marketSnapshotHashHex != localRun.marketSnapshotHashHex ||
        evidence.featureHashHex != localRun.featureHashHex ||
        evidence.decisionHashHex != localRun.decisionHashHex ||
        evidence.decision != localRun.decision.name) {
      return BingxFuturesShadowEvidenceVerdict.localParityMismatch;
    }
    if (receivedAtEpochMs < evidence.observedAtEpochMs) {
      return BingxFuturesShadowEvidenceVerdict.notYetValid;
    }
    if (receivedAtEpochMs > evidence.validUntilEpochMs) {
      return BingxFuturesShadowEvidenceVerdict.stale;
    }
    if (evidence.sequence == lastAcceptedSequence &&
        evidence.evidenceHashHex == lastAcceptedEvidenceHashHex) {
      return BingxFuturesShadowEvidenceVerdict.exactReplay;
    }
    if (evidence.sequence != lastAcceptedSequence + 1) {
      return BingxFuturesShadowEvidenceVerdict.sequenceConflict;
    }
    final expectedPreviousHash =
        lastAcceptedSequence == 0
            ? _emptyShadowEvidenceHash
            : lastAcceptedEvidenceHashHex;
    if (evidence.previousEvidenceHashHex != expectedPreviousHash) {
      return BingxFuturesShadowEvidenceVerdict.chainFork;
    }
    return BingxFuturesShadowEvidenceVerdict.accepted;
  }

  bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  List<int> _decodeHex(String value) {
    if (value.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
      throw const FormatException('invalid hex');
    }
    return <int>[
      for (var offset = 0; offset < value.length; offset += 2)
        int.parse(value.substring(offset, offset + 2), radix: 16),
    ];
  }
}
