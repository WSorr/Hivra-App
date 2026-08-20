import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_public_session_accumulator.dart';

void main() {
  late DateTime nowUtc;
  late BingxFuturesPublicSessionAccumulator accumulator;

  setUp(() {
    nowUtc = DateTime.utc(2026, 8, 19, 23, 59);
    accumulator = BingxFuturesPublicSessionAccumulator(
      symbol: 'BTC-USDT',
      clockUtc: () => nowUtc,
    );
  });

  test('coverage becomes complete only for buckets observed after connect', () {
    expect(accumulator.snapshot(), everyElement(_isIncomplete));

    accumulator.beginConnection();
    nowUtc = DateTime.utc(2026, 8, 20, 0, 1);
    accumulator.acceptDecodedTradeMessage(
      _trade(nowUtc, price: '100', quantity: '2', buyerIsMaker: false),
    );
    nowUtc = DateTime.utc(2026, 8, 20, 8, 1);
    accumulator.acceptDecodedTradeMessage(
      _trade(nowUtc, price: '110', quantity: '1', buyerIsMaker: true),
    );
    nowUtc = DateTime.utc(2026, 8, 20, 16, 1);
    accumulator.acceptDecodedTradeMessage(
      _trade(nowUtc, price: '120', quantity: '3', buyerIsMaker: false),
    );

    final sessions = accumulator.snapshot();
    expect(sessions, everyElement(_isComplete));
    expect(sessions.map((item) => item.volumeDecimal), <String>[
      '200.00000000',
      '110.00000000',
      '360.00000000',
    ]);
    expect(sessions.map((item) => item.deltaDecimal), <String>[
      '200.00000000',
      '-110.00000000',
      '360.00000000',
    ]);
  });

  test('stale heartbeat and disconnect invalidate all coverage', () {
    accumulator.beginConnection();
    nowUtc = DateTime.utc(2026, 8, 20, 0, 1);
    accumulator.acceptDecodedTradeMessage(_trade(nowUtc));

    nowUtc = nowUtc.add(
      BingxFuturesPublicSessionAccumulator.maxMessageSilence +
          const Duration(seconds: 1),
    );
    expect(accumulator.snapshot(), everyElement(_isIncomplete));

    accumulator.markDisconnected();
    expect(accumulator.snapshot(), everyElement(_isIncomplete));
    accumulator.beginConnection();
    expect(
      accumulator.snapshot().map((item) => item.volumeDecimal),
      everyElement('0.00000000'),
    );
  });

  test('malformed or cross-channel trade evidence is rejected', () {
    accumulator.beginConnection();
    nowUtc = DateTime.utc(2026, 8, 20, 0, 1);
    final valid = jsonDecode(_trade(nowUtc)) as Map<String, dynamic>;

    final mutations = <Object>[
      'not-json',
      <String, dynamic>{...valid, 'dataType': 'ETH-USDT@trade'},
      <String, dynamic>{
        ...valid,
        'data': <String, dynamic>{
          ...(valid['data'] as Map<String, dynamic>),
          's': 'ETH-USDT',
        },
      },
      <String, dynamic>{
        ...valid,
        'data': <String, dynamic>{
          ...(valid['data'] as Map<String, dynamic>),
          'T':
              nowUtc
                  .subtract(const Duration(minutes: 6))
                  .millisecondsSinceEpoch,
        },
      },
      <String, dynamic>{
        ...valid,
        'data': <String, dynamic>{
          ...(valid['data'] as Map<String, dynamic>),
          'p': '0',
        },
      },
      <String, dynamic>{
        ...valid,
        'data': <String, dynamic>{
          ...(valid['data'] as Map<String, dynamic>),
          'q': '-1',
        },
      },
      <String, dynamic>{
        ...valid,
        'data': <String, dynamic>{
          ...(valid['data'] as Map<String, dynamic>),
          'm': 'false',
        },
      },
    ];

    for (final mutation in mutations) {
      expect(
        () => accumulator.acceptDecodedTradeMessage(
          mutation is String ? mutation : jsonEncode(mutation),
        ),
        throwsFormatException,
      );
    }
  });

  test('bounded trade batch is validated before aggregate mutation', () {
    accumulator.beginConnection();
    nowUtc = DateTime.utc(2026, 8, 20, 0, 1);
    final valid =
        (jsonDecode(_trade(nowUtc)) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final invalid = <String, dynamic>{...valid, 's': 'ETH-USDT'};

    expect(
      () => accumulator.acceptDecodedTradeMessage(
        jsonEncode(<String, Object>{
          'dataType': 'BTC-USDT@trade',
          'data': <Object>[valid, invalid],
        }),
      ),
      throwsFormatException,
    );
    expect(
      accumulator.snapshot().map((item) => item.volumeDecimal),
      everyElement('0.00000000'),
    );
    expect(
      () => accumulator.acceptDecodedTradeMessage(
        jsonEncode(<String, Object>{
          'dataType': 'BTC-USDT@trade',
          'data': List<Object>.filled(
            BingxFuturesPublicSessionAccumulator.maxTradesPerMessage + 1,
            valid,
          ),
        }),
      ),
      throwsFormatException,
    );
  });
}

final _isComplete = isA<dynamic>()
    .having((item) => item.evidenceSource, 'source', 'public_trade_stream')
    .having((item) => item.coverageComplete, 'coverage', isTrue);

final _isIncomplete = isA<dynamic>()
    .having((item) => item.evidenceSource, 'source', 'public_trade_stream')
    .having((item) => item.coverageComplete, 'coverage', isFalse);

String _trade(
  DateTime timestampUtc, {
  String price = '100',
  String quantity = '1',
  bool buyerIsMaker = false,
}) => jsonEncode(<String, Object>{
  'dataType': 'BTC-USDT@trade',
  'data': <String, Object>{
    'T': timestampUtc.millisecondsSinceEpoch,
    's': 'BTC-USDT',
    'p': price,
    'q': quantity,
    'm': buyerIsMaker,
  },
});
