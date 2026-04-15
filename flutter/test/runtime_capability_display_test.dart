import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/utils/runtime_capability_display.dart';

void main() {
  test('returns empty summary for empty capabilities', () {
    final summary = summarizeRuntimeCapabilitiesForDisplay(
      const <String>[],
    );

    expect(summary.visibleCapabilities, isEmpty);
    expect(summary.hiddenCount, 0);
  });

  test('shows all capabilities when under limit', () {
    final summary = summarizeRuntimeCapabilitiesForDisplay(
      const <String>[
        'consensus_guard.read',
        'oracle.read.mock_weather',
      ],
      visibleLimit: 3,
    );

    expect(
      summary.visibleCapabilities,
      const <String>[
        'consensus_guard.read',
        'oracle.read.mock_weather',
      ],
    );
    expect(summary.hiddenCount, 0);
  });

  test('caps visible capabilities and reports hidden count', () {
    final summary = summarizeRuntimeCapabilitiesForDisplay(
      const <String>[
        'consensus_guard.read',
        'oracle.read.mock_weather',
        'exchange.trade.bingx.spot',
        'chat.send.capsule',
      ],
      visibleLimit: 3,
    );

    expect(
      summary.visibleCapabilities,
      const <String>[
        'consensus_guard.read',
        'oracle.read.mock_weather',
        'exchange.trade.bingx.spot',
      ],
    );
    expect(summary.hiddenCount, 1);
  });

  test('negative limit is treated as zero', () {
    final summary = summarizeRuntimeCapabilitiesForDisplay(
      const <String>[
        'consensus_guard.read',
        'oracle.read.mock_weather',
      ],
      visibleLimit: -5,
    );

    expect(summary.visibleCapabilities, isEmpty);
    expect(summary.hiddenCount, 2);
  });
}
