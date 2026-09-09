import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/widgets/moltbook_community_settings_widgets.dart';

void main() {
  testWidgets('existing community use does not require ownership', (
    tester,
  ) async {
    final primary = TextEditingController(text: 'person-first-runtime');
    final display = TextEditingController();
    final description = TextEditingController();
    addTearDown(primary.dispose);
    addTearDown(display.dispose);
    addTearDown(description.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoltbookCommunitySettingsCard(
            primaryCommunityController: primary,
            displayNameController: display,
            descriptionController: description,
            allowCrypto: false,
            ownershipVerified: false,
            connected: true,
            busy: false,
            onPrimaryCommunityChanged: (_) {},
            onAllowCryptoChanged: (_) {},
            onCreate: () {},
          ),
        ),
      ),
    );

    expect(
      find.text('Existing communities can be used without being their owner.'),
      findsOneWidget,
    );
    expect(find.text('m/'), findsOneWidget);
    expect(find.text('person-first-runtime'), findsOneWidget);
  });

  testWidgets('creation review shows exact descriptor and crypto policy', (
    tester,
  ) async {
    var approved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  approved = await showMoltbookCommunityCreationApproval(
                    context,
                    name: 'capsule-notes',
                    displayName: 'Capsule Notes',
                    description: 'Public notes from a personal Capsule.',
                    allowCrypto: true,
                  );
                },
                child: const Text('Review'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('m/capsule-notes'), findsOneWidget);
    expect(find.text('Crypto-related posts are allowed.'), findsOneWidget);

    await tester.tap(find.text('Create exact community'));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
  });
}
