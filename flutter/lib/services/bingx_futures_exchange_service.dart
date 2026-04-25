import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class BingxFuturesApiCredentials {
  final String apiKey;
  final String apiSecret;

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
  final String? triggerPriceDecimal;
  final String? intentHashHex;

  const BingxFuturesIntentPayload({
    required this.clientOrderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.quantityDecimal,
    required this.limitPriceDecimal,
    required this.timeInForce,
    required this.triggerPriceDecimal,
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
    final triggerPrice = result['trigger_price_decimal']?.toString().trim();
    if (normalizedOrderType == 'limit' &&
        (limitPrice == null || limitPrice.isEmpty)) {
      throw const FormatException('Limit intent requires limit_price_decimal');
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
      triggerPriceDecimal:
          (triggerPrice == null || triggerPrice.isEmpty) ? null : triggerPrice,
      intentHashHex: result['intent_hash_hex']?.toString().trim(),
    );
  }

  String get exchangeSide => side == 'buy' ? 'BUY' : 'SELL';
  String get positionSide => side == 'buy' ? 'LONG' : 'SHORT';
  String get exchangeOrderType => orderType == 'limit' ? 'LIMIT' : 'MARKET';
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

enum BingxFuturesLeverageSide {
  long,
  short,
}

enum BingxFuturesMarginType {
  isolated,
  crossed,
}

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

  const BingxHttpResponse({
    required this.statusCode,
    required this.body,
  });
}

typedef BingxHttpRequestSender = Future<BingxHttpResponse> Function(
  BingxHttpRequest request,
);

class BingxFuturesExchangeService {
  static const String _defaultBaseUrl = 'https://open-api.bingx.com';
  static const String _liveOrderPath = '/openApi/swap/v2/trade/order';
  static const String _testOrderPath = '/openApi/swap/v2/trade/order/test';
  static const String _switchLeveragePath = '/openApi/swap/v2/trade/leverage';
  static const String _switchMarginTypePath =
      '/openApi/swap/v2/trade/marginType';
  static const String _getLeveragePath = '/openApi/swap/v2/trade/leverage';
  static const String _getMarginTypePath = '/openApi/swap/v2/trade/marginType';

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
    if (intent.exchangeOrderType == 'LIMIT') {
      params['price'] = intent.limitPriceDecimal!;
      params['timeInForce'] = (intent.timeInForce ?? 'GTC').toUpperCase();
    }
    if (intent.triggerPriceDecimal != null &&
        intent.triggerPriceDecimal!.isNotEmpty) {
      params['stopPrice'] = intent.triggerPriceDecimal!;
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

  static int _defaultClockMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<BingxHttpResponse> _defaultRequestSender(
    BingxHttpRequest request,
  ) async {
    final client = HttpClient();
    try {
      final method = request.method.trim().toUpperCase();
      final httpRequest = switch (method) {
        'GET' => await client.getUrl(request.uri),
        'POST' => await client.postUrl(request.uri),
        _ => throw FormatException('Unsupported HTTP method: $method'),
      };
      request.headers.forEach(httpRequest.headers.set);
      if (request.body.isNotEmpty) {
        httpRequest.write(request.body);
      }
      final httpResponse = await httpRequest.close();
      final body = await utf8.decodeStream(httpResponse);
      return BingxHttpResponse(
        statusCode: httpResponse.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }
}
