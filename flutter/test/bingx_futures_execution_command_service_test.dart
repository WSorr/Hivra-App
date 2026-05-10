import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_execution_command_service.dart';

void main() {
  group('BingxFuturesExecutionCommandService', () {
    late InMemoryBingxExecutionCommandReplayStore replay;
    late BingxFuturesExecutionCommandService service;
    const localRoot =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const peerHex =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const intentHash =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    setUp(() {
      replay = InMemoryBingxExecutionCommandReplayStore();
      service = BingxFuturesExecutionCommandService(replayStore: replay);
    });

    test('accepts valid command and records replay key', () {
      final envelope = service.buildCommandEnvelope(
        commandId: 'cmd-001',
        intentHashHex: intentHash,
        symbol: 'BTC-USDT',
        side: 'buy',
        quantityDecimal: '0.01',
        entryPriceDecimal: '60000',
        stopLossDecimal: '59000',
        takeProfitDecimal: '62000',
        leverageDecimal: '10',
        riskPercentDecimal: '0.8',
        createdAtUtc: '2026-04-25T10:00:00Z',
        expiresAtUtc: '2026-04-25T10:05:00Z',
        targetCapsuleRootHex: localRoot,
      );

      final decision = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: true,
        nowUtc: DateTime.parse('2026-04-25T10:01:00Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
        hasKnownIntentHash: (hash) => hash == intentHash,
      );

      expect(decision.status, BingxExecutionDecisionStatus.accepted);
      expect(decision.decisionCode, 'accepted_for_execution');
      expect(decision.receiptHashHex.length, 64);
      expect(replay.hasProcessed('cmd-001'), isTrue);
    });

    test('rejects duplicate command_id on second pass', () {
      final envelope = service.buildCommandEnvelope(
        commandId: 'cmd-dup',
        intentHashHex: intentHash,
        symbol: 'BTC-USDT',
        side: 'buy',
        quantityDecimal: '0.01',
        entryPriceDecimal: '60000',
        stopLossDecimal: '59000',
        takeProfitDecimal: '62000',
        leverageDecimal: '10',
        riskPercentDecimal: '0.8',
        createdAtUtc: '2026-04-25T10:00:00Z',
        expiresAtUtc: '2026-04-25T10:05:00Z',
        targetCapsuleRootHex: localRoot,
      );

      final first = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: true,
        nowUtc: DateTime.parse('2026-04-25T10:01:00Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
      );
      final second = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: true,
        nowUtc: DateTime.parse('2026-04-25T10:01:10Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
      );

      expect(first.status, BingxExecutionDecisionStatus.accepted);
      expect(second.status, BingxExecutionDecisionStatus.rejected);
      expect(second.decisionCode, 'command_duplicate');
    });

    test('rejects expired command by ttl', () {
      final envelope = service.buildCommandEnvelope(
        commandId: 'cmd-exp',
        intentHashHex: intentHash,
        symbol: 'BTC-USDT',
        side: 'buy',
        quantityDecimal: '0.01',
        entryPriceDecimal: '60000',
        stopLossDecimal: '59000',
        takeProfitDecimal: '62000',
        leverageDecimal: '10',
        riskPercentDecimal: '0.8',
        createdAtUtc: '2026-04-25T10:00:00Z',
        expiresAtUtc: '2026-04-25T10:02:00Z',
        targetCapsuleRootHex: localRoot,
      );

      final decision = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: true,
        nowUtc: DateTime.parse('2026-04-25T10:03:00Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
      );

      expect(decision.status, BingxExecutionDecisionStatus.rejected);
      expect(decision.decisionCode, 'command_expired');
    });

    test('rejects command for different target capsule', () {
      final envelope = service.buildCommandEnvelope(
        commandId: 'cmd-target',
        intentHashHex: intentHash,
        symbol: 'BTC-USDT',
        side: 'buy',
        quantityDecimal: '0.01',
        entryPriceDecimal: '60000',
        stopLossDecimal: '59000',
        takeProfitDecimal: '62000',
        leverageDecimal: '10',
        riskPercentDecimal: '0.8',
        createdAtUtc: '2026-04-25T10:00:00Z',
        expiresAtUtc: '2026-04-25T10:05:00Z',
        targetCapsuleRootHex:
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      );

      final decision = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: true,
        nowUtc: DateTime.parse('2026-04-25T10:01:00Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
      );

      expect(decision.status, BingxExecutionDecisionStatus.rejected);
      expect(decision.decisionCode, 'target_capsule_mismatch');
    });

    test('rejects when sender consensus is not signable', () {
      final envelope = service.buildCommandEnvelope(
        commandId: 'cmd-consensus',
        intentHashHex: intentHash,
        symbol: 'BTC-USDT',
        side: 'buy',
        quantityDecimal: '0.01',
        entryPriceDecimal: '60000',
        stopLossDecimal: '59000',
        takeProfitDecimal: '62000',
        leverageDecimal: '10',
        riskPercentDecimal: '0.8',
        createdAtUtc: '2026-04-25T10:00:00Z',
        expiresAtUtc: '2026-04-25T10:05:00Z',
        targetCapsuleRootHex: localRoot,
      );

      final decision = service.evaluateIncomingCommand(
        commandEnvelopeJson: envelope,
        localCapsuleRootHex: localRoot,
        fromPeerHex: peerHex,
        isPeerSignable: false,
        nowUtc: DateTime.parse('2026-04-25T10:01:00Z'),
        policy: const BingxExecutionPolicy(
          allowedSymbols: <String>{'BTC-USDT'},
          maxLeverage: 20,
          maxRiskPercent: 1.0,
        ),
      );

      expect(decision.status, BingxExecutionDecisionStatus.rejected);
      expect(decision.decisionCode, 'pending_consensus');
      expect(replay.hasProcessed('cmd-consensus'), isFalse);
    });
  });
}
