import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:hivra_app/screens/main_screen.dart';

void main() {
  test('Relationships exposes only its canonical full refresh action', () {
    expect(showGlobalHeaderRefreshForTab(0), isTrue);
    expect(showGlobalHeaderRefreshForTab(1), isTrue);
    expect(showGlobalHeaderRefreshForTab(2), isFalse);
    expect(showGlobalHeaderRefreshForTab(3), isTrue);
    expect(showGlobalHeaderRefreshForTab(4), isTrue);
  });

  test('passive receive stays active while a desktop window is inactive', () {
    expect(shouldPausePassiveReceive(AppLifecycleState.inactive), isFalse);
    expect(shouldPausePassiveReceive(AppLifecycleState.paused), isTrue);
    expect(shouldPausePassiveReceive(AppLifecycleState.detached), isTrue);
  });

  testWidgets('compact Capsule header keeps Chat labeled and actionable', (
    tester,
  ) async {
    var opens = 0;

    Future<void> pumpHeader({
      required int unreadCount,
      bool chatEnabled = true,
      double textScale = 1,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: textScale,
                  maxScaleFactor: textScale,
                  child: capsuleHeaderSummary(
                    starterCount: 5,
                    relationshipCount: 1,
                    chatUnreadCount: unreadCount,
                    onOpenChat: chatEnabled ? () => opens++ : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpHeader(unreadCount: 3);
    final chat = find.text('Chat');
    expect(find.text('Starters'), findsOneWidget);
    expect(find.text('Relationships'), findsOneWidget);
    expect(chat, findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('Open Chat, 3 unread'), findsOneWidget);
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(chat);
    expect(opens, 1);

    await pumpHeader(unreadCount: 1200, textScale: 2);
    final badge = find.text('999+');
    expect(badge, findsOneWidget);
    final badgeRect = tester.getRect(badge);
    final chatRect = tester.getRect(chat);
    expect(
      badgeRect.overlaps(chatRect),
      isFalse,
      reason: '$badgeRect and $chatRect',
    );
    expect(
      badgeRect.right,
      lessThanOrEqualTo(tester.getRect(find.byType(TextButton)).right),
    );
    expect(tester.takeException(), isNull);

    await pumpHeader(unreadCount: 0, chatEnabled: false);
    expect(find.byType(Badge), findsNothing);
    await tester.tap(chat);
    expect(opens, 1);
  });
}
