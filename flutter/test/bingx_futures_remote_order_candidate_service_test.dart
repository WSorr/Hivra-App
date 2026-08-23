import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/bingx_futures_tvh_rule_models.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_risk_input_service.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_sizing_service.dart';
import 'package:hivra_app/services/bingx_futures_remote_order_candidate_service.dart';

void main() {
  group('BingxFuturesRemoteOrderCandidateService', () {
    test('composes one bounded candidate from exact verified inputs', () async {
      final fixture = await _fixture();
      final result = await fixture.service.compose(
        untrustedMarketEvidenceBytes: fixture.evidence.wireBytes,
        trustedRunnerKey: fixture.publicKey,
        lastAcceptedSequence: 0,
        lastAcceptedEvidenceHashHex: _zeroHash,
        expectedRunnerBuildId: 'runner-build',
        expectedPluginId: 'hivra.bingx-futures-trading',
        expectedPluginVersion: '0.2.7-plugins',
        expectedPackageDigestHex: 'a' * 64,
        expectedHostAbi: 'dart-headless-v1',
        mandate: fixture.mandate,
        accountRisk: _completeRisk,
        accountRiskObservedAtUtc: fixture.now,
        contractRules: _rules,
        nowUtc: fixture.now,
        stopLossPercent: 5,
        minimumRiskReward: 2,
      );

      expect(result.status, BingxFuturesRemoteOrderCandidateStatus.ready);
      expect(result.candidateHashHex, matches(RegExp(r'^[0-9a-f]{64}$')));
      final candidate = jsonDecode(result.canonicalJson!);
      expect(
        candidate['contract_version'],
        BingxFuturesRemoteOrderCandidateService.contractVersion,
      );
      expect(
        candidate['market_evidence_hash_hex'],
        fixture.evidence.evidenceHashHex,
      );
      expect(candidate['mandate_id'], fixture.mandate.mandateId);
      expect(candidate['symbol'], 'BTC-USDT');
      expect(candidate['side'], 'buy');
      expect(candidate['quantity_decimal'], '0.099');
      expect(candidate['limit_price_decimal'], '100.5');
      expect(candidate['trigger_price_decimal'], '101');
      expect(candidate['take_profit_decimal'], '111');
      expect(candidate['valid_until_utc'], '2026-08-22T12:01:00.000Z');
    });

    test(
      'adapts one fresh candidate into the existing exact-order path',
      () async {
        final fixture = await _fixture();
        final result = await _compose(fixture);
        final intent = result.toExactOrderIntent(nowUtc: fixture.now);

        expect(intent, isNotNull);
        expect(intent!.orderType, 'limit');
        expect(intent.timeInForce, 'GTC');
        expect(intent.entryMode, 'zone_pending');
        expect(intent.intentHashHex, result.candidateHashHex);
        final admission = BingxFuturesRemoteMandateAdmission.issueExactOrder(
          mandate: fixture.mandate,
          runnerKeyId: '7' * 64,
          exactOrder: intent.toExactOrderJson(
            testOrder: fixture.mandate.testOrder,
          ),
          signCommitment: (_) => '8' * 128,
        );
        expect(admission, isNotNull);
        expect(
          admission!.exactOrder?['intent_hash_hex'],
          result.candidateHashHex,
        );
      },
    );

    test('binds one deterministic cycle to exact runner policy', () async {
      final fixture = await _fixture();
      final canonicalPolicy =
          BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
            stopLossPercent: 5,
            minimumRiskReward: 2,
          );
      expect(canonicalPolicy, <String, dynamic>{
        'runner_build_id': 'systemd-public-shadow-v1',
        'plugin_id': 'hivra.bingx-futures-trading',
        'plugin_version': '0.2.3',
        'package_digest_hex':
            '2cb440885a2fa473971364fb26cce304d079d393832b2b5bed6fd95517e61889',
        'host_abi': 'wasm32-wasi-preview1',
        'stop_loss_percent': 5.0,
        'minimum_risk_reward': 2.0,
      });
      final admission =
          BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
            mandate: fixture.mandate,
            runnerKeyId: '7' * 64,
            strategyPolicy: canonicalPolicy,
            signCommitment: (_) => '8' * 128,
          );

      expect(admission, isNotNull);
      expect(admission!.isDeterministicOrder, isTrue);
      expect(admission.isExactOrder, isFalse);
      expect(
        admission.toJson()['operation_kind'],
        BingxFuturesRemoteMandateAdmission.deterministicOrderOperationKind,
      );
      final reparsed = BingxFuturesRemoteMandateAdmission.parseAndVerify(
        untrustedWireBytes: utf8.encode(admission.canonicalJson),
        verifySignature:
            ({
              required messageHashHex,
              required participantIdHex,
              required signatureHex,
            }) => true,
      );
      expect(reparsed?.canonicalJson, admission.canonicalJson);

      final mutated = jsonDecode(admission.canonicalJson);
      mutated['strategy_policy']['minimum_risk_reward'] = 1;
      expect(
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
          untrustedWireBytes: utf8.encode(jsonEncode(mutated)),
          verifySignature:
              ({
                required messageHashHex,
                required participantIdHex,
                required signatureHex,
              }) => true,
        ),
        isNull,
      );
    });

    test('binds a bounded session and derives exact cycle identities', () async {
      final fixture = await _fixture();
      final admission =
          BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
            mandate: fixture.mandate,
            runnerKeyId: '7' * 64,
            strategyPolicy:
                BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                  stopLossPercent: 5,
                  minimumRiskReward: 2,
                ),
            startsAtUtc: fixture.now,
            intervalSeconds: 300,
            maxCycles: 12,
            signCommitment: (_) => '8' * 128,
          );

      expect(admission, isNotNull);
      expect(admission!.isDeterministicSession, isTrue);
      expect(admission.isDeterministicOrder, isFalse);
      expect(admission.authorizedUses, 12);
      expect(admission.deterministicCycleOperationId(0), hasLength(64));
      expect(
        admission.deterministicCycleOperationId(1),
        isNot(admission.deterministicCycleOperationId(0)),
      );
      expect(admission.deterministicCycleOperationId(12), isNull);
      final reparsed = BingxFuturesRemoteMandateAdmission.parseAndVerify(
        untrustedWireBytes: utf8.encode(admission.canonicalJson),
        verifySignature:
            ({
              required messageHashHex,
              required participantIdHex,
              required signatureHex,
            }) => true,
      );
      expect(reparsed?.canonicalJson, admission.canonicalJson);

      final mutated = jsonDecode(admission.canonicalJson);
      mutated['session_policy']['max_cycles'] = 13;
      mutated['max_uses'] = 13;
      expect(
        BingxFuturesRemoteMandateAdmission.parseAndVerify(
          untrustedWireBytes: utf8.encode(jsonEncode(mutated)),
          verifySignature:
              ({
                required messageHashHex,
                required participantIdHex,
                required signatureHex,
              }) => true,
        ),
        isNull,
      );
      expect(
        BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
          mandate: fixture.mandate,
          runnerKeyId: '7' * 64,
          strategyPolicy:
              BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                stopLossPercent: 5,
                minimumRiskReward: 2,
              ),
          startsAtUtc: fixture.now,
          intervalSeconds: 30,
          maxCycles: 12,
          signCommitment: (_) => '8' * 128,
        ),
        isNull,
      );
    });

    test('session revocation binds exact session runner and Capsule', () async {
      final fixture = await _fixture();
      final session =
          BingxFuturesRemoteMandateAdmission.issueDeterministicSession(
            mandate: fixture.mandate,
            runnerKeyId: '7' * 64,
            strategyPolicy:
                BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                  stopLossPercent: 5,
                  minimumRiskReward: 2,
                ),
            startsAtUtc: fixture.now,
            intervalSeconds: 300,
            maxCycles: 12,
            signCommitment: (_) => '8' * 128,
          )!;
      final revocation = BingxFuturesRemoteSessionRevocation.issue(
        session: session,
        revokedAtUtc: fixture.now.add(const Duration(minutes: 1)),
        signCommitment: (_) => '9' * 128,
      );

      expect(revocation, isNotNull);
      expect(revocation!.targetSessionOperationId, session.operationId);
      expect(revocation.runnerKeyId, session.runnerKeyId);
      expect(revocation.capsuleRootHex, session.mandate.capsuleRootHex);
      expect(
        BingxFuturesRemoteSessionRevocation.parseAndVerify(
          untrustedWireBytes: utf8.encode(revocation.canonicalJson),
          verifySignature:
              ({
                required messageHashHex,
                required participantIdHex,
                required signatureHex,
              }) => true,
        )?.canonicalJson,
        revocation.canonicalJson,
      );

      for (final key in <String>[
        'target_session_operation_id',
        'runner_key_id',
        'capsule_root_hex',
        'revoked_at_utc',
        'signature_hex',
      ]) {
        final mutated = jsonDecode(revocation.canonicalJson);
        mutated[key] =
            key == 'revoked_at_utc'
                ? '2026-08-22T12:02:00.000Z'
                : key == 'signature_hex'
                ? 'a' * 128
                : 'a' * 64;
        expect(
          BingxFuturesRemoteSessionRevocation.parseAndVerify(
            untrustedWireBytes: utf8.encode(jsonEncode(mutated)),
            verifySignature:
                ({
                  required messageHashHex,
                  required participantIdHex,
                  required signatureHex,
                }) => key != 'signature_hex',
          ),
          isNull,
          reason: key,
        );
      }
      expect(
        BingxFuturesRemoteSessionRevocation.issue(
          session:
              BingxFuturesRemoteMandateAdmission.issueDeterministicOrder(
                mandate: fixture.mandate,
                runnerKeyId: '7' * 64,
                strategyPolicy:
                    BingxFuturesRemoteMandateAdmission.deterministicStrategyPolicy(
                      stopLossPercent: 5,
                      minimumRiskReward: 2,
                    ),
                signCommitment: (_) => '8' * 128,
              )!,
          revokedAtUtc: fixture.now,
          signCommitment: (_) => '9' * 128,
        ),
        isNull,
      );
    });

    test('does not adapt stale or mutated candidate bytes', () async {
      final fixture = await _fixture();
      final result = await _compose(fixture);

      expect(
        result.toExactOrderIntent(
          nowUtc: fixture.now.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
      final mutated = BingxFuturesRemoteOrderCandidateResult(
        status: result.status,
        reasonCode: result.reasonCode,
        canonicalJson: result.canonicalJson!.replaceFirst(
          '"quantity_decimal":"0.099"',
          '"quantity_decimal":"0.098"',
        ),
        candidateHashHex: result.candidateHashHex,
      );
      expect(mutated.toExactOrderIntent(nowUtc: fixture.now), isNull);

      final decoded = jsonDecode(result.canonicalJson!) as Map<String, dynamic>;
      decoded['stop_loss_decimal'] = null;
      final incompleteCanonical = jsonEncode(decoded);
      final incomplete = BingxFuturesRemoteOrderCandidateResult(
        status: result.status,
        reasonCode: result.reasonCode,
        canonicalJson: incompleteCanonical,
        candidateHashHex:
            sha256.convert(utf8.encode(incompleteCanonical)).toString(),
      );
      expect(incomplete.toExactOrderIntent(nowUtc: fixture.now), isNull);
    });

    test('rejects a proposal reused under another symbol mandate', () async {
      final fixture = await _fixture(mandateSymbol: 'ETH-USDT');
      final result = await _compose(fixture);
      expect(result.status, BingxFuturesRemoteOrderCandidateStatus.blocked);
      expect(result.reasonCode, 'market_symbol_mismatch');
    });

    test('rejects incomplete account state and stale evidence', () async {
      final fixture = await _fixture();
      final incomplete = await _compose(
        fixture,
        accountRisk: const BingxFuturesExchangeRiskInput(
          accountEquityQuoteDecimal: '1000',
          realizedDailyPnlQuoteDecimal: '0',
          concurrentPositions: 0,
          lossStreakCount: 0,
          lastLossAtUtc: null,
          usedBalanceFallback: true,
          usedPnlFallback: false,
          usedPositionsFallback: false,
          balanceUnavailableCode: 'balance_unavailable',
        ),
      );
      expect(incomplete.reasonCode, 'account_risk_incomplete');

      final stale = await _compose(
        fixture,
        now: fixture.now.add(const Duration(minutes: 2)),
      );
      expect(stale.reasonCode, 'market_evidence_stale');

      final staleAccount = await _compose(
        fixture,
        accountRiskObservedAt: fixture.now.subtract(
          BingxFuturesRemoteOrderCandidateService.maximumAccountRiskAge +
              const Duration(milliseconds: 1),
        ),
      );
      expect(staleAccount.reasonCode, 'account_risk_stale');
    });

    test('rejects a risk decision outside the mandate', () async {
      final fixture = await _fixture(maxRiskPerTradePercent: 0.01);
      final result = await _compose(fixture);
      expect(result.status, BingxFuturesRemoteOrderCandidateStatus.blocked);
      expect(result.reasonCode, 'risk_per_trade_exceeded');
      expect(result.canonicalJson, isNull);
    });

    test('rejects non-finite strategy inputs', () async {
      final fixture = await _fixture();
      final result = await fixture.service.compose(
        untrustedMarketEvidenceBytes: fixture.evidence.wireBytes,
        trustedRunnerKey: fixture.publicKey,
        lastAcceptedSequence: 0,
        lastAcceptedEvidenceHashHex: _zeroHash,
        expectedRunnerBuildId: 'runner-build',
        expectedPluginId: 'hivra.bingx-futures-trading',
        expectedPluginVersion: '0.2.7-plugins',
        expectedPackageDigestHex: 'a' * 64,
        expectedHostAbi: 'dart-headless-v1',
        mandate: fixture.mandate,
        accountRisk: _completeRisk,
        accountRiskObservedAtUtc: fixture.now,
        contractRules: _rules,
        nowUtc: fixture.now,
        stopLossPercent: double.nan,
        minimumRiskReward: 2,
      );
      expect(result.reasonCode, 'strategy_risk_input_invalid');
    });
  });
}

Future<BingxFuturesRemoteOrderCandidateResult> _compose(
  _CandidateFixture fixture, {
  BingxFuturesExchangeRiskInput accountRisk = _completeRisk,
  DateTime? accountRiskObservedAt,
  DateTime? now,
}) => fixture.service.compose(
  untrustedMarketEvidenceBytes: fixture.evidence.wireBytes,
  trustedRunnerKey: fixture.publicKey,
  lastAcceptedSequence: 0,
  lastAcceptedEvidenceHashHex: _zeroHash,
  expectedRunnerBuildId: 'runner-build',
  expectedPluginId: 'hivra.bingx-futures-trading',
  expectedPluginVersion: '0.2.7-plugins',
  expectedPackageDigestHex: 'a' * 64,
  expectedHostAbi: 'dart-headless-v1',
  mandate: fixture.mandate,
  accountRisk: accountRisk,
  accountRiskObservedAtUtc: accountRiskObservedAt ?? fixture.now,
  contractRules: _rules,
  nowUtc: now ?? fixture.now,
  stopLossPercent: 5,
  minimumRiskReward: 2,
);

Future<_CandidateFixture> _fixture({
  String mandateSymbol = 'BTC-USDT',
  double maxRiskPerTradePercent = 2,
}) async {
  final now = DateTime.utc(2026, 8, 22, 12);
  final signingKey = await Ed25519().newKeyPairFromSeed(
    List<int>.generate(32, (index) => index),
  );
  final publicKey = await signingKey.extractPublicKey();
  final proposal = <String, dynamic>{
    'schema_version': 2,
    'contract': 'bingx_futures_live_decision_v2',
    'market_snapshot_hash_hex': '1' * 64,
    'feature_hash_hex': '2' * 64,
    'tvh_decision_hash_hex': '3' * 64,
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
      'low_decimal': '100',
      'high_decimal': '101',
      'source': 'micro_sweep_reclaim',
      'side_reason': 'buy_signal',
      'conflict': false,
      'target_retest_pct': 0.01,
      'needs_farther_retest': false,
      'anchor_source': 'micro_sweep_reclaim',
      'anchor_executable': true,
      'anchor_lifecycle': 'fresh',
      'liquidity_event_id': '4' * 64,
      'liquidity_event_at_utc': '2026-08-22T11:50:00Z',
      'latest_closed_micro_bar_at_utc': '2026-08-22T11:55:00Z',
    },
    'profit_target': <String, dynamic>{
      'kind': 'opposite_external_liquidity',
      'price_decimal': '111',
      'source': '1d_fresh_high',
      'event_at_utc': '2026-08-21T00:00:00Z',
    },
    'reason_codes': <Map<String, dynamic>>[
      <String, dynamic>{'code': 'funding_guard', 'passed': true},
    ],
  };
  final proposalJson = jsonEncode(proposal);
  const harness = BingxFuturesDeterministicReplayHarnessService();
  final unsigned = harness.buildShadowEvidence(
    publicRun: BingxFuturesReplayRunResult(
      fixtureId: 'live:BTC-USDT',
      marketSnapshotHashHex: '1' * 64,
      featureHashHex: '2' * 64,
      decisionHashHex: sha256.convert(utf8.encode(proposalJson)).toString(),
      decision: BingxTvhDecisionKind.long,
      topReasonCode: 'funding_guard',
      marketSymbol: 'BTC-USDT',
      marketProposalStatus: 'READY',
      marketProposalJson: proposalJson,
    ),
    runnerBuildId: 'runner-build',
    pluginId: 'hivra.bingx-futures-trading',
    pluginVersion: '0.2.7-plugins',
    packageDigestHex: 'a' * 64,
    hostAbi: 'dart-headless-v1',
    observedAtEpochMs: now.millisecondsSinceEpoch,
    validUntilEpochMs:
        now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    sequence: 1,
    previousEvidenceHashHex: _zeroHash,
    runnerKeyId: sha256.convert(publicKey.bytes).toString(),
    contractVersion: 'trading-shadow-evidence-v2',
  );
  final signature = await Ed25519().sign(
    unsigned.signingPayload,
    keyPair: signingKey,
  );
  final mandate = BingxFuturesTradingMandate.issue(
    capsuleRootHex: '5' * 64,
    accountBindingHashHex: '6' * 64,
    symbol: mandateSymbol,
    testOrder: true,
    issuedAtUtc: now.subtract(const Duration(minutes: 1)),
    expiresAtUtc: now.add(const Duration(hours: 1)),
    maxOrderNotionalQuoteDecimal: '10',
    maxRiskPerTradePercent: maxRiskPerTradePercent,
    maxDailyLossPercent: 3,
    maxConcurrentPositions: 1,
    cooldownAfterLossStreak: 2,
    cooldownMinutes: 10,
    maxEffects: 1,
  );
  return _CandidateFixture(
    service: BingxFuturesRemoteOrderCandidateService(
      sizing: BingxFuturesOrderSizingService(
        exchange: BingxFuturesExchangeService(),
      ),
    ),
    evidence: unsigned.withSignature(_hex(signature.bytes)),
    publicKey: publicKey,
    mandate: mandate,
    now: now,
  );
}

class _CandidateFixture {
  final BingxFuturesRemoteOrderCandidateService service;
  final BingxFuturesShadowEvidence evidence;
  final SimplePublicKey publicKey;
  final BingxFuturesTradingMandate mandate;
  final DateTime now;

  const _CandidateFixture({
    required this.service,
    required this.evidence,
    required this.publicKey,
    required this.mandate,
    required this.now,
  });
}

const _completeRisk = BingxFuturesExchangeRiskInput(
  accountEquityQuoteDecimal: '1000',
  realizedDailyPnlQuoteDecimal: '0',
  concurrentPositions: 0,
  lossStreakCount: 0,
  lastLossAtUtc: null,
  usedBalanceFallback: false,
  usedPnlFallback: false,
  usedPositionsFallback: false,
);

const _rules = BingxFuturesContractRules(
  symbol: 'BTC-USDT',
  minimumQuantityDecimal: '0.001',
  minimumNotionalQuoteDecimal: '1',
  quantityPrecision: 3,
  pricePrecision: 2,
);

const _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
