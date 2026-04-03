import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/plugin_demo_contract_runner_service.dart';
import 'package:hivra_app/services/temperature_tomorrow_contract_service.dart';

void main() {
  group('PluginDemoContractRunnerService', () {
    test('returns noPairwisePaths when consensus has no peers', () {
      final runner = PluginDemoContractRunnerService(
        readChecks: () => const <ConsensusCheck>[],
        contractService: TemperatureTomorrowContractService(
          readSignable: (_) => _signable(),
        ),
      );

      final result = runner.runTemperatureTomorrowDemo(
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 90),
      );

      expect(result.state, PluginDemoRunState.noPairwisePaths);
      expect(result.pairResults, isEmpty);
      expect(result.peerHex, isNull);
      expect(result.settlement, isNull);
    });

    test('returns partial when some peers execute and some are blocked', () {
      final runner = PluginDemoContractRunnerService(
        readChecks: () => const <ConsensusCheck>[
          ConsensusCheck(
            peerHex: _blockedPeer,
            peerLabel: 'blocked',
            invitationCount: 1,
            relationshipCount: 1,
            hashHex: 'a',
            canonicalJson: '{}',
            isSignable: false,
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(code: 'pending_invitation'),
            ],
          ),
          ConsensusCheck(
            peerHex: _readyPeer,
            peerLabel: 'ready',
            invitationCount: 1,
            relationshipCount: 1,
            hashHex: 'b',
            canonicalJson: '{}',
            isSignable: true,
            blockingFacts: <ConsensusBlockingFact>[],
          ),
        ],
        contractService: TemperatureTomorrowContractService(
          readSignable: (peerHex) => peerHex == _readyPeer
              ? _signable()
              : const ConsensusSignableResult(
                  preview: null,
                  blockingFacts: <ConsensusBlockingFact>[
                    ConsensusBlockingFact(code: 'pending_invitation'),
                  ],
                ),
        ),
      );

      final result = runner.runTemperatureTomorrowDemo(
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 90),
      );

      expect(result.state, PluginDemoRunState.partial);
      expect(result.readyPairCount, 1);
      expect(result.blockedPairCount, 1);
      expect(result.pairResults, hasLength(2));
      expect(result.peerHex, _readyPeer);
      expect(result.settlement, isNotNull);
      expect(
        result.settlement!.outcome,
        TemperatureContractOutcome.proposerWins,
      );
    });

    test('returns executed when all peers are signable', () {
      final runner = PluginDemoContractRunnerService(
        readChecks: () => const <ConsensusCheck>[
          ConsensusCheck(
            peerHex: _readyPeer,
            peerLabel: 'ready',
            invitationCount: 1,
            relationshipCount: 1,
            hashHex: 'b',
            canonicalJson: '{}',
            isSignable: true,
            blockingFacts: <ConsensusBlockingFact>[],
          ),
        ],
        contractService: TemperatureTomorrowContractService(
          readSignable: (_) => _signable(),
        ),
      );

      final result = runner.runTemperatureTomorrowDemo(
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 90),
      );

      expect(result.state, PluginDemoRunState.executed);
      expect(result.readyPairCount, 1);
      expect(result.blockedPairCount, 0);
      expect(result.pairResults, hasLength(1));
      expect(result.pairResults.single.isExecuted, isTrue);
    });

    test('returns blocked when only blocked peer exists', () {
      final runner = PluginDemoContractRunnerService(
        readChecks: () => const <ConsensusCheck>[
          ConsensusCheck(
            peerHex: _blockedPeer,
            peerLabel: 'blocked',
            invitationCount: 1,
            relationshipCount: 1,
            hashHex: 'a',
            canonicalJson: '{}',
            isSignable: false,
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(code: 'pending_invitation'),
            ],
          ),
        ],
        contractService: TemperatureTomorrowContractService(
          readSignable: (_) => const ConsensusSignableResult(
            preview: null,
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(code: 'pending_invitation'),
            ],
          ),
        ),
      );

      final result = runner.runTemperatureTomorrowDemo(
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 90),
      );

      expect(result.state, PluginDemoRunState.blocked);
      expect(result.readyPairCount, 0);
      expect(result.blockedPairCount, 1);
      expect(result.peerHex, _blockedPeer);
      expect(result.settlement, isNull);
      expect(result.blockingFacts.map((f) => f.code),
          contains('pending_invitation'));
    });
  });
}

const String _readyPeer =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _blockedPeer =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

TemperatureTomorrowContractSpec _contract() =>
    const TemperatureTomorrowContractSpec(
      pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
      locationCode: 'LI',
      targetDateUtc: '2026-03-31',
      thresholdDeciCelsius: 85,
      proposerRule: TemperatureOutcomeRule.above,
      drawOnEqual: true,
    );

TemperatureOracleObservation _observation({required int observedDeciCelsius}) =>
    TemperatureOracleObservation(
      sourceId: 'oracle.mock.weather.v1',
      eventId: 'evt-001',
      locationCode: 'LI',
      targetDateUtc: '2026-03-31',
      recordedAtUtc: '2026-03-31T12:00:00Z',
      observedDeciCelsius: observedDeciCelsius,
    );

ConsensusSignableResult _signable() => const ConsensusSignableResult(
      preview: ConsensusPreview(
        peerHex: _readyPeer,
        peerLabel: 'ready',
        invitationCount: 1,
        relationshipCount: 1,
        hashHex:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        canonicalJson: '{}',
        blockingFacts: <ConsensusBlockingFact>[],
      ),
      blockingFacts: <ConsensusBlockingFact>[],
    );
