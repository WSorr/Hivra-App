import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/wasm_plugin_capability_policy_service.dart';

void main() {
  const service = WasmPluginCapabilityPolicyService();

  test('normalizes known capabilities and removes duplicates', () {
    final normalized = service.normalizeAndValidate(<String>[
      'consensus_guard.read',
      'exchange.read.bingx.market',
      'exchange.trade.bingx.spot',
      'exchange.trade.bingx.futures',
      'exchange.trade.bingx.futures',
    ]);

    expect(
      normalized,
      <String>[
        'consensus_guard.read',
        'exchange.read.bingx.market',
        'exchange.trade.bingx.futures',
        'exchange.trade.bingx.spot',
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
