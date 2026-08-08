import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/trading_drone_screen.dart';

void main() {
  testWidgets('BingX credentials stay masked until independently revealed', (
    tester,
  ) async {
    final apiKeyController = TextEditingController(text: 'visible-key');
    final apiSecretController = TextEditingController(text: 'visible-secret');
    addTearDown(apiKeyController.dispose);
    addTearDown(apiSecretController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-key-field'),
                controller: apiKeyController,
                label: 'BingX API Key',
                showTooltip: 'Show API key',
                hideTooltip: 'Hide API key',
              ),
              TradingDroneCredentialField(
                fieldKey: const ValueKey<String>('bingx-api-secret-field'),
                controller: apiSecretController,
                label: 'BingX API Secret',
                showTooltip: 'Show secret',
                hideTooltip: 'Hide secret',
              ),
            ],
          ),
        ),
      ),
    );

    TextField apiKeyField() => tester.widget<TextField>(
      find.byKey(const ValueKey<String>('bingx-api-key-field')),
    );
    TextField apiSecretField() => tester.widget<TextField>(
      find.byKey(const ValueKey<String>('bingx-api-secret-field')),
    );

    expect(apiKeyField().obscureText, isTrue);
    expect(apiSecretField().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show API key'));
    await tester.pump();

    expect(apiKeyField().obscureText, isFalse);
    expect(apiSecretField().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show secret'));
    await tester.pump();

    expect(apiKeyField().obscureText, isFalse);
    expect(apiSecretField().obscureText, isFalse);
  });
}
