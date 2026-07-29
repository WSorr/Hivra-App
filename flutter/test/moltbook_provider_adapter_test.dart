import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/moltbook_provider_adapter.dart';

void main() {
  test('observes and normalizes the authenticated account', () async {
    late MoltbookHttpRequest captured;
    final adapter = MoltbookProviderAdapter(
      send: (request) async {
        captured = request;
        return _jsonResponse(
          <String, dynamic>{
            'success': true,
            'agent': <String, dynamic>{
              'id': 'agent-123',
              'name': 'HivraAmbassador',
              'description': 'Capsule development updates',
              'karma': 12,
              'follower_count': 3,
              'following_count': 4,
              'posts_count': 5,
              'comments_count': 6,
              'is_claimed': true,
              'is_active': true,
            },
          },
          headers: const <String, String>{
            'X-RateLimit-Limit': '60',
            'X-RateLimit-Remaining': '59',
            'X-RateLimit-Reset': '1900000000',
          },
        );
      },
    );

    final result = await adapter.observeAccount('moltbook_secret');

    expect(captured.method, 'GET');
    expect(
      captured.uri.toString(),
      'https://www.moltbook.com/api/v1/agents/me',
    );
    expect(captured.headers['authorization'], 'Bearer moltbook_secret');
    expect(result.accountId, 'agent-123');
    expect(result.name, 'HivraAmbassador');
    expect(result.rateLimit.remaining, 59);
  });

  test(
    'observes bounded home projection without provider DTO leakage',
    () async {
      final adapter = MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'your_account': <String, dynamic>{
                'name': 'HivraAmbassador',
                'karma': 8,
                'unread_notification_count': 2,
              },
              'what_to_do_next': <String>[
                'Read two replies',
                'Review the following feed',
              ],
              'quick_links': <String, dynamic>{
                'ignored_provider_field': '/api/v1/feed',
              },
            }),
      );

      final result = await adapter.observeHome('moltbook_secret');

      expect(result.accountName, 'HivraAmbassador');
      expect(result.unreadNotificationCount, 2);
      expect(result.suggestedActions, <String>[
        'Read two replies',
        'Review the following feed',
      ]);
    },
  );

  test('observes and normalizes a bounded public feed', () async {
    late MoltbookHttpRequest captured;
    final adapter = MoltbookProviderAdapter(
      send: (request) async {
        captured = request;
        return _jsonResponse(<String, dynamic>{
          'success': true,
          'posts': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'post-1',
              'title': 'Deterministic effects',
              'content': 'A timeout is not a failure receipt.',
              'author': <String, dynamic>{
                'id': 'author-1',
                'name': 'ReliableAgent',
              },
              'submolt': <String, dynamic>{'name': 'general'},
              'score': 4,
              'comment_count': 2,
              'verification_status': 'verified',
              'is_spam': false,
              'created_at': '2026-07-29T10:00:00.000Z',
            },
          ],
          'has_more': true,
          'next_cursor': 'cursor-1',
        });
      },
    );

    final result = await adapter.observeFeed('secret', limit: 15);

    expect(captured.method, 'GET');
    expect(
      captured.uri.toString(),
      'https://www.moltbook.com/api/v1/posts?sort=new&limit=15',
    );
    expect(result.posts.single.postId, 'post-1');
    expect(result.posts.single.authorName, 'ReliableAgent');
    expect(result.posts.single.createdAtUtc, '2026-07-29T10:00:00.000Z');
    expect(result.nextCursor, 'cursor-1');
  });

  test('rejects malformed feed paging instead of inventing a cursor', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(<String, dynamic>{
            'posts': <dynamic>[],
            'has_more': true,
          }),
    );

    await expectLater(
      adapter.observeFeed('secret'),
      throwsA(_providerError('malformed_response', retryable: false)),
    );
  });

  test('observes only supported claim states', () async {
    final adapter = MoltbookProviderAdapter(
      send: (_) async => _jsonResponse(<String, dynamic>{'status': 'claimed'}),
    );

    final result = await adapter.observeClaimStatus('key');

    expect(result.status, 'claimed');
  });

  test('submits verification only to the pinned verify endpoint', () async {
    late MoltbookHttpRequest captured;
    final adapter = MoltbookProviderAdapter(
      send: (request) async {
        captured = request;
        return _jsonResponse(<String, dynamic>{
          'success': true,
          'content_type': 'post',
          'content_id': 'post-123',
        });
      },
    );

    final result = await adapter.verifyContent(
      apiKey: 'moltbook_secret',
      verificationCode: 'verify-123',
      answer: '4.00',
    );

    expect(captured.method, 'POST');
    expect(captured.uri.toString(), 'https://www.moltbook.com/api/v1/verify');
    expect(captured.headers['authorization'], 'Bearer moltbook_secret');
    expect(jsonDecode(utf8.decode(captured.bodyBytes!)), <String, dynamic>{
      'verification_code': 'verify-123',
      'answer': '4.00',
    });
    expect(result['content_id'], 'post-123');
  });

  test('rejects credentials before making a request', () async {
    var calls = 0;
    final adapter = MoltbookProviderAdapter(
      send: (_) async {
        calls += 1;
        return _jsonResponse(<String, dynamic>{});
      },
    );

    await expectLater(
      adapter.observeAccount('  '),
      throwsA(_providerError('invalid_credential', retryable: false)),
    );
    expect(calls, 0);
  });

  test('maps credential rejection to terminal failure', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(<String, dynamic>{
            'success': false,
            'error': 'Unauthorized',
          }, statusCode: 401),
    );

    await expectLater(
      adapter.observeAccount('bad-key'),
      throwsA(_providerError('credential_rejected', retryable: false)),
    );
  });

  test('maps rate limit with retry-after to retryable failure', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(
            <String, dynamic>{'message': 'Rate limit exceeded'},
            statusCode: 429,
            headers: const <String, String>{'Retry-After': '45'},
          ),
    );

    await expectLater(
      adapter.observeHome('key'),
      throwsA(
        isA<MoltbookProviderException>()
            .having((error) => error.code, 'code', 'rate_limited')
            .having((error) => error.retryable, 'retryable', isTrue)
            .having(
              (error) => error.retryAfterSeconds,
              'retryAfterSeconds',
              45,
            ),
      ),
    );
  });

  test('rejects malformed response instead of inventing defaults', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(<String, dynamic>{
            'success': true,
            'agent': <String, dynamic>{'name': 'missing required fields'},
          }),
    );

    await expectLater(
      adapter.observeAccount('key'),
      throwsA(_providerError('malformed_response', retryable: false)),
    );
  });

  test('rejects unknown claim state', () async {
    final adapter = MoltbookProviderAdapter(
      send: (_) async => _jsonResponse(<String, dynamic>{'status': 'unknown'}),
    );

    await expectLater(
      adapter.observeClaimStatus('key'),
      throwsA(_providerError('malformed_response', retryable: false)),
    );
  });

  test('rejects oversized responses from an injected transport', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => MoltbookHttpResponse(
            statusCode: 200,
            headers: const <String, String>{},
            bodyBytes: Uint8List(MoltbookProviderAdapter.maxResponseBytes + 1),
          ),
    );

    await expectLater(
      adapter.observeHome('key'),
      throwsA(_providerError('response_too_large', retryable: false)),
    );
  });

  test('rejects malformed rate-limit headers', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(
            <String, dynamic>{
              'your_account': <String, dynamic>{
                'name': 'HivraAmbassador',
                'karma': 0,
                'unread_notification_count': 0,
              },
              'what_to_do_next': <String>['Wait'],
            },
            headers: const <String, String>{'X-RateLimit-Remaining': 'many'},
          ),
    );

    await expectLater(
      adapter.observeHome('key'),
      throwsA(_providerError('malformed_response', retryable: false)),
    );
  });

  test('rejects redirects even through an injected transport', () async {
    final adapter = MoltbookProviderAdapter(
      send:
          (_) async => _jsonResponse(
            <String, dynamic>{},
            statusCode: 302,
            headers: const <String, String>{
              'location': 'https://moltbook.com/api/v1/home',
            },
          ),
    );

    await expectLater(
      adapter.observeHome('key'),
      throwsA(_providerError('redirect_rejected', retryable: false)),
    );
  });

  test('maps request timeout to retryable failure', () async {
    final adapter = MoltbookProviderAdapter(
      requestTimeout: const Duration(milliseconds: 5),
      send:
          (_) => Future<MoltbookHttpResponse>.delayed(
            const Duration(seconds: 1),
            () => _jsonResponse(<String, dynamic>{}),
          ),
    );

    await expectLater(
      adapter.observeHome('key'),
      throwsA(_providerError('timeout', retryable: true)),
    );
  });
}

MoltbookHttpResponse _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) {
  return MoltbookHttpResponse(
    statusCode: statusCode,
    headers: headers,
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
}

Matcher _providerError(String code, {required bool retryable}) {
  return isA<MoltbookProviderException>()
      .having((error) => error.code, 'code', code)
      .having((error) => error.retryable, 'retryable', retryable);
}
