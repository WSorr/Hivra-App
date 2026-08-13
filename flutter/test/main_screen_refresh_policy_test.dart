import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/screens/main_screen.dart';

void main() {
  test('Relationships exposes only its canonical full refresh action', () {
    expect(showGlobalHeaderRefreshForTab(0), isTrue);
    expect(showGlobalHeaderRefreshForTab(1), isTrue);
    expect(showGlobalHeaderRefreshForTab(2), isFalse);
    expect(showGlobalHeaderRefreshForTab(3), isTrue);
    expect(showGlobalHeaderRefreshForTab(4), isTrue);
  });
}
