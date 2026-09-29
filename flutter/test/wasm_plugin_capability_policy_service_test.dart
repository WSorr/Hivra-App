import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/wasm_plugin_capability_policy_service.dart';

void main() {
  const service = WasmPluginCapabilityPolicyService();

  test('normalizes known capabilities and removes duplicates', () {
    final normalized = service.normalizeAndValidate(<String>[
      'consensus_guard.read',
      'content.draft.prepare',
      'content.engagement.plan',
      'content.feed.plan',
      'content.reply.delegate',
      'content.reply.prepare',
      'content.feed.plan',
      'content.draft.prepare',
      'content.draft.prepare',
    ]);

    expect(normalized, <String>[
      'consensus_guard.read',
      'content.draft.prepare',
      'content.engagement.plan',
      'content.feed.plan',
      'content.reply.delegate',
      'content.reply.prepare',
    ]);
  });

  test('rejects unsupported capability', () {
    expect(
      () => service.normalizeAndValidate(<String>['transport.send.raw']),
      throwsA(isA<FormatException>()),
    );
  });
}
