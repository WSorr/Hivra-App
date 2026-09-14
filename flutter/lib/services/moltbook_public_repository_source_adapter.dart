import 'dart:convert';
import 'dart:io';

import '../models/moltbook_ambassador_models.dart';

typedef MoltbookPublicJsonReader = Future<Object?> Function(Uri uri);

class MoltbookPublicRepositorySourceAdapter {
  static const int _maxResponseBytes = 262144;
  static const Duration _requestTimeout = Duration(seconds: 12);

  final MoltbookPublicJsonReader _readJson;

  MoltbookPublicRepositorySourceAdapter({MoltbookPublicJsonReader? readJson})
    : _readJson = readJson ?? _readPublicJson;

  Future<({String sourceId, List<String> facts})?> observeLatestCommit(
    String repositoryUrl,
  ) async {
    final repository = MoltbookAmbassadorConfiguration.parsePublicRepositoryUrl(
      repositoryUrl,
    );
    if (repository == null) return null;
    final owner = repository.owner;
    final name = repository.name;
    final latest = await _readJson(
      Uri.https(
        'api.github.com',
        '/repos/$owner/$name/commits',
        <String, String>{'per_page': '1'},
      ),
    );
    if (latest is! List || latest.length != 1 || latest.single is! Map) {
      throw const FormatException('GitHub latest commit response is invalid');
    }
    final summary = Map<String, dynamic>.from(latest.single as Map);
    final sha = _commitSha(summary['sha']);
    final details = await _readJson(
      Uri.https('api.github.com', '/repos/$owner/$name/commits/$sha'),
    );
    if (details is! Map) {
      throw const FormatException('GitHub commit response is invalid');
    }
    final commit = Map<String, dynamic>.from(details);
    if (_commitSha(commit['sha']) != sha) {
      throw const FormatException('GitHub commit identity changed');
    }
    final metadata = commit['commit'];
    if (metadata is! Map) {
      throw const FormatException('GitHub commit metadata is invalid');
    }
    final metadataJson = Map<String, dynamic>.from(metadata);
    final subject = _commitSubject(metadataJson['message']);
    final author = metadataJson['author'];
    if (author is! Map) {
      throw const FormatException('GitHub commit author is invalid');
    }
    final recordedAt =
        DateTime.tryParse(
          Map<String, dynamic>.from(author)['date']?.toString() ?? '',
        )?.toUtc();
    if (recordedAt == null) {
      throw const FormatException('GitHub commit date is invalid');
    }
    final files = _changedFiles(commit['files']);
    final stats = commit['stats'];
    if (stats is! Map) {
      throw const FormatException('GitHub commit stats are invalid');
    }
    final statsJson = Map<String, dynamic>.from(stats);
    final additions = _boundedCount(statsJson['additions'], 'additions');
    final deletions = _boundedCount(statsJson['deletions'], 'deletions');
    final repositoryLabel = '$owner/$name';
    return (
      sourceId: 'github-$sha',
      facts: <String>[
        'Public repository $repositoryLabel recorded commit ${sha.substring(0, 12)} on ${recordedAt.toIso8601String()} with subject: $subject',
        'The public commit response lists ${files.length} changed file${files.length == 1 ? '' : 's'}: ${files.take(3).map((file) => _abbreviate(file, 60)).join(', ')}${files.length > 3 ? ', and ${files.length - 3} more' : ''}.',
        'The public commit reports $additions additions and $deletions deletions.',
      ],
    );
  }

  static String _commitSha(Object? value) {
    final sha = value?.toString().trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      throw const FormatException('GitHub commit SHA is invalid');
    }
    return sha;
  }

  static String _commitSubject(Object? value) {
    if (value is! String) {
      throw const FormatException('GitHub commit message is invalid');
    }
    final subject = value.split(RegExp(r'[\r\n]')).first.trim();
    if (subject.isEmpty ||
        subject.length > 100 ||
        _unsafeText.hasMatch(subject)) {
      throw const FormatException('GitHub commit subject is invalid');
    }
    return subject;
  }

  static List<String> _changedFiles(Object? value) {
    if (value is! List || value.isEmpty || value.length > 300) {
      throw const FormatException('GitHub changed files are invalid');
    }
    final files = <String>[];
    for (final raw in value) {
      if (raw is! Map) {
        throw const FormatException('GitHub changed file is invalid');
      }
      final filename = Map<String, dynamic>.from(raw)['filename'];
      if (filename is! String ||
          filename.isEmpty ||
          filename.length > 180 ||
          _unsafeText.hasMatch(filename)) {
        throw const FormatException('GitHub changed filename is invalid');
      }
      files.add(filename);
    }
    return List<String>.unmodifiable(files);
  }

  static int _boundedCount(Object? value, String field) {
    if (value is! int || value < 0 || value > 10000000) {
      throw FormatException('GitHub commit $field is invalid');
    }
    return value;
  }

  static String _abbreviate(String value, int maxCharacters) =>
      value.length <= maxCharacters
          ? value
          : '...${value.substring(value.length - maxCharacters + 3)}';

  static final RegExp _unsafeText = RegExp(
    r'[\x00-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
  );

  static Future<Object?> _readPublicJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28')
        ..set(HttpHeaders.userAgentHeader, 'Hivra-Moltbook-Ambassador/1.x');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'GitHub public repository request failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_requestTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          throw const FormatException(
            'GitHub public repository response exceeds its limit',
          );
        }
      }
      return jsonDecode(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}
