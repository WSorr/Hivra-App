import 'package:flutter_test/flutter_test.dart';

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

    test('uses minimum notional when it requires more than minimum quantity',
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
    });

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
  });
}
