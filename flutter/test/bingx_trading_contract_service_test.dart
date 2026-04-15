import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/bingx_trading_contract_service.dart';
import 'package:hivra_app/services/consensus_processor.dart';

void main() {
  group('BingxTradingContractService', () {
    test('returns blocked result when consensus is not signable', () {
      final service = BingxTradingContractService(
        readSignable: (_) => const ConsensusSignableResult(
          preview: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(
              code: 'pending_invitation',
              subjectId: 'abc',
            ),
          ],
        ),
      );

      final result = service.execute(
        peerHex: _peerHex,
        clientOrderId: 'ord-1',
        symbol: 'BTC-USDT',
        side: 'buy',
        orderType: 'limit',
        quantityDecimal: '0.01',
        limitPriceDecimal: '60000',
        timeInForce: 'GTC',
        entryMode: null,
        zoneSide: null,
        zoneLowDecimal: null,
        zoneHighDecimal: null,
        zonePriceRule: null,
        manualEntryPriceDecimal: null,
        triggerPriceDecimal: null,
        stopLossDecimal: null,
        takeProfitDecimal: null,
        createdAtUtc: '2026-04-09T10:00:00Z',
        strategyTag: 'demo',
      );

      expect(result.isExecutable, isFalse);
      expect(result.intent, isNull);
      expect(result.blockingFacts.map((fact) => fact.code),
          contains('pending_invitation'));
    });

    test('returns blocked result for pending_remote_break', () {
      final service = BingxTradingContractService(
        readSignable: (_) => const ConsensusSignableResult(
          preview: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(
              code: 'pending_remote_break',
              subjectId:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
          ],
        ),
      );

      final result = service.execute(
        peerHex: _peerHex,
        clientOrderId: 'ord-prb-1',
        symbol: 'BTC-USDT',
        side: 'buy',
        orderType: 'limit',
        quantityDecimal: '0.01',
        limitPriceDecimal: '60000',
        timeInForce: 'GTC',
        entryMode: null,
        zoneSide: null,
        zoneLowDecimal: null,
        zoneHighDecimal: null,
        zonePriceRule: null,
        manualEntryPriceDecimal: null,
        triggerPriceDecimal: null,
        stopLossDecimal: null,
        takeProfitDecimal: null,
        createdAtUtc: '2026-04-09T10:00:00Z',
        strategyTag: 'demo',
      );

      expect(result.isExecutable, isFalse);
      expect(result.intent, isNull);
      expect(
        result.blockingFacts.map((fact) => fact.code),
        contains('pending_remote_break'),
      );
      expect(
        result.blockingFacts.map((fact) => fact.code),
        isNot(contains('pending_invitation')),
      );
    });

    test('produces deterministic hash for identical inputs', () {
      final service = BingxTradingContractService(
        readSignable: _readySignable,
      );

      final first = service.evaluateDeterministic(
        peerHex: _peerHex,
        clientOrderId: 'ord-1',
        symbol: 'btc-usdt',
        side: 'buy',
        orderType: 'limit',
        quantityDecimal: '000.0100',
        limitPriceDecimal: '060000.0000',
        timeInForce: 'gtc',
        entryMode: null,
        zoneSide: null,
        zoneLowDecimal: null,
        zoneHighDecimal: null,
        zonePriceRule: null,
        manualEntryPriceDecimal: null,
        triggerPriceDecimal: null,
        stopLossDecimal: null,
        takeProfitDecimal: null,
        createdAtUtc: '2026-04-09T10:00:00Z',
        strategyTag: 'demo',
      );
      final second = service.evaluateDeterministic(
        peerHex: _peerHex,
        clientOrderId: 'ord-1',
        symbol: 'BTC-USDT',
        side: 'buy',
        orderType: 'limit',
        quantityDecimal: '0.01',
        limitPriceDecimal: '60000',
        timeInForce: 'GTC',
        entryMode: null,
        zoneSide: null,
        zoneLowDecimal: null,
        zoneHighDecimal: null,
        zonePriceRule: null,
        manualEntryPriceDecimal: null,
        triggerPriceDecimal: null,
        stopLossDecimal: null,
        takeProfitDecimal: null,
        createdAtUtc: '2026-04-09T10:00:00Z',
        strategyTag: 'demo',
      );

      expect(first.symbol, 'BTC-USDT');
      expect(first.quantityDecimal, '0.01');
      expect(first.limitPriceDecimal, '60000');
      expect(first.canonicalJson, second.canonicalJson);
      expect(first.intentHashHex, second.intentHashHex);
    });

    test('rejects limit order without limit price', () {
      final service = BingxTradingContractService(
        readSignable: _readySignable,
      );

      expect(
        () => service.evaluateDeterministic(
          peerHex: _peerHex,
          clientOrderId: 'ord-2',
          symbol: 'BTC-USDT',
          side: 'buy',
          orderType: 'limit',
          quantityDecimal: '0.1',
          limitPriceDecimal: null,
          timeInForce: 'GTC',
          entryMode: null,
          zoneSide: null,
          zoneLowDecimal: null,
          zoneHighDecimal: null,
          zonePriceRule: null,
          manualEntryPriceDecimal: null,
          triggerPriceDecimal: null,
          stopLossDecimal: null,
          takeProfitDecimal: null,
          createdAtUtc: '2026-04-09T10:00:00Z',
          strategyTag: null,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects market order when limit fields are provided', () {
      final service = BingxTradingContractService(
        readSignable: _readySignable,
      );

      expect(
        () => service.evaluateDeterministic(
          peerHex: _peerHex,
          clientOrderId: 'ord-3',
          symbol: 'BTC-USDT',
          side: 'sell',
          orderType: 'market',
          quantityDecimal: '0.1',
          limitPriceDecimal: '50000',
          timeInForce: null,
          entryMode: null,
          zoneSide: null,
          zoneLowDecimal: null,
          zoneHighDecimal: null,
          zonePriceRule: null,
          manualEntryPriceDecimal: null,
          triggerPriceDecimal: null,
          stopLossDecimal: null,
          takeProfitDecimal: null,
          createdAtUtc: '2026-04-09T10:00:00Z',
          strategyTag: null,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('supports zone-pending deterministic entry parameters', () {
      final service = BingxTradingContractService(
        readSignable: _readySignable,
      );

      final intent = service.evaluateDeterministic(
        peerHex: _peerHex,
        clientOrderId: 'ord-zone-1',
        symbol: 'BTC-USDT',
        side: 'buy',
        orderType: 'limit',
        quantityDecimal: '0.2',
        limitPriceDecimal: null,
        timeInForce: 'GTC',
        entryMode: 'zone_pending',
        zoneSide: 'buyside',
        zoneLowDecimal: '58000',
        zoneHighDecimal: '60000',
        zonePriceRule: 'zone_mid',
        manualEntryPriceDecimal: null,
        triggerPriceDecimal: '58900',
        stopLossDecimal: '57500',
        takeProfitDecimal: '62000',
        createdAtUtc: '2026-04-09T10:00:00Z',
        strategyTag: 'zone-demo',
      );

      expect(intent.entryMode, BingxEntryMode.zonePending);
      expect(intent.zoneSide, BingxZoneSide.buyside);
      expect(intent.zonePriceRule, BingxZonePriceRule.zoneMid);
      expect(intent.limitPriceDecimal, '59000');
      expect(intent.triggerPriceDecimal, '58900');
      expect(intent.stopLossDecimal, '57500');
      expect(intent.takeProfitDecimal, '62000');
      expect(intent.canonicalJson, contains('"entry_mode":"zone_pending"'));
      expect(intent.intentHashHex.length, 64);
    });
  });
}

const String _peerHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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
