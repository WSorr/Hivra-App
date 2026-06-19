import 'dart:math' as math;

import 'bingx_futures_exchange_service.dart';

enum BingxFuturesOrderSizingStatus {
  sized,
  blocked,
  unavailable,
}

class BingxFuturesOrderSizingResult {
  final BingxFuturesOrderSizingStatus status;
  final String reasonCode;
  final String reasonMessage;
  final String? quantityDecimal;
  final String? orderNotionalQuoteDecimal;
  final String? minimumQuantityDecimal;
  final String? minimumNotionalQuoteDecimal;

  const BingxFuturesOrderSizingResult({
    required this.status,
    required this.reasonCode,
    required this.reasonMessage,
    required this.quantityDecimal,
    required this.orderNotionalQuoteDecimal,
    required this.minimumQuantityDecimal,
    required this.minimumNotionalQuoteDecimal,
  });
}

class BingxFuturesOrderSizingService {
  final BingxFuturesExchangeService _exchange;

  const BingxFuturesOrderSizingService({
    required BingxFuturesExchangeService exchange,
  }) : _exchange = exchange;

  Future<BingxFuturesOrderSizingResult> size({
    required String symbol,
    required num maximumNotionalQuote,
  }) async {
    if (maximumNotionalQuote <= 0) {
      return _unavailable(
        code: 'risk_notional_invalid',
        message: 'Risk notional must be positive',
      );
    }

    final results = await Future.wait<Object>(<Future<Object>>[
      _exchange.getPublicPrice(symbol: symbol),
      _exchange.getPerpetualContractRules(symbol: symbol),
    ]);
    final quote = results[0] as BingxFuturesPublicPriceResult;
    final rulesResult = results[1] as BingxFuturesContractRulesResult;
    if (!quote.isSuccess || quote.priceDecimal == null) {
      return _unavailable(
        code: 'quote_unavailable',
        message: 'BingX quote is unavailable (${quote.exchangeCode})',
      );
    }
    if (!rulesResult.isSuccess || rulesResult.rules == null) {
      return _unavailable(
        code: 'contract_rules_unavailable',
        message:
            'BingX contract rules are unavailable (${rulesResult.exchangeCode})',
      );
    }

    return calculate(
      maximumNotionalQuote: maximumNotionalQuote,
      referencePriceDecimal: quote.priceDecimal!,
      rules: rulesResult.rules!,
    );
  }

  BingxFuturesOrderSizingResult calculate({
    required num maximumNotionalQuote,
    required String referencePriceDecimal,
    required BingxFuturesContractRules rules,
  }) {
    final referencePrice = num.tryParse(referencePriceDecimal.trim());
    if (maximumNotionalQuote <= 0 ||
        referencePrice == null ||
        referencePrice <= 0) {
      return _unavailable(
        code: 'sizing_input_invalid',
        message: 'Order sizing inputs are invalid',
      );
    }

    final minimumQuantity = _optionalNonNegative(
      rules.minimumQuantityDecimal,
    );
    final minimumNotional = _optionalNonNegative(
      rules.minimumNotionalQuoteDecimal,
    );
    if (minimumQuantity == null || minimumNotional == null) {
      return _unavailable(
        code: 'contract_rules_invalid',
        message: 'BingX contract minimums are invalid',
      );
    }

    final precision = (rules.quantityPrecision ?? 8).clamp(0, 12);
    final minimumFromNotional =
        minimumNotional > 0 ? minimumNotional / referencePrice : 0;
    final effectiveMinimumQuantity = math.max(
      minimumQuantity.toDouble(),
      minimumFromNotional.toDouble(),
    );
    final roundedMinimumQuantity = _ceilToPrecision(
      effectiveMinimumQuantity,
      precision,
    );
    final minimumOrderNotional = roundedMinimumQuantity * referencePrice;
    if (minimumOrderNotional > maximumNotionalQuote) {
      return BingxFuturesOrderSizingResult(
        status: BingxFuturesOrderSizingStatus.blocked,
        reasonCode: 'exchange_minimum_exceeds_risk_budget',
        reasonMessage: 'BingX minimum for ${rules.symbol} is about '
            '${_format(minimumOrderNotional, 4)} USDT, above the '
            '${_format(maximumNotionalQuote, 4)} USDT risk notional',
        quantityDecimal: null,
        orderNotionalQuoteDecimal: null,
        minimumQuantityDecimal: _format(roundedMinimumQuantity, precision),
        minimumNotionalQuoteDecimal: _format(minimumOrderNotional, 8),
      );
    }

    final riskQuantity = maximumNotionalQuote / referencePrice;
    final quantity = _floorToPrecision(riskQuantity, precision);
    if (quantity <= 0 || quantity < roundedMinimumQuantity) {
      return BingxFuturesOrderSizingResult(
        status: BingxFuturesOrderSizingStatus.blocked,
        reasonCode: 'exchange_minimum_exceeds_risk_budget',
        reasonMessage:
            'BingX minimum quantity ${_format(roundedMinimumQuantity, precision)} '
            'exceeds the risk-sized quantity',
        quantityDecimal: null,
        orderNotionalQuoteDecimal: null,
        minimumQuantityDecimal: _format(roundedMinimumQuantity, precision),
        minimumNotionalQuoteDecimal: _format(minimumOrderNotional, 8),
      );
    }

    return BingxFuturesOrderSizingResult(
      status: BingxFuturesOrderSizingStatus.sized,
      reasonCode: 'sized',
      reasonMessage: 'Order quantity fits risk and exchange minimums',
      quantityDecimal: _format(quantity, precision),
      orderNotionalQuoteDecimal: _format(quantity * referencePrice, 8),
      minimumQuantityDecimal: _format(roundedMinimumQuantity, precision),
      minimumNotionalQuoteDecimal: _format(minimumOrderNotional, 8),
    );
  }

  BingxFuturesOrderSizingResult _unavailable({
    required String code,
    required String message,
  }) {
    return BingxFuturesOrderSizingResult(
      status: BingxFuturesOrderSizingStatus.unavailable,
      reasonCode: code,
      reasonMessage: message,
      quantityDecimal: null,
      orderNotionalQuoteDecimal: null,
      minimumQuantityDecimal: null,
      minimumNotionalQuoteDecimal: null,
    );
  }

  num? _optionalNonNegative(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 0;
    final value = num.tryParse(raw.trim());
    if (value == null || value < 0) return null;
    return value;
  }

  double _floorToPrecision(num value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).floorToDouble() / factor;
  }

  double _ceilToPrecision(num value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).ceilToDouble() / factor;
  }

  String _format(num value, int precision) {
    final fixed = value.toStringAsFixed(precision);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
