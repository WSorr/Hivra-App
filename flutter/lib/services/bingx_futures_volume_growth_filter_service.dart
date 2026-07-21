import '../models/bingx_futures_exchange_models.dart';

class BingxFuturesVolumeGrowthFilterService {
  static const int fiveMinuteCandleDurationMs = 5 * 60 * 1000;

  const BingxFuturesVolumeGrowthFilterService();

  bool hasStrictlyRisingClosedVolume({
    required List<BingxFuturesPublicKline> klines,
    required int observedAtMs,
    int candleDurationMs = fiveMinuteCandleDurationMs,
  }) {
    final closed = klines
        .where((kline) => kline.openTimeMs + candleDurationMs <= observedAtMs)
        .toList(growable: false)
      ..sort((a, b) => a.openTimeMs.compareTo(b.openTimeMs));
    if (closed.length < 3) return false;

    final recent = closed.sublist(closed.length - 3);
    final volumes = recent
        .map(
          (kline) => double.tryParse(
            kline.volumeQuoteDecimal ?? kline.volumeBaseDecimal ?? '',
          ),
        )
        .toList(growable: false);
    if (volumes.any((volume) => volume == null || !volume.isFinite)) {
      return false;
    }

    return volumes[0]! > 0 &&
        volumes[0]! < volumes[1]! &&
        volumes[1]! < volumes[2]!;
  }
}
