import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';

void main() {
  final fixture = _loadFixture();
  final positive = Map<String, dynamic>.from(fixture['positive'] as Map);
  final negative = Map<String, dynamic>.from(
    fixture['negative_mutations'] as Map,
  );

  group('BingX provider contract conformance', () {
    test('accepts captured balance and contract rule shapes', () async {
      final balance = await _serviceFor(
        positive['balance'],
      ).getUserBalance(credentials: _credentials);
      final rules = await _serviceFor(
        positive['contract_rules'],
      ).getPerpetualContractRules(symbol: 'BTC-USDT');

      expect(balance.isSuccess, isTrue);
      expect(balance.accountEquityQuoteDecimal, '17.0000');
      expect(balance.realizedPnlQuoteDecimal, '0');
      expect(rules.isSuccess, isTrue);
      expect(rules.rules?.minimumQuantityDecimal, '0.0001');
      expect(rules.rules?.minimumNotionalQuoteDecimal, '2');
    });

    test('accepts captured empty account collection variants', () async {
      final income = await _serviceFor(
        positive['realized_pnl_empty'],
      ).getUserIncome(
        credentials: _credentials,
        startTimeMs: 1710000000000,
        endTimeMs: 1710003600000,
      );
      final positions = await _serviceFor(
        positive['positions_empty'],
      ).getUserPositions(credentials: _credentials);
      final openOrders = await _serviceFor(
        positive['open_trigger_orders_empty'],
      ).getOpenOrders(credentials: _credentials, symbol: 'BTC-USDT');

      expect(income.isSuccess, isTrue);
      expect(income.sourceRecordsShapeValid, isTrue);
      expect(income.sourceRecordCount, 0);
      expect(income.records, isEmpty);
      expect(positions.isSuccess, isTrue);
      expect(positions.positions, isEmpty);
      expect(openOrders.isSuccess, isTrue);
      expect(openOrders.orders, isEmpty);
    });

    test(
      'requires exact provider identity for placement and receipt',
      () async {
        late BingxHttpRequest placementRequest;
        final placement = await _serviceFor(
          positive['order_placement'],
          capture: (request) => placementRequest = request,
        ).placeOrder(
          credentials: _credentials,
          intent: _intent,
          testOrder: false,
        );
        final receipt = await _serviceFor(positive['order_receipt']).getOrder(
          credentials: _credentials,
          symbol: 'BTC-USDT',
          orderId: '9007199254740993',
        );

        expect(placement.isSuccess, isTrue);
        expect(placement.orderId, '9007199254740993');
        expect(placementRequest.body, contains('clientOrderId='));
        expect(placementRequest.body, isNot(contains('clientOrderID=')));
        expect(receipt.isSuccess, isTrue);
        expect(receipt.order?.orderId, placement.orderId);
        expect(receipt.order?.clientOrderId, _intent.clientOrderId);
        expect(receipt.order?.status, 'NEW');
      },
    );

    test(
      'rejects malformed read shapes without empty-state downgrade',
      () async {
        final balance = await _serviceFor(
          negative['balance_without_usdt'],
        ).getUserBalance(credentials: _credentials);
        final rules = await _serviceFor(
          negative['contract_rules_without_minimum_notional'],
        ).getPerpetualContractRules(symbol: 'BTC-USDT');
        final income = await _serviceFor(
          negative['realized_pnl_malformed_container'],
        ).getUserIncome(
          credentials: _credentials,
          startTimeMs: 1710000000000,
          endTimeMs: 1710003600000,
        );
        final positions = await _serviceFor(
          negative['positions_with_unparseable_row'],
        ).getUserPositions(credentials: _credentials);
        final openOrders = await _serviceFor(
          negative['open_orders_with_missing_identity'],
        ).getOpenOrders(credentials: _credentials, symbol: 'BTC-USDT');

        expect(balance.isSuccess, isFalse);
        expect(rules.isSuccess, isFalse);
        expect(income.sourceRecordsShapeValid, isFalse);
        expect(positions.isSuccess, isFalse);
        expect(openOrders.isSuccess, isFalse);
      },
    );

    test('rejects success envelopes without provider order identity', () async {
      final placement = await _serviceFor(
        negative['placement_without_order_identity'],
      ).placeOrder(
        credentials: _credentials,
        intent: _intent,
        testOrder: false,
      );
      final receipt = await _serviceFor(
        negative['receipt_without_order_identity'],
      ).getOrder(
        credentials: _credentials,
        symbol: 'BTC-USDT',
        clientOrderId: _intent.clientOrderId,
      );

      expect(placement.isSuccess, isFalse);
      expect(placement.orderId, isNull);
      expect(receipt.isSuccess, isFalse);
      expect(receipt.order, isNull);
    });
  });
}

const _credentials = BingxFuturesApiCredentials(
  apiKey: 'fixture-api-key',
  apiSecret: 'fixture-api-secret',
);

const _intent = BingxFuturesIntentPayload(
  clientOrderId: 'hivra-fixture-order',
  symbol: 'BTC-USDT',
  side: 'buy',
  orderType: 'limit',
  quantityDecimal: '0.0001',
  limitPriceDecimal: '70000.0',
  timeInForce: 'GTC',
  entryMode: 'zone_pending',
  triggerPriceDecimal: '70010.0',
  stopLossDecimal: null,
  takeProfitDecimal: null,
  intentHashHex: 'fixture-intent-hash',
);

Map<String, dynamic> _loadFixture() {
  final file = File('test/fixtures/bingx_provider_contract_v1.json');
  return Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
}

BingxFuturesExchangeService _serviceFor(
  dynamic response, {
  void Function(BingxHttpRequest request)? capture,
}) {
  return BingxFuturesExchangeService(
    clockMs: () => 1710000000000,
    requestSender: (request) async {
      capture?.call(request);
      return BingxHttpResponse(statusCode: 200, body: jsonEncode(response));
    },
  );
}
