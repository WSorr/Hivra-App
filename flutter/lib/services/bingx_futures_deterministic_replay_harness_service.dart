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

  Map<String, dynamic> get wireMap => <String, dynamic>{
    ...semanticMap,
    'signature_hex': signatureHex,
  };

  List<int> get wireBytes => utf8.encode(jsonEncode(wireMap));

  int get encodedLength => wireBytes.length;

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

  BingxFuturesReplayRunResult runPublicMarket({
    required String fixtureId,
    required BingxFuturesMarketSnapshotInput snapshotInput,
    required String fundingRateDecimal,
  }) {
    final snapshotDigest = _snapshotService.build(snapshotInput);
    final featureResult = _featureExtractor.extract(snapshotDigest);
    final decision = _ruleEngine.evaluateMarket(
      features: featureResult,
      fundingRateDecimal: fundingRateDecimal,
      policy: BingxTvhPolicy(
        minAbsTradeDelta: _policy.minAbsTradeDelta,
        minAbsSessionNetDelta: _policy.minAbsSessionNetDelta,
        maxAbsFundingRate: _policy.maxAbsFundingRate,
        requireWhaleActivation: _policy.requireWhaleActivation,
      ),
    );
    return BingxFuturesReplayRunResult(
      fixtureId: fixtureId,
      marketSnapshotHashHex: snapshotDigest.marketSnapshotHashHex,
      featureHashHex: featureResult.featureHashHex,
      decisionHashHex: decision.decisionHashHex,
      decision: decision.decision,
      topReasonCode:
          decision.reasons.isNotEmpty ? decision.reasons.first.code : '',
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

  String publicStrategyPolicyHashHex() {
    final canonical = jsonEncode(<String, dynamic>{
      'min_abs_trade_delta': _policy.minAbsTradeDelta,
      'min_abs_session_net_delta': _policy.minAbsSessionNetDelta,
      'max_abs_funding_rate': _policy.maxAbsFundingRate,
      'require_whale_activation': _policy.requireWhaleActivation,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  BingxFuturesShadowEvidence buildShadowEvidence({
    required BingxFuturesReplayRunResult publicRun,
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
      policyHashHex: publicStrategyPolicyHashHex(),
      marketSnapshotHashHex: publicRun.marketSnapshotHashHex,
      featureHashHex: publicRun.featureHashHex,
      decisionHashHex: publicRun.decisionHashHex,
      decision: publicRun.decision.name,
      observedAtEpochMs: observedAtEpochMs,
      validUntilEpochMs: validUntilEpochMs,
      sequence: sequence,
      previousEvidenceHashHex: previousEvidenceHashHex,
      runnerKeyId: runnerKeyId,
    );
  }

  Future<BingxFuturesShadowEvidenceVerdict> verifyShadowEvidence({
    required List<int> untrustedWireBytes,
    required BingxFuturesReplayRunResult localPublicRun,
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
    if (untrustedWireBytes.length > maxEncodedBytes) {
      return BingxFuturesShadowEvidenceVerdict.oversized;
    }
    late final BingxFuturesShadowEvidence evidence;
    try {
      evidence = parseShadowEvidence(
        untrustedWireBytes,
        maxEncodedBytes: maxEncodedBytes,
      );
    } on FormatException {
      return BingxFuturesShadowEvidenceVerdict.malformed;
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
    if (evidence.policyHashHex != publicStrategyPolicyHashHex()) {
      return BingxFuturesShadowEvidenceVerdict.policyDrift;
    }
    if (evidence.marketSnapshotHashHex !=
            localPublicRun.marketSnapshotHashHex ||
        evidence.featureHashHex != localPublicRun.featureHashHex ||
        evidence.decisionHashHex != localPublicRun.decisionHashHex ||
        evidence.decision != localPublicRun.decision.name) {
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

  BingxFuturesShadowEvidence parseShadowEvidence(
    List<int> untrustedWireBytes, {
    int maxEncodedBytes = 8192,
  }) {
    if (untrustedWireBytes.isEmpty ||
        untrustedWireBytes.length > maxEncodedBytes) {
      throw const FormatException('invalid shadow evidence size');
    }
    final decoded = jsonDecode(
      utf8.decode(untrustedWireBytes, allowMalformed: false),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('shadow evidence must be an object');
    }
    final evidence = BingxFuturesShadowEvidence(
      contractVersion: _requiredAscii(decoded, 'contract_version'),
      runnerBuildId: _requiredAscii(decoded, 'runner_build_id'),
      pluginId: _requiredAscii(decoded, 'plugin_id'),
      pluginVersion: _requiredAscii(decoded, 'plugin_version'),
      packageDigestHex: _requiredString(decoded, 'package_digest_hex'),
      hostAbi: _requiredAscii(decoded, 'host_abi'),
      policyHashHex: _requiredString(decoded, 'policy_hash_hex'),
      marketSnapshotHashHex: _requiredString(
        decoded,
        'market_snapshot_hash_hex',
      ),
      featureHashHex: _requiredString(decoded, 'feature_hash_hex'),
      decisionHashHex: _requiredString(decoded, 'decision_hash_hex'),
      decision: _requiredAscii(decoded, 'decision'),
      observedAtEpochMs: _requiredInt(decoded, 'observed_at_epoch_ms'),
      validUntilEpochMs: _requiredInt(decoded, 'valid_until_epoch_ms'),
      sequence: _requiredInt(decoded, 'sequence'),
      previousEvidenceHashHex: _requiredString(
        decoded,
        'previous_evidence_hash_hex',
      ),
      runnerKeyId: _requiredAscii(decoded, 'runner_key_id'),
      signatureSuite: _requiredAscii(decoded, 'signature_suite'),
      signatureHex: _requiredString(decoded, 'signature_hex'),
    );
    if (!_listEquals(untrustedWireBytes, evidence.wireBytes)) {
      throw const FormatException('shadow evidence is not canonical');
    }
    return evidence;
  }

  bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  String _requiredAscii(Map<String, dynamic> map, String key) {
    final value = _requiredString(map, key);
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
      throw FormatException('$key must use canonical ASCII');
    }
    return value;
  }

  int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw FormatException('$key must be an integer');
    }
    return value;
  }

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

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
