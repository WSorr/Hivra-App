import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/models/bingx_futures_risk_models.dart';
import 'package:hivra_app/services/bingx_futures_exchange_service.dart';
import 'package:hivra_app/services/bingx_futures_risk_history_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  group('BingxFuturesRiskHistoryService', () {
    late Directory tempHome;
    late BingxFuturesRiskHistoryService service;
    final nowUtc = DateTime.utc(2026, 8, 2, 12);

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-risk-history-');
      service = BingxFuturesRiskHistoryService(
        readActiveCapsuleRootHex: () => List.filled(64, 'a').join(),
        fileStore: CapsuleFileStore(
          dirs: UserVisibleDataDirectoryService(homeOverride: tempHome.path),
        ),
      );
    });

    tearDown(() async {
      if (await tempHome.exists()) await tempHome.delete(recursive: true);
    });

    test('persists deduplicated UTC daily PnL and loss streak', () async {
      final rows = <Map<String, dynamic>>[
        _row('old-win', 5, DateTime.utc(2026, 8, 1, 20)),
        _row('loss-1', -2, DateTime.utc(2026, 8, 2, 10)),
        _row('loss-1', -2, DateTime.utc(2026, 8, 2, 10)),
        _row('zero', 0, DateTime.utc(2026, 8, 2, 10, 30)),
        _row('loss-2', -3, DateTime.utc(2026, 8, 2, 11)),
      ];
      final exchange = _exchange(
        rows: rows,
        clockMs: nowUtc.millisecondsSinceEpoch,
      );

      final projection = await service.refresh(
        exchangeService: exchange,
        credentials: _credentials,
        nowUtc: nowUtc,
      );

      expect(projection.isComplete, isTrue);
      expect(projection.realizedDailyPnlQuoteDecimal, '-5.00000000');
      expect(projection.lossStreakCount, 2);
      expect(projection.lastLossAtUtc, '2026-08-02T11:00:00.000Z');
      expect(projection.recordCount, 4);
      final persisted = await service.load();
      expect(persisted, isNotNull);
      expect(persisted!.records, hasLength(4));
      expect(persisted.records.map((record) => record.transactionId), <String>[
        'old-win',
        'loss-1',
        'zero',
        'loss-2',
      ]);
    });

    test('latest win resets streak but retains real last-loss time', () {
      final snapshot = _snapshot(<Map<String, dynamic>>[
        _row('loss', -2, DateTime.utc(2026, 8, 2, 9)),
        _row('win', 3, DateTime.utc(2026, 8, 2, 10)),
      ]);

      final projection = service.project(snapshot: snapshot, nowUtc: nowUtc);

      expect(projection.lossStreakCount, 0);
      expect(projection.lastLossAtUtc, '2026-08-02T09:00:00.000Z');
      expect(projection.realizedDailyPnlQuoteDecimal, '1.00000000');
    });

    test('fails closed when the exchange result reaches its limit', () async {
      final rows = List<Map<String, dynamic>>.generate(
        1000,
        (index) => _row(
          'loss-$index',
          -0.01,
          nowUtc.subtract(Duration(minutes: index)),
        ),
      );

      final projection = await service.refresh(
        exchangeService: _exchange(
          rows: rows,
          clockMs: nowUtc.millisecondsSinceEpoch,
        ),
        credentials: _credentials,
        nowUtc: nowUtc,
      );

      expect(projection.isComplete, isFalse);
      expect(projection.unavailableCode, 'income_history_truncated');
      expect(projection.recordCount, 1000);
      expect(await service.load(), isNull);
    });

    test(
      'fails closed on conflicting records with the same stable id',
      () async {
        final projection = await service.refresh(
          exchangeService: _exchange(
            rows: <Map<String, dynamic>>[
              _row('same', -1, DateTime.utc(2026, 8, 2, 10)),
              _row('same', -2, DateTime.utc(2026, 8, 2, 10)),
            ],
            clockMs: nowUtc.millisecondsSinceEpoch,
          ),
          credentials: _credentials,
          nowUtc: nowUtc,
        );

        expect(projection.isComplete, isFalse);
        expect(projection.unavailableCode, 'income_history_invalid');
        expect(
          projection.unavailableMessage,
          'Conflicting realized PnL record id',
        );
        expect(await service.load(), isNull);
      },
    );

    test('fails closed when any exchange row is malformed', () async {
      final projection = await service.refresh(
        exchangeService: _exchange(
          rows: <Map<String, dynamic>>[
            _row('valid', -1, DateTime.utc(2026, 8, 2, 10)),
            <String, dynamic>{'income': '-2'},
          ],
          clockMs: nowUtc.millisecondsSinceEpoch,
        ),
        credentials: _credentials,
        nowUtc: nowUtc,
      );

      expect(projection.isComplete, isFalse);
      expect(projection.unavailableCode, 'income_history_invalid');
      expect(projection.recordCount, 1);
      expect(await service.load(), isNull);
    });
  });
}

const _credentials = BingxFuturesApiCredentials(
  apiKey: 'key',
  apiSecret: 'secret',
);

BingxFuturesExchangeService _exchange({
  required List<Map<String, dynamic>> rows,
  required int clockMs,
}) {
  return BingxFuturesExchangeService(
    clockMs: () => clockMs,
    requestSender: (request) async {
      expect(request.uri.path, '/openApi/swap/v2/user/income');
      expect(request.uri.queryParameters['incomeType'], 'REALIZED_PNL');
      expect(request.uri.queryParameters['limit'], '1000');
      return BingxHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, dynamic>{
          'code': 0,
          'msg': 'ok',
          'data': rows,
        }),
      );
    },
  );
}

Map<String, dynamic> _row(String id, num income, DateTime time) {
  return <String, dynamic>{
    'symbol': 'BTC-USDT',
    'incomeType': 'REALIZED_PNL',
    'income': income.toString(),
    'asset': 'USDT',
    'time': time.millisecondsSinceEpoch,
    'tranId': id,
    'tradeId': 'trade-$id',
  };
}

BingxFuturesRiskHistorySnapshot _snapshot(List<Map<String, dynamic>> rows) {
  final serviceRows =
      rows.map((row) {
        final id = row['tranId']!.toString();
        return BingxFuturesRealizedPnlRecord(
          recordId: id,
          symbol: row['symbol']!.toString(),
          incomeQuoteDecimal: double.parse(
            row['income']!.toString(),
          ).toStringAsFixed(8),
          timestampMs: row['time']! as int,
          transactionId: id,
          tradeId: row['tradeId']!.toString(),
        );
      }).toList();
  return BingxFuturesRiskHistorySnapshot(
    records: serviceRows,
    refreshedAtUtc: '2026-08-02T12:00:00.000Z',
  );
}
