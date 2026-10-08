import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

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
}
