import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
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
          stopLossDecimal: null,
          takeProfitDecimal: null,
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
          stopLossDecimal: '64000',
          takeProfitDecimal: '62000',
          intentHashHex: 'def',
        ),
        testOrder: true,
      );

      expect(capturedRequest.body, contains('type=TRIGGER_LIMIT'));
      expect(capturedRequest.body, contains('stopPrice=62950'));
      expect(capturedRequest.body, contains('price=63000'));
      final params = Uri.splitQueryString(capturedRequest.body);
      final stopLossRaw = params['stopLoss'];
      final takeProfitRaw = params['takeProfit'];
      expect(stopLossRaw, isNotNull);
      expect(takeProfitRaw, isNotNull);
      final stopLoss = jsonDecode(stopLossRaw!) as Map<String, dynamic>;
      final takeProfit = jsonDecode(takeProfitRaw!) as Map<String, dynamic>;
      expect(stopLoss['type'], 'STOP_MARKET');
      expect(stopLoss['stopPrice'], 64000);
      expect(stopLoss['price'], 64000);
      expect(stopLoss['workingType'], 'MARK_PRICE');
      expect(takeProfit['type'], 'TAKE_PROFIT_MARKET');
      expect(takeProfit['stopPrice'], 62000);
      expect(takeProfit['price'], 62000);
      expect(takeProfit['workingType'], 'MARK_PRICE');
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

    test('reads open orders via signed GET endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"orders":[{"orderId":"111","symbol":"BTC-USDT","side":"SELL","positionSide":"SHORT","type":"TRIGGER_LIMIT","status":"NEW","price":"81900","stopPrice":"81800","origQty":"0.001","executedQty":"0","time":1710000000000}]}}',
          );
        },
      );

      final result = await service.getOpenOrders(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'btc-usdt',
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/openOrders');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.orders, hasLength(1));
      expect(result.orders.first.orderId, '111');
      expect(result.orders.first.priceDecimal, '81900');
      expect(result.orders.first.triggerPriceDecimal, '81800');
    });

    test('reads open orders without symbol filter', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"orders":[{"orderId":"222","symbol":"SOL-USDT","side":"BUY","positionSide":"LONG","type":"TRIGGER_LIMIT","status":"NEW","price":"120.5","stopPrice":"121.0","origQty":"1","executedQty":"0","time":1710000000000}]}}',
          );
        },
      );

      final result = await service.getOpenOrders(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/openOrders');
      expect(capturedRequest.uri.query, isNot(contains('symbol=')));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(result.isSuccess, isTrue);
      expect(result.symbol, 'ALL');
      expect(result.orders, hasLength(1));
      expect(result.orders.first.orderId, '222');
      expect(result.orders.first.symbol, 'SOL-USDT');
    });

    test('cancels order via signed DELETE endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{"orderId":"111"}}',
          );
        },
      );

      final result = await service.cancelOrder(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'BTC-USDT',
        orderId: '111',
      );

      expect(capturedRequest.method, 'DELETE');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/order');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('orderId=111'));
      expect(capturedRequest.uri.query, contains('timestamp=1710000000000'));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(capturedRequest.body, isEmpty);
      expect(result.isSuccess, isTrue);
      expect(result.requestedOrderId, '111');
      expect(result.canceledOrderId, '111');
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

    test('reads perpetual symbols via unsigned contracts endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"contracts":[{"symbol":"BTC-USDT"},{"symbol":"ETH-USDT"},{"symbol":"SOL-USDT"}]}}',
          );
        },
      );

      final result = await service.getPerpetualSymbols();

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/contracts');
      expect(capturedRequest.headers.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
      expect(
        result.symbols,
        <String>['BTC-USDT', 'ETH-USDT', 'SOL-USDT'],
      );
    });

    test('reads perpetual symbols when data payload is list', () async {
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":"0","msg":"ok","data":[{"symbol":"DOGE-USDT"},"XRP-USDT",{"pair":"BNB-USDT"}]}',
          );
        },
      );

      final result = await service.getPerpetualSymbols();

      expect(result.isSuccess, isTrue);
      expect(
        result.symbols,
        <String>['BNB-USDT', 'DOGE-USDT', 'XRP-USDT'],
      );
    });

    test('reads deterministic contract order limits', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","tradeMinQuantity":0.001},{"symbol":"ETH-USDT","tradeMinQuantity":0.01,"tradeMinUSDT":2,"quantityPrecision":2,"pricePrecision":2}]}',
          );
        },
      );

      final result = await service.getPerpetualContractRules(
        symbol: 'eth-usdt',
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/contracts');
      expect(capturedRequest.uri.queryParameters['symbol'], 'ETH-USDT');
      expect(result.isSuccess, isTrue);
      expect(result.rules?.symbol, 'ETH-USDT');
      expect(result.rules?.minimumQuantityDecimal, '0.01');
      expect(result.rules?.minimumNotionalQuoteDecimal, '2');
      expect(result.rules?.quantityPrecision, 2);
      expect(result.rules?.pricePrecision, 2);
    });

    test('reads public depth via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"time":1710000000123,"bids":[["60010","12.5"],["60000","3"]],"asks":[["60020","8.1"],["60030","1"]]}}',
          );
        },
      );

      final result = await service.getPublicDepth(
        symbol: 'btc-usdt',
        limit: 20,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/depth');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('limit=20'));
      expect(capturedRequest.headers.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.bids, hasLength(2));
      expect(result.asks, hasLength(2));
      expect(result.bids.first.priceDecimal, '60010');
      expect(result.asks.first.quantityDecimal, '8.1');
      expect(result.timestampMs, '1710000000123');
    });

    test('reads public trades via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":"0","msg":"ok","data":[{"id":"t1","side":"BUY","price":"60001","qty":"0.5","time":1710000001000},{"id":"t2","side":"sell","price":"60002","qty":"1.0","time":1710000002000}]}',
          );
        },
      );

      final result = await service.getPublicTrades(
        symbol: 'BTC-USDT',
        limit: 2,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/trades');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('limit=2'));
      expect(result.isSuccess, isTrue);
      expect(result.trades, hasLength(2));
      expect(result.trades.first.tradeId, 't1');
      expect(result.trades.first.side, 'buy');
      expect(result.trades.last.side, 'sell');
    });

    test('maps BingX isBuyerMaker to public trade aggressor side', () async {
      final service = BingxFuturesExchangeService(
        requestSender: (request) async => const BingxHttpResponse(
          statusCode: 200,
          body: '''
{"code":0,"msg":"","data":[
  {"time":1710000000002,"isBuyerMaker":true,"price":"63001","qty":"0.2","fillId":"2"},
  {"time":1710000000001,"isBuyerMaker":false,"price":"63000","qty":"0.1","fillId":"1"}
]}''',
        ),
      );

      final result = await service.getPublicTrades(
        symbol: 'BTC-USDT',
        limit: 200,
      );

      expect(result.isSuccess, isTrue);
      expect(result.trades.map((trade) => trade.side), <String>['buy', 'sell']);
      expect(result.trades.map((trade) => trade.tradeId), <String>['1', '2']);
    });

    test('drops public trades with no deterministic aggressor side', () async {
      final service = BingxFuturesExchangeService(
        requestSender: (request) async => const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"","data":[{"time":1710000000000,"price":"63000","qty":"0.1"}]}',
        ),
      );

      final result = await service.getPublicTrades(
        symbol: 'BTC-USDT',
        limit: 200,
      );

      expect(result.isSuccess, isFalse);
      expect(result.trades, isEmpty);
    });

    test('reads premium index via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"symbol":"BTC-USDT","markPrice":"60100.1","indexPrice":"60098.8","lastFundingRate":"0.0001","nextFundingTime":1710003600000,"time":1710000000000}}',
          );
        },
      );

      final result = await service.getPublicPremiumIndex(symbol: 'btc-usdt');

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/premiumIndex');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(result.isSuccess, isTrue);
      expect(result.markPriceDecimal, '60100.1');
      expect(result.indexPriceDecimal, '60098.8');
      expect(result.fundingRateDecimal, '0.0001');
      expect(result.nextFundingTimeMs, '1710003600000');
    });

    test('reads open interest via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"symbol":"BTC-USDT","openInterest":"123456.78","time":1710000009999}}',
          );
        },
      );

      final result = await service.getPublicOpenInterest(symbol: 'BTC-USDT');

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/openInterest');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(result.isSuccess, isTrue);
      expect(result.openInterestDecimal, '123456.78');
      expect(result.timestampMs, '1710000009999');
    });

    test('reads open interest history via unsigned endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"list":[{"openInterest":"1000","time":1710000000000},{"openInterest":"1050","time":1710000300000},{"openInterest":"1100","time":1710000600000}]}}',
          );
        },
      );

      final result = await service.getPublicOpenInterestHistory(
        symbol: 'btc-usdt',
        period: '5m',
        limit: 24,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/quote/openInterest');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('period=5m'));
      expect(capturedRequest.uri.query, contains('limit=24'));
      expect(result.isSuccess, isTrue);
      expect(result.points, hasLength(3));
      expect(result.points.first.openInterestDecimal, '1000');
      expect(result.points.last.openInterestDecimal, '1100');
      expect(result.points.last.timestampMs, '1710000600000');
    });

    test('reads user force orders via signed endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"orders":[{"symbol":"BTC-USDT","side":"BUY","positionSide":"LONG","avgPrice":"60000","origQty":"0.1","time":1710000001000},{"symbol":"BTC-USDT","side":"SELL","positionSide":"SHORT","avgPrice":"62000","origQty":"0.2","time":1710000002000}]}}',
          );
        },
      );

      final result = await service.getUserForceOrders(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
        symbol: 'btc-usdt',
        limit: 50,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/trade/forceOrders');
      expect(capturedRequest.uri.query, contains('symbol=BTC-USDT'));
      expect(capturedRequest.uri.query, contains('limit=50'));
      expect(capturedRequest.uri.query, contains('signature='));
      expect(capturedRequest.headers['X-BX-APIKEY'], 'api-key');
      expect(result.isSuccess, isTrue);
      expect(result.orders, hasLength(2));
      expect(result.orders.first.avgPriceDecimal, '62000');
      expect(result.orders.last.avgPriceDecimal, '60000');
    });

    test('reads user balance via signed endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"balance":{"asset":"USDT","equity":"1000.5","realisedProfit":"-5.25"}}}',
          );
        },
      );

      final result = await service.getUserBalance(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/user/balance');
      expect(capturedRequest.uri.query, contains('signature='));
      expect(capturedRequest.headers['X-BX-APIKEY'], 'api-key');
      expect(result.isSuccess, isTrue);
      expect(result.accountEquityQuoteDecimal, '1000.5');
      expect(result.realizedPnlQuoteDecimal, '-5.25');
    });

    test('reads user positions via signed endpoint', () async {
      late BingxHttpRequest capturedRequest;
      final service = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          capturedRequest = request;
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","positionAmt":"0.1","positionSide":"LONG"},{"symbol":"ETH-USDT","positionAmt":"-1.2","positionSide":"SHORT"}]}',
          );
        },
      );

      final result = await service.getUserPositions(
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'api-key',
          apiSecret: 'api-secret',
        ),
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.uri.path, '/openApi/swap/v2/user/positions');
      expect(capturedRequest.uri.query, contains('signature='));
      expect(capturedRequest.headers['X-BX-APIKEY'], 'api-key');
      expect(result.isSuccess, isTrue);
      expect(result.positions, hasLength(2));
      expect(result.positions.first.symbol, 'BTC-USDT');
      expect(result.positions.last.quantityDecimal, '-1.2');
    });
  });
}
