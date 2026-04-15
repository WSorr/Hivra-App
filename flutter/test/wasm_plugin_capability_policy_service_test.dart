import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/wasm_plugin_capability_policy_service.dart';

void main() {
  const service = WasmPluginCapabilityPolicyService();

  test('normalizes known capabilities and removes duplicates', () {
    final normalized = service.normalizeAndValidate(<String>[
      'oracle.read.mock_weather',
      'consensus_guard.read',
      'exchange.trade.bingx.spot',
      'oracle.read.mock_weather',
    ]);

    expect(
      normalized,
      <String>[
        'consensus_guard.read',
        'exchange.trade.bingx.spot',
        'oracle.read.mock_weather',
      ],
    );
  });

  test('rejects unsupported capability', () {
    expect(
      () => service.normalizeAndValidate(<String>['transport.send.raw']),
      throwsA(isA<FormatException>()),
    );
  });
}
