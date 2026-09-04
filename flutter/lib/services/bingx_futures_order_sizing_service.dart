import 'dart:math' as math;

import '../models/bingx_futures_exchange_models.dart';
import '../models/bingx_futures_order_sizing_models.dart';
import 'bingx_futures_exchange_service.dart';
import 'bingx_futures_risk_governor_service.dart';

class BingxFuturesOrderSizingService {
  final BingxFuturesExchangeService _exchange;

  const BingxFuturesOrderSizingService({
    required BingxFuturesExchangeService exchange,
  }) : _exchange = exchange;

  Future<String> describeExposure({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
    required num maximumNotionalQuote,
    required num stopLossPercent,
    BingxFuturesIntentPayload? intent,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty ||
        !maximumNotionalQuote.isFinite ||
        maximumNotionalQuote <= 0 ||
        !stopLossPercent.isFinite ||
        stopLossPercent <= 0 ||
        stopLossPercent >= 100 ||
        (intent != null && intent.symbol != normalizedSymbol)) {
      throw const FormatException(
        'Invalid exposure inputs. Prepare a fresh request.',
      );
    }
    final values = await Future.wait<Object>([
      _exchange.getUserBalance(credentials: credentials),
      _exchange.getLeverage(credentials: credentials, symbol: normalizedSymbol),
      _exchange.getMarginType(
        credentials: credentials,
        symbol: normalizedSymbol,
      ),
    ]);
    final balance = values[0] as BingxFuturesUserBalanceResult;
    final leverage = values[1] as BingxFuturesLeverageReadResult;
    final margin = values[2] as BingxFuturesMarginTypeReadResult;
    final available = num.tryParse(balance.availableMarginQuoteDecimal ?? '');
    final mode = margin.marginType;
    final long = leverage.longLeverage;
    final short = leverage.shortLeverage;
    if (!balance.isSuccess ||
        !leverage.isSuccess ||
        !margin.isSuccess ||
        available == null ||
        !available.isFinite ||
        available < 0 ||
        !{'ISOLATED', 'CROSSED'}.contains(mode) ||
        long == null ||
        short == null ||
        long <= 0 ||
        short <= 0) {
      throw StateError(
        'Exchange leverage, margin mode or available margin is unknown. '
        'No estimate or approval is available.',
      );
    }
    num notional = maximumNotionalQuote;
    num loss = notional * stopLossPercent / 100;
    if (intent != null) {
      final quantity = num.tryParse(intent.quantityDecimal);
      final price = num.tryParse(intent.limitPriceDecimal ?? '');
      final stop = num.tryParse(intent.stopLossDecimal ?? '');
      if (quantity == null ||
          price == null ||
          stop == null ||
          !quantity.isFinite ||
          !price.isFinite ||
          !stop.isFinite ||
          quantity <= 0 ||
          price <= 0 ||
          stop <= 0 ||
          !{'buy', 'sell'}.contains(intent.side) ||
          (intent.side == 'buy' ? stop >= price : stop <= price)) {
        throw StateError('A priced intent with a valid stop loss is required.');
      }
      notional = quantity * price;
      loss = quantity * (price - stop).abs();
      if (!notional.isFinite ||
          !loss.isFinite ||
          notional > maximumNotionalQuote) {
        throw StateError(
          'Prepared position exceeds the selected notional cap.',
        );
      }
    }
    String collateral(String side, int factor) {
      final estimate = notional / factor;
      final share =
          available > 0
              ? '${(estimate / available * 100).toStringAsFixed(2)}% of available margin'
              : 'no available margin';
      return '$side: ${factor}x · estimated initial margin '
          '${estimate.toStringAsFixed(4)} USDT ($share)';
    }

    final selectedLeverage = intent?.side == 'buy' ? long : short;
    if (intent != null) {
      final blocker = BingxFuturesRiskGovernorService.exposureBlocker(
        notional: notional,
        lossAtStop: loss,
        openingLeverage: selectedLeverage,
        marginType: mode,
        availableMarginQuoteDecimal: balance.availableMarginQuoteDecimal,
      );
      if (blocker != null) {
        throw StateError('The order cannot be approved. '
          '${BingxFuturesRiskGovernorService.exposureMessage(blocker)}');
      }
    }
    return [
      '$normalizedSymbol · ${intent == null ? "Position-cap estimate, not an order" : "Prepared ${intent.side.toUpperCase()} order"}',
      'Position notional: ${notional.toStringAsFixed(4)} USDT (not your deposit)',
      if (intent != null) 'Quantity: ${intent.quantityDecimal}',
      'Exchange margin mode: $mode',
      'Available margin: ${available.toStringAsFixed(4)} USDT',
      if (intent == null || intent.side == 'buy') collateral('Long', long),
      if (intent == null || intent.side == 'sell') collateral('Short', short),
      if (intent == null && stopLossPercent >= 100 / long)
        'UNSAFE LONG: selected SL is outside the nominal '
            '${(100 / long).toStringAsFixed(2)}% leverage buffer.',
      if (intent == null && stopLossPercent >= 100 / short)
        'UNSAFE SHORT: selected SL is outside the nominal '
            '${(100 / short).toStringAsFixed(2)}% leverage buffer.',
      'Estimated loss at SL: ${loss.toStringAsFixed(4)} USDT before costs',
      'Fees, funding and slippage are not included. A stop loss is not a '
          'guaranteed loss limit. Cross margin can expose other account funds.',
      'The nominal leverage buffer is not a liquidation-price estimate. Actual '
          'liquidation can occur earlier. Snapshot only: exchange settings and '
          'available funds may change before fill. '
          'No leverage or margin setting has been changed.',
    ].join('\n\n');
  }

  Future<
    ({
      num fittedNotionalQuote,
      num safeNotionalQuote,
      BingxFuturesOrderSizingResult? sizing,
    })
  >
  fitMaximumNotional({
    required String symbol,
    required num accountEquityQuote,
    required num maximumRiskPercent,
    required num stopLossPercent,
  }) async {
    if (accountEquityQuote <= 0 ||
        maximumRiskPercent <= 0 ||
        stopLossPercent <= 0) {
      throw ArgumentError('Auto-fit risk inputs must be positive');
    }

    final riskQuoteLimit = accountEquityQuote * (maximumRiskPercent / 100);
    final safeNotionalQuote = riskQuoteLimit / (stopLossPercent / 100);
    num fittedNotionalQuote = safeNotionalQuote * 0.98;
    BingxFuturesOrderSizingResult? sizing;
    final normalizedSymbol = symbol.trim();
    if (normalizedSymbol.isNotEmpty) {
      sizing = await size(
        symbol: normalizedSymbol,
        maximumNotionalQuote: fittedNotionalQuote,
      );
      if (sizing.status == BingxFuturesOrderSizingStatus.blocked &&
          sizing.reasonCode == 'exchange_minimum_exceeds_risk_budget') {
        final minimumNotional = num.tryParse(
          sizing.minimumNotionalQuoteDecimal ?? '',
        );
        if (minimumNotional != null &&
            minimumNotional > fittedNotionalQuote &&
            minimumNotional <= safeNotionalQuote) {
          fittedNotionalQuote = minimumNotional;
          sizing = await size(
            symbol: normalizedSymbol,
            maximumNotionalQuote: fittedNotionalQuote,
          );
        }
      }
    }

    return (
      fittedNotionalQuote: fittedNotionalQuote,
      safeNotionalQuote: safeNotionalQuote,
      sizing: sizing,
    );
  }

  Future<BingxFuturesOrderSizingResult> size({
    required String symbol,
    required num maximumNotionalQuote,
    String? referencePriceDecimal,
  }) async {
    if (maximumNotionalQuote <= 0) {
      return _unavailable(
        code: 'risk_notional_invalid',
        message: 'Risk notional must be positive',
      );
    }

    final normalizedReferencePrice = referencePriceDecimal?.trim();
    final quoteFuture =
        normalizedReferencePrice == null || normalizedReferencePrice.isEmpty
            ? _exchange.getPublicPrice(symbol: symbol)
            : Future<BingxFuturesPublicPriceResult?>.value(null);
    final results = await Future.wait<Object?>(<Future<Object?>>[
      quoteFuture,
      _exchange.getPerpetualContractRules(symbol: symbol),
    ]);
    final quote = results[0] as BingxFuturesPublicPriceResult?;
    final rulesResult = results[1] as BingxFuturesContractRulesResult;
    final sizingReferencePrice =
        normalizedReferencePrice == null || normalizedReferencePrice.isEmpty
            ? quote?.priceDecimal
            : normalizedReferencePrice;
    if (sizingReferencePrice == null || sizingReferencePrice.isEmpty) {
      return _unavailable(
        code: 'quote_unavailable',
        message: 'BingX quote is unavailable (${quote?.exchangeCode ?? '-'})',
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
      referencePriceDecimal: sizingReferencePrice,
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

    final minimumQuantity = _optionalNonNegative(rules.minimumQuantityDecimal);
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
        reasonMessage:
            'BingX minimum for ${rules.symbol} is about '
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
