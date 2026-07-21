class BingxFuturesApiCredentials {
  final String apiKey;
  final String apiSecret;
  static final RegExp _visibleAsciiPattern = RegExp(r'^[\x21-\x7E]+$');

  const BingxFuturesApiCredentials({
    required this.apiKey,
    required this.apiSecret,
  });

  BingxFuturesApiCredentials normalized() {
    final normalizedKey = apiKey.trim();
    final normalizedSecret = apiSecret.trim();
    if (normalizedKey.isEmpty) {
      throw const FormatException('BingX API key is required');
    }
    if (normalizedSecret.isEmpty) {
      throw const FormatException('BingX API secret is required');
    }
    if (!_visibleAsciiPattern.hasMatch(normalizedKey)) {
      throw const FormatException('BingX API key contains invalid characters');
    }
    if (!_visibleAsciiPattern.hasMatch(normalizedSecret)) {
      throw const FormatException(
        'BingX API secret contains invalid characters',
      );
    }
    return BingxFuturesApiCredentials(
      apiKey: normalizedKey,
      apiSecret: normalizedSecret,
    );
  }
}

class BingxFuturesIntentPayload {
  final String clientOrderId;
  final String symbol;
  final String side;
  final String orderType;
  final String quantityDecimal;
  final String? limitPriceDecimal;
  final String? timeInForce;
  final String entryMode;
  final String? triggerPriceDecimal;
  final String? stopLossDecimal;
  final String? takeProfitDecimal;
  final String? intentHashHex;

  const BingxFuturesIntentPayload({
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.limitPriceDecimal,
    required this.timeInForce,
    required this.entryMode,
    required this.triggerPriceDecimal,
    required this.stopLossDecimal,
    required this.takeProfitDecimal,
    required this.intentHashHex,
  });

  factory BingxFuturesIntentPayload.fromPluginResult(
    Map<String, dynamic> result,
  ) {
    String readRequiredString(String key) {
      final value = result[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw FormatException('Intent field "$key" is required');
      }
      return value;
    }

    final side = readRequiredString('side').toLowerCase();
    final normalizedSide = switch (side) {
      'buy' => 'buy',
      'sell' => 'sell',
      _ => throw const FormatException('Intent side must be buy or sell'),
    };
    final orderType = readRequiredString('order_type').toLowerCase();
    final normalizedOrderType = switch (orderType) {
      'limit' => 'limit',
      'market' => 'market',
      _ =>
        throw const FormatException('Intent order_type must be limit/market'),
    };
    final quantity = readRequiredString('quantity_decimal');
    final limitPrice = result['limit_price_decimal']?.toString().trim();
    final timeInForce = result['time_in_force']?.toString().trim();
    final entryModeRaw = result['entry_mode']?.toString().trim().toLowerCase();
    final entryMode = switch (entryModeRaw) {
      null || '' || 'direct' => 'direct',
      'zone_pending' => 'zone_pending',
      _ =>
        throw const FormatException(
          'Intent entry_mode must be direct or zone_pending',
        ),
    };
    final triggerPrice = result['trigger_price_decimal']?.toString().trim();
    final stopLoss = result['stop_loss_decimal']?.toString().trim();
    final takeProfit = result['take_profit_decimal']?.toString().trim();
    if (normalizedOrderType == 'limit' &&
        (limitPrice == null || limitPrice.isEmpty)) {
      throw const FormatException('Limit intent requires limit_price_decimal');
    }
    if (entryMode == 'zone_pending' &&
        (triggerPrice == null || triggerPrice.isEmpty)) {
      throw const FormatException(
        'zone_pending intent requires trigger_price_decimal',
      );
    }
    return BingxFuturesIntentPayload(
      clientOrderId: readRequiredString('client_order_id'),
      symbol: readRequiredString('symbol').toUpperCase(),
      side: normalizedSide,
      orderType: normalizedOrderType,
      quantityDecimal: quantity,
      limitPriceDecimal:
          (limitPrice == null || limitPrice.isEmpty) ? null : limitPrice,
      timeInForce:
          (timeInForce == null || timeInForce.isEmpty) ? null : timeInForce,
      entryMode: entryMode,
      triggerPriceDecimal:
          (triggerPrice == null || triggerPrice.isEmpty) ? null : triggerPrice,
      stopLossDecimal: (stopLoss == null || stopLoss.isEmpty) ? null : stopLoss,
      takeProfitDecimal:
          (takeProfit == null || takeProfit.isEmpty) ? null : takeProfit,
      intentHashHex: result['intent_hash_hex']?.toString().trim(),
    );
  }

  String get exchangeSide => side == 'buy' ? 'BUY' : 'SELL';
  String get positionSide => side == 'buy' ? 'LONG' : 'SHORT';
  String get exchangeOrderType {
    if (entryMode == 'zone_pending' && orderType == 'limit') {
      return 'TRIGGER_LIMIT';
    }
    return orderType == 'limit' ? 'LIMIT' : 'MARKET';
  }
}

class BingxFuturesOrderExecutionResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String? orderId;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String? intentHashHex;

  const BingxFuturesOrderExecutionResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.orderId,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.intentHashHex,
  });
}

enum BingxFuturesLeverageSide { long, short }

enum BingxFuturesMarginType { isolated, crossed }

class BingxFuturesControlActionResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String actionName;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;

  const BingxFuturesControlActionResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.actionName,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
  });
}

class BingxFuturesOpenOrder {
  final String orderId;
  final String symbol;
  final String side;
  final String positionSide;
  final String orderType;
  final String status;
  final String? priceDecimal;
  final String? triggerPriceDecimal;
  final String? quantityDecimal;
  final String? executedQuantityDecimal;
  final int? createdAtMs;

  const BingxFuturesOpenOrder({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.positionSide,
    required this.orderType,
    required this.status,
    required this.priceDecimal,
    required this.triggerPriceDecimal,
    required this.quantityDecimal,
    required this.executedQuantityDecimal,
    required this.createdAtMs,
  });
}

class BingxFuturesOpenOrdersResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;
  final List<BingxFuturesOpenOrder> orders;

  const BingxFuturesOpenOrdersResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
    required this.orders,
  });
}

class BingxFuturesCancelOrderResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;
  final String requestedOrderId;
  final String? canceledOrderId;

  const BingxFuturesCancelOrderResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
    required this.requestedOrderId,
    required this.canceledOrderId,
  });
}

class BingxFuturesLeverageReadResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;
  final int? longLeverage;
  final int? shortLeverage;

  const BingxFuturesLeverageReadResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
    required this.longLeverage,
    required this.shortLeverage,
  });
}

class BingxFuturesMarginTypeReadResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;
  final String? marginType;

  const BingxFuturesMarginTypeReadResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
    required this.marginType,
  });
}

class BingxFuturesPublicPriceResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String? priceDecimal;
  final String? timestampMs;

  const BingxFuturesPublicPriceResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.priceDecimal,
    required this.timestampMs,
  });
}

class BingxFuturesPublicKline {
  final int openTimeMs;
  final String openDecimal;
  final String highDecimal;
  final String lowDecimal;
  final String closeDecimal;
  final String? volumeBaseDecimal;
  final String? volumeQuoteDecimal;

  const BingxFuturesPublicKline({
    required this.openTimeMs,
    required this.openDecimal,
    required this.highDecimal,
    required this.lowDecimal,
    required this.closeDecimal,
    this.volumeBaseDecimal,
    this.volumeQuoteDecimal,
  });
}

class BingxFuturesPublicKlinesResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String interval;
  final List<BingxFuturesPublicKline> klines;

  const BingxFuturesPublicKlinesResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.interval,
    required this.klines,
  });
}

class BingxFuturesPublicOrderBookLevel {
  final String priceDecimal;
  final String quantityDecimal;

  const BingxFuturesPublicOrderBookLevel({
    required this.priceDecimal,
    required this.quantityDecimal,
  });
}

class BingxFuturesPublicOrderBookResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String? timestampMs;
  final List<BingxFuturesPublicOrderBookLevel> bids;
  final List<BingxFuturesPublicOrderBookLevel> asks;

  const BingxFuturesPublicOrderBookResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.timestampMs,
    required this.bids,
    required this.asks,
  });
}

class BingxFuturesPublicTrade {
  final String? tradeId;
  final String side;
  final String priceDecimal;
  final String quantityDecimal;
  final String? timestampMs;

  const BingxFuturesPublicTrade({
    required this.tradeId,
    required this.side,
    required this.priceDecimal,
    required this.quantityDecimal,
    required this.timestampMs,
  });
}

class BingxFuturesPublicTradesResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final List<BingxFuturesPublicTrade> trades;

  const BingxFuturesPublicTradesResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.trades,
  });
}

class BingxFuturesPublicPremiumIndexResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String? markPriceDecimal;
  final String? indexPriceDecimal;
  final String? fundingRateDecimal;
  final String? nextFundingTimeMs;
  final String? timestampMs;

  const BingxFuturesPublicPremiumIndexResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.markPriceDecimal,
    required this.indexPriceDecimal,
    required this.fundingRateDecimal,
    required this.nextFundingTimeMs,
    required this.timestampMs,
  });
}

class BingxFuturesPublicOpenInterestResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String? openInterestDecimal;
  final String? timestampMs;

  const BingxFuturesPublicOpenInterestResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.openInterestDecimal,
    required this.timestampMs,
  });
}

class BingxFuturesPublicOpenInterestHistoryPoint {
  final String openInterestDecimal;
  final String timestampMs;

  const BingxFuturesPublicOpenInterestHistoryPoint({
    required this.openInterestDecimal,
    required this.timestampMs,
  });
}

class BingxFuturesPublicOpenInterestHistoryResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final String period;
  final List<BingxFuturesPublicOpenInterestHistoryPoint> points;

  const BingxFuturesPublicOpenInterestHistoryResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.period,
    required this.points,
  });
}

class BingxFuturesForceOrder {
  final String symbol;
  final String side;
  final String positionSide;
  final String? avgPriceDecimal;
  final String? priceDecimal;
  final String? quantityDecimal;
  final String? timestampMs;

  const BingxFuturesForceOrder({
    required this.symbol,
    required this.side,
    required this.positionSide,
    required this.avgPriceDecimal,
    required this.priceDecimal,
    required this.quantityDecimal,
    required this.timestampMs,
  });
}

class BingxFuturesUserForceOrdersResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String symbol;
  final List<BingxFuturesForceOrder> orders;

  const BingxFuturesUserForceOrdersResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.symbol,
    required this.orders,
  });
}

class BingxFuturesUserBalanceResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final String? accountEquityQuoteDecimal;
  final String? realizedPnlQuoteDecimal;

  const BingxFuturesUserBalanceResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.accountEquityQuoteDecimal,
    required this.realizedPnlQuoteDecimal,
  });
}

class BingxFuturesUserPosition {
  final String symbol;
  final String? quantityDecimal;
  final String? unrealizedPnlDecimal;
  final String? positionSide;

  const BingxFuturesUserPosition({
    required this.symbol,
    required this.quantityDecimal,
    required this.unrealizedPnlDecimal,
    required this.positionSide,
  });
}

class BingxFuturesUserPositionsResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String signedPayloadHashHex;
  final String responseBody;
  final List<BingxFuturesUserPosition> positions;

  const BingxFuturesUserPositionsResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.signedPayloadHashHex,
    required this.responseBody,
    required this.positions,
  });
}

class BingxFuturesPerpetualSymbolsResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final List<String> symbols;

  const BingxFuturesPerpetualSymbolsResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbols,
  });
}

class BingxFuturesPublicTicker {
  final String symbol;
  final String? lastPriceDecimal;
  final String? priceChangePercentDecimal;
  final String? volumeBaseDecimal;
  final String? volumeQuoteDecimal;

  const BingxFuturesPublicTicker({
    required this.symbol,
    required this.lastPriceDecimal,
    required this.priceChangePercentDecimal,
    required this.volumeBaseDecimal,
    required this.volumeQuoteDecimal,
  });
}

class BingxFuturesPublicTickersResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final List<BingxFuturesPublicTicker> tickers;

  const BingxFuturesPublicTickersResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.tickers,
  });
}

class BingxFuturesContractRules {
  final String symbol;
  final String? minimumQuantityDecimal;
  final String? minimumNotionalQuoteDecimal;
  final int? quantityPrecision;
  final int? pricePrecision;

  const BingxFuturesContractRules({
    required this.symbol,
    required this.minimumQuantityDecimal,
    required this.minimumNotionalQuoteDecimal,
    required this.quantityPrecision,
    required this.pricePrecision,
  });
}

class BingxFuturesContractRulesResult {
  final bool isSuccess;
  final int httpStatusCode;
  final String exchangeCode;
  final String exchangeMessage;
  final String endpointPath;
  final String responseBody;
  final String symbol;
  final BingxFuturesContractRules? rules;

  const BingxFuturesContractRulesResult({
    required this.isSuccess,
    required this.httpStatusCode,
    required this.exchangeCode,
    required this.exchangeMessage,
    required this.endpointPath,
    required this.responseBody,
    required this.symbol,
    required this.rules,
  });
}

class BingxHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  const BingxHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });
}

class BingxHttpResponse {
  final int statusCode;
  final String body;

  const BingxHttpResponse({required this.statusCode, required this.body});
}
