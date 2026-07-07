import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_exchange_risk_input_service.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';

void main() {
  group('BingxFuturesExchangeRiskInputService', () {
    test('reads equity/pnl/positions from exchange responses', () async {
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          if (request.uri.path == '/openApi/swap/v2/user/balance') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":{"balance":{"asset":"USDT","equity":"1234.5","realisedProfit":"-12.3"}}}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/positions') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","positionAmt":"0.01"},{"symbol":"ETH-USDT","positionAmt":"0"},{"symbol":"XRP-USDT","positionAmt":"-2"}]}',
            );
          }
          return const BingxHttpResponse(statusCode: 404, body: '{}');
        },
      );
      const service = BingxFuturesExchangeRiskInputService();

      final result = await service.read(
        exchangeService: exchange,
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      );

      expect(result.accountEquityQuoteDecimal, '1234.50000000');
      expect(result.realizedDailyPnlQuoteDecimal, '-12.30000000');
      expect(result.concurrentPositions, 2);
      expect(result.usedBalanceFallback, isFalse);
      expect(result.usedPnlFallback, isFalse);
      expect(result.usedPositionsFallback, isFalse);
    });

    test('falls back deterministically on exchange failure', () async {
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          if (request.uri.path == '/openApi/swap/v2/user/balance') {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":100001,"msg":"signature invalid","data":{}}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/positions') {
            return const BingxHttpResponse(
              statusCode: 500,
              body: '{"code":500,"msg":"internal error"}',
            );
          }
          return const BingxHttpResponse(statusCode: 404, body: '{}');
        },
      );
      const service = BingxFuturesExchangeRiskInputService();

      final result = await service.read(
        exchangeService: exchange,
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        fallbackEquityQuote: 250,
      );

      expect(result.accountEquityQuoteDecimal, '250.00000000');
      expect(result.realizedDailyPnlQuoteDecimal, '0.00000000');
      expect(result.concurrentPositions, 0);
      expect(result.usedBalanceFallback, isTrue);
      expect(result.usedPnlFallback, isTrue);
      expect(result.usedPositionsFallback, isTrue);
    });
  });
}
