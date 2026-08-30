import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';

void main() {
  group('AiDeveloperWorkspaceService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hivra-ai-workspace-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('scans allowlisted files deterministically without file contents',
        () async {
      await File('${tempDir.path}/README.md').writeAsString('hello hivra');
      await Directory('${tempDir.path}/docs').create();
      await File('${tempDir.path}/docs/specification.md').writeAsString('spec');
      await Directory('${tempDir.path}/build').create();
      await File('${tempDir.path}/build/generated.dart').writeAsString('skip');

      const service = AiDeveloperWorkspaceService();
      final first = await service.scanLocalRepositories(<String>[tempDir.path]);
      final second =
          await service.scanLocalRepositories(<String>[tempDir.path]);

      expect(first.reportHashHex, second.reportHashHex);
      expect(first.repositories.single.scannedFileCount, 2);
      expect(
        first.repositories.single.files.map((file) => file.relativePath),
        containsAll(<String>['README.md', 'docs/specification.md']),
      );
      expect(first.repositories.single.files.first.sha256Hex.length, 64);
    });

    test('indexes relevant source beyond the old first-120 boundary', () async {
      final docs = await Directory('${tempDir.path}/docs').create();
      for (var index = 0; index < 130; index++) {
        await File('${docs.path}/archive_$index.md').writeAsString('$index');
      }
      final services = await Directory('${tempDir.path}/flutter/lib/services')
          .create(recursive: true);
      await File('${services.path}/delivery_outbox_store.dart')
          .writeAsString('class DeliveryOutboxStore {}');

      const service = AiDeveloperWorkspaceService();
      final report = await service.scanLocalRepositories(<String>[
        tempDir.path,
      ]);

      expect(report.repositories.single.scannedFileCount, 131);
      expect(
        report.repositories.single.files.map((file) => file.relativePath),
        contains('flutter/lib/services/delivery_outbox_store.dart'),
      );
    });

    test('focus selects implementation test and contract instead of README',
        () {
      const service = AiDeveloperWorkspaceService();
      const report = AiDeveloperWorkspaceReport(
        schemaVersion: 1,
        repositories: <AiDeveloperWorkspaceRepoSummary>[
          AiDeveloperWorkspaceRepoSummary(
            rootPath: '/repo',
            scannedFileCount: 6,
            skippedFileCount: 0,
            skippedDirectoryCount: 0,
            files: <AiDeveloperWorkspaceFileSummary>[
              AiDeveloperWorkspaceFileSummary(
                relativePath: 'README.md',
                sizeBytes: 1,
                sha256Hex: '00',
              ),
              AiDeveloperWorkspaceFileSummary(
                relativePath:
                    'flutter/lib/services/delivery_outbox_store.dart',
                sizeBytes: 1,
                sha256Hex: '01',
              ),
              AiDeveloperWorkspaceFileSummary(
                relativePath:
                    'flutter/lib/services/capsule_chat_delivery_service.dart',
                sizeBytes: 1,
                sha256Hex: '02',
              ),
              AiDeveloperWorkspaceFileSummary(
                relativePath: 'flutter/test/delivery_outbox_store_test.dart',
                sizeBytes: 25000,
                sha256Hex: '03',
              ),
              AiDeveloperWorkspaceFileSummary(
                relativePath: 'flutter/test/delivery_outbox_retry_test.dart',
                sizeBytes: 1,
                sha256Hex: '05',
              ),
              AiDeveloperWorkspaceFileSummary(
                relativePath:
                    'docs/architecture/transport-delivery-lifecycle.md',
                sizeBytes: 1,
                sha256Hex: '04',
              ),
            ],
            findings: <AiDeveloperFinding>[],
          ),
        ],
        reportHashHex: '11',
      );

      final selected = service.suggestFocusedFileSelections(
        report: report,
        area: 'transport',
        title: 'Delivery outbox has pending work',
      );

      expect(
        selected,
        containsAll(<String>[
          '/repo/flutter/lib/services/delivery_outbox_store.dart',
          '/repo/flutter/test/delivery_outbox_retry_test.dart',
          '/repo/docs/architecture/transport-delivery-lifecycle.md',
        ]),
      );
      expect(selected, isNot(contains('/repo/README.md')));
      expect(
        selected,
        isNot(contains('/repo/flutter/test/delivery_outbox_store_test.dart')),
      );
    });

    test('skips denylisted credential paths', () async {
      await Directory('${tempDir.path}/docs').create();
      await File('${tempDir.path}/docs/.env').writeAsString('TOKEN=secret');
      await File('${tempDir.path}/docs/capsule_seeds.json')
          .writeAsString('seed phrase');
      await File('${tempDir.path}/docs/public.md').writeAsString('ok');

      const service = AiDeveloperWorkspaceService();
      final report =
          await service.scanLocalRepositories(<String>[tempDir.path]);

      final repo = report.repositories.single;
      expect(repo.scannedFileCount, 1);
      expect(repo.files.single.relativePath, 'docs/public.md');
      expect(repo.findings.map((finding) => finding.title),
          everyElement('Denylisted file skipped'));
    });

    test('skips symlinks instead of following them', () async {
      await Directory('${tempDir.path}/docs').create();
      await File('${tempDir.path}/outside_secret.md').writeAsString('secret');
      await Link('${tempDir.path}/docs/linked_secret.md')
          .create('${tempDir.path}/outside_secret.md');

      const service = AiDeveloperWorkspaceService();
      final report =
          await service.scanLocalRepositories(<String>[tempDir.path]);

      final repo = report.repositories.single;
      expect(repo.scannedFileCount, 0);
      expect(repo.findings.single.title, 'Symlink skipped');
    });

    test('builds selected file context from previewed files only', () async {
      await Directory('${tempDir.path}/docs').create();
      await File('${tempDir.path}/docs/a.md').writeAsString('alpha');
      await File('${tempDir.path}/docs/b.md').writeAsString('beta');
      const service = AiDeveloperWorkspaceService();
      final report =
          await service.scanLocalRepositories(<String>[tempDir.path]);

      final context = await service.buildSelectedFileContext(
        report: report,
        selectedFilePaths: <String>[
          _selection(tempDir, 'docs/b.md'),
          _selection(tempDir, 'docs/a.md'),
        ],
      );
      final second = await service.buildSelectedFileContext(
        report: report,
        selectedFilePaths: <String>[
          _selection(tempDir, 'docs/a.md'),
          _selection(tempDir, 'docs/b.md'),
        ],
      );

      expect(context.contextHashHex, second.contextHashHex);
      expect(context.snippets.map((snippet) => snippet.relativePath),
          <String>['docs/a.md', 'docs/b.md']);
      expect(context.toPrettyJson(), contains('alpha'));
      expect(context.findings.single.title,
          'Selected source is untrusted prompt input');
    });

    test('blocks selected file when it changed after preview', () async {
      await Directory('${tempDir.path}/docs').create();
      final file = File('${tempDir.path}/docs/a.md');
      await file.writeAsString('alpha');
      const service = AiDeveloperWorkspaceService();
      final report =
          await service.scanLocalRepositories(<String>[tempDir.path]);
      await file.writeAsString('changed');

      final context = await service.buildSelectedFileContext(
        report: report,
        selectedFilePaths: <String>[_selection(tempDir, 'docs/a.md')],
      );

      expect(context.snippets, isEmpty);
      expect(
          context.findings.single.title, 'Selected file changed after preview');
    });

    test('rejects too many selected files', () async {
      await Directory('${tempDir.path}/docs').create();
      const service = AiDeveloperWorkspaceService();
      final selections = <String>[];
      for (var i = 0;
          i < AiDeveloperWorkspaceService.maxSelectedFiles + 1;
          i++) {
        final path = 'docs/$i.md';
        await File('${tempDir.path}/$path').writeAsString('$i');
        selections.add(_selection(tempDir, path));
      }
      final report =
          await service.scanLocalRepositories(<String>[tempDir.path]);

      await expectLater(
        service.buildSelectedFileContext(
          report: report,
          selectedFilePaths: selections,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('binds duplicate relative paths to the exact repository', () async {
      final firstRepo = await Directory('${tempDir.path}/first').create();
      final secondRepo = await Directory('${tempDir.path}/second').create();
      await File('${firstRepo.path}/README.md').writeAsString('first');
      await File('${secondRepo.path}/README.md').writeAsString('second');
      const service = AiDeveloperWorkspaceService();
      final report = await service.scanLocalRepositories(<String>[
        firstRepo.path,
        secondRepo.path,
      ]);

      final context = await service.buildSelectedFileContext(
        report: report,
        selectedFilePaths: <String>[_selection(secondRepo, 'README.md')],
      );

      expect(context.snippets.single.rootPath, secondRepo.absolute.path);
      expect(context.snippets.single.text, 'second');
    });

    test('rejects an unbound relative selection', () async {
      await File('${tempDir.path}/README.md').writeAsString('content');
      const service = AiDeveloperWorkspaceService();
      final report = await service.scanLocalRepositories(<String>[
        tempDir.path,
      ]);

      final context = await service.buildSelectedFileContext(
        report: report,
        selectedFilePaths: const <String>['README.md'],
      );

      expect(context.snippets, isEmpty);
      expect(
        context.findings.single.title,
        'Selected file not in workspace preview',
      );
    });
  });
}

String _selection(Directory root, String relativePath) {
  return AiDeveloperWorkspaceService.canonicalSelectionPath(
    rootPath: root.absolute.path,
    relativePath: relativePath,
  );
}
