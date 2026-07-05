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
  });
}
