import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/moltbook_publication_service.dart';
import 'package:hivra_app/widgets/moltbook_person_first_runtime_community_widgets.dart';

void main() {
  testWidgets('community card exposes review without creating by itself', (
    tester,
  ) async {
    var createCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoltbookPersonFirstRuntimeCommunityCard(
            operation: null,
            busy: false,
            connected: true,
            onCreate: () => createCalls++,
          ),
        ),
      ),
    );

    expect(find.text('m/person-first-runtime'), findsOneWidget);
    expect(find.text('Review community creation'), findsOneWidget);
    expect(createCalls, 0);

    await tester.tap(find.text('Review community creation'));
    expect(createCalls, 1);
  });

  testWidgets('approval dialog binds the exact permanent descriptor', (
    tester,
  ) async {
    bool? approved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    approved =
                        await showMoltbookPersonFirstRuntimeCommunityApproval(
                          context,
                        );
                  },
                  child: const Text('Open'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('m/person-first-runtime'), findsOneWidget);
    expect(
      find.text(
        MoltbookPublicationService.personFirstRuntimeSubmoltDescription,
      ),
      findsOneWidget,
    );
    expect(find.text('Create exact community'), findsOneWidget);
    expect(approved, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
  });
}
