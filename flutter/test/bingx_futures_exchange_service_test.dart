import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';

void main() {
  group('BingxFuturesExchangeService', () {
    test('builds deterministic canonical param string and signature', () {
      final service = BingxFuturesExchangeService();
      final canonical = service.buildCanonicalParamString(
        <String, String>{
          'symbol': 'BTC-USDT',
          'type': 'LIMIT',
          'side': 'BUY',
          'positionSide': 'LONG',
          'price': '63000',
          'quantity': '0.01',
          'timestamp': '1710000000000',
          'recvWindow': '5000',
          'clientOrderID': 'ord-1',
          'timeInForce': 'GTC',
        },
      );
      expect(
        canonical,
        'clientOrderID=ord-1&positionSide=LONG&price=63000&quantity=0.01&recvWindow=5000&side=BUY&symbol=BTC-USDT&timeInForce=GTC&timestamp=1710000000000&type=LIMIT',
      );
      final signature = service.signParamString(
        canonicalParamString: canonical,
        apiSecret: 'test-secret',
      );
      expect(
        signature,
        '5aa70449d084c7b3fd3591b46bf2d092de3979c79bc3150bac028219baf44e33',
      );
    });

    test('executes test-order request and parses success response', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"OK","data":{"order":{"orderId":"789"}}}',
          );
        },
      );

      final result = await service.placeOrder(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        intent: const BingxFuturesIntentPayload(
          clientOrderId: 'ord-1',
          symbol: 'BTC-USDT',
          side: 'buy',
          orderType: 'limit',
          quantityDecimal: '0.01',
          limitPriceDecimal: '63000',
          timeInForce: 'GTC',
          entryMode: 'direct',
          triggerPriceDecimal: null,
          intentHashHex: 'abc',
        ),
        testOrder: true,
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/order/test');
      expect(capturedRequest.headers['X-BX-APIKEY'], 'api-key');
      expect(capturedRequest.body, contains('signature='));
      expect(capturedRequest.body, contains('type=LIMIT'));
      expect(result.isSuccess, isTrue);
      expect(result.orderId, '789');
      expect(result.exchangeCode, '0');
    });

    test('parses payload from plugin host intent result', () {
      final payload = BingxFuturesIntentPayload.fromPluginResult(
        <String, dynamic>{
          'client_order_id': 'ord-22',
          'symbol': 'btc-usdt',
          'side': 'sell',
          'order_type': 'market',
          'quantity_decimal': '0.25',
          'intent_hash_hex': 'fff',
        },
      );
      expect(payload.symbol, 'BTC-USDT');
      expect(payload.exchangeSide, 'SELL');
      expect(payload.positionSide, 'SHORT');
      expect(payload.exchangeOrderType, 'MARKET');
    });

    test('maps zone_pending limit intent to trigger-limit order payload',
        () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"OK","data":{"order":{"orderId":"555"}}}',
          );
        },
      );

      final result = await service.placeOrder(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        intent: const BingxFuturesIntentPayload(
          clientOrderId: 'ord-zp-1',
          symbol: 'BTC-USDT',
          side: 'sell',
          orderType: 'limit',
          quantityDecimal: '0.01',
          limitPriceDecimal: '63000',
          timeInForce: 'GTC',
          entryMode: 'zone_pending',
          triggerPriceDecimal: '62950',
          intentHashHex: 'def',
        ),
        testOrder: true,
      );

      expect(capturedRequest.body, contains('type=TRIGGER_LIMIT'));
      expect(capturedRequest.body, contains('stopPrice=62950'));
      expect(capturedRequest.body, contains('price=63000'));
      expect(result.isSuccess, isTrue);
      expect(result.orderId, '555');
    });

    test('switches leverage with signed v2 trade endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{}}',
          );
        },
      );

      final result = await service.switchLeverage(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'btc-usdt',
        side: BingxFuturesLeverageSide.long,
        leverage: 6,
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/leverage');
      expect(capturedRequest.body, contains('symbol=BTC-USDT'));
      expect(capturedRequest.body, contains('side=LONG'));
      expect(capturedRequest.body, contains('leverage=6'));
      expect(capturedRequest.body, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.actionName, 'switch_leverage');
    });

    test('switches margin type with signed v2 trade endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{}}',
          );
        },
      );

      final result = await service.switchMarginType(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'BTC-USDT',
        marginType: BingxFuturesMarginType.crossed,
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/marginType');
      expect(capturedRequest.body, contains('symbol=BTC-USDT'));
      expect(capturedRequest.body, contains('marginType=CROSSED'));
      expect(capturedRequest.body, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.actionName, 'switch_margin_type');
    });

    test('reads current leverage via signed GET endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"longLeverage":"8","shortLeverage":"5"}}',
          );
        },
      );

      final result = await service.getLeverage(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'btc-usdt',
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/leverage');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.longLeverage, 8);
      expect(result.shortLeverage, 5);
    });

    test('reads current margin type via signed GET endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{"marginType":"ISOLATED"}}',
          );
        },
      );

      final result = await service.getMarginType(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'BTC-USDT',
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/marginType');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.marginType, 'ISOLATED');
    });

    test('reads public quote price via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"","data":{"symbol":"BTC-USDT","price":"80078.0","time":1778255944017}}',
          );
        },
      );

      final result = await service.getPublicPrice(symbol: 'btc-usdt');

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/price');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.headers.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.symbol, 'BTC-USDT');
      expect(result.priceDecimal, '80078.0');
      expect(result.exchangeCode, '0');
    });

    test('reads public klines via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"","data":[[1710000000000,"60000","60100","59900","60050"],[1710000300000,"60050","60200","60020","60180"]]}',
          );
        },
      );

      final result = await service.getPublicKlines(
        symbol: 'btc-usdt',
        interval: '5m',
        limit: 50,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v3/quote/klines');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('interval=5m'));
      expect(capturedRequest.uri.query, contains('limit=50'));
      expect(capturedRequest.headers.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.interval, '5m');
      expect(result.klines, hasLength(2));
      expect(result.klines.first.openTimeMs, 1710000000000);
      expect(result.klines.first.highDecimal, '60100');
      expect(result.klines.last.closeDecimal, '60180');
    });
  });
}
