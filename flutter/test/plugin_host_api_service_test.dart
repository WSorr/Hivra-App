import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/bingx_trading_contract_service.dart';
import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/capsule_chat_contract_service.dart';
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
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
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
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
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

    test('executeWithRuntimeHook tags external package metadata', () async {
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
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        resolveRuntimeBinding: (_) async =>
            const PluginRuntimeBinding.externalPackage(
          packageId: 'pkg-123',
          packageVersion: '1.0.0',
          packageKind: 'zip',
          contractKind: 'trade_signal_v1',
        ),
      );

      final response = await service.executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.temperaturePluginId,
          method: PluginHostApiService.settleTemperatureMethod,
          args: _validArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.executionSource, 'external_package');
      expect(response.executionPackageId, 'pkg-123');
      expect(response.executionPackageVersion, '1.0.0');
      expect(response.executionPackageKind, 'zip');
      expect(response.executionContractKind, 'trade_signal_v1');
    });

    test('returns rejected response for unsupported plugin id', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
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
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
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

    test('executes bingx plugin request with deterministic intent hash', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: ({
          required peerHex,
          required clientOrderId,
          required symbol,
          required side,
          required orderType,
          required quantityDecimal,
          required limitPriceDecimal,
          required timeInForce,
          required entryMode,
          required zoneSide,
          required zoneLowDecimal,
          required zoneHighDecimal,
          required zonePriceRule,
          required manualEntryPriceDecimal,
          required triggerPriceDecimal,
          required stopLossDecimal,
          required takeProfitDecimal,
          required createdAtUtc,
          required strategyTag,
        }) =>
            const BingxTradingExecutionResult(
          intent: BingxSpotOrderIntent(
            pluginId: BingxTradingContractService.pluginId,
            peerHex: _peerHex,
            clientOrderId: 'ord-1',
            symbol: 'BTC-USDT',
            side: BingxOrderSide.buy,
            orderType: BingxOrderType.limit,
            quantityDecimal: '0.01',
            limitPriceDecimal: '60000',
            timeInForce: 'GTC',
            entryMode: BingxEntryMode.direct,
            zoneSide: null,
            zoneLowDecimal: null,
            zoneHighDecimal: null,
            zonePriceRule: null,
            triggerPriceDecimal: null,
            stopLossDecimal: null,
            takeProfitDecimal: null,
            createdAtUtc: '2026-04-09T10:00:00Z',
            strategyTag: 'demo',
            canonicalJson: '{"bingx":"intent"}',
            intentHashHex:
                'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          ),
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final request = PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: PluginHostApiService.bingxTradingPluginId,
        method: PluginHostApiService.placeBingxSpotOrderIntentMethod,
        args: _validBingxArgs(),
      );

      final first = service.execute(request);
      final second = service.execute(request);

      expect(first.status, PluginHostApiStatus.executed);
      expect(first.result!['intent_hash_hex'],
          contains('dddddddddddddddddddddddddddddddd'));
      expect(first.responseHashHex, second.responseHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('returns rejected response for bingx invalid args', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.bingxTradingPluginId,
          method: PluginHostApiService.placeBingxSpotOrderIntentMethod,
          args: <String, dynamic>{
            ..._validBingxArgs(),
            'peer_hex': 'bad-peer',
          },
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'invalid_args');
    });

    test(
        'executes capsule chat plugin request with deterministic envelope hash',
        () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) {
          return CapsuleChatExecutionResult(
            envelope: const CapsuleChatEnvelope(
              pluginId: CapsuleChatContractService.pluginId,
              peerHex: _peerHex,
              clientMessageId: 'm1',
              messageText: 'hello',
              createdAtUtc: '2026-04-04T10:00:00Z',
              canonicalJson: '{"chat":"envelope"}',
              envelopeHashHex:
                  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            ),
            blockingFacts: const <ConsensusBlockingFact>[],
          );
        },
      );

      final request = PluginHostApiRequest(
        schemaVersion: 1,
        pluginId: PluginHostApiService.capsuleChatPluginId,
        method: PluginHostApiService.postCapsuleChatMethod,
        args: <String, dynamic>{
          'peer_hex': _peerHex,
          'client_message_id': 'm1',
          'message_text': 'hello',
          'created_at_utc': '2026-04-04T10:00:00Z',
        },
      );

      final first = service.execute(request);
      final second = service.execute(request);

      expect(first.status, PluginHostApiStatus.executed);
      expect(first.result!['envelope_hash_hex'],
          contains('cccccccccccccccccccccccccccccccc'));
      expect(first.responseHashHex, second.responseHashHex);
      expect(first.canonicalJson, second.canonicalJson);
    });

    test('returns blocked response for capsule chat when guard blocks', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(
              code: 'pending_invitation',
              subjectId: 'deadbeef',
            ),
          ],
        ),
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.capsuleChatPluginId,
          method: PluginHostApiService.postCapsuleChatMethod,
          args: <String, dynamic>{
            'peer_hex': _peerHex,
            'client_message_id': 'm2',
            'message_text': 'hello blocked',
            'created_at_utc': '2026-04-04T10:00:00Z',
          },
        ),
      );

      expect(response.status, PluginHostApiStatus.blocked);
      expect(response.errorCode, isNull);
      expect(response.result, isNull);
      expect(
        response.blockingFacts.map((fact) => fact.code),
        contains('pending_invitation'),
      );
    });

    test('returns rejected response for capsule chat invalid args', () {
      final service = PluginHostApiService(
        runTemperatureDemo: ({required contract, required observation}) =>
            const PluginDemoRunResult(
          state: PluginDemoRunState.noPairwisePaths,
          pairResults: <PluginDemoPairRunResult>[],
          blockingFacts: <ConsensusBlockingFact>[],
        ),
        runBingxSpotOrder: _noopBingx,
        runCapsuleChat: ({
          required peerHex,
          required clientMessageId,
          required messageText,
          required createdAtUtc,
        }) =>
            const CapsuleChatExecutionResult(
          envelope: null,
          blockingFacts: <ConsensusBlockingFact>[],
        ),
      );

      final response = service.execute(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: PluginHostApiService.capsuleChatPluginId,
          method: PluginHostApiService.postCapsuleChatMethod,
          args: <String, dynamic>{
            'peer_hex': 'bad-peer',
            'client_message_id': 'm3',
            'message_text': 'hello',
            'created_at_utc': '2026-04-04T10:00:00Z',
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

BingxTradingExecutionResult _noopBingx({
  required String peerHex,
  required String clientOrderId,
  required String symbol,
  required String side,
  required String orderType,
  required String quantityDecimal,
  required String? limitPriceDecimal,
  required String? timeInForce,
  required String? entryMode,
  required String? zoneSide,
  required String? zoneLowDecimal,
  required String? zoneHighDecimal,
  required String? zonePriceRule,
  required String? manualEntryPriceDecimal,
  required String? triggerPriceDecimal,
  required String? stopLossDecimal,
  required String? takeProfitDecimal,
  required String createdAtUtc,
  required String? strategyTag,
}) =>
    const BingxTradingExecutionResult(
      intent: null,
      blockingFacts: <ConsensusBlockingFact>[],
    );

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

Map<String, dynamic> _validBingxArgs() => <String, dynamic>{
      'peer_hex': _peerHex,
      'client_order_id': 'ord-1',
      'symbol': 'BTC-USDT',
      'side': 'buy',
      'order_type': 'limit',
      'quantity_decimal': '0.01',
      'limit_price_decimal': '60000',
      'time_in_force': 'GTC',
      'created_at_utc': '2026-04-09T10:00:00Z',
      'strategy_tag': 'demo',
    };
