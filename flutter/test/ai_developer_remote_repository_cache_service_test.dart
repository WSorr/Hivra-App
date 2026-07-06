import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_developer_remote_repository_cache_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeGit {
  final List<_GitCall> calls = <_GitCall>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_GitCall(
      executable: executable,
      arguments: List<String>.from(arguments),
      workingDirectory: workingDirectory,
      environment: Map<String, String>.from(environment ?? const {}),
    ));
    if (arguments.length == 2 &&
        arguments[0] == 'rev-parse' &&
        arguments[1] == 'HEAD') {
      return ProcessResult(
        1,
        0,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n',
        '',
      );
    }
    return ProcessResult(1, 0, '', '');
  }
}

class _GitCall {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;

  const _GitCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });
}

void main() {
  group('AiDeveloperRemoteRepositoryCacheService', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('hivra-remote-cache-');
    });

    tearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('rejects non-HTTPS and non-GitHub repository URLs', () async {
      final service = _service(tempHome, _FakeGit());

      await expectLater(
        service.cacheRepository(const AiDeveloperRemoteRepositoryRequest(
          remoteUrl: 'git@github.com:WSorr/hivra-plugins.git',
        )),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        service.cacheRepository(const AiDeveloperRemoteRepositoryRequest(
          remoteUrl: 'https://example.com/WSorr/hivra-plugins',
        )),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('clones into controlled cache with hooks and submodules disabled',
        () async {
      final git = _FakeGit();
      final service = _service(tempHome, git);

      final report = await service.cacheRepository(
        const AiDeveloperRemoteRepositoryRequest(
          remoteUrl: 'https://github.com/WSorr/hivra-plugins',
        ),
      );

      expect(report.normalizedRemoteUrl,
          'https://github.com/WSorr/hivra-plugins.git');
      expect(report.cachePath,
          contains('/Documents/Hivra/Developer Cache/Remote Repositories/'));
      expect(report.resolvedCommit, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(report.mutableRefDangerous, isTrue);
      expect(report.submodulesBlocked, isTrue);
      expect(report.findings.single.title, 'Mutable repository context');

      final clone = git.calls.first;
      expect(clone.executable, 'git');
      expect(
          clone.arguments,
          containsAll(<String>[
            'core.hooksPath=/dev/null',
            'protocol.file.allow=never',
            'submodule.recurse=false',
            'clone',
            '--filter=blob:none',
            '--no-tags',
            '--depth',
            '1',
          ]));
      expect(clone.environment['GIT_TERMINAL_PROMPT'], '0');
      expect(clone.environment['GIT_ASKPASS'], '');
      expect(
        git.calls.any((call) =>
            call.arguments.contains('submodule') ||
            call.arguments.contains('update')),
        isFalse,
      );
    });

    test('fetches requested ref and marks full commit hash as immutable',
        () async {
      final git = _FakeGit();
      final service = _service(tempHome, git);
      final ref = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

      final report = await service.cacheRepository(
        AiDeveloperRemoteRepositoryRequest(
          remoteUrl: 'https://github.com/WSorr/hivra-plugins.git',
          ref: ref,
        ),
      );

      expect(report.requestedRef, ref);
      expect(report.mutableRefDangerous, isFalse);
      expect(report.findings, isEmpty);
      expect(
        git.calls.any((call) =>
            call.arguments.length >= 6 &&
            call.arguments.contains('fetch') &&
            call.arguments.last == ref),
        isTrue,
      );
      expect(
        git.calls.any((call) =>
            call.arguments.length == 3 &&
            call.arguments[0] == 'checkout' &&
            call.arguments[1] == '--detach' &&
            call.arguments[2] == 'FETCH_HEAD'),
        isTrue,
      );
    });

    test('clear cache removes controlled cache directory only', () async {
      final git = _FakeGit();
      final service = _service(tempHome, git);
      final root = Directory(
        '${tempHome.path}/Documents/Hivra/Developer Cache/Remote Repositories',
      );
      await root.create(recursive: true);
      await File('${root.path}/marker.txt').writeAsString('cache');
      final unrelated = File('${tempHome.path}/Documents/Hivra/keep.txt');
      await unrelated.create(recursive: true);

      await service.clearCache();

      expect(await root.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    });
  });
}

AiDeveloperRemoteRepositoryCacheService _service(
  Directory tempHome,
  _FakeGit git,
) {
  return AiDeveloperRemoteRepositoryCacheService(
    dataDirectoryService: UserVisibleDataDirectoryService(
      homeOverride: tempHome.path,
    ),
    gitRunner: git.run,
  );
}
