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
      endsWith(
        '[Hivra on GitHub](https://github.com/WSorr/Hivra-App#'
        'hivra-effect:post-1)',
      ),
    );
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
  });

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
}

ExternalEffectAdapterRequest _request({String owner = _owner}) {
  const payload =
      '{"schema_version":1,"account_name":"HivraAgent",'
      '"submolt_name":"general","title":"Release note",'
      '"content":"Public fact\\n\\n[Hivra on GitHub]'
      '(https://github.com/WSorr/Hivra-App#hivra-effect:post-1)",'
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

MoltbookHttpResponse _jsonResponse(Map<String, dynamic> body) {
  return MoltbookHttpResponse(
    statusCode: 200,
    headers: const <String, String>{},
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
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
