import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
  test('remote session reserves one bounded provisioning window', () {
    expect(
      tradingRemoteSessionFirstCycleStart(DateTime.utc(2026, 8, 25, 12, 1, 1)),
      DateTime.utc(2026, 8, 25, 12, 20),
    );
    expect(
      tradingRemoteSessionFirstCycleStart(DateTime.utc(2026, 8, 25, 12, 5)),
      DateTime.utc(2026, 8, 25, 12, 20),
    );
    expect(
      tradingRemoteSessionProvisioningLeadTime,
      const Duration(minutes: 15),
    );
    expect(tradingRemoteSessionIntervalSeconds, 300);
  });

  test('prepared VPS session command is exact and bounded', () {
    const runner =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(
      tradingPreparedSessionApplyCommand(
        runnerKeyId: runner,
        mandateFileName: 'trading-remote-session-deadbeef.json',
      ),
      'sudo ./public_shadow_runner_artifact.sh '
      '--apply-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runner '
      "--mandate-artifact '/path/to/trading-remote-session-deadbeef.json'",
    );
    expect(
      tradingPreparedSessionApplyCommand(
        runnerKeyId: runner,
        mandateFileName: '../foreign.json',
      ),
      contains("--mandate-artifact '/path/to/signed-session.json'"),
    );
    expect(
      tradingPreparedSessionActivationCommand(runnerKeyId: runner),
      'sudo ./public_shadow_runner_artifact.sh '
      '--activate-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runner',
    );
    expect(
      tradingPreparedSessionRunCommand(runnerKeyId: runner),
      'sudo ./public_shadow_runner_artifact.sh '
      '--run-prepared-session /path/to/runner-bundle '
      '--expected-runner-key-id $runner',
    );
  });

  test('prepared intent outcome does not claim provider execution', () async {
    final events = <String>[];

    final outcome = await runTradingIntentWithTerminalEvidence(
      pipeline: () async => preparedTradingIntentTerminalOutcome,
      log: (source, message) async => events.add('$source $message'),
    );

    expect(outcome, 'intent:prepared');
    expect(outcome, isNot(contains('executed')));
    expect(
      events.singleWhere((event) => event.startsWith('bingx.intent.finally ')),
      contains('outcome=intent:prepared'),
    );
  });

  test('early guard records one terminal outcome in finally', () async {
    final events = <String>[];

    final outcome = await runTradingIntentWithTerminalEvidence(
      pipeline: () async => 'blocked:drone_paused',
      log: (source, message) async => events.add('$source $message'),
    );

    expect(outcome, 'blocked:drone_paused');
    expect(
      events.where((event) => event.startsWith('bingx.intent.tap ')),
      hasLength(1),
    );
    expect(
      events.where((event) => event.startsWith('bingx.intent.finally ')),
      hasLength(1),
    );
    expect(
      events.singleWhere((event) => event.startsWith('bingx.intent.finally ')),
      contains('outcome=blocked:drone_paused'),
    );
  });

  test('pipeline exception records error and terminal finally', () async {
    final events = <String>[];

    await expectLater(
      runTradingIntentWithTerminalEvidence(
        pipeline: () async => throw StateError('boom'),
        log: (source, message) async => events.add('$source $message'),
      ),
      throwsStateError,
    );

    expect(
      events.where((event) => event.startsWith('bingx.intent.error ')),
      hasLength(1),
    );
    expect(
      events.singleWhere((event) => event.startsWith('bingx.intent.finally ')),
      contains('outcome=error:unhandled'),
    );
    expect(
      events.where((event) => event.startsWith('bingx.intent.finally ')),
      hasLength(1),
    );
  });
}
