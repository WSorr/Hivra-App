import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_live_snapshot_builder_service.dart';

void main() {
  group('BingxFuturesLiveSnapshotBuilderService', () {
    test('builds snapshot with OI history and liquidation proxy levels',
        () async {
      final builder = BingxFuturesLiveSnapshotBuilderService(
        clockUtc: () => DateTime.fromMillisecondsSinceEpoch(
          1710000400000,
          isUtc: true,
        ),
      );
      var requestedExtended4hHistory = false;
      final exchange = BingxFuturesExchangeService(
        requestSender: (request) async {
          final path = request.uri.path;
          if (path == '/openApi/swap/v2/quote/price') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"price":"100.5","time":1710000000000}}',
            );
          }
          if (path == '/openApi/swap/v3/quote/klines') {
            if (request.uri.queryParameters['interval'] == '4h' &&
                request.uri.queryParameters['limit'] == '500') {
              requestedExtended4hHistory = true;
            }
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[[1710000000000,"100","102","99","101"],[1710000300000,"101","103","100","102"]]}',
            );
          }
          if (path == '/openApi/swap/v2/quote/trades') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"id":"t1","side":"BUY","price":"100.4","qty":"4","time":1710000001000},{"id":"t2","side":"SELL","price":"100.6","qty":"2","time":1710000002000}]}',
            );
          }
          if (path == '/openApi/swap/v2/quote/premiumIndex') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"markPrice":"100.5","indexPrice":"100.4","lastFundingRate":"0.0001","nextFundingTime":1710003600000,"time":1710000000000}}',
            );
          }
          if (path == '/openApi/swap/v2/quote/openInterest') {
            if (request.uri.query.contains('period=5m')) {
              return const BingxHttpResponse(
                statusCode: 200,
                body:
                    '{"code":0,"msg":"ok","data":{"list":[{"openInterest":"1000","time":1710000000000},{"openInterest":"1030","time":1710000300000},{"openInterest":"1065","time":1710000600000}]}}',
              );
            }
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"openInterest":"1065","time":1710000600000}}',
            );
          }
          if (path == '/openApi/swap/v2/quote/depth') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"time":1710000399000,"bids":[["100.1","45"],["100.0","5"]],"asks":[["100.8","51"],["100.9","6"]]}}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 404,
            body: '{"code":404,"msg":"not found"}',
          );
        },
      );

      final result = await builder.fetchAndBuild(
        exchange: exchange,
        symbol: 'BTC-USDT',
      );

      expect(result.isSuccess, isTrue);
      final snapshot = result.snapshotInput!;
      expect(snapshot.openInterest.length, 3);
      expect(
        snapshot.liquidityLevels
            .any((item) => item.kind == 'liquidation_proxy'),
        isTrue,
      );
      expect(requestedExtended4hHistory, isTrue);
      final fiveMinuteCandles = snapshot.candles
          .where((item) => item.timeframe == '5m')
          .toList(growable: false);
      expect(fiveMinuteCandles.map((item) => item.isClosed), <bool>[
        true,
        false,
      ]);
      expect(
        snapshot.liquidityLevels
            .singleWhere(
              (item) => item.kind == 'internal' && item.side == 'sellside',
            )
            .priceDecimal,
        '102',
      );
    });

    test('does not treat account force-orders as market liquidation feed',
        () async {
      final builder = BingxFuturesLiveSnapshotBuilderService(
        clockUtc: () => DateTime.fromMillisecondsSinceEpoch(
          1710000400000,
          isUtc: true,
        ),
      );
      var requestedAccountForceOrders = false;
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710009999000,
        requestSender: (request) async {
          final path = request.uri.path;
          if (path == '/openApi/swap/v2/quote/price') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"price":"100.5","time":1710000000000}}',
            );
          }
          if (path == '/openApi/swap/v3/quote/klines') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[[1710000000000,"100","102","99","101"],[1710000300000,"101","103","100","102"]]}',
            );
          }
          if (path == '/openApi/swap/v2/quote/trades') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"id":"t1","side":"BUY","price":"100.4","qty":"4","time":1710000001000},{"id":"t2","side":"SELL","price":"100.6","qty":"2","time":1710000002000}]}',
            );
          }
          if (path == '/openApi/swap/v2/quote/premiumIndex') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"markPrice":"100.5","indexPrice":"100.4","lastFundingRate":"0.0001","nextFundingTime":1710003600000,"time":1710000000000}}',
            );
          }
          if (path == '/openApi/swap/v2/quote/openInterest') {
            if (request.uri.query.contains('period=5m')) {
              return const BingxHttpResponse(
                statusCode: 200,
                body:
                    '{"code":0,"msg":"ok","data":{"list":[{"openInterest":"1000","time":1710000000000},{"openInterest":"1030","time":1710000300000},{"openInterest":"1065","time":1710000600000}]}}',
              );
            }
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"openInterest":"1065","time":1710000600000}}',
            );
          }
          if (path == '/openApi/swap/v2/quote/depth') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"time":1710000399000,"bids":[["100.1","45"],["100.0","5"]],"asks":[["100.8","51"],["100.9","6"]]}}',
            );
          }
          if (path == '/openApi/swap/v2/trade/forceOrders') {
            requestedAccountForceOrders = true;
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"orders":[{"symbol":"BTC-USDT","side":"SELL","positionSide":"SHORT","avgPrice":"101.8","time":1710000700000},{"symbol":"BTC-USDT","side":"BUY","positionSide":"LONG","avgPrice":"99.2","time":1710000710000}]}}',
            );
          }
          return const BingxHttpResponse(
            statusCode: 404,
            body: '{"code":404,"msg":"not found"}',
          );
        },
      );

      final result = await builder.fetchAndBuild(
        exchange: exchange,
        symbol: 'BTC-USDT',
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'a',
          apiSecret: 'b',
        ),
      );

      expect(result.isSuccess, isTrue);
      final snapshot = result.snapshotInput!;
      final liquidationFeed = snapshot.liquidityLevels
          .where((item) => item.kind == 'liquidation')
          .toList(growable: false);
      final proxy = snapshot.liquidityLevels
          .where((item) => item.kind == 'liquidation_proxy')
          .toList(growable: false);
      expect(requestedAccountForceOrders, isFalse);
      expect(liquidationFeed, isEmpty);
      expect(proxy, isNotEmpty);
      expect(proxy.any((item) => item.priceDecimal == '101.8'), isFalse);
      expect(proxy.any((item) => item.priceDecimal == '99.2'), isFalse);
    });

    test('clusters depth deterministically and bounds each side', () async {
      final builder = BingxFuturesLiveSnapshotBuilderService(
        clockUtc:
            () =>
                DateTime.fromMillisecondsSinceEpoch(1710000400000, isUtc: true),
      );
      const orderedDepth =
          '{"code":0,"msg":"ok","data":{"time":1710000399000,"bids":[["100.4","12"],["100.3","9"],["100.2","11"],["100.1","8"],["100.0","13"],["99.9","7"]],"asks":[["100.6","7"],["100.7","13"],["100.8","8"],["100.9","11"],["101.0","9"],["101.1","12"]]}}';
      const permutedDepth =
          '{"code":0,"msg":"ok","data":{"time":1710000399000,"bids":[["99.9","7"],["100.1","8"],["100.3","9"],["100.0","13"],["100.4","12"],["100.2","11"]],"asks":[["101.1","12"],["100.9","11"],["100.7","13"],["101.0","9"],["100.6","7"],["100.8","8"]]}}';

      final ordered = await builder.fetchAndBuild(
        exchange: _exchangeForDepth(orderedDepth),
        symbol: 'BTC-USDT',
      );
      final permuted = await builder.fetchAndBuild(
        exchange: _exchangeForDepth(permutedDepth),
        symbol: 'BTC-USDT',
      );

      expect(ordered.isSuccess, isTrue);
      expect(permuted.isSuccess, isTrue);
      List<String> proxies(BingxFuturesLiveSnapshotBuildResult result) => result
          .snapshotInput!
          .liquidityLevels
          .where((level) => level.kind == 'liquidation_proxy')
          .map((level) => '${level.side}|${level.priceDecimal}')
          .toList(growable: false);
      expect(proxies(permuted), proxies(ordered));
      expect(
        ordered.snapshotInput!.liquidityLevels
            .where(
              (level) =>
                  level.kind == 'liquidation_proxy' && level.side == 'buyside',
            )
            .length,
        lessThanOrEqualTo(3),
      );
      expect(
        ordered.snapshotInput!.liquidityLevels
            .where(
              (level) =>
                  level.kind == 'liquidation_proxy' && level.side == 'sellside',
            )
            .length,
        lessThanOrEqualTo(3),
      );
    });

    test('drops stale and crossed depth from liquidation proxies', () async {
      final builder = BingxFuturesLiveSnapshotBuilderService(
        clockUtc:
            () =>
                DateTime.fromMillisecondsSinceEpoch(1710000400000, isUtc: true),
      );
      const staleDepth =
          '{"code":0,"msg":"ok","data":{"time":1710000000000,"bids":[["100.1","45"]],"asks":[["100.8","51"]]}}';
      const crossedDepth =
          '{"code":0,"msg":"ok","data":{"time":1710000399000,"bids":[["100.8","45"]],"asks":[["100.1","51"]]}}';

      for (final depth in <String>[staleDepth, crossedDepth]) {
        final result = await builder.fetchAndBuild(
          exchange: _exchangeForDepth(depth),
          symbol: 'BTC-USDT',
        );
        expect(result.isSuccess, isTrue);
        expect(
          result.snapshotInput!.liquidityLevels.where(
            (level) => level.kind == 'liquidation_proxy',
          ),
          isEmpty,
        );
      }
    });
  });
}

BingxFuturesExchangeService _exchangeForDepth(String depthBody) {
  return BingxFuturesExchangeService(
    requestSender: (request) async {
      final path = request.uri.path;
      if (path == '/openApi/swap/v2/quote/price') {
        return const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"ok","data":{"price":"100.5","time":1710000399000}}',
        );
      }
      if (path == '/openApi/swap/v3/quote/klines') {
        return const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"ok","data":[[1710000000000,"100","102","99","101"],[1710000300000,"101","103","100","102"]]}',
        );
      }
      if (path == '/openApi/swap/v2/quote/trades') {
        return const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"ok","data":[{"id":"t1","side":"BUY","price":"100.4","qty":"4","time":1710000397000},{"id":"t2","side":"SELL","price":"100.6","qty":"2","time":1710000398000}]}',
        );
      }
      if (path == '/openApi/swap/v2/quote/premiumIndex') {
        return const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"ok","data":{"markPrice":"100.5","indexPrice":"100.4","lastFundingRate":"0.0001","nextFundingTime":1710003600000,"time":1710000399000}}',
        );
      }
      if (path == '/openApi/swap/v2/quote/openInterest') {
        if (request.uri.query.contains('period=5m')) {
          return const BingxHttpResponse(
            statusCode: 200,
            body:
                '{"code":0,"msg":"ok","data":{"list":[{"openInterest":"1000","time":1710000000000},{"openInterest":"1065","time":1710000300000}]}}',
          );
        }
        return const BingxHttpResponse(
          statusCode: 200,
          body:
              '{"code":0,"msg":"ok","data":{"openInterest":"1065","time":1710000300000}}',
        );
      }
      if (path == '/openApi/swap/v2/quote/depth') {
        return BingxHttpResponse(statusCode: 200, body: depthBody);
      }
      return const BingxHttpResponse(
        statusCode: 404,
        body: '{"code":404,"msg":"not found"}',
      );
    },
  );
}
