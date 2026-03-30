import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/temperature_tomorrow_contract_service.dart';

void main() {
  group('TemperatureTomorrowContractSpec.fromManifestJson', () {
    test('parses valid v1 manifest for Liechtenstein contract', () {
      final spec = TemperatureTomorrowContractSpec.fromManifestJson(
        jsonEncode({
          'schema': 'hivra.plugin.manifest',
          'version': 1,
          'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
          'contract': {
            'kind': 'temperature_tomorrow_liechtenstein',
            'location_code': 'LI',
            'target_date_utc': '2026-03-31',
            'threshold_deci_celsius': 85,
            'proposer_rule': 'above',
            'draw_on_equal': true,
          },
        }),
      );

      expect(spec.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
      expect(spec.locationCode, 'LI');
      expect(spec.targetDateUtc, '2026-03-31');
      expect(spec.thresholdDeciCelsius, 85);
      expect(spec.proposerRule, TemperatureOutcomeRule.above);
      expect(spec.drawOnEqual, isTrue);
    });

    test('rejects unsupported location', () {
      expect(
        () => TemperatureTomorrowContractSpec.fromManifestJson(
          jsonEncode({
            'schema': 'hivra.plugin.manifest',
            'version': 1,
            'plugin_id': 'x',
            'contract': {
              'kind': 'temperature_tomorrow_liechtenstein',
              'location_code': 'CH',
              'target_date_utc': '2026-03-31',
              'threshold_deci_celsius': 85,
              'proposer_rule': 'above',
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TemperatureTomorrowContractService', () {
    test('returns blocked result when consensus is not signable', () {
      final service = TemperatureTomorrowContractService(
        readSignable: (_) => const ConsensusSignableResult(
          preview: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(code: 'pending_invitation', subjectId: 'abc'),
          ],
        ),
      );

      final result = service.execute(
        peerHex: _peerHex,
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 90),
      );

      expect(result.isExecutable, isFalse);
      expect(result.settlement, isNull);
      expect(result.blockingFacts.map((f) => f.code),
          contains('pending_invitation'));
    });

    test('settles proposer win when observed above threshold', () {
      final service =
          TemperatureTomorrowContractService(readSignable: _readySignable);

      final result = service.execute(
        peerHex: _peerHex,
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 91),
      );

      expect(result.isExecutable, isTrue);
      expect(result.settlement, isNotNull);
      expect(
        result.settlement!.outcome,
        TemperatureContractOutcome.proposerWins,
      );
      expect(result.settlement!.winnerRole, 'proposer');
      expect(result.settlement!.settlementHashHex.length, 64);
    });

    test('settles counterparty win when observed below threshold', () {
      final service =
          TemperatureTomorrowContractService(readSignable: _readySignable);

      final settlement = service.evaluateDeterministic(
        peerHex: _peerHex,
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 79),
      );

      expect(settlement.outcome, TemperatureContractOutcome.counterpartyWins);
      expect(settlement.winnerRole, 'counterparty');
    });

    test('settles draw when observed equals threshold and draw_on_equal', () {
      final service =
          TemperatureTomorrowContractService(readSignable: _readySignable);

      final settlement = service.evaluateDeterministic(
        peerHex: _peerHex,
        contract: _contract(),
        observation: _observation(observedDeciCelsius: 85),
      );

      expect(settlement.outcome, TemperatureContractOutcome.draw);
      expect(settlement.winnerRole, 'draw');
    });

    test('produces deterministic hash for identical inputs', () {
      final service =
          TemperatureTomorrowContractService(readSignable: _readySignable);
      final contract = _contract();
      final observation = _observation(observedDeciCelsius: 90);

      final first = service.evaluateDeterministic(
        peerHex: _peerHex,
        contract: contract,
        observation: observation,
      );
      final second = service.evaluateDeterministic(
        peerHex: _peerHex,
        contract: contract,
        observation: observation,
      );

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.settlementHashHex, second.settlementHashHex);
    });
  });
}

const String _peerHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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

ConsensusSignableResult _readySignable(String _) =>
    const ConsensusSignableResult(
      preview: ConsensusPreview(
        peerHex: _peerHex,
        peerLabel: 'peer',
        invitationCount: 1,
        relationshipCount: 1,
        hashHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        canonicalJson: '{}',
        blockingFacts: <ConsensusBlockingFact>[],
      ),
      blockingFacts: <ConsensusBlockingFact>[],
    );
