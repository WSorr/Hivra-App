import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/capsule_doctor_screen.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_developer_engineer_service.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';
import 'package:hivra_app/services/capsule_ai_runtime_service.dart';
import 'package:hivra_app/services/ui_event_log_service.dart';
import 'package:hivra_app/widgets/ai_diagnostics/developer_workspace_widgets.dart';

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

  testWidgets('selected context preview appears before repository file lists', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapsuleDoctorDeveloperModeBoundary(
              snapshot: _emptySnapshot,
              workspaceService: const _TestWorkspaceService(),
              engineerService: AiDeveloperEngineerService(
                runtime: _TestInferenceRuntime(),
              ),
              uiLog: _SilentLog(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Scan workspace preview'));
    await tester.pump();
    await tester.pump();
    final selectedFilesField =
        find
            .byKey(
              const ValueKey<String>('hivra_engineer_selected_relative_files'),
            )
            .first;
    expect(
      tester.widget<TextField>(selectedFilesField).controller!.text,
      '/repo/README.md\n'
      '/repo/docs/development-control.md\n'
      '/repo/docs/product-axis.md',
    );
    await tester.tap(find.text('Build selected context preview'));
    await tester.pump();
    await tester.pump();

    final contextTop = tester.getTopLeft(
      find.byType(AiDeveloperSelectedContextPanel),
    );
    final repositoryTop = tester.getTopLeft(
      find.byType(AiDeveloperWorkspaceRepoTile).first,
    );
    expect(contextTop.dy, lessThan(repositoryTop.dy));
  });

  testWidgets('analyst finding prepares focused source test and contract', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapsuleDoctorDeveloperModeBoundary(
              snapshot: _emptySnapshot,
              findings: const <AiCapsuleInspectionFinding>[_transportFocus],
              workspaceService: const _TestWorkspaceService(),
              engineerService: AiDeveloperEngineerService(
                runtime: _TestInferenceRuntime(),
              ),
              uiLog: _SilentLog(),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Prepared focus:'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Scan workspace preview'));
    await tester.pump();
    await tester.pump();

    final selectedFilesField = find.byKey(
      const ValueKey<String>('hivra_engineer_selected_relative_files'),
    );
    final selected = tester.widget<TextField>(selectedFilesField).controller!.text;
    expect(
      selected,
      contains('/repo/flutter/lib/services/delivery_outbox_store.dart'),
    );
    expect(
      selected,
      contains('/repo/flutter/test/delivery_outbox_store_test.dart'),
    );
    expect(
      selected,
      contains('/repo/docs/architecture/transport-delivery-lifecycle.md'),
    );
    expect(selected, isNot(contains('/repo/README.md')));
    await tester.tap(find.text('Build selected context preview'));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Ask Hivra Engineer'))
          .controller!
          .text,
      contains('Delivery outbox has pending work'),
    );
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

const _transportFocus = AiCapsuleInspectionFinding(
  severity: 'warning',
  area: 'transport',
  title: 'Delivery outbox has pending work',
  detail: 'Two delivery items are waiting for retry.',
  recommendedAction: 'Inspect transport delivery and outbox state.',
);

class _TestInferenceRuntime implements CapsuleInferenceRuntime {
  @override
  Future<String?> loadPreferredProviderId() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWorkspaceService extends AiDeveloperWorkspaceService {
  const _TestWorkspaceService();

  @override
  Future<AiDeveloperWorkspaceReport> scanLocalRepositories(
    Iterable<String> rootPaths,
  ) async {
    return const AiDeveloperWorkspaceReport(
      schemaVersion: 1,
      repositories: <AiDeveloperWorkspaceRepoSummary>[
        AiDeveloperWorkspaceRepoSummary(
          rootPath: '/repo-plugins',
          scannedFileCount: 2,
          skippedFileCount: 0,
          skippedDirectoryCount: 0,
          files: <AiDeveloperWorkspaceFileSummary>[
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'Cargo.toml',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'README.md',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
          ],
          findings: <AiDeveloperFinding>[],
        ),
        AiDeveloperWorkspaceRepoSummary(
          rootPath: '/repo',
          scannedFileCount: 6,
          skippedFileCount: 0,
          skippedDirectoryCount: 0,
          files: <AiDeveloperWorkspaceFileSummary>[
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'README.md',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'docs/development-control.md',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'docs/product-axis.md',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath:
                  'docs/architecture/transport-delivery-lifecycle.md',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'flutter/lib/services/delivery_outbox_store.dart',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
            AiDeveloperWorkspaceFileSummary(
              relativePath: 'flutter/test/delivery_outbox_store_test.dart',
              sizeBytes: 6,
              sha256Hex: '00',
            ),
          ],
          findings: <AiDeveloperFinding>[],
        ),
      ],
      reportHashHex: '11',
    );
  }

  @override
  Future<AiDeveloperWorkspaceSelectedContext> buildSelectedFileContext({
    required AiDeveloperWorkspaceReport report,
    required Iterable<String> selectedFilePaths,
  }) async {
    return const AiDeveloperWorkspaceSelectedContext(
      schemaVersion: 1,
      snippets: <AiDeveloperWorkspaceSnippet>[
        AiDeveloperWorkspaceSnippet(
          rootPath: '/repo',
          relativePath: 'README.md',
          sizeBytes: 6,
          sha256Hex: '00',
          text: 'Hivra',
        ),
      ],
      findings: <AiDeveloperFinding>[],
      contextHashHex: '22',
    );
  }
}

class _SilentLog implements UiEventLogService {
  @override
  Future<void> log(String source, String message) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
