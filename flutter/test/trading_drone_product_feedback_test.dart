import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 8, 20, 10);
  final mandate = BingxFuturesTradingMandate.issue(
    capsuleRootHex: List<String>.filled(32, '11').join(),
    accountBindingHashHex: List<String>.filled(32, '22').join(),
    symbol: 'XRP-USDT',
    testOrder: true,
    issuedAtUtc: issuedAt,
    expiresAtUtc: issuedAt.add(const Duration(hours: 24)),
    maxOrderNotionalQuoteDecimal: '100',
    maxRiskPerTradePercent: 2,
    maxDailyLossPercent: 5,
    maxConcurrentPositions: 3,
    cooldownAfterLossStreak: 2,
    cooldownMinutes: 60,
    maxEffects: 32,
  );

  test('signal scan action remains refresh after results exist', () {
    expect(tradingSignalScanActionLabel(scanning: false), 'Refresh Scan');
    expect(tradingSignalScanActionLabel(scanning: true), 'Scanning');
  });

  test('exact export selection must match active mandate symbol and mode', () {
    final now = issuedAt.add(const Duration(minutes: 1));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'xrp-usdt',
        testOrder: true,
        nowUtc: now,
      ),
      isTrue,
    );
    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'ADA-USDT',
        testOrder: true,
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: false,
        nowUtc: now,
      ),
      isFalse,
    );
  });

  test('expired mandate is fail-closed and receives explicit feedback', () {
    final expiredAt = issuedAt.add(const Duration(hours: 25));

    expect(
      tradingMandateMatchesSelection(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: true,
        nowUtc: expiredAt,
      ),
      isFalse,
    );
    expect(
      tradingMandateSelectionNotice(
        mandate: mandate,
        droneEnabled: true,
        selectedSymbol: 'XRP-USDT',
        testOrder: true,
        nowUtc: expiredAt,
      ),
      'Trading mandate expired. Re-authorize before exact export.',
    );
  });

  test('scan snapshot is explicitly observational and timestamped', () {
    expect(
      tradingSignalSnapshotLabel(DateTime.utc(2026, 8, 20, 10, 39, 15)),
      'Snapshot 2026-08-20T10:39:15.000Z. READY is observational; '
      'Run Intent revalidates current market.',
    );
  });
}
