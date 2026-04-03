import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/plugin_demo_contract_runner_service.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/temperature_tomorrow_contract_service.dart';

void main() {
  group('PluginHostApiService', () {
    test('returns executed response with deterministic hash', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({
          required contract,
          required observation,
        }) {
          return PluginDemoRunResult(
            state: PluginDemoRunState.executed,
            pairResults: const <PluginDemoPairRunResult>[
              PluginDemoPairRunResult(
                peerHex: _peerHex,
                peerLabel: 'peer',
                settlement: TemperatureContractSettlement(
                  pluginId: PluginHostApiService.temperaturePluginId,
                  peerHex: _peerHex,
                  locationCode: 'LI',
                  targetDateUtc: '2026-04-01',
                  thresholdDeciCelsius: 85,
                  observedDeciCelsius: 90,
                  proposerRule: TemperatureOutcomeRule.above,
                  outcome: TemperatureContractOutcome.proposerWins,
                  winnerRole: 'proposer',
                  canonicalJson: '{"demo":"settlement"}',
                  settlementHashHex:
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  oracleSourceId: 'oracle.mock.weather.v1',
                  oracleEventId: 'evt-1',
                  oracleRecordedAtUtc: '2026-04-01T12:00:00Z',
                ),
                blockingFacts: <ConsensusBlockingFact>[],
              ),
            ],
            blockingFacts: const <ConsensusBlockingFact>[],
          );
        },
      );

      final request = PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: PluginHostApiService.temperaturePluginId,
        method: PluginHostApiService.settleTemperatureMethod,
        args: _validArgs(),
      );
      final first = service.execute(request);
      final second = service.execute(request);

      expect(first.status, PluginHostApiStatus.executed);
      expect(first.errorCode, isNull);
      expect(first.result, isNotNull);
      expect(first.result!['outcome'], 'proposerWins');
      expect(first.responseHashHex.length, 64);
      expect(first.responseHashHex, second.responseHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('returns blocked response when demo-run is blocked', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({
          required contract,
          required observation,
        }) {
          return const PluginDemoRunResult(
            state: PluginDemoRunState.blocked,
            pairResults: <PluginDemoPairRunResult>[
              PluginDemoPairRunResult(
                peerHex: _peerHex,
                peerLabel: 'peer',
                settlement: null,
                blockingFacts: <ConsensusBlockingFact>[
                  ConsensusBlockingFact(
                    code: 'pending_invitation',
                    subjectId: 'deadbeef',
                  ),
                ],
              ),
            ],
            blockingFacts: <ConsensusBlockingFact>[
              ConsensusBlockingFact(
                code: 'pending_invitation',
                subjectId: 'deadbeef',
              ),
            ],
          );
        },
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.temperaturePluginId,
          method: PluginHostApiService.settleTemperatureMethod,
          args: _validArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.blocked);
      expect(response.result, isNull);
      expect(response.blockingFacts.map((f) => f.code),
          contains('pending_invitation'));
      expect(response.errorCode, isNull);
    });

    test('returns rejected response for unsupported plugin id', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.unknown.v1',
          method: PluginHostApiService.settleTemperatureMethod,
          args: _validArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'unsupported_plugin');
      expect(response.result, isNull);
    });

    test('returns rejected response for invalid args', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.temperaturePluginId,
          method: PluginHostApiService.settleTemperatureMethod,
          args: <String, dynamic>{
            ..._validArgs(),
            'target_date_utc': '2026/04/01',
          },
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'invalid_args');
    });
  });
}

const String _peerHex =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> _validArgs() => <String, dynamic>{
      'target_date_utc': '2026-04-01',
      'threshold_deci_celsius': 85,
      'proposer_rule': 'above',
      'draw_on_equal': true,
      'location_code': 'LI',
      'observed_deci_celsius': 90,
      'oracle_source_id': 'oracle.mock.weather.v1',
      'oracle_event_id': 'evt-1',
      'oracle_recorded_at_utc': '2026-04-01T12:00:00Z',
    };
