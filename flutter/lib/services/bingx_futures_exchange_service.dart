import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/bingx_futures_exchange_models.dart';

typedef BingxHttpRequestSender = Future<BingxHttpResponse> Function(
  BingxHttpRequest request,
);

class BingxFuturesExchangeService {
  static const Duration _httpTimeout = Duration(seconds: 12);
  static const String _defaultBaseUrl = 'https://open-api.bingx.com';
  static const String _publicPricePath = '/openApi/swap/v2/quote/price';
  static const String _publicKlinesPath = '/openApi/swap/v3/quote/klines';
  static const String _publicDepthPath = '/openApi/swap/v2/quote/depth';
  static const String _publicTradesPath = '/openApi/swap/v2/quote/trades';
  static const String _publicPremiumIndexPath =
      '/openApi/swap/v2/quote/premiumIndex';
  static const String _publicOpenInterestPath =
      '/openApi/swap/v2/quote/openInterest';
  static const String _publicContractsPath = '/openApi/swap/v2/quote/contracts';
  static const String _liveOrderPath = '/openApi/swap/v2/trade/order';
  static const String _testOrderPath = '/openApi/swap/v2/trade/order/test';
  static const String _switchLeveragePath = '/openApi/swap/v2/trade/leverage';
  static const String _switchMarginTypePath =
      '/openApi/swap/v2/trade/marginType';
  static const String _getLeveragePath = '/openApi/swap/v2/trade/leverage';
  static const String _getMarginTypePath = '/openApi/swap/v2/trade/marginType';
  static const String _getOpenOrdersPath = '/openApi/swap/v2/trade/openOrders';
  static const String _cancelOrderPath = '/openApi/swap/v2/trade/order';
  static const String _forceOrdersPath = '/openApi/swap/v2/trade/forceOrders';
  static const String _userBalancePath = '/openApi/swap/v2/user/balance';
  static const String _userPositionsPath = '/openApi/swap/v2/user/positions';

  final BingxHttpRequestSender _requestSender;
  final int Function() _clockMs;
  final String _baseUrl;
  final int recvWindowMs;

  BingxFuturesExchangeService({
    BingxHttpRequestSender? requestSender,
    int Function()? clockMs,
    String? baseUrl,
    this.recvWindowMs = 5000,
  })  : _requestSender = requestSender ?? _defaultRequestSender,
        _clockMs = clockMs ?? _defaultClockMs,
        _baseUrl = (baseUrl ?? _defaultBaseUrl).trim();

  Future<BingxFuturesOrderExecutionResult> placeOrder({
    required BingxFuturesApiCredentials credentials,
    required BingxFuturesIntentPayload intent,
    required bool testOrder,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final endpointPath = testOrder ? _testOrderPath : _liveOrderPath;
    final timestampMs = _clockMs();
    final params = <String, String>{
      'clientOrderID': intent.clientOrderId,
      'positionSide': intent.positionSide,
      'quantity': intent.quantityDecimal,
      'recvWindow': recvWindowMs.toString(),
      'side': intent.exchangeSide,
      'symbol': intent.symbol,
      'timestamp': timestampMs.toString(),
      'type': intent.exchangeOrderType,
    };
    if (intent.exchangeOrderType == 'LIMIT' ||
        intent.exchangeOrderType == 'TRIGGER_LIMIT') {
      params['price'] = intent.limitPriceDecimal!;
      params['timeInForce'] = (intent.timeInForce ?? 'GTC').toUpperCase();
    }
    if (intent.exchangeOrderType.startsWith('TRIGGER') &&
        (intent.triggerPriceDecimal == null ||
            intent.triggerPriceDecimal!.isEmpty)) {
      throw const FormatException(
          'Trigger order requires trigger_price_decimal');
    }
    if (intent.triggerPriceDecimal != null &&
        intent.triggerPriceDecimal!.isNotEmpty) {
      params['stopPrice'] = intent.triggerPriceDecimal!;
    }
    String encodeProtectionParam({
      required String type,
      required String stopPrice,
    }) {
      final numericStopPrice = num.tryParse(stopPrice);
      final encodedPrice = numericStopPrice ?? stopPrice;
      return jsonEncode(<String, dynamic>{
        'type': type,
        'stopPrice': encodedPrice,
        'price': encodedPrice,
        'workingType': 'MARK_PRICE',
      });
    }

    if (intent.stopLossDecimal != null && intent.stopLossDecimal!.isNotEmpty) {
      params['stopLoss'] = encodeProtectionParam(
        type: 'STOP_MARKET',
        stopPrice: intent.stopLossDecimal!,
      );
    }
    if (intent.takeProfitDecimal != null &&
        intent.takeProfitDecimal!.isNotEmpty) {
      params['takeProfit'] = encodeProtectionParam(
        type: 'TAKE_PROFIT_MARKET',
        stopPrice: intent.takeProfitDecimal!,
      );
    }

    final canonicalParamString = buildCanonicalParamString(params);
    final signature = signParamString(
      canonicalParamString: canonicalParamString,
      apiSecret: normalizedCredentials.apiSecret,
    );
    final signedBody = '$canonicalParamString&signature=$signature';
    final signedPayloadHashHex =
        sha256.convert(utf8.encode(signedBody)).toString();
    final requestUri = Uri.parse('$_baseUrl$endpointPath');
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'POST',
        uri: requestUri,
        headers: <String, String>{
          'X-BX-APIKEY': normalizedCredentials.apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: signedBody,
      ),
    );

    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final orderId = _extractOrderId(decoded);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok');

    return BingxFuturesOrderExecutionResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      orderId: orderId,
      endpointPath: endpointPath,
      signedPayloadHashHex: signedPayloadHashHex,
      responseBody: response.body,
      intentHashHex: intent.intentHashHex,
    );
  }

  Future<BingxFuturesControlActionResult> switchLeverage({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
    required BingxFuturesLeverageSide side,
    required int leverage,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    if (leverage < 1 || leverage > 200) {
      throw const FormatException('Leverage must be in range 1..200');
    }
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'side': side == BingxFuturesLeverageSide.long ? 'LONG' : 'SHORT',
      'leverage': leverage.toString(),
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final execution = await _executeSignedPost(
      credentials: normalizedCredentials,
      endpointPath: _switchLeveragePath,
      params: params,
      actionName: 'switch_leverage',
      symbol: normalizedSymbol,
    );
    return execution;
  }

  Future<BingxFuturesLeverageReadResult> getLeverage({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _getLeveragePath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final data = decoded?['data'];
    int? longLeverage;
    int? shortLeverage;
    if (data is Map) {
      longLeverage = int.tryParse(data['longLeverage']?.toString() ?? '');
      shortLeverage = int.tryParse(data['shortLeverage']?.toString() ?? '');
    }
    return BingxFuturesLeverageReadResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _getLeveragePath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      symbol: normalizedSymbol,
      longLeverage: longLeverage,
      shortLeverage: shortLeverage,
    );
  }

  Future<BingxFuturesMarginTypeReadResult> getMarginType({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _getMarginTypePath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final data = decoded?['data'];
    String? marginType;
    if (data is Map) {
      final value = data['marginType']?.toString().trim().toUpperCase();
      if (value != null && value.isNotEmpty) {
        marginType = value;
      }
    }
    return BingxFuturesMarginTypeReadResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _getMarginTypePath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      symbol: normalizedSymbol,
      marginType: marginType,
    );
  }

  Future<BingxFuturesOpenOrdersResult> getOpenOrders({
    required BingxFuturesApiCredentials credentials,
    String? symbol,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final timestampMs = _clockMs();
    final params = <String, String>{
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    String? normalizedSymbol;
    final symbolValue = symbol?.trim() ?? '';
    if (symbolValue.isNotEmpty) {
      normalizedSymbol = _normalizeSymbol(symbolValue);
      params['symbol'] = normalizedSymbol;
    }
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _getOpenOrdersPath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final orders = _extractOpenOrders(
      decoded: decoded,
      fallbackSymbol: normalizedSymbol ?? '',
    );
    return BingxFuturesOpenOrdersResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _getOpenOrdersPath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      symbol: normalizedSymbol ?? 'ALL',
      orders: orders,
    );
  }

  Future<BingxFuturesCancelOrderResult> cancelOrder({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
    required String orderId,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw const FormatException('orderId is required');
    }
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'orderId': normalizedOrderId,
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final response = await _executeSignedDelete(
      credentials: normalizedCredentials,
      endpointPath: _cancelOrderPath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final canceledOrderId = _extractOrderId(decoded);
    return BingxFuturesCancelOrderResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _cancelOrderPath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      symbol: normalizedSymbol,
      requestedOrderId: normalizedOrderId,
      canceledOrderId: canceledOrderId,
    );
  }

  Future<BingxFuturesPublicPriceResult> getPublicPrice({
    required String symbol,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final requestUri = Uri.parse(
      '$_baseUrl$_publicPricePath?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    String? priceDecimal;
    String? timestampMs;
    final data = decoded?['data'];
    if (data is Map) {
      final rawPrice = data['price']?.toString().trim();
      if (rawPrice != null && rawPrice.isNotEmpty) {
        priceDecimal = rawPrice;
      }
      final rawTime = data['time']?.toString().trim();
      if (rawTime != null && rawTime.isNotEmpty) {
        timestampMs = rawTime;
      }
    }
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        priceDecimal != null &&
        priceDecimal.isNotEmpty;
    return BingxFuturesPublicPriceResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicPricePath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      priceDecimal: priceDecimal,
      timestampMs: timestampMs,
    );
  }

  Future<BingxFuturesPublicKlinesResult> getPublicKlines({
    required String symbol,
    required String interval,
    int limit = 120,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final normalizedInterval = interval.trim().toLowerCase();
    if (!RegExp(r'^\d+[mhdw]$').hasMatch(normalizedInterval)) {
      throw const FormatException(
        'Interval format is invalid (expected 1m/5m/1h/4h/1d/1w)',
      );
    }
    if (limit < 10 || limit > 1000) {
      throw const FormatException('Kline limit must be in range 10..1000');
    }

    final requestUri = Uri.parse(
      '$_baseUrl$_publicKlinesPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}'
      '&interval=${Uri.encodeQueryComponent(normalizedInterval)}'
      '&limit=$limit',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);

    final parsed = <BingxFuturesPublicKline>[];
    final dynamic data = decoded?['data'];
    if (data is List) {
      for (final raw in data) {
        final kline = _extractPublicKline(raw);
        if (kline != null) {
          parsed.add(kline);
        }
      }
    } else if (data is Map) {
      final nested = data['list'];
      if (nested is List) {
        for (final raw in nested) {
          final kline = _extractPublicKline(raw);
          if (kline != null) {
            parsed.add(kline);
          }
        }
      }
    }

    parsed.sort((a, b) => a.openTimeMs.compareTo(b.openTimeMs));
    final klines = List<BingxFuturesPublicKline>.unmodifiable(parsed);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        klines.isNotEmpty;
    return BingxFuturesPublicKlinesResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicKlinesPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      interval: normalizedInterval,
      klines: klines,
    );
  }

  Future<BingxFuturesPublicOrderBookResult> getPublicDepth({
    required String symbol,
    int limit = 20,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    if (limit < 1 || limit > 200) {
      throw const FormatException('Depth limit must be in range 1..200');
    }
    final requestUri = Uri.parse(
      '$_baseUrl$_publicDepthPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}'
      '&limit=$limit',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final depth = _extractOrderBook(decoded);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        (depth.bids.isNotEmpty || depth.asks.isNotEmpty);
    return BingxFuturesPublicOrderBookResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicDepthPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      timestampMs: depth.timestampMs,
      bids: depth.bids,
      asks: depth.asks,
    );
  }

  Future<BingxFuturesPublicTradesResult> getPublicTrades({
    required String symbol,
    int limit = 100,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    if (limit < 1 || limit > 1000) {
      throw const FormatException('Trades limit must be in range 1..1000');
    }
    final requestUri = Uri.parse(
      '$_baseUrl$_publicTradesPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}'
      '&limit=$limit',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final trades = _extractPublicTrades(decoded);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        trades.isNotEmpty;
    return BingxFuturesPublicTradesResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicTradesPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      trades: trades,
    );
  }

  Future<BingxFuturesPublicPremiumIndexResult> getPublicPremiumIndex({
    required String symbol,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final requestUri = Uri.parse(
      '$_baseUrl$_publicPremiumIndexPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final data = decoded?['data'];
    final row = _extractFirstRow(data);
    final markPrice = _readStringField(row, const <String>[
      'markPrice',
      'mark_price',
      'mark',
    ]);
    final indexPrice = _readStringField(row, const <String>[
      'indexPrice',
      'index_price',
      'index',
    ]);
    final fundingRate = _readStringField(row, const <String>[
      'lastFundingRate',
      'fundingRate',
      'funding_rate',
    ]);
    final nextFunding = _readStringField(row, const <String>[
      'nextFundingTime',
      'nextFundingTimeStamp',
      'nextFundingAt',
      'nextFunding',
    ]);
    final timestampMs = _readStringField(row, const <String>[
      'time',
      'timestamp',
      'ts',
    ]);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        fundingRate != null &&
        fundingRate.isNotEmpty;
    return BingxFuturesPublicPremiumIndexResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicPremiumIndexPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      markPriceDecimal: markPrice,
      indexPriceDecimal: indexPrice,
      fundingRateDecimal: fundingRate,
      nextFundingTimeMs: nextFunding,
      timestampMs: timestampMs,
    );
  }

  Future<BingxFuturesPublicOpenInterestResult> getPublicOpenInterest({
    required String symbol,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final requestUri = Uri.parse(
      '$_baseUrl$_publicOpenInterestPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final data = decoded?['data'];
    final row = _extractFirstRow(data);
    final openInterest = _readStringField(row, const <String>[
      'openInterest',
      'open_interest',
      'openInterestAmount',
      'amount',
    ]);
    final timestampMs = _readStringField(row, const <String>[
      'time',
      'timestamp',
      'ts',
    ]);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        openInterest != null &&
        openInterest.isNotEmpty;
    return BingxFuturesPublicOpenInterestResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicOpenInterestPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      openInterestDecimal: openInterest,
      timestampMs: timestampMs,
    );
  }

  Future<BingxFuturesPublicOpenInterestHistoryResult>
      getPublicOpenInterestHistory({
    required String symbol,
    String period = '5m',
    int limit = 24,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final normalizedPeriod = period.trim().toLowerCase();
    if (!RegExp(r'^\d+[mhdw]$').hasMatch(normalizedPeriod)) {
      throw const FormatException(
        'Open interest period format is invalid (expected 5m/15m/1h/4h/1d/1w)',
      );
    }
    if (limit < 2 || limit > 200) {
      throw const FormatException(
        'Open interest history limit must be in range 2..200',
      );
    }
    final requestUri = Uri.parse(
      '$_baseUrl$_publicOpenInterestPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}'
      '&period=${Uri.encodeQueryComponent(normalizedPeriod)}'
      '&limit=$limit',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final points = _extractOpenInterestHistory(decoded);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        points.isNotEmpty;
    return BingxFuturesPublicOpenInterestHistoryResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicOpenInterestPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      period: normalizedPeriod,
      points: points,
    );
  }

  Future<BingxFuturesUserForceOrdersResult> getUserForceOrders({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
    int limit = 50,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    if (limit < 1 || limit > 200) {
      throw const FormatException('Force orders limit must be in range 1..200');
    }
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'limit': limit.toString(),
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _forceOrdersPath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final orders = _extractForceOrders(
      decoded: decoded,
      fallbackSymbol: normalizedSymbol,
    );
    return BingxFuturesUserForceOrdersResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _forceOrdersPath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      symbol: normalizedSymbol,
      orders: orders,
    );
  }

  Future<BingxFuturesUserBalanceResult> getUserBalance({
    required BingxFuturesApiCredentials credentials,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final timestampMs = _clockMs();
    final params = <String, String>{
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _userBalancePath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final row = _extractBalanceRow(decoded?['data']);
    final equity = _readStringField(row, const <String>[
      'equity',
      'accountEquity',
      'balance',
      'totalBalance',
      'walletBalance',
      'availableBalance',
    ]);
    final realizedPnl = _readStringField(row, const <String>[
      'realizedPnl',
      'realizedPNL',
      'todayRealizedPnl',
      'dailyRealizedPnl',
      'realizedProfit',
      'realisedProfit',
      'realized_profit',
      'realised_profit',
    ]);
    return BingxFuturesUserBalanceResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _userBalancePath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      accountEquityQuoteDecimal: equity,
      realizedPnlQuoteDecimal: realizedPnl,
    );
  }

  Future<BingxFuturesUserPositionsResult> getUserPositions({
    required BingxFuturesApiCredentials credentials,
    String? symbol,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final timestampMs = _clockMs();
    final params = <String, String>{
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final normalizedSymbol = symbol?.trim().toUpperCase();
    if (normalizedSymbol != null && normalizedSymbol.isNotEmpty) {
      params['symbol'] = _normalizeSymbol(normalizedSymbol);
    }
    final response = await _executeSignedGet(
      credentials: normalizedCredentials,
      endpointPath: _userPositionsPath,
      params: params,
    );
    final decoded = _tryDecodeMap(response.body);
    final positions = _extractUserPositions(decoded);
    return BingxFuturesUserPositionsResult(
      isSuccess: response.isSuccess,
      httpStatusCode: response.httpStatusCode,
      exchangeCode: response.exchangeCode,
      exchangeMessage: response.exchangeMessage,
      endpointPath: _userPositionsPath,
      signedPayloadHashHex: response.signedPayloadHashHex,
      responseBody: response.body,
      positions: positions,
    );
  }

  Future<BingxFuturesPerpetualSymbolsResult> getPerpetualSymbols() async {
    final requestUri = Uri.parse('$_baseUrl$_publicContractsPath');
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final symbols = _extractPerpetualSymbols(decoded);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        symbols.isNotEmpty;
    return BingxFuturesPerpetualSymbolsResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicContractsPath,
      responseBody: response.body,
      symbols: symbols,
    );
  }

  Future<BingxFuturesContractRulesResult> getPerpetualContractRules({
    required String symbol,
  }) async {
    final normalizedSymbol = _normalizeSymbol(symbol);
    final requestUri = Uri.parse(
      '$_baseUrl$_publicContractsPath'
      '?symbol=${Uri.encodeQueryComponent(normalizedSymbol)}',
    );
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: const <String, String>{},
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final rules = _extractContractRules(decoded, normalizedSymbol);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok') &&
        rules != null;
    return BingxFuturesContractRulesResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      endpointPath: _publicContractsPath,
      responseBody: response.body,
      symbol: normalizedSymbol,
      rules: rules,
    );
  }

  Future<BingxFuturesControlActionResult> switchMarginType({
    required BingxFuturesApiCredentials credentials,
    required String symbol,
    required BingxFuturesMarginType marginType,
  }) async {
    final normalizedCredentials = credentials.normalized();
    final normalizedSymbol = _normalizeSymbol(symbol);
    final timestampMs = _clockMs();
    final params = <String, String>{
      'symbol': normalizedSymbol,
      'marginType': marginType == BingxFuturesMarginType.isolated
          ? 'ISOLATED'
          : 'CROSSED',
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestampMs.toString(),
    };
    final execution = await _executeSignedPost(
      credentials: normalizedCredentials,
      endpointPath: _switchMarginTypePath,
      params: params,
      actionName: 'switch_margin_type',
      symbol: normalizedSymbol,
    );
    return execution;
  }

  String buildCanonicalParamString(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final parts = <String>[];
    for (final key in sortedKeys) {
      final value = params[key];
      if (value == null) continue;
      final normalized = value.trim();
      if (normalized.isEmpty) continue;
      parts.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(normalized)}',
      );
    }
    if (parts.isEmpty) {
      throw const FormatException('No request parameters to sign');
    }
    return parts.join('&');
  }

  String signParamString({
    required String canonicalParamString,
    required String apiSecret,
  }) {
    final normalizedSecret = apiSecret.trim();
    if (normalizedSecret.isEmpty) {
      throw const FormatException('BingX API secret is required');
    }
    final hmac = Hmac(sha256, utf8.encode(normalizedSecret));
    return hmac.convert(utf8.encode(canonicalParamString)).toString();
  }

  Future<BingxFuturesControlActionResult> _executeSignedPost({
    required BingxFuturesApiCredentials credentials,
    required String endpointPath,
    required Map<String, String> params,
    required String actionName,
    required String symbol,
  }) async {
    final canonicalParamString = buildCanonicalParamString(params);
    final signature = signParamString(
      canonicalParamString: canonicalParamString,
      apiSecret: credentials.apiSecret,
    );
    final signedBody = '$canonicalParamString&signature=$signature';
    final signedPayloadHashHex =
        sha256.convert(utf8.encode(signedBody)).toString();
    final requestUri = Uri.parse('$_baseUrl$endpointPath');
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'POST',
        uri: requestUri,
        headers: <String, String>{
          'X-BX-APIKEY': credentials.apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: signedBody,
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok');
    return BingxFuturesControlActionResult(
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      actionName: actionName,
      endpointPath: endpointPath,
      signedPayloadHashHex: signedPayloadHashHex,
      responseBody: response.body,
      symbol: symbol,
    );
  }

  Future<
      ({
        bool isSuccess,
        int httpStatusCode,
        String exchangeCode,
        String exchangeMessage,
        String signedPayloadHashHex,
        String body,
      })> _executeSignedGet({
    required BingxFuturesApiCredentials credentials,
    required String endpointPath,
    required Map<String, String> params,
  }) async {
    final canonicalParamString = buildCanonicalParamString(params);
    final signature = signParamString(
      canonicalParamString: canonicalParamString,
      apiSecret: credentials.apiSecret,
    );
    final signedQuery = '$canonicalParamString&signature=$signature';
    final signedPayloadHashHex =
        sha256.convert(utf8.encode(signedQuery)).toString();
    final requestUri = Uri.parse('$_baseUrl$endpointPath?$signedQuery');
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'GET',
        uri: requestUri,
        headers: <String, String>{
          'X-BX-APIKEY': credentials.apiKey,
        },
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok');
    return (
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      signedPayloadHashHex: signedPayloadHashHex,
      body: response.body,
    );
  }

  Future<
      ({
        bool isSuccess,
        int httpStatusCode,
        String exchangeCode,
        String exchangeMessage,
        String signedPayloadHashHex,
        String body,
      })> _executeSignedDelete({
    required BingxFuturesApiCredentials credentials,
    required String endpointPath,
    required Map<String, String> params,
  }) async {
    final canonicalParamString = buildCanonicalParamString(params);
    final signature = signParamString(
      canonicalParamString: canonicalParamString,
      apiSecret: credentials.apiSecret,
    );
    final signedQuery = '$canonicalParamString&signature=$signature';
    final signedPayloadHashHex =
        sha256.convert(utf8.encode(signedQuery)).toString();
    final requestUri = Uri.parse('$_baseUrl$endpointPath?$signedQuery');
    final response = await _requestSender(
      BingxHttpRequest(
        method: 'DELETE',
        uri: requestUri,
        headers: <String, String>{
          'X-BX-APIKEY': credentials.apiKey,
        },
        body: '',
      ),
    );
    final decoded = _tryDecodeMap(response.body);
    final exchangeCode =
        decoded?['code']?.toString() ?? 'http_${response.statusCode}';
    final exchangeMessage = decoded?['msg']?.toString() ??
        decoded?['message']?.toString() ??
        (response.body.trim().isEmpty ? 'No response body' : response.body);
    final isSuccess = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (exchangeCode == '0' || exchangeCode == 'OK' || exchangeCode == 'ok');
    return (
      isSuccess: isSuccess,
      httpStatusCode: response.statusCode,
      exchangeCode: exchangeCode,
      exchangeMessage: exchangeMessage,
      signedPayloadHashHex: signedPayloadHashHex,
      body: response.body,
    );
  }

  String _normalizeSymbol(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,20}([-_/][A-Z0-9]{2,20})?$')
        .hasMatch(normalized)) {
      throw const FormatException('Symbol format is invalid');
    }
    return normalized;
  }

  static Map<String, dynamic>? _tryDecodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractOrderId(Map<String, dynamic>? decoded) {
    if (decoded == null) return null;
    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      final direct = data['orderId']?.toString();
      if (direct != null && direct.isNotEmpty) return direct;
      final order = data['order'];
      if (order is Map<String, dynamic>) {
        final nested = order['orderId']?.toString();
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
    return null;
  }

  static List<BingxFuturesOpenOrder> _extractOpenOrders({
    required Map<String, dynamic>? decoded,
    required String fallbackSymbol,
  }) {
    if (decoded == null) return const <BingxFuturesOpenOrder>[];
    final data = decoded['data'];
    final rawList = <dynamic>[];
    if (data is List) {
      rawList.addAll(data);
    } else if (data is Map<String, dynamic>) {
      final orders = data['orders'];
      if (orders is List) {
        rawList.addAll(orders);
      } else {
        final rows = data['rows'];
        if (rows is List) {
          rawList.addAll(rows);
        } else {
          final list = data['list'];
          if (list is List) {
            rawList.addAll(list);
          }
        }
      }
    }

    final parsed = <BingxFuturesOpenOrder>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final orderId = map['orderId']?.toString().trim() ??
          map['orderID']?.toString().trim() ??
          map['id']?.toString().trim() ??
          '';
      if (orderId.isEmpty) continue;
      final symbol = map['symbol']?.toString().trim().toUpperCase();
      final side = map['side']?.toString().trim().toUpperCase() ?? '';
      final positionSide =
          map['positionSide']?.toString().trim().toUpperCase() ?? '';
      final orderType = map['type']?.toString().trim().toUpperCase() ?? '';
      final status = map['status']?.toString().trim().toUpperCase() ?? '';
      final price = map['price']?.toString().trim().isNotEmpty == true
          ? map['price']?.toString().trim()
          : map['avgPrice']?.toString().trim();
      final stopPrice = map['stopPrice']?.toString().trim();
      final quantity = map['origQty']?.toString().trim().isNotEmpty == true
          ? map['origQty']?.toString().trim()
          : map['quantity']?.toString().trim();
      final executedQty =
          map['executedQty']?.toString().trim().isNotEmpty == true
              ? map['executedQty']?.toString().trim()
              : map['cumQuote']?.toString().trim();
      final createdAtMs = int.tryParse(
        map['time']?.toString() ??
            map['createTime']?.toString() ??
            map['timestamp']?.toString() ??
            '',
      );
      parsed.add(
        BingxFuturesOpenOrder(
          orderId: orderId,
          symbol: symbol == null || symbol.isEmpty ? fallbackSymbol : symbol,
          side: side,
          positionSide: positionSide,
          orderType: orderType,
          status: status,
          priceDecimal: (price == null || price.isEmpty) ? null : price,
          triggerPriceDecimal:
              (stopPrice == null || stopPrice.isEmpty) ? null : stopPrice,
          quantityDecimal:
              (quantity == null || quantity.isEmpty) ? null : quantity,
          executedQuantityDecimal:
              (executedQty == null || executedQty.isEmpty) ? null : executedQty,
          createdAtMs: createdAtMs,
        ),
      );
    }
    parsed.sort((a, b) {
      final ta = a.createdAtMs ?? 0;
      final tb = b.createdAtMs ?? 0;
      return tb.compareTo(ta);
    });
    return List<BingxFuturesOpenOrder>.unmodifiable(parsed);
  }

  static BingxFuturesPublicKline? _extractPublicKline(dynamic raw) {
    if (raw is List && raw.length >= 5) {
      final openTimeMs = int.tryParse(raw[0].toString());
      final open = raw[1].toString().trim();
      final high = raw[2].toString().trim();
      final low = raw[3].toString().trim();
      final close = raw[4].toString().trim();
      if (openTimeMs == null ||
          open.isEmpty ||
          high.isEmpty ||
          low.isEmpty ||
          close.isEmpty) {
        return null;
      }
      return BingxFuturesPublicKline(
        openTimeMs: openTimeMs,
        openDecimal: open,
        highDecimal: high,
        lowDecimal: low,
        closeDecimal: close,
      );
    }
    if (raw is Map) {
      final openTimeRaw =
          raw['time'] ?? raw['openTime'] ?? raw['timestamp'] ?? raw['t'];
      final openRaw = raw['open'] ?? raw['o'];
      final highRaw = raw['high'] ?? raw['h'];
      final lowRaw = raw['low'] ?? raw['l'];
      final closeRaw = raw['close'] ?? raw['c'];
      final openTimeMs = int.tryParse(openTimeRaw?.toString() ?? '');
      final open = openRaw?.toString().trim() ?? '';
      final high = highRaw?.toString().trim() ?? '';
      final low = lowRaw?.toString().trim() ?? '';
      final close = closeRaw?.toString().trim() ?? '';
      if (openTimeMs == null ||
          open.isEmpty ||
          high.isEmpty ||
          low.isEmpty ||
          close.isEmpty) {
        return null;
      }
      return BingxFuturesPublicKline(
        openTimeMs: openTimeMs,
        openDecimal: open,
        highDecimal: high,
        lowDecimal: low,
        closeDecimal: close,
      );
    }
    return null;
  }

  static ({
    List<BingxFuturesPublicOrderBookLevel> bids,
    List<BingxFuturesPublicOrderBookLevel> asks,
    String? timestampMs,
  }) _extractOrderBook(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return (
        bids: const <BingxFuturesPublicOrderBookLevel>[],
        asks: const <BingxFuturesPublicOrderBookLevel>[],
        timestampMs: null,
      );
    }
    final data = decoded['data'];
    final row = _extractFirstRow(data);
    if (row == null) {
      return (
        bids: const <BingxFuturesPublicOrderBookLevel>[],
        asks: const <BingxFuturesPublicOrderBookLevel>[],
        timestampMs: null,
      );
    }
    final bids = _extractOrderBookSide(row, const <String>['bids', 'bid']);
    final asks = _extractOrderBookSide(row, const <String>['asks', 'ask']);
    final timestampMs = _readStringField(row, const <String>[
      'time',
      'timestamp',
      'ts',
    ]);
    return (
      bids: bids,
      asks: asks,
      timestampMs: timestampMs,
    );
  }

  static List<BingxFuturesPublicOrderBookLevel> _extractOrderBookSide(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    List<dynamic>? rawLevels;
    for (final key in keys) {
      final value = row[key];
      if (value is List) {
        rawLevels = value;
        break;
      }
    }
    if (rawLevels == null || rawLevels.isEmpty) {
      return const <BingxFuturesPublicOrderBookLevel>[];
    }
    final parsed = <BingxFuturesPublicOrderBookLevel>[];
    for (final level in rawLevels) {
      if (level is List && level.length >= 2) {
        final price = level[0].toString().trim();
        final quantity = level[1].toString().trim();
        if (price.isEmpty || quantity.isEmpty) continue;
        parsed.add(
          BingxFuturesPublicOrderBookLevel(
            priceDecimal: price,
            quantityDecimal: quantity,
          ),
        );
        continue;
      }
      if (level is Map) {
        final map = Map<String, dynamic>.from(level);
        final price = _readStringField(map, const <String>['price', 'p']);
        final quantity = _readStringField(
          map,
          const <String>['qty', 'quantity', 'q', 'size'],
        );
        if (price == null || quantity == null) continue;
        parsed.add(
          BingxFuturesPublicOrderBookLevel(
            priceDecimal: price,
            quantityDecimal: quantity,
          ),
        );
      }
    }
    return List<BingxFuturesPublicOrderBookLevel>.unmodifiable(parsed);
  }

  static List<BingxFuturesPublicTrade> _extractPublicTrades(
    Map<String, dynamic>? decoded,
  ) {
    if (decoded == null) return const <BingxFuturesPublicTrade>[];
    final data = decoded['data'];
    final rows = <dynamic>[];
    if (data is List) {
      rows.addAll(data);
    } else if (data is Map) {
      final candidates = <dynamic>[
        data['list'],
        data['rows'],
        data['trades'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          rows.addAll(candidate);
          break;
        }
      }
    }
    if (rows.isEmpty) return const <BingxFuturesPublicTrade>[];
    final parsed = <BingxFuturesPublicTrade>[];
    for (final item in rows) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final price = _readStringField(map, const <String>['price', 'p']);
      final quantity = _readStringField(
        map,
        const <String>['qty', 'quantity', 'q', 'size'],
      );
      if (price == null || quantity == null) continue;
      final sideRaw = _readStringField(
        map,
        const <String>['side', 's', 'makerSide'],
      );
      final side = _normalizePublicTradeSide(map, sideRaw);
      if (side == 'unknown') continue;
      final tradeId = _readStringField(map, const <String>[
        'id',
        'tradeId',
        'fillId',
        't',
      ]);
      final timestampMs = _readStringField(map, const <String>[
        'time',
        'timestamp',
        'ts',
      ]);
      parsed.add(
        BingxFuturesPublicTrade(
          tradeId: tradeId,
          side: side,
          priceDecimal: price,
          quantityDecimal: quantity,
          timestampMs: timestampMs,
        ),
      );
    }
    parsed.sort((a, b) {
      final ta = int.tryParse(a.timestampMs ?? '') ?? 0;
      final tb = int.tryParse(b.timestampMs ?? '') ?? 0;
      return ta.compareTo(tb);
    });
    return List<BingxFuturesPublicTrade>.unmodifiable(parsed);
  }

  static String _normalizeTradeSide(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return 'unknown';
    if (normalized == 'buy' || normalized == 'bid') return 'buy';
    if (normalized == 'sell' || normalized == 'ask') return 'sell';
    return normalized;
  }

  static String _normalizePublicTradeSide(
    Map<String, dynamic> map,
    String? explicitSide,
  ) {
    final normalized = _normalizeTradeSide(explicitSide);
    if (normalized == 'buy' || normalized == 'sell') {
      return normalized;
    }

    final rawBuyerMaker = map['isBuyerMaker'];
    final isBuyerMaker = switch (rawBuyerMaker) {
      bool value => value,
      String value when value.trim().toLowerCase() == 'true' => true,
      String value when value.trim().toLowerCase() == 'false' => false,
      num value when value == 1 => true,
      num value when value == 0 => false,
      _ => null,
    };
    if (isBuyerMaker == null) return 'unknown';

    // BingX reports maker side; TVH consumes the aggressor side.
    return isBuyerMaker ? 'sell' : 'buy';
  }

  static List<BingxFuturesPublicOpenInterestHistoryPoint>
      _extractOpenInterestHistory(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return const <BingxFuturesPublicOpenInterestHistoryPoint>[];
    }
    final data = decoded['data'];
    final rows = <dynamic>[];
    if (data is List) {
      rows.addAll(data);
    } else if (data is Map) {
      final candidates = <dynamic>[
        data['list'],
        data['rows'],
        data['history'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          rows.addAll(candidate);
          break;
        }
      }
      if (rows.isEmpty) {
        rows.add(data);
      }
    }
    if (rows.isEmpty) {
      return const <BingxFuturesPublicOpenInterestHistoryPoint>[];
    }
    final parsed = <BingxFuturesPublicOpenInterestHistoryPoint>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final openInterest = _readStringField(map, const <String>[
        'openInterest',
        'open_interest',
        'openInterestAmount',
        'amount',
      ]);
      final timestamp = _readStringField(map, const <String>[
        'time',
        'timestamp',
        'ts',
      ]);
      if (openInterest == null || timestamp == null) continue;
      parsed.add(
        BingxFuturesPublicOpenInterestHistoryPoint(
          openInterestDecimal: openInterest,
          timestampMs: timestamp,
        ),
      );
    }
    parsed.sort((a, b) {
      final ta = int.tryParse(a.timestampMs) ?? 0;
      final tb = int.tryParse(b.timestampMs) ?? 0;
      return ta.compareTo(tb);
    });
    return List<BingxFuturesPublicOpenInterestHistoryPoint>.unmodifiable(
        parsed);
  }

  static List<BingxFuturesForceOrder> _extractForceOrders({
    required Map<String, dynamic>? decoded,
    required String fallbackSymbol,
  }) {
    if (decoded == null) return const <BingxFuturesForceOrder>[];
    final data = decoded['data'];
    final rows = <dynamic>[];
    if (data is List) {
      rows.addAll(data);
    } else if (data is Map) {
      final candidates = <dynamic>[
        data['orders'],
        data['rows'],
        data['list'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          rows.addAll(candidate);
          break;
        }
      }
      if (rows.isEmpty) rows.add(data);
    }
    if (rows.isEmpty) return const <BingxFuturesForceOrder>[];
    final parsed = <BingxFuturesForceOrder>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final symbol =
          _readStringField(map, const <String>['symbol']) ?? fallbackSymbol;
      final side =
          _readStringField(map, const <String>['side'])?.toUpperCase() ?? '';
      final positionSide = _readStringField(
            map,
            const <String>['positionSide', 'posSide'],
          )?.toUpperCase() ??
          '';
      final avgPrice = _readStringField(
        map,
        const <String>['avgPrice', 'averagePrice', 'avg_price'],
      );
      final price = _readStringField(
        map,
        const <String>['price', 'orderPrice'],
      );
      final qty = _readStringField(
        map,
        const <String>['origQty', 'quantity', 'qty', 'executedQty'],
      );
      final ts = _readStringField(
        map,
        const <String>['time', 'timestamp', 'ts', 'updateTime'],
      );
      if (side.isEmpty &&
          positionSide.isEmpty &&
          avgPrice == null &&
          price == null) {
        continue;
      }
      parsed.add(
        BingxFuturesForceOrder(
          symbol: _tryNormalizeSymbol(symbol) ?? fallbackSymbol,
          side: side,
          positionSide: positionSide,
          avgPriceDecimal: avgPrice,
          priceDecimal: price,
          quantityDecimal: qty,
          timestampMs: ts,
        ),
      );
    }
    parsed.sort((a, b) {
      final ta = int.tryParse(a.timestampMs ?? '') ?? 0;
      final tb = int.tryParse(b.timestampMs ?? '') ?? 0;
      return tb.compareTo(ta);
    });
    return List<BingxFuturesForceOrder>.unmodifiable(parsed);
  }

  static List<BingxFuturesUserPosition> _extractUserPositions(
    Map<String, dynamic>? decoded,
  ) {
    if (decoded == null) return const <BingxFuturesUserPosition>[];
    final data = decoded['data'];
    final rows = <dynamic>[];
    if (data is List) {
      rows.addAll(data);
    } else if (data is Map) {
      final candidates = <dynamic>[
        data['positions'],
        data['rows'],
        data['list'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          rows.addAll(candidate);
          break;
        }
      }
      if (rows.isEmpty) rows.add(data);
    }
    final parsed = <BingxFuturesUserPosition>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final symbol = _readStringField(map, const <String>[
        'symbol',
        'pair',
      ]);
      if (symbol == null) continue;
      parsed.add(
        BingxFuturesUserPosition(
          symbol: _tryNormalizeSymbol(symbol) ?? symbol.toUpperCase(),
          quantityDecimal: _readStringField(
            map,
            const <String>['positionAmt', 'positionAmount', 'quantity', 'size'],
          ),
          unrealizedPnlDecimal: _readStringField(
            map,
            const <String>['unRealizedProfit', 'unrealizedPnl', 'uPnl'],
          ),
          positionSide: _readStringField(
            map,
            const <String>['positionSide', 'side'],
          ),
        ),
      );
    }
    return List<BingxFuturesUserPosition>.unmodifiable(parsed);
  }

  static Map<String, dynamic>? _extractFirstRow(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List) {
      for (final item in data) {
        if (item is Map) return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  static Map<String, dynamic>? _extractBalanceRow(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final nested = map['balance'];
      if (nested is Map) {
        return Map<String, dynamic>.from(nested);
      }
      final nestedList = map['balances'];
      if (nestedList is List) {
        for (final row in nestedList) {
          if (row is! Map) continue;
          final rowMap = Map<String, dynamic>.from(row);
          final asset = rowMap['asset']?.toString().trim().toUpperCase();
          if (asset == 'USDT') {
            return rowMap;
          }
        }
      }
    }
    return _extractFirstRow(data);
  }

  static String? _readStringField(
      Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _extractPerpetualSymbols(Map<String, dynamic>? decoded) {
    final rawItems = _extractContractItems(decoded);

    final out = <String>{};
    for (final item in rawItems) {
      if (item is String) {
        final normalized = _tryNormalizeSymbol(item);
        if (normalized != null) out.add(normalized);
        continue;
      }
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final candidates = <String?>[
        map['symbol']?.toString(),
        map['contractSymbol']?.toString(),
        map['pair']?.toString(),
        map['instrumentId']?.toString(),
      ];
      for (final raw in candidates) {
        if (raw == null) continue;
        final normalized = _tryNormalizeSymbol(raw);
        if (normalized != null) {
          out.add(normalized);
          break;
        }
      }
    }

    final sorted = out.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  static BingxFuturesContractRules? _extractContractRules(
    Map<String, dynamic>? decoded,
    String symbol,
  ) {
    for (final item in _extractContractItems(decoded)) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final rawSymbol = _readStringField(
        map,
        const <String>['symbol', 'contractSymbol', 'pair', 'instrumentId'],
      );
      if (rawSymbol == null || _tryNormalizeSymbol(rawSymbol) != symbol) {
        continue;
      }
      return BingxFuturesContractRules(
        symbol: symbol,
        minimumQuantityDecimal: _readStringField(
          map,
          const <String>['tradeMinQuantity', 'minQty', 'minimumQuantity'],
        ),
        minimumNotionalQuoteDecimal: _readStringField(
          map,
          const <String>['tradeMinUSDT', 'minNotional', 'minimumNotional'],
        ),
        quantityPrecision: int.tryParse(
          _readStringField(map, const <String>['quantityPrecision']) ?? '',
        ),
        pricePrecision: int.tryParse(
          _readStringField(map, const <String>['pricePrecision']) ?? '',
        ),
      );
    }
    return null;
  }

  static List<dynamic> _extractContractItems(
    Map<String, dynamic>? decoded,
  ) {
    if (decoded == null) return const <dynamic>[];
    final data = decoded['data'];
    if (data is List) return List<dynamic>.from(data);
    if (data is! Map) return const <dynamic>[];
    for (final key in const <String>['contracts', 'symbols', 'list', 'rows']) {
      final items = data[key];
      if (items is List) return List<dynamic>.from(items);
    }
    return const <dynamic>[];
  }

  static String? _tryNormalizeSymbol(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^[A-Z0-9]{2,20}([-_/][A-Z0-9]{2,20})?$')
        .hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static int _defaultClockMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<BingxHttpResponse> _defaultRequestSender(
    BingxHttpRequest request,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = _httpTimeout;
    try {
      final method = request.method.trim().toUpperCase();
      final httpRequest = switch (method) {
        'GET' => await client.getUrl(request.uri).timeout(_httpTimeout),
        'POST' => await client.postUrl(request.uri).timeout(_httpTimeout),
        'DELETE' => await client.deleteUrl(request.uri).timeout(_httpTimeout),
        _ => throw FormatException('Unsupported HTTP method: $method'),
      };
      request.headers.forEach(httpRequest.headers.set);
      if (request.body.isNotEmpty) {
        httpRequest.write(request.body);
      }
      final httpResponse = await httpRequest.close().timeout(_httpTimeout);
      final body = await utf8.decodeStream(httpResponse).timeout(_httpTimeout);
      return BingxHttpResponse(
        statusCode: httpResponse.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }
}
