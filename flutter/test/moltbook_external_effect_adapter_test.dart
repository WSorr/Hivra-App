import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/moltbook_external_effect_adapter.dart';
import 'package:hivra_app/services/moltbook_provider_adapter.dart';

void main() {
  late _FakeSecureStorage storage;
  late CapsuleScopedSecretVault vault;

  setUp(() async {
    storage = _FakeSecureStorage();
    vault = CapsuleScopedSecretVault(secureStorage: storage);
    await vault.saveSecret(
      capsuleHex: _owner,
      pluginId: moltbookAmbassadorPluginId,
      providerId: 'moltbook',
      accountId: 'account-1',
      secretName: 'api_key',
      secretValue: 'secret-1',
    );
  });

  test('publishes exact payload and returns a bound receipt', () async {
    late MoltbookHttpRequest captured;
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send: (request) async {
          captured = request;
          return _jsonResponse(<String, dynamic>{
            'success': true,
            'post': <String, dynamic>{'id': 'post-123'},
          });
        },
      ),
      clock: () => DateTime.utc(2026, 7, 26, 14),
    );

    final result = await adapter.deliver(_request());

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'post-123');
    expect(captured.method, 'POST');
    expect(captured.headers['authorization'], 'Bearer secret-1');
    final body = jsonDecode(utf8.decode(captured.bodyBytes!));
    expect(body['submolt_name'], 'general');
    expect(body['title'], 'Release note');
    expect(
      body['content'],
      'Public fact\n\n[Hivra on GitHub](https://github.com/WSorr/Hivra-App)',
    );
    expect(body['content'], isNot(contains('hivra-effect:')));
  });

  test('publishes exact reviewed reply through comment effect', () async {
    late MoltbookHttpRequest captured;
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send: (request) async {
          captured = request;
          return _jsonResponse(<String, dynamic>{
            'success': true,
            'comment': <String, dynamic>{'id': 'comment-2'},
          });
        },
      ),
    );

    final result = await adapter.deliver(_commentRequest());

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'comment-2');
    expect(captured.uri.path, '/api/v1/posts/post-1/comments');
    expect(jsonDecode(utf8.decode(captured.bodyBytes!)), <String, dynamic>{
      'content': 'A bounded reviewed reply.',
      'parent_id': 'comment-1',
    });
  });

  test('accepts a target-bound v2 reply payload', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'comment': <String, dynamic>{'id': 'comment-v2'},
            }),
      ),
    );

    final result = await adapter.deliver(_commentRequest(schemaVersion: 2));

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'comment-v2');
  });

  test(
    'keeps legacy operation markers readable for existing effects',
    () async {
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send:
              (_) async => _jsonResponse(<String, dynamic>{
                'success': true,
                'post': <String, dynamic>{'id': 'legacy-post'},
              }),
        ),
      );

      final result = await adapter.deliver(_legacyRequest());

      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(result.receipt?.providerReceiptId, 'legacy-post');
    },
  );

  test('verification challenge never becomes a successful receipt', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'post': <String, dynamic>{'id': 'hidden-post'},
              'verification_required': true,
              'verification': <String, dynamic>{'challenge': '2 + 2'},
            }),
      ),
    );

    final result = await adapter.deliver(_request());

    expect(result.status, ExternalEffectAdapterStatus.unresolved);
    expect(result.errorCode, 'verification_required');
    expect(result.receipt, isNull);
  });

  test('nested post verification challenge never becomes success', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'post': <String, dynamic>{
                'id': 'hidden-post-123',
                'verification_status': 'pending',
                'verification': <String, dynamic>{
                  'verification_code': 'verify-123',
                  'challenge_text': 'two plus two',
                  'expires_at': '2026-07-26T14:05:00.000Z',
                },
              },
            }),
      ),
      clock: () => DateTime.utc(2026, 7, 26, 14),
    );

    final result = await adapter.deliver(_request());

    expect(result.status, ExternalEffectAdapterStatus.unresolved);
    expect(result.errorCode, 'verification_required');
    expect(result.receipt, isNull);
    expect(result.requiredAction?.providerReferenceId, 'hidden-post-123');
    expect(result.requiredAction?.actionToken, 'verify-123');
    expect(result.requiredAction?.prompt, 'two plus two');
  });

  test('verification success becomes the bound provider receipt', () async {
    final requests = <MoltbookHttpRequest>[];
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send: (request) async {
          requests.add(request);
          if (request.uri.path.endsWith('/verify')) {
            return _jsonResponse(<String, dynamic>{
              'success': true,
              'content_type': 'post',
              'content_id': 'hidden-post-123',
            });
          }
          if (request.uri.path.endsWith('/posts/hidden-post-123')) {
            return _postResponse('hidden-post-123');
          }
          throw StateError('Unexpected request: ${request.uri}');
        },
      ),
      clock: () => DateTime.utc(2026, 7, 26, 14, 1),
    );
    const action = ExternalEffectRequiredAction(
      kind: 'numeric_challenge',
      providerReferenceId: 'hidden-post-123',
      actionToken: 'verify-123',
      prompt: 'two plus two',
      expiresAtUtc: '2026-07-26T14:05:00.000Z',
    );

    final result = await adapter.resolveRequiredAction(_request(), action, '4');

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'hidden-post-123');
    expect(requests.map((request) => request.uri.path), <String>[
      '/api/v1/verify',
      '/api/v1/posts/hidden-post-123',
    ]);
    final verifyBody = jsonDecode(utf8.decode(requests.first.bodyBytes!));
    expect(verifyBody['answer'], '4.00');
  });

  test('verification for another post remains unresolved', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'content_type': 'post',
              'content_id': 'another-post',
            }),
      ),
      clock: () => DateTime.utc(2026, 7, 26, 14, 1),
    );
    const action = ExternalEffectRequiredAction(
      kind: 'numeric_challenge',
      providerReferenceId: 'hidden-post-123',
      actionToken: 'verify-123',
      prompt: 'two plus two',
      expiresAtUtc: '2026-07-26T14:05:00.000Z',
    );

    final result = await adapter.resolveRequiredAction(_request(), action, '4');

    expect(result.status, ExternalEffectAdapterStatus.unresolved);
    expect(result.errorCode, 'verification_rejected');
    expect(result.receipt, isNull);
    expect(result.requiredAction, action);
    expect(result.requiredActionResolved, isFalse);
  });

  test(
    'accepted verification clears challenge while receipt visibility catches up',
    () async {
      final requests = <MoltbookHttpRequest>[];
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send: (request) async {
            requests.add(request);
            if (request.uri.path.endsWith('/verify')) {
              return _jsonResponse(<String, dynamic>{
                'success': true,
                'content_type': 'post',
                'content_id': 'hidden-post-123',
              });
            }
            if (request.uri.path.endsWith('/posts/hidden-post-123')) {
              return _postResponse(
                'hidden-post-123',
                verificationStatus: 'pending',
              );
            }
            throw StateError('Unexpected request: ${request.uri}');
          },
        ),
        clock: () => DateTime.utc(2026, 7, 26, 14, 1),
      );
      const action = ExternalEffectRequiredAction(
        kind: 'numeric_challenge',
        providerReferenceId: 'hidden-post-123',
        actionToken: 'verify-123',
        prompt: 'two plus two',
        expiresAtUtc: '2026-07-26T14:05:00.000Z',
      );

      final result = await adapter.resolveRequiredAction(
        _request(),
        action,
        '4',
      );

      expect(result.status, ExternalEffectAdapterStatus.unresolved);
      expect(result.errorCode, 'receipt_not_observed');
      expect(result.requiredAction, isNull);
      expect(result.requiredActionResolved, isTrue);
      expect(result.providerReferenceId, 'hidden-post-123');
      expect(requests.map((request) => request.uri.path), <String>[
        '/api/v1/verify',
        '/api/v1/posts/hidden-post-123',
      ]);
      final verifyBody = jsonDecode(utf8.decode(requests.first.bodyBytes!));
      expect(verifyBody['answer'], '4.00');
    },
  );

  test('missing reconciliation marker blocks blind resubmission', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'agent': <String, dynamic>{'name': 'HivraAgent'},
              'recentPosts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'other-post',
                  'title': 'Other',
                  'content': 'No operation marker',
                },
              ],
            }),
      ),
    );

    final result = await adapter.reconcile(_request());

    expect(result.status, ExternalEffectAdapterStatus.unresolved);
    expect(result.errorCode, 'receipt_not_observed');
  });

  test(
    'reconciles v2 publication by exact approved title and content',
    () async {
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send:
              (_) async => _jsonResponse(<String, dynamic>{
                'success': true,
                'agent': <String, dynamic>{'name': 'HivraAgent'},
                'recentPosts': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'matched-post',
                    'title': 'Release note',
                    'content':
                        'Public fact\n\n'
                        '[Hivra on GitHub](https://github.com/WSorr/Hivra-App)',
                    'verification_status': 'verified',
                    'is_spam': false,
                  },
                ],
              }),
        ),
      );

      final result = await adapter.reconcile(_request());

      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(result.receipt?.providerReceiptId, 'matched-post');
    },
  );

  test(
    'reconciles a durable provider reference by exact post lookup',
    () async {
      final requests = <MoltbookHttpRequest>[];
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send: (request) async {
            requests.add(request);
            return _postResponse('matched-post');
          },
        ),
      );

      final result = await adapter.reconcile(
        _request(providerReferenceId: 'matched-post'),
      );

      expect(result.status, ExternalEffectAdapterStatus.succeeded);
      expect(result.receipt?.providerReceiptId, 'matched-post');
      expect(requests.single.uri.path, '/api/v1/posts/matched-post');
    },
  );

  test(
    'rejects a provider reference whose exact post payload differs',
    () async {
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send:
              (_) async =>
                  _postResponse('wrong-post', title: 'Different title'),
        ),
      );

      final result = await adapter.reconcile(
        _request(providerReferenceId: 'wrong-post'),
      );

      expect(result.status, ExternalEffectAdapterStatus.unresolved);
      expect(result.errorCode, 'receipt_not_observed');
      expect(result.receipt, isNull);
    },
  );

  test('keeps v1 marker reconciliation for existing queued effects', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'agent': <String, dynamic>{'name': 'HivraAgent'},
              'recentPosts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'legacy-matched-post',
                  'title': 'Release note',
                  'content':
                      'Public fact\n\n'
                      '[Hivra on GitHub]'
                      '(https://github.com/WSorr/Hivra-App#'
                      'hivra-effect:post-1)',
                  'verification_status': 'verified',
                  'is_spam': false,
                },
              ],
            }),
      ),
    );

    final result = await adapter.reconcile(_legacyCurrentMarkerRequest());

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'legacy-matched-post');
  });

  test('does not reconcile hidden or spam-moderated posts', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send:
            (_) async => _jsonResponse(<String, dynamic>{
              'success': true,
              'agent': <String, dynamic>{'name': 'HivraAgent'},
              'recentPosts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'hidden-match',
                  'title': 'Release note',
                  'content':
                      'Public fact\n\n'
                      '[Hivra on GitHub](https://github.com/WSorr/Hivra-App)',
                  'verification_status': 'pending',
                  'is_spam': false,
                },
                <String, dynamic>{
                  'id': 'spam-match',
                  'title': 'Release note',
                  'content':
                      'Public fact\n\n'
                      '[Hivra on GitHub](https://github.com/WSorr/Hivra-App)',
                  'verification_status': 'verified',
                  'is_spam': true,
                },
              ],
            }),
      ),
    );

    final result = await adapter.reconcile(_request());

    expect(result.status, ExternalEffectAdapterStatus.unresolved);
    expect(result.errorCode, 'receipt_not_observed');
    expect(result.receipt, isNull);
  });

  test('reconciles reply only by exact target, author, and content', () async {
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send: (request) async {
          if (request.uri.path.endsWith('/comments')) {
            return _jsonResponse(<String, dynamic>{
              'post_id': 'post-1',
              'sort': 'new',
              'comments': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'comment-2',
                  'content': 'A bounded reviewed reply.',
                  'parent_id': 'comment-1',
                  'upvotes': 0,
                  'downvotes': 0,
                  'created_at': '2026-07-29T10:05:00.000Z',
                  'author': <String, dynamic>{
                    'id': 'agent-1',
                    'name': 'HivraAgent',
                  },
                },
              ],
              'has_more': false,
            });
          }
          return _jsonResponse(<String, dynamic>{
            'post': <String, dynamic>{
              'id': 'post-1',
              'title': 'Post',
              'content': 'Body',
              'author': <String, dynamic>{'id': 'writer', 'name': 'Writer'},
              'submolt': <String, dynamic>{'name': 'general'},
              'score': 0,
              'comment_count': 1,
              'verification_status': 'verified',
              'is_spam': false,
              'is_locked': false,
              'created_at': '2026-07-29T10:00:00.000Z',
              'updated_at': '2026-07-29T10:05:00.000Z',
            },
          });
        },
      ),
    );

    final result = await adapter.reconcile(_commentRequest());

    expect(result.status, ExternalEffectAdapterStatus.succeeded);
    expect(result.receipt?.providerReceiptId, 'comment-2');
  });

  test('credential lookup is bound to originating capsule scope', () async {
    final request = _request(owner: _otherOwner);
    var networkCalls = 0;
    final adapter = MoltbookExternalEffectAdapter(
      secretVault: vault,
      provider: MoltbookProviderAdapter(
        send: (_) async {
          networkCalls += 1;
          return _jsonResponse(<String, dynamic>{});
        },
      ),
    );

    final result = await adapter.deliver(request);

    expect(result.status, ExternalEffectAdapterStatus.terminalFailure);
    expect(result.errorCode, 'credential_unavailable');
    expect(networkCalls, 0);
  });

  test(
    'rejects effect payload fields outside the canonical contract',
    () async {
      var networkCalls = 0;
      final adapter = MoltbookExternalEffectAdapter(
        secretVault: vault,
        provider: MoltbookProviderAdapter(
          send: (_) async {
            networkCalls += 1;
            return _jsonResponse(<String, dynamic>{});
          },
        ),
      );
      final base = _request();
      final decoded =
          jsonDecode(base.canonicalPayloadJson) as Map<String, dynamic>;
      decoded['target_url'] = 'https://attacker.invalid/publish';
      final request = ExternalEffectAdapterRequest(
        ownerCapsuleHex: base.ownerCapsuleHex,
        operationId: base.operationId,
        pluginId: base.pluginId,
        providerId: base.providerId,
        accountBindingId: base.accountBindingId,
        effectKind: base.effectKind,
        canonicalPayloadJson: jsonEncode(decoded),
        payloadHashHex: base.payloadHashHex,
      );

      final result = await adapter.deliver(request);

      expect(result.status, ExternalEffectAdapterStatus.terminalFailure);
      expect(result.errorCode, 'invalid_effect_payload');
      expect(networkCalls, 0);
    },
  );
}

ExternalEffectAdapterRequest _request({
  String owner = _owner,
  String? providerReferenceId,
}) {
  const payload =
      '{"schema_version":2,"account_name":"HivraAgent",'
      '"submolt_name":"general","title":"Release note",'
      '"content":"Public fact\\n\\n[Hivra on GitHub]'
      '(https://github.com/WSorr/Hivra-App)",'
      '"operation_marker":"hivra-effect:post-1",'
      '"source_draft_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';
  return ExternalEffectAdapterRequest(
    ownerCapsuleHex: owner,
    operationId: 'post-1',
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-1',
    effectKind: MoltbookExternalEffectAdapter.effectKind,
    canonicalPayloadJson: payload,
    payloadHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    providerReferenceId: providerReferenceId,
  );
}

ExternalEffectAdapterRequest _commentRequest({int schemaVersion = 1}) {
  final engagementField =
      schemaVersion == 2
          ? '"engagement_id":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",'
          : '';
  final payload =
      '{"schema_version":$schemaVersion,$engagementField"account_name":"HivraAgent",'
      '"post_id":"post-1","parent_comment_id":"comment-1",'
      '"content":"A bounded reviewed reply.",'
      '"operation_marker":"hivra-effect:comment-1",'
      '"source_draft_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
      '"engagement_plan_hash_hex":"cccccccccccccccccccccccccccccccc'
      'cccccccccccccccccccccccccccccccc"}';
  return ExternalEffectAdapterRequest(
    ownerCapsuleHex: _owner,
    operationId: 'comment-1',
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-1',
    effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
    canonicalPayloadJson: payload,
    payloadHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );
}

ExternalEffectAdapterRequest _legacyRequest() {
  const payload =
      '{"schema_version":1,"account_name":"HivraAgent",'
      '"submolt_name":"general","title":"Release note",'
      '"content":"Public fact\\n\\n[hivra-effect:post-1]",'
      '"operation_marker":"[hivra-effect:post-1]",'
      '"source_draft_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';
  return ExternalEffectAdapterRequest(
    ownerCapsuleHex: _owner,
    operationId: 'post-1',
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-1',
    effectKind: MoltbookExternalEffectAdapter.effectKind,
    canonicalPayloadJson: payload,
    payloadHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );
}

ExternalEffectAdapterRequest _legacyCurrentMarkerRequest() {
  const payload =
      '{"schema_version":1,"account_name":"HivraAgent",'
      '"submolt_name":"general","title":"Release note",'
      '"content":"Public fact\\n\\n[Hivra on GitHub]'
      '(https://github.com/WSorr/Hivra-App#hivra-effect:post-1)",'
      '"operation_marker":"hivra-effect:post-1",'
      '"source_draft_hash_hex":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';
  return ExternalEffectAdapterRequest(
    ownerCapsuleHex: _owner,
    operationId: 'post-1',
    pluginId: moltbookAmbassadorPluginId,
    providerId: 'moltbook',
    accountBindingId: 'account-1',
    effectKind: MoltbookExternalEffectAdapter.effectKind,
    canonicalPayloadJson: payload,
    payloadHashHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );
}

MoltbookHttpResponse _jsonResponse(Map<String, dynamic> body) {
  return MoltbookHttpResponse(
    statusCode: 200,
    headers: const <String, String>{},
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
}

MoltbookHttpResponse _postResponse(
  String postId, {
  String title = 'Release note',
  String verificationStatus = 'verified',
  bool isSpam = false,
}) {
  return _jsonResponse(<String, dynamic>{
    'success': true,
    'post': <String, dynamic>{
      'id': postId,
      'title': title,
      'content':
          'Public fact\n\n'
          '[Hivra on GitHub](https://github.com/WSorr/Hivra-App)',
      'verification_status': verificationStatus,
      'is_spam': isSpam,
      'is_locked': false,
      'score': 0,
      'comment_count': 0,
      'created_at': '2026-07-26T14:00:00.000Z',
      'updated_at': '2026-07-26T14:01:00.000Z',
      'author': <String, dynamic>{'id': 'account-1', 'name': 'HivraAgent'},
      'submolt': <String, dynamic>{'name': 'general'},
    },
  });
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

const String _owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _otherOwner =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
