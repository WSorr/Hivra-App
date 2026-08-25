import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_order_sizing_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_order_sizing_service.dart';

void main() {
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
