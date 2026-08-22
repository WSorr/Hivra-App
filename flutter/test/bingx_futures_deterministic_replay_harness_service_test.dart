import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_live_snapshot_builder_service.dart';
import 'package:hivra_app/services/bingx_futures_public_market_data_port.dart';

void main() {
  group('BingxFuturesDeterministicReplayHarnessService', () {
    const service = BingxFuturesDeterministicReplayHarnessService(
      policy: BingxTvhPolicy(
        minAbsTradeImbalanceRatio: 0.5,
        maxAbsFundingRate: 0.01,
        requireConsensusSignable: true,
      ),
    );

    final fixtures = <BingxFuturesReplayFixture>[
      _fixtureLong(),
      _fixtureShort(),
      _fixtureNoSignal(),
      _fixtureBlocked(),
    ];

    test('matches expected decision branches', () {
      for (final fixture in fixtures) {
        final run = service.runFixture(fixture);
        expect(
          run.decision,
          fixture.expectedDecision,
          reason: 'fixture=${fixture.id}',
        );
        expect(
          run.topReasonCode,
          fixture.expectedReasonCode,
          reason: 'fixture=${fixture.id}',
        );
      }
    });

    test('is bit-stable across repeated replay cycles', () {
      final runs = service.runMany(fixtures: fixtures, repeat: 4);
      final byFixture = <String, List<BingxFuturesReplayRunResult>>{};
      for (final run in runs) {
        final history = byFixture.putIfAbsent(
          run.fixtureId,
          () => <BingxFuturesReplayRunResult>[],
        );
        history.add(run);
      }

      for (final fixture in fixtures) {
        final history = byFixture[fixture.id]!;
        final snapshotHashes =
            history.map((item) => item.marketSnapshotHashHex).toSet();
        final featureHashes =
            history.map((item) => item.featureHashHex).toSet();
        final decisionHashes =
            history.map((item) => item.decisionHashHex).toSet();
        expect(
          snapshotHashes.length,
          1,
          reason: 'snapshot drift ${fixture.id}',
        );
        expect(featureHashes.length, 1, reason: 'feature drift ${fixture.id}');
        expect(
          decisionHashes.length,
          1,
          reason: 'decision drift ${fixture.id}',
        );
      }
    });

    test('stays deterministic across input ordering permutations', () {
      for (final fixture in fixtures) {
        final base = service.runFixture(fixture);
        final permuted = service.runFixture(
          BingxFuturesReplayFixture(
            id: fixture.id,
            snapshotInput: _permuteInput(fixture.snapshotInput),
            fundingRateDecimal: fixture.fundingRateDecimal,
            isConsensusSignable: fixture.isConsensusSignable,
            blockingFactCodes: fixture.blockingFactCodes,
            expectedDecision: fixture.expectedDecision,
            expectedReasonCode: fixture.expectedReasonCode,
          ),
        );
        expect(
          permuted.marketSnapshotHashHex,
          base.marketSnapshotHashHex,
          reason: 'snapshot permutation drift ${fixture.id}',
        );
        expect(
          permuted.featureHashHex,
          base.featureHashHex,
          reason: 'feature permutation drift ${fixture.id}',
        );
        expect(
          permuted.decisionHashHex,
          base.decisionHashHex,
          reason: 'decision permutation drift ${fixture.id}',
        );
      }
    });

    test('accepts the canonical signed shadow evidence vector', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );
      expect(
        evidence.evidenceHashHex,
        '4fc12ad3041b61d36986239d61337cdcb49b11ac8bbb21b5c32d702de1f764ac',
      );
      final golden = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/trading_shadow_evidence_v1.json',
              ).readAsStringSync(),
            )
            as Map,
      );
      expect(evidence.semanticMap, golden['semantic_fields']);
      expect(evidence.semanticJson, golden['expected_semantic_json']);
      expect(utf8.decode(evidence.wireBytes), golden['expected_wire_utf8']);
      expect(_hex(publicKey.bytes), golden['runner_public_key_hex']);
      expect(
        await _verify(
          service: service,
          evidence: evidence,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.accepted,
      );
    });

    test('accepts only a complete READY market proposal in v2', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final proposal = <String, dynamic>{
        'schema_version': 2,
        'contract': 'bingx_futures_live_decision_v2',
        'market_snapshot_hash_hex': '1'.padLeft(64, '1'),
        'feature_hash_hex': '2'.padLeft(64, '2'),
        'tvh_decision_hash_hex': '3'.padLeft(64, '3'),
        'decision': 'long',
        'can_prepare_intent': true,
        'trend_bundle': <String, dynamic>{
          'trend_15m': 'bullish',
          'trend_4h': 'bull',
          'trend_1d': 'bull',
        },
        'trend_gate': <String, dynamic>{'blocked': false, 'code': 'ok'},
        'side': 'buy',
        'zone_evaluation_side': 'buy',
        'zone': <String, dynamic>{
          'side': 'buyside',
          'low_decimal': '100.25',
          'high_decimal': '101.50',
          'source': 'micro_sweep_reclaim',
          'side_reason': 'buy_signal',
          'conflict': false,
          'target_retest_pct': 0.01,
          'needs_farther_retest': false,
          'anchor_source': 'micro_sweep_reclaim',
          'anchor_executable': true,
          'anchor_lifecycle': 'fresh',
          'liquidity_event_id': '4'.padLeft(64, '4'),
          'liquidity_event_at_utc': '2026-08-22T10:00:00Z',
          'latest_closed_micro_bar_at_utc': '2026-08-22T10:05:00Z',
        },
        'profit_target': <String, dynamic>{
          'kind': 'opposite_external_liquidity',
          'price_decimal': '110.00',
          'source': '1d_fresh_high',
          'event_at_utc': '2026-08-21T00:00:00Z',
        },
        'reason_codes': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'funding_guard', 'passed': true},
        ],
      };
      final proposalJson = jsonEncode(proposal);
      final run = BingxFuturesReplayRunResult(
        fixtureId: 'ready',
        marketSnapshotHashHex: '1'.padLeft(64, '1'),
        featureHashHex: '2'.padLeft(64, '2'),
        decisionHashHex: sha256.convert(utf8.encode(proposalJson)).toString(),
        decision: BingxTvhDecisionKind.long,
        topReasonCode: 'funding_guard',
        marketProposalStatus: 'READY',
        marketProposalJson: proposalJson,
      );
      final unsigned = service.buildShadowEvidence(
        publicRun: run,
        runnerBuildId: 'runner-build-ready',
        pluginId: 'hivra.bingx-futures-trading',
        pluginVersion: '0.2.7-plugins',
        packageDigestHex: _packageDigest,
        hostAbi: 'dart-headless-v1',
        observedAtEpochMs: 1770000000000,
        validUntilEpochMs: 1770000060000,
        sequence: 1,
        previousEvidenceHashHex: _emptyEvidenceHash,
        runnerKeyId: _runnerKeyId(publicKey),
        contractVersion: 'trading-shadow-evidence-v2',
      );
      final evidence = await _resign(unsigned, signingKey);

      expect(
        service.parseShadowEvidence(evidence.wireBytes).marketProposalStatus,
        'READY',
      );
      final missingTarget = <String, dynamic>{
        ...proposal,
        'profit_target': null,
      };
      final invalidJson = jsonEncode(missingTarget);
      expect(
        () => service.buildShadowEvidence(
          publicRun: BingxFuturesReplayRunResult(
            fixtureId: 'invalid-ready',
            marketSnapshotHashHex: '1'.padLeft(64, '1'),
            featureHashHex: '2'.padLeft(64, '2'),
            decisionHashHex:
                sha256.convert(utf8.encode(invalidJson)).toString(),
            decision: BingxTvhDecisionKind.long,
            topReasonCode: 'funding_guard',
            marketProposalStatus: 'READY',
            marketProposalJson: invalidJson,
          ),
          runnerBuildId: 'runner-build-ready',
          pluginId: 'hivra.bingx-futures-trading',
          pluginVersion: '0.2.7-plugins',
          packageDigestHex: _packageDigest,
          hostAbi: 'dart-headless-v1',
          observedAtEpochMs: 1770000000000,
          validUntilEpochMs: 1770000060000,
          sequence: 1,
          previousEvidenceHashHex: _emptyEvidenceHash,
          runnerKeyId: _runnerKeyId(publicKey),
          contractVersion: 'trading-shadow-evidence-v2',
        ),
        throwsFormatException,
      );
    });

    test('produces signed one-shot evidence from public live input', () async {
      final fixture = _fixtureLong();
      final marketData = _PublicMarketDataStub();
      var loadedSymbol = '';
      final liveService = BingxFuturesDeterministicReplayHarnessService(
        policy: const BingxTvhPolicy(
          minAbsTradeImbalanceRatio: 0.5,
          maxAbsFundingRate: 0.01,
          requireConsensusSignable: true,
        ),
        loadLiveSnapshot: ({required exchange, required symbol}) async {
          expect(exchange, same(marketData));
          loadedSymbol = symbol;
          return BingxFuturesLiveSnapshotBuildResult(
            isSuccess: true,
            errorCode: '0',
            errorMessage: 'ok',
            snapshotInput: fixture.snapshotInput,
            symbol: symbol,
          );
        },
      );
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();

      final evidence = await liveService.runLivePublicShadow(
        marketData: marketData,
        symbol: ' btc-usdt ',
        signingKey: signingKey,
        runnerBuildId: 'runner-build-live',
        pluginId: 'hivra.bingx-futures-trading',
        pluginVersion: '0.2.7-plugins',
        packageDigestHex: _packageDigest,
        hostAbi: 'dart-headless-v1',
        observedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          1770000000000,
          isUtc: true,
        ),
        sequence: 1,
        previousEvidenceHashHex: _emptyEvidenceHash,
      );

      expect(loadedSymbol, 'BTC-USDT');
      expect(evidence.sequence, 1);
      expect(evidence.previousEvidenceHashHex, _emptyEvidenceHash);
      expect(evidence.runnerKeyId, _runnerKeyId(publicKey));
      expect(evidence.validUntilEpochMs - evidence.observedAtEpochMs, 60000);
      final expected = liveService.runPublicLiveMarket(
        fixtureId: 'live:BTC-USDT',
        snapshotInput: fixture.snapshotInput,
      );
      expect(evidence.marketSnapshotHashHex, expected.marketSnapshotHashHex);
      expect(evidence.featureHashHex, expected.featureHashHex);
      expect(evidence.decisionHashHex, expected.decisionHashHex);
      expect(evidence.decision, expected.decision.name);
      expect(evidence.contractVersion, 'trading-shadow-evidence-v2');
      expect(evidence.marketProposalStatus, expected.marketProposalStatus);
      expect(evidence.marketProposalJson, expected.marketProposalJson);
      expect(
        liveService.parseShadowEvidence(evidence.wireBytes).evidenceHashHex,
        evidence.evidenceHashHex,
      );
      expect(
        await liveService.verifyShadowEvidenceContinuity(
          untrustedWireBytes: evidence.wireBytes,
          trustedRunnerKey: publicKey,
          lastAcceptedSequence: 0,
          lastAcceptedEvidenceHashHex: _emptyEvidenceHash,
        ),
        BingxFuturesShadowEvidenceVerdict.accepted,
      );
      expect(
        await Ed25519().verify(
          evidence.signingPayload,
          signature: Signature(
            _decodeHex(evidence.signatureHex),
            publicKey: publicKey,
          ),
        ),
        isTrue,
      );

      final tamperedProposal = jsonEncode(<String, dynamic>{
        ...Map<String, dynamic>.from(
          jsonDecode(evidence.marketProposalJson!) as Map,
        ),
        'can_prepare_intent': evidence.marketProposalStatus != 'READY',
      });
      expect(
        () => liveService.parseShadowEvidence(
          _copyEvidence(
            evidence,
            marketProposalJson: tamperedProposal,
          ).wireBytes,
        ),
        throwsFormatException,
      );
    });

    test('accepts a v2 continuation of an existing v1 stream', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final anchor = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );
      final fixture = _fixtureLong();
      final liveService = BingxFuturesDeterministicReplayHarnessService(
        loadLiveSnapshot: ({required exchange, required symbol}) async {
          return BingxFuturesLiveSnapshotBuildResult(
            isSuccess: true,
            errorCode: '0',
            errorMessage: 'ok',
            snapshotInput: fixture.snapshotInput,
            symbol: symbol,
          );
        },
      );

      final continuation = await liveService.runLivePublicShadow(
        marketData: _PublicMarketDataStub(),
        symbol: 'BTC-USDT',
        signingKey: signingKey,
        runnerBuildId: 'runner-build-live',
        pluginId: 'hivra.bingx-futures-trading',
        pluginVersion: '0.2.7-plugins',
        packageDigestHex: _packageDigest,
        hostAbi: 'dart-headless-v1',
        observedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          1770000000000,
          isUtc: true,
        ),
        sequence: 2,
        previousEvidenceHashHex: anchor.evidenceHashHex,
      );

      expect(anchor.contractVersion, 'trading-shadow-evidence-v1');
      expect(continuation.contractVersion, 'trading-shadow-evidence-v2');
      expect(continuation.previousEvidenceHashHex, anchor.evidenceHashHex);
      expect(
        await liveService.verifyShadowEvidenceContinuity(
          untrustedWireBytes: continuation.wireBytes,
          trustedRunnerKey: publicKey,
          lastAcceptedSequence: anchor.sequence,
          lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
        ),
        BingxFuturesShadowEvidenceVerdict.accepted,
      );
    });

    test('fails closed when public live input is unavailable', () async {
      var loadCount = 0;
      final liveService = BingxFuturesDeterministicReplayHarnessService(
        loadLiveSnapshot: ({required exchange, required symbol}) async {
          loadCount++;
          return BingxFuturesLiveSnapshotBuildResult(
            isSuccess: false,
            errorCode: 'public_timeout',
            errorMessage: 'timeout',
            snapshotInput: null,
            symbol: symbol,
          );
        },
      );

      await expectLater(
        liveService.runLivePublicShadow(
          marketData: _PublicMarketDataStub(),
          symbol: 'BTC-USDT',
          signingKey: await _runnerSigningKey(),
          runnerBuildId: 'runner-build-live',
          pluginId: 'hivra.bingx-futures-trading',
          pluginVersion: '0.2.7-plugins',
          packageDigestHex: _packageDigest,
          hostAbi: 'dart-headless-v1',
          observedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            1770000000000,
            isUtc: true,
          ),
          sequence: 1,
          previousEvidenceHashHex: _emptyEvidenceHash,
        ),
        throwsStateError,
      );
      expect(loadCount, 1);
    });

    test('rejects malformed live metadata before public observation', () async {
      var loadCount = 0;
      final liveService = BingxFuturesDeterministicReplayHarnessService(
        loadLiveSnapshot: ({required exchange, required symbol}) async {
          loadCount++;
          throw StateError('must not load');
        },
      );

      await expectLater(
        liveService.runLivePublicShadow(
          marketData: _PublicMarketDataStub(),
          symbol: 'BTC-USDT',
          signingKey: await _runnerSigningKey(),
          runnerBuildId: 'runner build with spaces',
          pluginId: 'hivra.bingx-futures-trading',
          pluginVersion: '0.2.7-plugins',
          packageDigestHex: 'not-a-digest',
          hostAbi: 'dart-headless-v1',
          observedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            1770000000000,
            isUtc: true,
          ),
          sequence: 1,
          previousEvidenceHashHex: _emptyEvidenceHash,
        ),
        throwsFormatException,
      );
      expect(loadCount, 0);
    });

    test('keeps local consensus blocking out of public shadow evidence', () {
      final fixture = _fixtureBlocked();
      final local = service.runFixture(fixture);
      final shadow = service.runPublicMarket(
        fixtureId: fixture.id,
        snapshotInput: fixture.snapshotInput,
        fundingRateDecimal: fixture.fundingRateDecimal,
      );

      expect(local.decision, BingxTvhDecisionKind.blocked);
      expect(local.topReasonCode, 'consensus_guard');
      expect(shadow.decision, BingxTvhDecisionKind.long);
      expect(shadow.topReasonCode, 'funding_guard');
    });

    test('rejects non-canonical and unknown untrusted wire bytes', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );
      final decoded = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(evidence.wireBytes)) as Map,
      );

      expect(
        () => service.parseShadowEvidence(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(decoded)),
        ),
        throwsFormatException,
      );
      expect(
        () => service.parseShadowEvidence(
          utf8.encode(jsonEncode(<String, dynamic>{...decoded, 'extra': true})),
        ),
        throwsFormatException,
      );
      expect(
        () => service.parseShadowEvidence(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'signature_hex': decoded['signature_hex'],
              ...decoded..remove('signature_hex'),
            }),
          ),
        ),
        throwsFormatException,
      );
    });

    test('accepts only an exact replay at the accepted sequence', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );
      expect(
        await _verify(
          service: service,
          evidence: evidence,
          trustedRunnerKey: publicKey,
          lastAcceptedSequence: evidence.sequence,
          lastAcceptedEvidenceHashHex: evidence.evidenceHashHex,
        ),
        BingxFuturesShadowEvidenceVerdict.exactReplay,
      );

      final conflicting = await _resign(
        _copyEvidence(evidence, observedAtEpochMs: 1770000000001),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: conflicting,
          trustedRunnerKey: publicKey,
          lastAcceptedSequence: evidence.sequence,
          lastAcceptedEvidenceHashHex: evidence.evidenceHashHex,
        ),
        BingxFuturesShadowEvidenceVerdict.sequenceConflict,
      );
    });

    test('fails closed for wrong runner, signature, and chain fork', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );

      final wrongRunner = await _resign(
        _copyEvidence(evidence, runnerKeyId: 'f' * 64),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: wrongRunner,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.wrongRunner,
      );

      final invalidSignature = evidence.withSignature('00');
      expect(
        await _verify(
          service: service,
          evidence: invalidSignature,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.invalidSignature,
      );

      final forked = await _resign(
        _copyEvidence(evidence, sequence: 2, previousEvidenceHashHex: 'e' * 64),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: forked,
          trustedRunnerKey: publicKey,
          lastAcceptedSequence: 1,
          lastAcceptedEvidenceHashHex: 'd' * 64,
        ),
        BingxFuturesShadowEvidenceVerdict.chainFork,
      );
    });

    test('fails closed for stale, plugin, policy, and parity drift', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );

      expect(
        await _verify(
          service: service,
          evidence: evidence,
          trustedRunnerKey: publicKey,
          receivedAtEpochMs: 1770000060001,
        ),
        BingxFuturesShadowEvidenceVerdict.stale,
      );

      final pluginDrift = await _resign(
        _copyEvidence(evidence, pluginVersion: '0.2.8-drift'),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: pluginDrift,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.pluginDrift,
      );

      final policyDrift = await _resign(
        _copyEvidence(evidence, policyHashHex: 'c' * 64),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: policyDrift,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.policyDrift,
      );

      final parityDrift = await _resign(
        _copyEvidence(evidence, decisionHashHex: 'b' * 64),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: parityDrift,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.localParityMismatch,
      );
    });

    test('fails closed for downgrade, build, and package drift', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );

      final contractDowngrade = await _resign(
        _copyEvidence(evidence, contractVersion: 'trading-shadow-evidence-v0'),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: contractDowngrade,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.unsupportedContract,
      );

      final suiteDowngrade = await _resign(
        _copyEvidence(evidence, signatureSuite: 'legacy-v0'),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: suiteDowngrade,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.unsupportedSignatureSuite,
      );

      final buildDrift = await _resign(
        _copyEvidence(evidence, hostAbi: 'wasm32-unknown'),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: buildDrift,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.buildDrift,
      );

      final packageDrift = await _resign(
        _copyEvidence(evidence, packageDigestHex: '9' * 64),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: packageDrift,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.pluginDrift,
      );
    });

    test('bounds evidence before accepting runner content', () async {
      final signingKey = await _runnerSigningKey();
      final publicKey = await signingKey.extractPublicKey();
      final evidence = await _signedEvidence(
        service: service,
        signingKey: signingKey,
        runnerKeyId: _runnerKeyId(publicKey),
      );
      final oversized = await _resign(
        _copyEvidence(evidence, runnerBuildId: 'x' * 9000),
        signingKey,
      );

      expect(
        await _verify(
          service: service,
          evidence: oversized,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.oversized,
      );

      final unboundedValidity = await _resign(
        _copyEvidence(evidence, validUntilEpochMs: 1770000060001),
        signingKey,
      );
      expect(
        await _verify(
          service: service,
          evidence: unboundedValidity,
          trustedRunnerKey: publicKey,
        ),
        BingxFuturesShadowEvidenceVerdict.malformed,
      );
    });

    test(
      'verifies an external anchor and only its exact continuation',
      () async {
        final signingKey = await _runnerSigningKey();
        final publicKey = await signingKey.extractPublicKey();
        final anchor = await _signedEvidence(
          service: service,
          signingKey: signingKey,
          runnerKeyId: _runnerKeyId(publicKey),
        );
        final continuation = await _resign(
          _copyEvidence(
            anchor,
            sequence: 2,
            previousEvidenceHashHex: anchor.evidenceHashHex,
          ),
          signingKey,
        );

        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: anchor.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.exactReplay,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: continuation.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.accepted,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: anchor.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: continuation.sequence,
            lastAcceptedEvidenceHashHex: continuation.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.sequenceConflict,
        );

        final conflictingReplay = await _resign(
          _copyEvidence(anchor, decisionHashHex: 'e' * 64),
          signingKey,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: conflictingReplay.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.sequenceConflict,
        );

        final fork = await _resign(
          _copyEvidence(continuation, previousEvidenceHashHex: 'f' * 64),
          signingKey,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: fork.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.chainFork,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: continuation.withSignature('00' * 64).wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.invalidSignature,
        );
        final foreignPublicKey = await Ed25519()
            .newKeyPairFromSeed(List<int>.generate(32, (index) => 255 - index))
            .then((keyPair) => keyPair.extractPublicKey());
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: anchor.wireBytes,
            trustedRunnerKey: foreignPublicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
          ),
          BingxFuturesShadowEvidenceVerdict.wrongRunner,
        );
        expect(
          await service.verifyShadowEvidenceContinuity(
            untrustedWireBytes: anchor.wireBytes,
            trustedRunnerKey: publicKey,
            lastAcceptedSequence: anchor.sequence,
            lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
            maxEncodedBytes: 1,
          ),
          BingxFuturesShadowEvidenceVerdict.oversized,
        );
      },
    );
  });
}

class _PublicMarketDataStub implements BingxFuturesPublicMarketDataPort {
  @override
  Future<BingxFuturesPublicOrderBookResult> getPublicDepth({
    required String symbol,
    int limit = 20,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicKlinesResult> getPublicKlines({
    required String symbol,
    required String interval,
    int limit = 120,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicOpenInterestResult> getPublicOpenInterest({
    required String symbol,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicOpenInterestHistoryResult>
  getPublicOpenInterestHistory({
    required String symbol,
    String period = '5m',
    int limit = 24,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicPremiumIndexResult> getPublicPremiumIndex({
    required String symbol,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicPriceResult> getPublicPrice({
    required String symbol,
  }) => throw UnimplementedError();

  @override
  Future<BingxFuturesPublicTradesResult> getPublicTrades({
    required String symbol,
    int limit = 100,
  }) => throw UnimplementedError();
}

const _packageDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _emptyEvidenceHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

Future<SimpleKeyPair> _runnerSigningKey() {
  return Ed25519().newKeyPairFromSeed(List<int>.generate(32, (index) => index));
}

String _runnerKeyId(SimplePublicKey publicKey) {
  return sha256.convert(publicKey.bytes).toString();
}

Future<BingxFuturesShadowEvidence> _signedEvidence({
  required BingxFuturesDeterministicReplayHarnessService service,
  required SimpleKeyPair signingKey,
  required String runnerKeyId,
}) async {
  final fixture = _fixtureLong();
  final localRun = service.runPublicMarket(
    fixtureId: fixture.id,
    snapshotInput: fixture.snapshotInput,
    fundingRateDecimal: fixture.fundingRateDecimal,
  );
  final unsigned = service.buildShadowEvidence(
    publicRun: localRun,
    runnerBuildId: 'runner-build-2026-08-11',
    pluginId: 'hivra.bingx-futures-trading',
    pluginVersion: '0.2.7-plugins',
    packageDigestHex: _packageDigest,
    hostAbi: 'wasm32-wasi-preview1',
    observedAtEpochMs: 1770000000000,
    validUntilEpochMs: 1770000060000,
    sequence: 1,
    previousEvidenceHashHex: _emptyEvidenceHash,
    runnerKeyId: runnerKeyId,
  );
  return _resign(unsigned, signingKey);
}

Future<BingxFuturesShadowEvidence> _resign(
  BingxFuturesShadowEvidence evidence,
  SimpleKeyPair signingKey,
) async {
  final signature = await Ed25519().sign(
    evidence.signingPayload,
    keyPair: signingKey,
  );
  return evidence.withSignature(_hex(signature.bytes));
}

Future<BingxFuturesShadowEvidenceVerdict> _verify({
  required BingxFuturesDeterministicReplayHarnessService service,
  required BingxFuturesShadowEvidence evidence,
  required SimplePublicKey trustedRunnerKey,
  int receivedAtEpochMs = 1770000030000,
  int lastAcceptedSequence = 0,
  String lastAcceptedEvidenceHashHex = _emptyEvidenceHash,
}) {
  final fixture = _fixtureLong();
  return service.verifyShadowEvidence(
    untrustedWireBytes: evidence.wireBytes,
    localPublicRun: service.runPublicMarket(
      fixtureId: fixture.id,
      snapshotInput: fixture.snapshotInput,
      fundingRateDecimal: fixture.fundingRateDecimal,
    ),
    trustedRunnerKey: trustedRunnerKey,
    expectedRunnerBuildId: 'runner-build-2026-08-11',
    expectedPluginId: 'hivra.bingx-futures-trading',
    expectedPluginVersion: '0.2.7-plugins',
    expectedPackageDigestHex: _packageDigest,
    expectedHostAbi: 'wasm32-wasi-preview1',
    receivedAtEpochMs: receivedAtEpochMs,
    lastAcceptedSequence: lastAcceptedSequence,
    lastAcceptedEvidenceHashHex: lastAcceptedEvidenceHashHex,
  );
}

BingxFuturesShadowEvidence _copyEvidence(
  BingxFuturesShadowEvidence evidence, {
  String? contractVersion,
  String? runnerBuildId,
  String? pluginVersion,
  String? packageDigestHex,
  String? hostAbi,
  String? policyHashHex,
  String? decisionHashHex,
  String? marketProposalStatus,
  String? marketProposalJson,
  int? observedAtEpochMs,
  int? validUntilEpochMs,
  int? sequence,
  String? previousEvidenceHashHex,
  String? runnerKeyId,
  String? signatureSuite,
}) {
  return BingxFuturesShadowEvidence(
    contractVersion: contractVersion ?? evidence.contractVersion,
    runnerBuildId: runnerBuildId ?? evidence.runnerBuildId,
    pluginId: evidence.pluginId,
    pluginVersion: pluginVersion ?? evidence.pluginVersion,
    packageDigestHex: packageDigestHex ?? evidence.packageDigestHex,
    hostAbi: hostAbi ?? evidence.hostAbi,
    policyHashHex: policyHashHex ?? evidence.policyHashHex,
    marketSnapshotHashHex: evidence.marketSnapshotHashHex,
    featureHashHex: evidence.featureHashHex,
    decisionHashHex: decisionHashHex ?? evidence.decisionHashHex,
    decision: evidence.decision,
    marketProposalStatus: marketProposalStatus ?? evidence.marketProposalStatus,
    marketProposalJson: marketProposalJson ?? evidence.marketProposalJson,
    observedAtEpochMs: observedAtEpochMs ?? evidence.observedAtEpochMs,
    validUntilEpochMs: validUntilEpochMs ?? evidence.validUntilEpochMs,
    sequence: sequence ?? evidence.sequence,
    previousEvidenceHashHex:
        previousEvidenceHashHex ?? evidence.previousEvidenceHashHex,
    runnerKeyId: runnerKeyId ?? evidence.runnerKeyId,
    signatureSuite: signatureSuite ?? evidence.signatureSuite,
  );
}

String _hex(List<int> bytes) {
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

List<int> _decodeHex(String value) => <int>[
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];

BingxFuturesReplayFixture _fixtureLong() {
  return BingxFuturesReplayFixture(
    id: 'long',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bullish,
      includeBuyWhale: true,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[20.0, 35.0, 10.0],
      openInterestStart: 500000,
      openInterestEnd: 500140,
    ),
    fundingRateDecimal: '0.0008',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.long,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureShort() {
  return BingxFuturesReplayFixture(
    id: 'short',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bearish,
      includeBuyWhale: false,
      includeSellWhale: true,
      sessionDeltaSigns: const <double>[-18.0, -22.0, -9.0],
      openInterestStart: 500140,
      openInterestEnd: 499900,
    ),
    fundingRateDecimal: '-0.0009',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.short,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureNoSignal() {
  return BingxFuturesReplayFixture(
    id: 'no_signal',
    snapshotInput: _buildInput(
      trend: _TrendPattern.neutral,
      includeBuyWhale: false,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[0.1, -0.1, 0.0],
      openInterestStart: 500000,
      openInterestEnd: 500000,
      keepLiquidityFarFromTrades: true,
    ),
    fundingRateDecimal: '0.0001',
    isConsensusSignable: true,
    expectedDecision: BingxTvhDecisionKind.noSignal,
    expectedReasonCode: 'funding_guard',
  );
}

BingxFuturesReplayFixture _fixtureBlocked() {
  return BingxFuturesReplayFixture(
    id: 'blocked',
    snapshotInput: _buildInput(
      trend: _TrendPattern.bullish,
      includeBuyWhale: true,
      includeSellWhale: false,
      sessionDeltaSigns: const <double>[20.0, 35.0, 10.0],
      openInterestStart: 500000,
      openInterestEnd: 500140,
    ),
    fundingRateDecimal: '0.0008',
    isConsensusSignable: false,
    blockingFactCodes: const <String>['pending_remote_break'],
    expectedDecision: BingxTvhDecisionKind.blocked,
    expectedReasonCode: 'consensus_guard',
  );
}

BingxFuturesMarketSnapshotInput _permuteInput(
  BingxFuturesMarketSnapshotInput a,
) {
  return BingxFuturesMarketSnapshotInput(
    instrument: a.instrument,
    prices: a.prices,
    candles: a.candles.reversed.toList(),
    trades: a.trades.reversed.toList(),
    openInterest: a.openInterest.reversed.toList(),
    funding: a.funding,
    liquidityLevels: a.liquidityLevels.reversed.toList(),
    sessionVolumes: a.sessionVolumes.reversed.toList(),
    orderBookTopLevels: a.orderBookTopLevels.reversed.toList(),
  );
}

enum _TrendPattern { bullish, bearish, neutral }

BingxFuturesMarketSnapshotInput _buildInput({
  required _TrendPattern trend,
  required bool includeBuyWhale,
  required bool includeSellWhale,
  required List<double> sessionDeltaSigns,
  required double openInterestStart,
  required double openInterestEnd,
  bool keepLiquidityFarFromTrades = false,
}) {
  final candles = <BingxFuturesCandle>[
    ..._generate15mCandles(trend: trend, count: 220),
    ..._generate5mCandles(count: 80),
    _singleCandle(
      timeframe: '1m',
      openTimeUtc: '2026-04-25T09:59:00Z',
      closeTimeUtc: '2026-04-25T10:00:00Z',
      open: 100.0,
      high: 100.8,
      low: 99.8,
      close: 100.2,
    ),
    _singleCandle(
      timeframe: '1h',
      openTimeUtc: '2026-04-25T09:00:00Z',
      closeTimeUtc: '2026-04-25T10:00:00Z',
      open: 98.0,
      high: 104.0,
      low: 96.0,
      close: 100.0,
    ),
    _singleCandle(
      timeframe: '4h',
      openTimeUtc: '2026-04-25T08:00:00Z',
      closeTimeUtc: '2026-04-25T12:00:00Z',
      open: 97.0,
      high: 105.0,
      low: 95.0,
      close: 100.1,
    ),
    _singleCandle(
      timeframe: '1d',
      openTimeUtc: '2026-04-24T00:00:00Z',
      closeTimeUtc: '2026-04-25T00:00:00Z',
      open: 95.0,
      high: 106.0,
      low: 94.0,
      close: 100.0,
    ),
    _singleCandle(
      timeframe: '1w',
      openTimeUtc: '2026-04-18T00:00:00Z',
      closeTimeUtc: '2026-04-25T00:00:00Z',
      open: 92.0,
      high: 108.0,
      low: 90.0,
      close: 100.0,
    ),
  ];

  final trades = <BingxFuturesTrade>[
    const BingxFuturesTrade(
      tradeId: 't01',
      timestampUtc: '2026-04-25T09:59:20Z',
      side: 'buy',
      priceDecimal: '100.10',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't02',
      timestampUtc: '2026-04-25T09:59:25Z',
      side: 'sell',
      priceDecimal: '100.00',
      quantityDecimal: '0.19',
    ),
    const BingxFuturesTrade(
      tradeId: 't03',
      timestampUtc: '2026-04-25T09:59:30Z',
      side: 'buy',
      priceDecimal: '100.20',
      quantityDecimal: '0.21',
    ),
    const BingxFuturesTrade(
      tradeId: 't04',
      timestampUtc: '2026-04-25T09:59:35Z',
      side: 'sell',
      priceDecimal: '100.15',
      quantityDecimal: '0.20',
    ),
    const BingxFuturesTrade(
      tradeId: 't05',
      timestampUtc: '2026-04-25T09:59:40Z',
      side: 'buy',
      priceDecimal: '100.30',
      quantityDecimal: '0.22',
    ),
    if (includeBuyWhale)
      const BingxFuturesTrade(
        tradeId: 't06',
        timestampUtc: '2026-04-25T09:59:50Z',
        side: 'buy',
        priceDecimal: '106.02',
        quantityDecimal: '8.00',
      ),
    if (includeSellWhale)
      const BingxFuturesTrade(
        tradeId: 't07',
        timestampUtc: '2026-04-25T09:59:55Z',
        side: 'sell',
        priceDecimal: '93.98',
        quantityDecimal: '8.00',
      ),
  ];

  final liquidityLevels = <BingxFuturesLiquidityLevel>[
    BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'sellside',
      timeframe: '1h',
      priceDecimal: keepLiquidityFarFromTrades ? '120.00' : '106.00',
    ),
    BingxFuturesLiquidityLevel(
      kind: 'external',
      side: 'buyside',
      timeframe: '1h',
      priceDecimal: keepLiquidityFarFromTrades ? '80.00' : '94.00',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'sellside',
      timeframe: '5m',
      priceDecimal: '104.20',
    ),
    const BingxFuturesLiquidityLevel(
      kind: 'internal',
      side: 'buyside',
      timeframe: '5m',
      priceDecimal: '98.40',
    ),
  ];

  final sessions = <BingxFuturesSessionVolumePoint>[
    BingxFuturesSessionVolumePoint(
      session: 'asia',
      bucketStartUtc: '2026-04-25T00:00:00Z',
      volumeDecimal: '1100.0',
      deltaDecimal: sessionDeltaSigns[0].toStringAsFixed(4),
    ),
    BingxFuturesSessionVolumePoint(
      session: 'london',
      bucketStartUtc: '2026-04-25T07:00:00Z',
      volumeDecimal: '1800.0',
      deltaDecimal: sessionDeltaSigns[1].toStringAsFixed(4),
    ),
    BingxFuturesSessionVolumePoint(
      session: 'newyork',
      bucketStartUtc: '2026-04-25T13:00:00Z',
      volumeDecimal: '1500.0',
      deltaDecimal: sessionDeltaSigns[2].toStringAsFixed(4),
    ),
  ];

  return BingxFuturesMarketSnapshotInput(
    instrument: const BingxFuturesInstrumentMeta(
      symbol: 'BTC-USDT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      tickSizeDecimal: '0.10',
      qtyStepDecimal: '0.001',
      minQtyDecimal: '0.001',
      maxLeverageDecimal: '125',
    ),
    prices: const BingxFuturesPriceSnapshot(
      lastTradePriceDecimal: '100.20',
      markPriceDecimal: '100.15',
      indexPriceDecimal: '100.10',
    ),
    candles: candles,
    trades: trades,
    openInterest: <BingxFuturesOpenInterestPoint>[
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-25T09:45:00Z',
        openInterestDecimal: openInterestStart.toStringAsFixed(4),
      ),
      BingxFuturesOpenInterestPoint(
        timestampUtc: '2026-04-25T10:00:00Z',
        openInterestDecimal: openInterestEnd.toStringAsFixed(4),
      ),
    ],
    funding: const BingxFuturesFundingSnapshot(
      timestampUtc: '2026-04-25T10:00:00Z',
      fundingRateDecimal: '0.0001',
      nextFundingAtUtc: '2026-04-25T12:00:00Z',
    ),
    liquidityLevels: liquidityLevels,
    sessionVolumes: sessions,
    orderBookTopLevels: const <BingxFuturesOrderBookLevel>[
      BingxFuturesOrderBookLevel(
        side: 'bid',
        priceDecimal: '100.10',
        quantityDecimal: '9.0',
      ),
      BingxFuturesOrderBookLevel(
        side: 'ask',
        priceDecimal: '100.20',
        quantityDecimal: '9.5',
      ),
    ],
  );
}

List<BingxFuturesCandle> _generate15mCandles({
  required _TrendPattern trend,
  required int count,
}) {
  final result = <BingxFuturesCandle>[];
  var close = 100.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    close = switch (trend) {
      _TrendPattern.bullish => close + 0.05,
      _TrendPattern.bearish => close - 0.05,
      _TrendPattern.neutral => 100.0,
    };
    final high = (open > close ? open : close) + 0.2;
    final low = (open < close ? open : close) - 0.2;
    final openTime = DateTime.utc(2026, 4, 23).add(Duration(minutes: 15 * i));
    final closeTime = openTime.add(const Duration(minutes: 15));
    result.add(
      BingxFuturesCandle(
        timeframe: '15m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: high.toStringAsFixed(4),
        lowDecimal: low.toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '10.0',
        volumeQuoteDecimal: '1000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

List<BingxFuturesCandle> _generate5mCandles({required int count}) {
  final result = <BingxFuturesCandle>[];
  var close = 100.0;
  for (var i = 0; i < count; i++) {
    final open = close;
    final drift = (i % 6) * 0.02;
    final spike =
        i % 16 == 5
            ? 0.8
            : i % 16 == 11
            ? -0.8
            : 0.0;
    close = 100.0 + drift + spike;
    final high = (open > close ? open : close) + 0.6;
    final low = (open < close ? open : close) - 0.6;
    final openTime = DateTime.utc(2026, 4, 25, 3).add(Duration(minutes: 5 * i));
    final closeTime = openTime.add(const Duration(minutes: 5));
    result.add(
      BingxFuturesCandle(
        timeframe: '5m',
        openTimeUtc: openTime.toIso8601String(),
        closeTimeUtc: closeTime.toIso8601String(),
        openDecimal: open.toStringAsFixed(4),
        highDecimal: high.toStringAsFixed(4),
        lowDecimal: low.toStringAsFixed(4),
        closeDecimal: close.toStringAsFixed(4),
        volumeBaseDecimal: '100.0',
        volumeQuoteDecimal: '10000.0',
        isClosed: true,
      ),
    );
  }
  return result;
}

BingxFuturesCandle _singleCandle({
  required String timeframe,
  required String openTimeUtc,
  required String closeTimeUtc,
  required double open,
  required double high,
  required double low,
  required double close,
}) {
  return BingxFuturesCandle(
    timeframe: timeframe,
    openTimeUtc: openTimeUtc,
    closeTimeUtc: closeTimeUtc,
    openDecimal: open.toStringAsFixed(4),
    highDecimal: high.toStringAsFixed(4),
    lowDecimal: low.toStringAsFixed(4),
    closeDecimal: close.toStringAsFixed(4),
    volumeBaseDecimal: '100.0',
    volumeQuoteDecimal: '10000.0',
    isClosed: true,
  );
}
