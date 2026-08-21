import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
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
