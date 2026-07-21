import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/bingx_futures_exchange_models.dart';
import 'package:hivra_app/services/bingx_futures_volume_growth_filter_service.dart';

void main() {
  const service = BingxFuturesVolumeGrowthFilterService();
  const interval =
      BingxFuturesVolumeGrowthFilterService.fiveMinuteCandleDurationMs;

  test('accepts strictly rising volume on three closed candles', () {
    expect(
      service.hasStrictlyRisingClosedVolume(
        klines: <BingxFuturesPublicKline>[
          _kline(2 * interval, '20'),
          _kline(0, '10'),
          _kline(interval, '15'),
        ],
        observedAtMs: 3 * interval,
      ),
      isTrue,
    );
  });

  test('ignores a still-forming candle even when its volume spikes', () {
    expect(
      service.hasStrictlyRisingClosedVolume(
        klines: <BingxFuturesPublicKline>[
          _kline(0, '30'),
          _kline(interval, '20'),
          _kline(2 * interval, '10'),
          _kline(3 * interval, '1000'),
        ],
        observedAtMs: 3 * interval + 1,
      ),
      isFalse,
    );
  });

  test('rejects flat or malformed closed volume', () {
    expect(
      service.hasStrictlyRisingClosedVolume(
        klines: <BingxFuturesPublicKline>[
          _kline(0, '10'),
          _kline(interval, '10'),
          _kline(2 * interval, 'bad'),
        ],
        observedAtMs: 3 * interval,
      ),
      isFalse,
    );
  });
}

BingxFuturesPublicKline _kline(int openTimeMs, String volume) {
  return BingxFuturesPublicKline(
    openTimeMs: openTimeMs,
    openDecimal: '1',
    highDecimal: '1',
    lowDecimal: '1',
    closeDecimal: '1',
    volumeQuoteDecimal: volume,
  );
}
