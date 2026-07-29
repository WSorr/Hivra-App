import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/moltbook_provider_models.dart';

typedef MoltbookHttpSender =
    Future<MoltbookHttpResponse> Function(MoltbookHttpRequest request);

abstract interface class MoltbookObservePort {
  Future<MoltbookAccountObservation> observeAccount(String apiKey);

  Future<MoltbookHomeObservation> observeHome(String apiKey);

  Future<MoltbookFeedObservation> observeFeed(
    String apiKey, {
    String sort = 'new',
    int limit = 15,
    String? cursor,
  });
}

class MoltbookHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;

  const MoltbookHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.bodyBytes,
  });
}

class MoltbookHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  const MoltbookHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });
}

class MoltbookProviderException implements Exception {
  final String code;
  final String message;
  final bool retryable;
  final int? retryAfterSeconds;

  const MoltbookProviderException({
    required this.code,
    required this.message,
    required this.retryable,
    this.retryAfterSeconds,
  });

  @override
  String toString() => 'MoltbookProviderException($code): $message';
}

class MoltbookProviderAdapter implements MoltbookObservePort {
  static final Uri apiBaseUri = Uri.parse('https://www.moltbook.com/api/v1/');
  static const int maxResponseBytes = 256 * 1024;
  static const Duration defaultRequestTimeout = Duration(seconds: 12);

  final MoltbookHttpSender _send;
  final Duration _requestTimeout;

  MoltbookProviderAdapter({
    MoltbookHttpSender? send,
    Duration requestTimeout = defaultRequestTimeout,
  }) : _send = send ?? _sendStrict,
       _requestTimeout = requestTimeout;

  @override
  Future<MoltbookAccountObservation> observeAccount(String apiKey) async {
    final response = await _get('agents/me', apiKey);
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    final rawAgent = json['agent'];
    if (rawAgent is! Map) {
      throw _malformed('Account response has no agent object');
    }
    final agent = Map<String, dynamic>.from(rawAgent);
    final observation = MoltbookAccountObservation(
      accountId: _requiredString(agent, 'id'),
      name: _requiredString(agent, 'name'),
      description: _optionalString(agent, 'description'),
      karma: _requiredNonNegativeInt(agent, 'karma'),
      followerCount: _requiredNonNegativeInt(agent, 'follower_count'),
      followingCount: _requiredNonNegativeInt(agent, 'following_count'),
      postsCount: _requiredNonNegativeInt(agent, 'posts_count'),
      commentsCount: _requiredNonNegativeInt(agent, 'comments_count'),
      isClaimed: _requiredBool(agent, 'is_claimed'),
      isActive: _requiredBool(agent, 'is_active'),
      rateLimit: _rateLimit(response),
    );
    _validateObservation(observation.validate);
    return observation;
  }

  @override
  Future<MoltbookHomeObservation> observeHome(String apiKey) async {
    final response = await _get('home', apiKey);
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    final rawAccount = json['your_account'];
    if (rawAccount is! Map) {
      throw _malformed('Home response has no your_account object');
    }
    final account = Map<String, dynamic>.from(rawAccount);
    final rawActions = json['what_to_do_next'];
    if (rawActions is! List) {
      throw _malformed('Home response has no what_to_do_next list');
    }
    final actions = rawActions
        .map((value) {
          if (value is! String || value.trim().isEmpty) {
            throw _malformed('Home suggested action is invalid');
          }
          return value.trim();
        })
        .toList(growable: false);
    final observation = MoltbookHomeObservation(
      accountName: _requiredString(account, 'name'),
      karma: _requiredNonNegativeInt(account, 'karma'),
      unreadNotificationCount: _requiredNonNegativeInt(
        account,
        'unread_notification_count',
      ),
      suggestedActions: actions,
      rateLimit: _rateLimit(response),
    );
    _validateObservation(observation.validate);
    return observation;
  }

  @override
  Future<MoltbookFeedObservation> observeFeed(
    String apiKey, {
    String sort = 'new',
    int limit = 15,
    String? cursor,
  }) async {
    if (!const <String>{'hot', 'new', 'top', 'rising'}.contains(sort)) {
      throw const MoltbookProviderException(
        code: 'invalid_feed_sort',
        message: 'Moltbook feed sort is invalid',
        retryable: false,
      );
    }
    if (limit < 1 || limit > 25) {
      throw const MoltbookProviderException(
        code: 'invalid_feed_limit',
        message: 'Moltbook feed limit must be within 1..25',
        retryable: false,
      );
    }
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null &&
        (normalizedCursor.isEmpty || normalizedCursor.length > 2048)) {
      throw const MoltbookProviderException(
        code: 'invalid_feed_cursor',
        message: 'Moltbook feed cursor is invalid',
        retryable: false,
      );
    }
    final query = <String, String>{
      'sort': sort,
      'limit': '$limit',
      if (normalizedCursor != null) 'cursor': normalizedCursor,
    };
    final relativeUri = Uri(path: 'posts', queryParameters: query);
    final response = await _get(relativeUri.toString(), apiKey);
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    final rawPosts = json['posts'];
    if (rawPosts is! List || json['has_more'] is! bool) {
      throw _malformed('Feed response has invalid paging fields');
    }
    final posts = rawPosts
        .map((value) {
          if (value is! Map) {
            throw _malformed('Feed response contains an invalid post');
          }
          final post = Map<String, dynamic>.from(value);
          final rawAuthor = post['author'];
          final rawSubmolt = post['submolt'];
          if (rawAuthor is! Map || rawSubmolt is! Map) {
            throw _malformed('Feed post identity projection is invalid');
          }
          final author = Map<String, dynamic>.from(rawAuthor);
          final submolt = Map<String, dynamic>.from(rawSubmolt);
          final timestamp =
              DateTime.tryParse(_requiredString(post, 'created_at'))?.toUtc();
          if (timestamp == null) {
            throw _malformed('Feed post timestamp is invalid');
          }
          return MoltbookFeedPost(
            postId: _requiredString(post, 'id'),
            title: _requiredString(post, 'title'),
            content: _optionalString(post, 'content'),
            authorId: _requiredString(author, 'id'),
            authorName: _requiredString(author, 'name'),
            submoltName: _requiredString(submolt, 'name'),
            score: _requiredNonNegativeInt(post, 'score'),
            commentCount: _requiredNonNegativeInt(post, 'comment_count'),
            isVerified:
                _requiredString(post, 'verification_status') == 'verified',
            isSpam: _requiredBool(post, 'is_spam'),
            createdAtUtc: timestamp.toIso8601String(),
          );
        })
        .toList(growable: false);
    final hasMore = json['has_more'] as bool;
    final rawCursor = json['next_cursor'];
    if (rawCursor != null && rawCursor is! String) {
      throw _malformed('Feed response cursor is invalid');
    }
    final observation = MoltbookFeedObservation(
      posts: posts,
      hasMore: hasMore,
      nextCursor: rawCursor as String?,
      rateLimit: _rateLimit(response),
    );
    _validateObservation(observation.validate);
    return observation;
  }

  Future<MoltbookClaimObservation> observeClaimStatus(String apiKey) async {
    final response = await _get('agents/status', apiKey);
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    final observation = MoltbookClaimObservation(
      status: _requiredString(json, 'status'),
      rateLimit: _rateLimit(response),
    );
    _validateObservation(observation.validate);
    return observation;
  }

  Future<Map<String, dynamic>> createPost({
    required String apiKey,
    required String submoltName,
    required String title,
    required String content,
  }) async {
    final response = await _request(
      method: 'POST',
      relativePath: 'posts',
      apiKey: apiKey,
      body: <String, dynamic>{
        'submolt_name': submoltName,
        'title': title,
        'content': content,
      },
    );
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    return json;
  }

  Future<Map<String, dynamic>> observeProfile({
    required String apiKey,
    required String accountName,
  }) async {
    final response = await _request(
      method: 'GET',
      relativePath:
          'agents/profile?name=${Uri.encodeQueryComponent(accountName)}',
      apiKey: apiKey,
    );
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    return json;
  }

  Future<Map<String, dynamic>> verifyContent({
    required String apiKey,
    required String verificationCode,
    required String answer,
  }) async {
    final response = await _request(
      method: 'POST',
      relativePath: 'verify',
      apiKey: apiKey,
      body: <String, dynamic>{
        'verification_code': verificationCode,
        'answer': answer,
      },
    );
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    return json;
  }

  Future<Map<String, dynamic>> observePost({
    required String apiKey,
    required String postId,
  }) async {
    final normalizedId = postId.trim();
    if (!RegExp(r'^[A-Za-z0-9-]{1,256}$').hasMatch(normalizedId)) {
      throw const MoltbookProviderException(
        code: 'invalid_post_id',
        message: 'Moltbook post id is invalid',
        retryable: false,
      );
    }
    final response = await _request(
      method: 'GET',
      relativePath: 'posts/${Uri.encodeComponent(normalizedId)}',
      apiKey: apiKey,
    );
    final json = _decodeObject(response);
    _rejectProviderFailure(json, response);
    return json;
  }

  Future<MoltbookHttpResponse> _get(String relativePath, String apiKey) async {
    return _request(method: 'GET', relativePath: relativePath, apiKey: apiKey);
  }

  Future<MoltbookHttpResponse> _request({
    required String method,
    required String relativePath,
    required String apiKey,
    Map<String, dynamic>? body,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty || normalizedKey.length > 1024) {
      throw const MoltbookProviderException(
        code: 'invalid_credential',
        message: 'Moltbook API key is empty or too large',
        retryable: false,
      );
    }
    final uri = apiBaseUri.resolve(relativePath);
    _validateEndpoint(uri);
    if (method != 'GET' && method != 'POST') {
      throw const MoltbookProviderException(
        code: 'method_not_allowed',
        message: 'Moltbook adapter only permits GET and POST',
        retryable: false,
      );
    }
    final bodyBytes =
        body == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    MoltbookHttpResponse response;
    try {
      response = await _send(
        MoltbookHttpRequest(
          method: method,
          uri: uri,
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer $normalizedKey',
            if (bodyBytes != null)
              HttpHeaders.contentTypeHeader: 'application/json',
          },
          bodyBytes: bodyBytes,
        ),
      ).timeout(_requestTimeout);
    } on TimeoutException {
      throw const MoltbookProviderException(
        code: 'timeout',
        message: 'Moltbook request timed out',
        retryable: true,
      );
    } on MoltbookProviderException {
      rethrow;
    } catch (error) {
      throw MoltbookProviderException(
        code: 'network_error',
        message: 'Moltbook network request failed: $error',
        retryable: true,
      );
    }
    if (response.bodyBytes.length > maxResponseBytes) {
      throw const MoltbookProviderException(
        code: 'response_too_large',
        message: 'Moltbook response exceeded the size limit',
        retryable: false,
      );
    }
    _rejectHttpFailure(response);
    return response;
  }

  static Future<MoltbookHttpResponse> _sendStrict(
    MoltbookHttpRequest request,
  ) async {
    _validateEndpoint(request.uri);
    if (request.method != 'GET' && request.method != 'POST') {
      throw const MoltbookProviderException(
        code: 'method_not_allowed',
        message: 'Moltbook transport only permits GET and POST',
        retryable: false,
      );
    }
    final client = HttpClient()..connectionTimeout = defaultRequestTimeout;
    try {
      final outgoing = await client
          .openUrl(request.method, request.uri)
          .timeout(defaultRequestTimeout);
      outgoing.followRedirects = false;
      outgoing.maxRedirects = 0;
      request.headers.forEach(outgoing.headers.set);
      final bodyBytes = request.bodyBytes;
      if (bodyBytes != null) {
        outgoing.add(bodyBytes);
      }
      final incoming = await outgoing.close().timeout(defaultRequestTimeout);
      if (incoming.isRedirect ||
          (incoming.statusCode >= 300 && incoming.statusCode < 400)) {
        throw const MoltbookProviderException(
          code: 'redirect_rejected',
          message: 'Moltbook redirects are not permitted',
          retryable: false,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in incoming.timeout(defaultRequestTimeout)) {
        if (builder.length + chunk.length > maxResponseBytes) {
          throw const MoltbookProviderException(
            code: 'response_too_large',
            message: 'Moltbook response exceeded the size limit',
            retryable: false,
          );
        }
        builder.add(chunk);
      }
      final headers = <String, String>{};
      incoming.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      return MoltbookHttpResponse(
        statusCode: incoming.statusCode,
        headers: headers,
        bodyBytes: builder.takeBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static void _validateEndpoint(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'www.moltbook.com' ||
        uri.port != 443 ||
        !uri.path.startsWith('/api/v1/')) {
      throw const MoltbookProviderException(
        code: 'endpoint_not_allowed',
        message: 'Moltbook endpoint is outside the pinned API origin',
        retryable: false,
      );
    }
  }

  static Map<String, dynamic> _decodeObject(MoltbookHttpResponse response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('response root is not an object');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      throw _malformed('Moltbook returned malformed JSON: $error');
    }
  }

  static void _rejectProviderFailure(
    Map<String, dynamic> json,
    MoltbookHttpResponse response,
  ) {
    if (json['success'] != false) return;
    final message =
        json['error']?.toString().trim().isNotEmpty == true
            ? json['error'].toString().trim()
            : 'Moltbook rejected the request';
    throw MoltbookProviderException(
      code: 'provider_rejected',
      message: message,
      retryable: false,
      retryAfterSeconds: _rateLimit(response).retryAfterSeconds,
    );
  }

  static void _rejectHttpFailure(MoltbookHttpResponse response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status >= 300 && status < 400) {
      throw const MoltbookProviderException(
        code: 'redirect_rejected',
        message: 'Moltbook redirects are not permitted',
        retryable: false,
      );
    }
    final retryAfter = _rateLimit(response).retryAfterSeconds;
    if (status == 401 || status == 403) {
      throw const MoltbookProviderException(
        code: 'credential_rejected',
        message: 'Moltbook rejected the API credential',
        retryable: false,
      );
    }
    if (status == 429) {
      throw MoltbookProviderException(
        code: 'rate_limited',
        message: 'Moltbook rate limit exceeded',
        retryable: true,
        retryAfterSeconds: retryAfter,
      );
    }
    if (status == 408 || status >= 500) {
      throw MoltbookProviderException(
        code: 'provider_unavailable',
        message: 'Moltbook is temporarily unavailable (HTTP $status)',
        retryable: true,
        retryAfterSeconds: retryAfter,
      );
    }
    throw MoltbookProviderException(
      code: 'http_$status',
      message: 'Moltbook rejected the request (HTTP $status)',
      retryable: false,
    );
  }

  static MoltbookRateLimitSnapshot _rateLimit(MoltbookHttpResponse response) {
    final headers = response.headers.map(
      (key, value) => MapEntry(key.toLowerCase(), value.trim()),
    );
    final snapshot = MoltbookRateLimitSnapshot(
      limit: _optionalHeaderInt(headers, 'x-ratelimit-limit'),
      remaining: _optionalHeaderInt(headers, 'x-ratelimit-remaining'),
      resetEpochSeconds: _optionalHeaderInt(headers, 'x-ratelimit-reset'),
      retryAfterSeconds: _optionalHeaderInt(headers, 'retry-after'),
    );
    snapshot.validate();
    return snapshot;
  }

  static int? _optionalHeaderInt(Map<String, String> headers, String name) {
    final raw = headers[name];
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw _malformed('Invalid Moltbook $name header');
    }
    return value;
  }

  static String _requiredString(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! String || value.trim().isEmpty) {
      throw _malformed('Moltbook field $field must be a non-empty string');
    }
    return value.trim();
  }

  static String _optionalString(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value == null) return '';
    if (value is! String) {
      throw _malformed('Moltbook field $field must be a string');
    }
    return value.trim();
  }

  static int _requiredNonNegativeInt(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! int || value < 0) {
      throw _malformed('Moltbook field $field must be a non-negative integer');
    }
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! bool) {
      throw _malformed('Moltbook field $field must be a boolean');
    }
    return value;
  }

  static MoltbookProviderException _malformed(String message) {
    return MoltbookProviderException(
      code: 'malformed_response',
      message: message,
      retryable: false,
    );
  }

  static void _validateObservation(void Function() validate) {
    try {
      validate();
    } on FormatException catch (error) {
      throw _malformed('Moltbook response validation failed: ${error.message}');
    }
  }
}
