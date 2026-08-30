import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/capsule_doctor_screen.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_developer_engineer_service.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';

void main() {
  test('quick add extends and deduplicates developer workspace selection', () {
    final merged = mergeDeveloperWorkspaceFileSelections(
      currentPaths: const <String>[
        'docs/roadmap.md',
        'docs/specification.md',
        ' docs/roadmap.md ',
      ],
      suggestedPaths: const <String>[
        'README.md',
        'docs/specification.md',
        'Cargo.toml',
      ],
    );

    expect(merged, const <String>[
      'Cargo.toml',
      'README.md',
      'docs/roadmap.md',
      'docs/specification.md',
    ]);
  });

  test('quick add never exceeds the developer workspace selection limit', () {
    final merged = mergeDeveloperWorkspaceFileSelections(
      currentPaths: const <String>['one.md', 'two.md', 'three.md'],
      suggestedPaths: const <String>['four.md', 'five.md', 'six.md'],
      maxPaths: 4,
    );

    expect(merged, const <String>['four.md', 'one.md', 'three.md', 'two.md']);
  });

  testWidgets('developer mode remains enabled after scrolling offscreen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              const SizedBox(height: 800),
              CapsuleDoctorDeveloperModeBoundary(
                snapshot: _emptySnapshot,
                workspaceService: const AiDeveloperWorkspaceService(),
                engineerService: AiDeveloperEngineerService(
                  runtime: _TestInferenceRuntime(),
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Developer Mode'), 500);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(
      find.textContaining('Developer Mode is enabled for this screen session'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pump();

    expect(
      find.textContaining('Developer Mode is enabled for this screen session'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}

const _emptySnapshot = AiCapsuleInspectionSnapshot(
  schemaVersion: 1,
  mode: 'test',
  capsule: <String, dynamic>{},
  ledgerSummary: <String, dynamic>{},
  invitationSummary: <String, dynamic>{},
  relationshipSummary: <String, dynamic>{},
  transportSummary: <String, dynamic>{},
  consensusSummary: <String, dynamic>{},
  pluginSummary: <String, dynamic>{},
  bootstrapSummary: <String, dynamic>{},
  traceSummary: <String, dynamic>{},
  redaction: <String, dynamic>{},
  snapshotHashHex: '00',
);

class _TestInferenceRuntime implements CapsuleInferenceRuntime {
  @override
  Future<String?> loadPreferredProviderId() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
