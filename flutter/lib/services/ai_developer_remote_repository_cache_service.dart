import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'user_visible_data_directory_service.dart';

typedef AiDeveloperGitRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

class AiDeveloperRemoteRepositoryRequest {
  final String remoteUrl;
  final String? ref;

  const AiDeveloperRemoteRepositoryRequest({
    required this.remoteUrl,
    this.ref,
  });
}

class AiDeveloperRemoteRepositoryFinding {
  final String severity;
  final String title;
  final String detail;
  final String recommendedAction;

  const AiDeveloperRemoteRepositoryFinding({
    required this.severity,
    required this.title,
    required this.detail,
    required this.recommendedAction,
  });
}

class AiDeveloperRemoteRepositoryCacheReport {
  final int schemaVersion;
  final String normalizedRemoteUrl;
  final String cachePath;
  final String? requestedRef;
  final String resolvedCommit;
  final bool mutableRefDangerous;
  final bool submodulesBlocked;
  final List<String> gitCommands;
  final List<AiDeveloperRemoteRepositoryFinding> findings;
  final String reportHashHex;

  const AiDeveloperRemoteRepositoryCacheReport({
    required this.schemaVersion,
    required this.normalizedRemoteUrl,
    required this.cachePath,
    required this.requestedRef,
    required this.resolvedCommit,
    required this.mutableRefDangerous,
    required this.submodulesBlocked,
    required this.gitCommands,
    required this.findings,
    required this.reportHashHex,
  });
}

class AiDeveloperRemoteRepositoryCacheService {
  static const String cacheDirectoryName =
      'Developer Cache/Remote Repositories';
  static final RegExp _githubPathPattern = RegExp(
    r'^/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$',
  );
  static final RegExp _immutableCommitPattern = RegExp(r'^[0-9a-fA-F]{40}$');

  final UserVisibleDataDirectoryService _dataDirectoryService;
  final AiDeveloperGitRunner _gitRunner;

  const AiDeveloperRemoteRepositoryCacheService({
    UserVisibleDataDirectoryService dataDirectoryService =
        const UserVisibleDataDirectoryService(),
    AiDeveloperGitRunner? gitRunner,
  })  : _dataDirectoryService = dataDirectoryService,
        _gitRunner = gitRunner ?? _defaultGitRunner;

  Future<AiDeveloperRemoteRepositoryCacheReport> cacheRepository(
    AiDeveloperRemoteRepositoryRequest request,
  ) async {
    final normalizedUrl = _normalizeGitHubUrl(request.remoteUrl);
    final requestedRef = request.ref?.trim();
    final cacheRoot = await _cacheRoot(create: true);
    final repoDir = Directory('${cacheRoot.path}/${_cacheKey(normalizedUrl)}');
    final commands = <String>[];

    if (!await repoDir.exists()) {
      await _runGit(
        commands,
        <String>[
          '-c',
          'core.hooksPath=/dev/null',
          '-c',
          'protocol.file.allow=never',
          '-c',
          'submodule.recurse=false',
          'clone',
          '--filter=blob:none',
          '--no-tags',
          '--depth',
          '1',
          normalizedUrl,
          repoDir.path,
        ],
      );
    } else {
      await _runGit(
        commands,
        <String>[
          '-c',
          'core.hooksPath=/dev/null',
          '-c',
          'protocol.file.allow=never',
          '-c',
          'submodule.recurse=false',
          'fetch',
          '--depth',
          '1',
          'origin',
        ],
        workingDirectory: repoDir.path,
      );
    }

    await _runGit(
      commands,
      <String>['config', '--local', 'core.hooksPath', '/dev/null'],
      workingDirectory: repoDir.path,
    );
    await _runGit(
      commands,
      <String>['config', '--local', 'submodule.recurse', 'false'],
      workingDirectory: repoDir.path,
    );

    if (requestedRef != null && requestedRef.isNotEmpty) {
      await _runGit(
        commands,
        <String>[
          '-c',
          'core.hooksPath=/dev/null',
          '-c',
          'protocol.file.allow=never',
          '-c',
          'submodule.recurse=false',
          'fetch',
          '--depth',
          '1',
          'origin',
          requestedRef,
        ],
        workingDirectory: repoDir.path,
      );
      await _runGit(
        commands,
        <String>['checkout', '--detach', 'FETCH_HEAD'],
        workingDirectory: repoDir.path,
      );
    }

    final resolvedCommit = await _readGit(
      commands,
      <String>['rev-parse', 'HEAD'],
      workingDirectory: repoDir.path,
    );
    final findings = <AiDeveloperRemoteRepositoryFinding>[];
    final mutableRefDangerous =
        requestedRef == null || !_immutableCommitPattern.hasMatch(requestedRef);
    if (mutableRefDangerous) {
      findings.add(const AiDeveloperRemoteRepositoryFinding(
        severity: 'warning',
        title: 'Mutable repository context',
        detail:
            'No immutable commit was provided. The resolved commit is recorded, but the requested ref can move.',
        recommendedAction:
            'Prefer a full 40-character commit hash for reproducible developer context.',
      ));
    }
    if (await File('${repoDir.path}/.gitmodules').exists()) {
      findings.add(const AiDeveloperRemoteRepositoryFinding(
        severity: 'warning',
        title: 'Submodules blocked',
        detail:
            'Repository declares submodules. Hivra does not initialize submodules for developer context cache.',
        recommendedAction:
            'Review submodule sources separately and explicitly if needed.',
      ));
    }

    final canonical = <String, dynamic>{
      'schema_version': 1,
      'normalized_remote_url': normalizedUrl,
      'cache_path': repoDir.path,
      'requested_ref': requestedRef,
      'resolved_commit': resolvedCommit,
      'mutable_ref_dangerous': mutableRefDangerous,
      'submodules_blocked': true,
      'git_commands': commands,
      'findings': findings
          .map((finding) => <String, dynamic>{
                'severity': finding.severity,
                'title': finding.title,
                'detail': finding.detail,
              })
          .toList(growable: false),
    };
    return AiDeveloperRemoteRepositoryCacheReport(
      schemaVersion: 1,
      normalizedRemoteUrl: normalizedUrl,
      cachePath: repoDir.path,
      requestedRef: requestedRef,
      resolvedCommit: resolvedCommit,
      mutableRefDangerous: mutableRefDangerous,
      submodulesBlocked: true,
      gitCommands: commands,
      findings: findings,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  Future<void> clearCache() async {
    final cacheRoot = await _cacheRoot(create: false);
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  }

  Future<Directory> _cacheRoot({required bool create}) async {
    final root = await _dataDirectoryService.rootDirectory(create: create);
    final cacheRoot = Directory('${root.path}/$cacheDirectoryName');
    if (create && !await cacheRoot.exists()) {
      await cacheRoot.create(recursive: true);
    }
    return cacheRoot;
  }

  Future<void> _runGit(
    List<String> commands,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final result = await _runGitProcess(commands, arguments,
        workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  Future<String> _readGit(
    List<String> commands,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final result = await _runGitProcess(commands, arguments,
        workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
    return result.stdout.toString().trim();
  }

  Future<ProcessResult> _runGitProcess(
    List<String> commands,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    commands.add('git ${arguments.join(' ')}');
    return _gitRunner(
      'git',
      arguments,
      workingDirectory: workingDirectory,
      environment: const <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_ASKPASS': '',
      },
    );
  }

  String _normalizeGitHubUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https') {
      throw ArgumentError('Only HTTPS GitHub repository URLs are allowed');
    }
    final host = uri.host.toLowerCase();
    if (host != 'github.com' && host != 'www.github.com') {
      throw ArgumentError('Only github.com repository URLs are allowed');
    }
    final match = _githubPathPattern.firstMatch(uri.path);
    if (match == null) {
      throw ArgumentError('GitHub repository URL must be /owner/repo');
    }
    final owner = match.group(1)!;
    final repo = match.group(2)!;
    return 'https://github.com/$owner/$repo.git';
  }

  String _cacheKey(String normalizedUrl) {
    return sha256.convert(utf8.encode(normalizedUrl)).toString();
  }

  String _hashCanonical(Object? value) {
    return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}

Future<ProcessResult> _defaultGitRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
