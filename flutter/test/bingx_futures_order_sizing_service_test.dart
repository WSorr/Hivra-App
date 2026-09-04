import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_sizing_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_sizing_service.dart';

void main() {
  test(
    'exposure uses side leverage and free margin, never wallet equity',
    () async {
      final requests = <String>[];
      var available = '10';
      var long = '5';
      var mode = 'ISOLATED';
      final owner = BingxFuturesOrderSizingService(
        exchange: BingxFuturesExchangeService(
          requestSender: (request) async {
            expect(request.method, 'GET');
            requests.add(request.uri.path);
            final data =
                request.uri.path.endsWith('/leverage')
                    ? '{"longLeverage":"$long","shortLeverage":"2"}'
                    : request.uri.path.endsWith('/marginType')
                    ? '{"marginType":"$mode"}'
                    : '[{"asset":"USDT","equity":"1000","availableMargin":"$available"}]';
            return BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"data":$data}',
            );
          },
        ),
      );
      Future<String> read({
        String side = 'buy',
        num cap = 8,
        num selectedStop = 5,
        String? exactStop,
      }) => owner.describeExposure(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'test',
          apiSecret: 'test',
        ),
        symbol: 'DOGE-USDT',
        maximumNotionalQuote: cap,
        stopLossPercent: selectedStop,
        intent: BingxFuturesIntentPayload(
          clientOrderId: 'test',
          symbol: 'DOGE-USDT',
          side: side,
          orderType: 'limit',
          quantityDecimal: '80',
          limitPriceDecimal: '0.1',
          timeInForce: 'GTC',
          entryMode: 'zone_pending',
          triggerPriceDecimal: '0.1',
          stopLossDecimal: exactStop ?? (side == 'buy' ? '0.095' : '0.105'),
          takeProfitDecimal: null,
          intentHashHex: null,
        ),
      );
      final buy = await read();
      expect(buy, contains('1.6000 USDT (16.00%'));
      expect(buy, contains('0.4000 USDT before costs'));
      expect(buy, isNot(contains('Short:')));
      expect(buy, contains('nominal leverage buffer'));
      expect(await read(side: 'sell'), contains('4.0000 USDT (40.00%'));
      expect(requests.toSet(), hasLength(3));
      await expectLater(read(cap: 7), throwsStateError);
      available = '0';
      await expectLater(read(), throwsStateError);
      available = 'NaN';
      await expectLater(read(), throwsStateError);
      available = '';
      await expectLater(read(), throwsStateError);
      available = '10';
      long = '0';
      await expectLater(read(), throwsStateError);
      long = '5';
      mode = 'UNKNOWN';
      await expectLater(read(), throwsStateError);
      mode = 'ISOLATED';
      long = '60';
      await expectLater(read(selectedStop: 0.1), throwsStateError);
      expect(
        await read(selectedStop: 5, exactStop: '0.0995'),
        contains('0.0400 USDT before costs'),
      );
      await expectLater(
        read(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('order cannot be approved'),
          ),
        ),
      );
      final capOnly = await owner.describeExposure(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'test',
          apiSecret: 'test',
        ),
        symbol: 'DOGE-USDT',
        maximumNotionalQuote: 8,
        stopLossPercent: 5,
      );
      expect(capOnly, contains('UNSAFE LONG'));
    },
  );

  group('BingxFuturesOrderSizingService', () {
    final service = BingxFuturesOrderSizingService(
      exchange: BingxFuturesExchangeService(),
    );

    test('blocks BNB when exchange minimum exceeds risk budget', () {
      final result = service.calculate(
        maximumNotionalQuote: 3.2178,
        referencePriceDecimal: '609.80',
        rules: const BingxFuturesContractRules(
          symbol: 'BNB-USDT',
          minimumQuantityDecimal: '0.01',
          minimumNotionalQuoteDecimal: '2',
          quantityPrecision: 2,
          pricePrecision: 2,
        ),
      );

      expect(result.status, BingxFuturesOrderSizingStatus.blocked);
      expect(result.reasonCode, 'exchange_minimum_exceeds_risk_budget');
      expect(result.minimumQuantityDecimal, '0.01');
      expect(result.minimumNotionalQuoteDecimal, '6.098');
      expect(result.reasonMessage, contains('6.098'));
      expect(result.reasonMessage, contains('3.2178'));
    });

    test('sizes above exchange minimum and rounds down to precision', () {
      final result = service.calculate(
        maximumNotionalQuote: 7,
        referencePriceDecimal: '609.80',
        rules: const BingxFuturesContractRules(
          symbol: 'BNB-USDT',
          minimumQuantityDecimal: '0.01',
          minimumNotionalQuoteDecimal: '2',
          quantityPrecision: 3,
          pricePrecision: 2,
        ),
      );

      expect(result.status, BingxFuturesOrderSizingStatus.sized);
      expect(result.quantityDecimal, '0.011');
      expect(result.orderNotionalQuoteDecimal, '6.7078');
    });

    test('sizes pending order against its exact zone entry price', () {
      final result = service.calculate(
        maximumNotionalQuote: 100,
        referencePriceDecimal: '746.092468',
        rules: const BingxFuturesContractRules(
          symbol: 'BNB-USDT',
          minimumQuantityDecimal: '0.01',
          minimumNotionalQuoteDecimal: '2',
          quantityPrecision: 2,
          pricePrecision: 2,
        ),
      );

      expect(result.status, BingxFuturesOrderSizingStatus.sized);
      expect(result.quantityDecimal, '0.13');
      expect(
        num.parse(result.orderNotionalQuoteDecimal!),
        lessThanOrEqualTo(100),
      );
    });

    test(
      'uses minimum notional when it requires more than minimum quantity',
      () {
        final result = service.calculate(
          maximumNotionalQuote: 5,
          referencePriceDecimal: '100',
          rules: const BingxFuturesContractRules(
            symbol: 'TEST-USDT',
            minimumQuantityDecimal: '0.01',
            minimumNotionalQuoteDecimal: '4',
            quantityPrecision: 2,
            pricePrecision: 2,
          ),
        );

        expect(result.status, BingxFuturesOrderSizingStatus.sized);
        expect(result.minimumQuantityDecimal, '0.04');
        expect(result.quantityDecimal, '0.05');
      },
    );

    test('is deterministic for identical inputs', () {
      BingxFuturesOrderSizingResult calculate() => service.calculate(
        maximumNotionalQuote: 10,
        referencePriceDecimal: '68.125',
        rules: const BingxFuturesContractRules(
          symbol: 'SOL-USDT',
          minimumQuantityDecimal: '0.01',
          minimumNotionalQuoteDecimal: '2',
          quantityPrecision: 3,
          pricePrecision: 3,
        ),
      );

      final first = calculate();
      final second = calculate();
      expect(first.status, second.status);
      expect(first.quantityDecimal, second.quantityDecimal);
      expect(first.orderNotionalQuoteDecimal, second.orderNotionalQuoteDecimal);
    });

    test(
      'auto-fit preserves the risk limit when symbol minimum blocks',
      () async {
        final service = BingxFuturesOrderSizingService(
          exchange: _exchangeWithRules(
            price: '78628.6',
            minimumQuantity: '0.0001',
            minimumNotional: '2',
            quantityPrecision: 4,
          ),
        );

        final result = await service.fitMaximumNotional(
          symbol: 'BTC-USDT',
          accountEquityQuote: 13.1422,
          maximumRiskPercent: 2,
          stopLossPercent: 5,
        );

        expect(result.fittedNotionalQuote, closeTo(5.1517424, 0.0000001));
        expect(result.safeNotionalQuote, closeTo(5.25688, 0.0000001));
        expect(result.sizing?.status, BingxFuturesOrderSizingStatus.blocked);
        expect(
          result.sizing?.reasonCode,
          'exchange_minimum_exceeds_risk_budget',
        );
      },
    );

    test(
      'auto-fit may use the exchange minimum inside the safe limit',
      () async {
        final service = BingxFuturesOrderSizingService(
          exchange: _exchangeWithRules(
            price: '5.2',
            minimumQuantity: '1',
            minimumNotional: '2',
            quantityPrecision: 1,
          ),
        );

        final result = await service.fitMaximumNotional(
          symbol: 'BTC-USDT',
          accountEquityQuote: 13.1422,
          maximumRiskPercent: 2,
          stopLossPercent: 5,
        );

        expect(result.fittedNotionalQuote, 5.2);
        expect(result.fittedNotionalQuote, lessThan(result.safeNotionalQuote));
        expect(result.sizing?.status, BingxFuturesOrderSizingStatus.sized);
        expect(result.sizing?.quantityDecimal, '1');
      },
    );
  });
}

BingxFuturesExchangeService _exchangeWithRules({
  required String price,
  required String minimumQuantity,
  required String minimumNotional,
  required int quantityPrecision,
}) => BingxFuturesExchangeService(
  requestSender: (request) async {
    final body = switch (request.uri.path) {
      '/openApi/swap/v2/quote/price' =>
        '{"code":0,"msg":"ok","data":{"symbol":"BTC-USDT","price":"$price"}}',
      '/openApi/swap/v2/quote/contracts' =>
        '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT",'
            '"tradeMinQuantity":"$minimumQuantity",'
            '"tradeMinUSDT":"$minimumNotional",'
            '"quantityPrecision":$quantityPrecision,"pricePrecision":4}]}',
      _ => throw StateError('unexpected endpoint ${request.uri.path}'),
    };
    return BingxHttpResponse(statusCode: 200, body: body);
  },
);
