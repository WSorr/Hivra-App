import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_exchange_risk_input_service.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_risk_history_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('BingxFuturesExchangeRiskInputService', () {
    late Directory tempHome;
    late BingxFuturesRiskHistoryService riskHistory;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-risk-input-');
      riskHistory = BingxFuturesRiskHistoryService(
        readActiveCapsuleRootHex: () => List.filled(64, 'a').join(),
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
    });

    tearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });

    test('reads equity/pnl/positions from exchange responses', () async {
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          if (request.uri.path == '/openApi/swap/v3/user/balance') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"asset":"USDT","equity":"1234.5","realisedProfit":"-12.3"}]}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/positions') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","positionAmt":"0.01"},{"symbol":"ETH-USDT","positionAmt":"0"},{"symbol":"XRP-USDT","positionAmt":"-2"}]}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/income') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"symbol":"BTC-USDT","incomeType":"REALIZED_PNL","income":"-12.3","asset":"USDT","time":1710000000000,"tranId":"tran-1","tradeId":"trade-1"}]}',
            );
          }
          return const BingxHttpResponse(statusCode: 404, body: '{}');
        },
      );
      const service = BingxFuturesExchangeRiskInputService();

      final result = await service.read(
        exchangeService: exchange,
        riskHistoryService: riskHistory,
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        nowUtc: DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );

      expect(result.accountEquityQuoteDecimal, '1234.50000000');
      expect(result.realizedDailyPnlQuoteDecimal, '-12.30000000');
      expect(result.concurrentPositions, 2);
      expect(result.lossStreakCount, 1);
      expect(result.lastLossAtUtc, '2024-03-09T16:00:00.000Z');
      expect(result.isComplete, isTrue);
    });

    test('keeps unavailable exchange inputs absent', () async {
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          if (request.uri.path == '/openApi/swap/v3/user/balance') {
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
        riskHistoryService: riskHistory,
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        nowUtc: DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );

      expect(result.accountEquityQuoteDecimal, isNull);
      expect(result.realizedDailyPnlQuoteDecimal, isNull);
      expect(result.concurrentPositions, isNull);
      expect(result.lossStreakCount, isNull);
      expect(result.isComplete, isFalse);
      expect(result.balanceUnavailableCode, '100001');
      expect(result.balanceUnavailableMessage, 'signature invalid');
      expect(result.positionsUnavailableCode, '500');
      expect(result.positionsUnavailableMessage, 'internal error');
      expect(result.firstUnavailableReason, '100001 signature invalid');
    });

    test('treats non-positive exchange equity as unavailable', () async {
      final exchange = BingxFuturesExchangeService(
        clockMs: () => 1710000000000,
        requestSender: (request) async {
          if (request.uri.path == '/openApi/swap/v3/user/balance') {
            return const BingxHttpResponse(
              statusCode: 200,
              body:
                  '{"code":0,"msg":"ok","data":[{"asset":"USDT","equity":"0"}]}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/positions') {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":[]}',
            );
          }
          if (request.uri.path == '/openApi/swap/v2/user/income') {
            return const BingxHttpResponse(
              statusCode: 200,
              body: '{"code":0,"msg":"ok","data":[]}',
            );
          }
          return const BingxHttpResponse(statusCode: 404, body: '{}');
        },
      );
      const service = BingxFuturesExchangeRiskInputService();

      final result = await service.read(
        exchangeService: exchange,
        riskHistoryService: riskHistory,
        credentials: const BingxFuturesApiCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        nowUtc: DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );

      expect(result.accountEquityQuoteDecimal, isNull);
      expect(result.isComplete, isFalse);
      expect(result.balanceUnavailableCode, 'account_equity_non_positive');
      expect(
        result.firstUnavailableReason,
        'account_equity_non_positive BingX account equity must be positive',
      );
    });
  });
}
