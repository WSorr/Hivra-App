import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class AiDeveloperWorkspaceFinding {
  final String severity;
  final String title;
  final String detail;
  final String recommendedAction;

  const AiDeveloperWorkspaceFinding({
    required this.severity,
    required this.title,
    required this.detail,
    required this.recommendedAction,
  });
}

class AiDeveloperWorkspaceFileSummary {
  final String relativePath;
  final int sizeBytes;
  final String sha256Hex;

  const AiDeveloperWorkspaceFileSummary({
    required this.relativePath,
    required this.sizeBytes,
    required this.sha256Hex,
  });
}

class AiDeveloperWorkspaceRepoSummary {
  final String rootPath;
  final int scannedFileCount;
  final int skippedFileCount;
  final int skippedDirectoryCount;
  final List<AiDeveloperWorkspaceFileSummary> files;
  final List<AiDeveloperWorkspaceFinding> findings;

  const AiDeveloperWorkspaceRepoSummary({
    required this.rootPath,
    required this.scannedFileCount,
    required this.skippedFileCount,
    required this.skippedDirectoryCount,
    required this.files,
    required this.findings,
  });
}

class AiDeveloperWorkspaceReport {
  final int schemaVersion;
  final List<AiDeveloperWorkspaceRepoSummary> repositories;
  final String reportHashHex;

  const AiDeveloperWorkspaceReport({
    required this.schemaVersion,
    required this.repositories,
    required this.reportHashHex,
  });

  List<AiDeveloperWorkspaceFinding> get findings =>
      repositories.expand((repo) => repo.findings).toList(growable: false);
}

class AiDeveloperWorkspaceService {
  static const int maxFilesPerRepo = 120;
  static const int maxFileBytes = 96 * 1024;

  static const Set<String> _allowedRootFiles = <String>{
    'README.md',
    'Cargo.toml',
    'pubspec.yaml',
  };
  static const Set<String> _allowedTopLevelDirs = <String>{
    'docs',
    'tools',
    'core',
    'engine',
    'adapters',
    'platform',
    'flutter',
    'contracts',
    'checklists',
    'scripts',
    'src',
    'tests',
    'test',
  };
  static const Set<String> _skippedDirs = <String>{
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'target',
    'dist',
    'Pods',
    'node_modules',
  };
  static final RegExp _allowedFilePattern = RegExp(
    r'\.(md|txt|toml|yaml|yml|json|dart|rs|sh)$',
    caseSensitive: false,
  );
  static final RegExp _denylistedPathPattern = RegExp(
    r'(^|/)(\.env[^/]*|.*\.pem|.*\.key|capsule_seeds\.json|bingx_futures_credentials\.json|.*credential.*\.json)$',
    caseSensitive: false,
  );

  const AiDeveloperWorkspaceService();

  Future<AiDeveloperWorkspaceReport> scanLocalRepositories(
    Iterable<String> rootPaths,
  ) async {
    final normalizedRoots = rootPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalizedRoots.isEmpty) {
      throw ArgumentError('At least one repository path is required');
    }

    final repos = <AiDeveloperWorkspaceRepoSummary>[];
    for (final rootPath in normalizedRoots) {
      repos.add(await _scanRepo(rootPath));
    }
    final canonical = <String, dynamic>{
      'schema_version': 1,
      'repositories': repos
          .map(
            (repo) => <String, dynamic>{
              'root_path': repo.rootPath,
              'scanned_file_count': repo.scannedFileCount,
              'skipped_file_count': repo.skippedFileCount,
              'skipped_directory_count': repo.skippedDirectoryCount,
              'files': repo.files
                  .map(
                    (file) => <String, dynamic>{
                      'relative_path': file.relativePath,
                      'size_bytes': file.sizeBytes,
                      'sha256_hex': file.sha256Hex,
                    },
                  )
                  .toList(growable: false),
              'findings': repo.findings
                  .map(
                    (finding) => <String, dynamic>{
                      'severity': finding.severity,
                      'title': finding.title,
                      'detail': finding.detail,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
    return AiDeveloperWorkspaceReport(
      schemaVersion: 1,
      repositories: repos,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  Future<AiDeveloperWorkspaceRepoSummary> _scanRepo(String rootPath) async {
    final root = Directory(rootPath);
    final findings = <AiDeveloperWorkspaceFinding>[];
    if (!await root.exists()) {
      return AiDeveloperWorkspaceRepoSummary(
        rootPath: root.absolute.path,
        scannedFileCount: 0,
        skippedFileCount: 0,
        skippedDirectoryCount: 0,
        files: const <AiDeveloperWorkspaceFileSummary>[],
        findings: <AiDeveloperWorkspaceFinding>[
          AiDeveloperWorkspaceFinding(
            severity: 'critical',
            title: 'Repository path does not exist',
            detail: root.absolute.path,
            recommendedAction: 'Choose an existing local repository path.',
          ),
        ],
      );
    }

    final rootAbsolute = root.absolute.path;
    final files = <AiDeveloperWorkspaceFileSummary>[];
    var skippedFiles = 0;
    var skippedDirs = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relativePath = _relativePath(rootAbsolute, entity.absolute.path);
      if (relativePath == null || relativePath.isEmpty) continue;
      if (!_isAllowedTopLevel(relativePath)) {
        if (entity is Directory) skippedDirs++;
        if (entity is File) skippedFiles++;
        continue;
      }
      if (_hasSkippedDirectory(relativePath)) {
        if (entity is Directory) skippedDirs++;
        if (entity is File) skippedFiles++;
        continue;
      }
      if (_denylistedPathPattern.hasMatch(relativePath)) {
        skippedFiles++;
        findings.add(AiDeveloperWorkspaceFinding(
          severity: 'warning',
          title: 'Denylisted file skipped',
          detail: relativePath,
          recommendedAction:
              'Keep secrets outside AI workspace context and repository commits.',
        ));
        continue;
      }
      if (entity is Link) {
        skippedFiles++;
        findings.add(AiDeveloperWorkspaceFinding(
          severity: 'warning',
          title: 'Symlink skipped',
          detail: relativePath,
          recommendedAction:
              'Use real files inside the repository when sharing context.',
        ));
        continue;
      }
      if (entity is! File) continue;
      if (!_allowedFilePattern.hasMatch(relativePath)) {
        skippedFiles++;
        continue;
      }
      final sizeBytes = await entity.length();
      if (sizeBytes > maxFileBytes) {
        skippedFiles++;
        findings.add(AiDeveloperWorkspaceFinding(
          severity: 'info',
          title: 'Large file skipped',
          detail: '$relativePath ($sizeBytes bytes)',
          recommendedAction:
              'Select smaller focused snippets when developer mode supports excerpts.',
        ));
        continue;
      }
      if (files.length >= maxFilesPerRepo) {
        skippedFiles++;
        continue;
      }
      final bytes = await entity.readAsBytes();
      files.add(AiDeveloperWorkspaceFileSummary(
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        sha256Hex: sha256.convert(bytes).toString(),
      ));
    }

    files
        .sort((left, right) => left.relativePath.compareTo(right.relativePath));
    return AiDeveloperWorkspaceRepoSummary(
      rootPath: rootAbsolute,
      scannedFileCount: files.length,
      skippedFileCount: skippedFiles,
      skippedDirectoryCount: skippedDirs,
      files: files,
      findings: findings,
    );
  }

  bool _isAllowedTopLevel(String relativePath) {
    final first = relativePath.split('/').first;
    if (_allowedRootFiles.contains(relativePath)) return true;
    return _allowedTopLevelDirs.contains(first);
  }

  bool _hasSkippedDirectory(String relativePath) {
    return relativePath
        .split('/')
        .any((segment) => _skippedDirs.contains(segment));
  }

  String? _relativePath(String rootPath, String entityPath) {
    final normalizedRoot = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    if (!entityPath.startsWith(normalizedRoot)) return null;
    return entityPath.substring(normalizedRoot.length).replaceAll('\\', '/');
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
