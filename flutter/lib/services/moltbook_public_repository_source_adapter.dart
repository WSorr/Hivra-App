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
    final commit = Map<String, dynamic>.from(latest.single as Map);
    final sha = _commitSha(commit['sha']);
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
    if (DateTime.tryParse(
          Map<String, dynamic>.from(author)['date']?.toString() ?? '',
        ) ==
        null) {
      throw const FormatException('GitHub commit date is invalid');
    }
    final detailsText = _commitDetails(metadataJson['message']);
    final facts = <String>[
      'Commit summary: $subject',
      if (detailsText != null) 'Commit detail: $detailsText',
      'A new public repository commit was observed at ${sha.substring(0, 12)}.',
    ];
    return (sourceId: 'github-news-v2-$sha', facts: facts);
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

  static String? _commitDetails(Object? value) {
    if (value is! String) return null;
    final lines = value.split(RegExp(r'[\r\n]+')).skip(1);
    for (final raw in lines) {
      final line = raw.trim();
      if (line.length >= 16 &&
          line.length <= 220 &&
          !_unsafeText.hasMatch(line)) {
        return line;
      }
    }
    return null;
  }

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
