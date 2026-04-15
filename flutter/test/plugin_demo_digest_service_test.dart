import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/plugin_demo_contract_runner_service.dart';
import 'package:hivra_app/services/plugin_demo_digest_service.dart';
import 'package:hivra_app/services/temperature_tomorrow_contract_service.dart';

void main() {
  group('PluginDemoDigestService', () {
    const service = PluginDemoDigestService();

    test('guard digest is stable when settlement payload changes', () {
      final resultA = PluginDemoRunResult(
        state: PluginDemoRunState.executed,
        pairResults: <PluginDemoPairRunResult>[
          _executedPair(
            peerHex: _peerA,
            consensusHashHex: _consensusA,
            settlementHashHex: _settlementA1,
          ),
          _executedPair(
            peerHex: _peerB,
            consensusHashHex: _consensusB,
            settlementHashHex: _settlementB1,
          ),
        ],
        blockingFacts: const <ConsensusBlockingFact>[],
      );
      final resultB = PluginDemoRunResult(
        state: PluginDemoRunState.executed,
        pairResults: <PluginDemoPairRunResult>[
          _executedPair(
            peerHex: _peerA,
            consensusHashHex: _consensusA,
            settlementHashHex: _settlementA2,
          ),
          _executedPair(
            peerHex: _peerB,
            consensusHashHex: _consensusB,
            settlementHashHex: _settlementB2,
          ),
        ],
        blockingFacts: const <ConsensusBlockingFact>[],
      );

      final digestA = service.build(resultA);
      final digestB = service.build(resultB);

      expect(digestA.guardDigestHex, digestB.guardDigestHex);
      expect(digestA.runDigestHex, isNot(digestB.runDigestHex));
    });

    test('digests are order invariant for pair list permutations', () {
      final pairA = _executedPair(
        peerHex: _peerA,
        consensusHashHex: _consensusA,
        settlementHashHex: _settlementA1,
      );
      final pairB = _blockedPair(
        peerHex: _peerB,
        consensusHashHex: _consensusB,
        facts: const <ConsensusBlockingFact>[
          ConsensusBlockingFact(
              code: 'pending_remote_break', subjectId: _peerB),
        ],
      );

      final resultA = PluginDemoRunResult(
        state: PluginDemoRunState.partial,
        pairResults: <PluginDemoPairRunResult>[pairA, pairB],
        blockingFacts: const <ConsensusBlockingFact>[
          ConsensusBlockingFact(
              code: 'pending_remote_break', subjectId: _peerB),
        ],
      );
      final resultB = PluginDemoRunResult(
        state: PluginDemoRunState.partial,
        pairResults: <PluginDemoPairRunResult>[pairB, pairA],
        blockingFacts: const <ConsensusBlockingFact>[
          ConsensusBlockingFact(
              code: 'pending_remote_break', subjectId: _peerB),
        ],
      );

      final digestA = service.build(resultA);
      final digestB = service.build(resultB);

      expect(digestA.guardDigestHex, digestB.guardDigestHex);
      expect(digestA.runDigestHex, digestB.runDigestHex);
    });

    test('guard digest changes when blocking facts change', () {
      final blockedA = PluginDemoRunResult(
        state: PluginDemoRunState.blocked,
        pairResults: <PluginDemoPairRunResult>[
          _blockedPair(
            peerHex: _peerA,
            consensusHashHex: _consensusA,
            facts: const <ConsensusBlockingFact>[
              ConsensusBlockingFact(
                  code: 'pending_invitation', subjectId: _peerA),
            ],
          ),
        ],
        blockingFacts: const <ConsensusBlockingFact>[
          ConsensusBlockingFact(code: 'pending_invitation', subjectId: _peerA),
        ],
      );
      final blockedB = PluginDemoRunResult(
        state: PluginDemoRunState.blocked,
        pairResults: <PluginDemoPairRunResult>[
          _blockedPair(
            peerHex: _peerA,
            consensusHashHex: _consensusA,
            facts: const <ConsensusBlockingFact>[
              ConsensusBlockingFact(
                code: 'pending_remote_break',
                subjectId: _peerA,
              ),
            ],
          ),
        ],
        blockingFacts: const <ConsensusBlockingFact>[
          ConsensusBlockingFact(
              code: 'pending_remote_break', subjectId: _peerA),
        ],
      );

      final digestA = service.build(blockedA);
      final digestB = service.build(blockedB);

      expect(digestA.guardDigestHex, isNot(digestB.guardDigestHex));
    });
  });
}

PluginDemoPairRunResult _executedPair({
  required String peerHex,
  required String consensusHashHex,
  required String settlementHashHex,
}) {
  return PluginDemoPairRunResult(
    peerHex: peerHex,
    peerLabel: peerHex,
    consensusHashHex: consensusHashHex,
    settlement: TemperatureContractSettlement(
      pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
      peerHex: peerHex,
      locationCode: 'LI',
      targetDateUtc: '2026-04-11',
      thresholdDeciCelsius: 85,
      observedDeciCelsius: 90,
      proposerRule: TemperatureOutcomeRule.above,
      outcome: TemperatureContractOutcome.proposerWins,
      winnerRole: 'proposer',
      canonicalJson: '{"kind":"demo"}',
      settlementHashHex: settlementHashHex,
      oracleSourceId: 'oracle.mock.weather.v1',
      oracleEventId: 'demo-event',
      oracleRecordedAtUtc: '2026-04-10T00:00:00Z',
    ),
    blockingFacts: const <ConsensusBlockingFact>[],
  );
}

PluginDemoPairRunResult _blockedPair({
  required String peerHex,
  required String consensusHashHex,
  required List<ConsensusBlockingFact> facts,
}) {
  return PluginDemoPairRunResult(
    peerHex: peerHex,
    peerLabel: peerHex,
    consensusHashHex: consensusHashHex,
    settlement: null,
    blockingFacts: facts,
  );
}

const String _peerA =
    '0517c48e1c20135024635b3a8c5120408becaf0dd0f16ced2caec8b31fcc4c57';
const String _peerB =
    'f4fcd71c1a0f9a9a8ed5b853f7448c7fd4854daa22eb179bd8d30627cf080378';
const String _consensusA =
    '6fe47a8e25bbd256c3ac795d6580c0a6283f276c19f7069b63d21f6b57f2a6a4';
const String _consensusB =
    '326797ce2900f2bd99ebc1ef3f973cf5f737fd0d59543fd0f9055b26bf8c06b7';
const String _settlementA1 =
    '8b25dc8e77c81497cb95f2d0600fc09aa2cad97a2bcc3047fe51071dad4a4c61';
const String _settlementA2 =
    '9c7ce71344e76592325ed82a54686a7da4dd868b681f0f560d4e89309d2d8971';
const String _settlementB1 =
    'db9d4d4735f14e07ec507dbd04d765e9471367484c190093e22632cf40dce54e';
const String _settlementB2 =
    'a2860892f0675e3559c73a839034969155b003bc2ff3efac8e81fe04d00f9d78';
