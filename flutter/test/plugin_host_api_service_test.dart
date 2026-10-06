import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/consensus_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/models/plugin_host_api_models.dart';
import 'package:hivra_app/services/plugin_contract_handlers.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_host_contract_handler.dart';

void main() {
  group('PluginHostApiService', () {
    test(
      'raw binding cannot authorize or invoke an external package',
      () async {
        var calls = 0;
        final host = PluginHostApiService(
          handlers: const [MoltbookAmbassadorPluginContractHandler()],
          resolveRuntimeBinding:
              (_) async => const PluginRuntimeBinding.externalPackage(
                packageId: 'raw',
                packageVersion: '1',
                packageKind: 'wasm',
                contractKind: 'moltbook_ambassador_draft',
                capabilities: ['content.draft.prepare', 'consensus_guard.read'],
              ),
          resolveRuntimeInvoke: (_, _) async {
            calls++;
            return null;
          },
        );
        final response = await host.executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: moltbookAmbassadorPluginId,
            method: prepareMoltbookDraftMethod,
            args: {},
          ),
        );
        expect(response.errorCode, 'runtime_binding_invalid');
        await expectLater(
          host.captureRuntimeAuthorization(
            pluginId: moltbookAmbassadorPluginId,
            method: prepareMoltbookDraftMethod,
          ),
          throwsStateError,
        );
        expect(calls, 0);
      },
    );
    test('rejects unsupported plugin id', () {
      final response = _service().execute(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: 'hivra.contract.unknown.v1',
          method: 'unknown_method',
          args: <String, dynamic>{},
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'unsupported_plugin');
    });

    test('executes plugin-owned chat envelope with runtime hook', () async {
      final response = await _service().executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: capsuleChatPluginId,
          method: postCapsuleChatMethod,
          args: _validChatArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.result?['message_text'], 'hello');
    });

    test('rejects chat envelope with a different request identity', () async {
      final canonical = _canonicalChat.replaceFirst('"msg-1"', '"msg-2"');
      final response = await _service(
        runtimeInvoke: _chatRuntimeEvidence(canonical: canonical),
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: capsuleChatPluginId,
          method: postCapsuleChatMethod,
          args: _validChatArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'runtime_result_invalid');
    });

    test('rejects chat envelope with missing semantic content', () async {
      final canonical = _canonicalChat.replaceFirst('"hello"', '""');
      final response = await _service(
        runtimeInvoke: _chatRuntimeEvidence(canonical: canonical),
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: capsuleChatPluginId,
          method: postCapsuleChatMethod,
          args: _validChatArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'runtime_result_invalid');
    });

    test('executes plugin-owned Moltbook draft with approval gate', () async {
      final response = await _service().executeWithRuntimeHook(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: moltbookAmbassadorPluginId,
          method: prepareMoltbookDraftMethod,
          args: <String, dynamic>{
            'bulletin_id': 'release-v1.0.3-test14',
            'facts': <String>['A public Hivra development fact.'],
          },
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.result?['plugin_id'], moltbookAmbassadorPluginId);
      expect(response.result?['approval_required'], isTrue);
      expect(response.result?['draft_hash_hex'], _moltbookDraftHash);
    });

    test('executes Moltbook heartbeat without effect permission', () async {
      final response = await _service(
        runtimeInvoke: _moltbookHeartbeatRuntimeEvidence(),
      ).executeWithRuntimeHook(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: moltbookAmbassadorPluginId,
          method: planMoltbookHeartbeatMethod,
          args: <String, dynamic>{},
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.result?['priority'], 'inspect_feed');
      expect(response.result?['publish_allowed'], isFalse);
      expect(response.result?['human_review_required'], isTrue);
    });

    test('executes Moltbook engagement proposal without effect', () async {
      final response = await _service(
        runtimeInvoke: _moltbookEngagementRuntimeEvidence(),
      ).executeWithRuntimeHook(
        const PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: moltbookAmbassadorPluginId,
          method: planMoltbookEngagementMethod,
          args: <String, dynamic>{},
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.result?['action_class'], 'reply_draft');
      expect(response.result?['publish_allowed'], isFalse);
      expect(response.result?['human_review_required'], isTrue);
    });

    test(
      'executes hash-bound Moltbook delegated reply authorization',
      () async {
        final response = await _service(
          runtimeInvoke: _moltbookDelegatedReplyRuntimeEvidence(),
        ).executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: moltbookAmbassadorPluginId,
            method: authorizeMoltbookDelegatedReplyMethod,
            args: <String, dynamic>{},
          ),
        );

        expect(response.status, PluginHostApiStatus.executed);
        expect(response.result?['publish_allowed'], isTrue);
        expect(response.result?['human_review_required'], isFalse);
        expect(response.result?['reply_draft_hash_hex'], _hexB);
      },
    );
  });
}

PluginHostApiService _service({
  PluginConsensusSignableReader readSignable = _signable,
  PluginConsensusAsyncSignableReader? readAttestedSignable,
  PluginRuntimeBinding? runtimeBinding,
  PluginRuntimeInvokeEvidence? runtimeInvoke,
  void Function()? onRuntimeInvoke,
}) {
  return PluginHostApiService(
    handlers: <PluginHostContractHandler>[
      CapsuleChatPluginContractHandler(
        readSignable: readSignable,
        readAttestedSignable: readAttestedSignable,
      ),
      const MoltbookAmbassadorPluginContractHandler(),
    ],
    resolveRuntimeBinding:
        (pluginId) => Future<PluginRuntimeBinding>.value(
          runtimeBinding ??
              PluginRuntimeBinding.externalPackage(
                packageId: 'pkg-runtime-1',
                packageVersion: '0.2.0',
                packageKind: 'zip',
                packageDigestHex:
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                runtimeAbi: 'hivra_host_abi_v2',
                runtimeEntryExport: 'hivra_evaluate_v1',
                runtimeModulePath: 'plugin/module.wasm',
                contractKind: switch (pluginId) {
                  capsuleChatPluginId => 'capsule_chat',
                  moltbookAmbassadorPluginId => 'moltbook_ambassador_draft',
                  _ => null,
                },
                capabilities: <String>[
                  if (pluginId == capsuleChatPluginId) 'consensus_guard.read',
                  if (pluginId == moltbookAmbassadorPluginId)
                    'content.draft.prepare',
                  if (pluginId == moltbookAmbassadorPluginId)
                    'content.feed.plan',
                  if (pluginId == moltbookAmbassadorPluginId)
                    'content.engagement.plan',
                  if (pluginId == moltbookAmbassadorPluginId)
                    'content.reply.delegate',
                  if (pluginId == moltbookAmbassadorPluginId)
                    'content.reply.prepare',
                ],
              ),
        ),
    resolveRuntimeInvoke:
        (request, _) => Future<PluginRuntimeInvokeEvidence>.sync(() {
          onRuntimeInvoke?.call();
          return runtimeInvoke ??
              switch (request.pluginId) {
                capsuleChatPluginId => _chatRuntimeEvidence(),
                moltbookAmbassadorPluginId => _moltbookRuntimeEvidence(),
                _ => _chatRuntimeEvidence(),
              };
        }),
  );
}

PluginRuntimeInvokeEvidence _moltbookRuntimeEvidence() {
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('7'),
    invokeDigestHex: _hex('8'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': _canonicalMoltbookDraft,
      'draft_hash_hex': _moltbookDraftHash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

PluginRuntimeInvokeEvidence _moltbookHeartbeatRuntimeEvidence() {
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('7'),
    invokeDigestHex: _hex('9'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': _canonicalMoltbookHeartbeat,
      'plan_hash_hex': _moltbookHeartbeatHash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

PluginRuntimeInvokeEvidence _moltbookEngagementRuntimeEvidence() {
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('7'),
    invokeDigestHex: _hex('a'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': _canonicalMoltbookEngagement,
      'plan_hash_hex': _moltbookEngagementHash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

PluginRuntimeInvokeEvidence _moltbookDelegatedReplyRuntimeEvidence() {
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('7'),
    invokeDigestHex: _hex('b'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': _canonicalMoltbookDelegatedReply,
      'authorization_hash_hex': _moltbookDelegatedReplyHash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

PluginRuntimeInvokeEvidence _chatRuntimeEvidence({String? canonical}) {
  final canonicalJson = canonical ?? _canonicalChat;
  final hash = sha256.convert(utf8.encode(canonicalJson)).toString();
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('e'),
    invokeDigestHex: _hex('f'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': canonicalJson,
      'envelope_hash_hex': hash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

ConsensusSignableResult _signable(String _) => const ConsensusSignableResult(
  preview: ConsensusPreview(
    peerHex: _peerHex,
    peerLabel: 'peer',
    invitationCount: 1,
    relationshipCount: 1,
    hashHex: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    canonicalJson: '{}',
    blockingFacts: <ConsensusBlockingFact>[],
  ),
  blockingFacts: <ConsensusBlockingFact>[],
);

Map<String, dynamic> _validChatArgs() => <String, dynamic>{
  'peer_hex': _peerHex,
  'client_message_id': 'msg-1',
  'message_text': 'hello',
  'created_at_utc': '2026-01-01T00:00:00Z',
};

const String _peerHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _canonicalChat =
    '{"schema_version":1,"plugin_id":"hivra.contract.capsule-chat.v1",'
    '"contract_kind":"capsule_chat_direct",'
    '"peer_hex":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",'
    '"client_message_id":"msg-1","message_text":"hello",'
    '"created_at_utc":"2026-01-01T00:00:00Z"}';
const String _canonicalMoltbookDraft =
    '{"schema_version":1,'
    '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
    '"contract_kind":"moltbook_ambassador_draft",'
    '"bulletin_id":"release-v1.0.3-test14",'
    '"release_tag":"v1.0.3-test14","category":"release",'
    '"title":"Hivra development","body":"A public Hivra development fact.",'
    '"audience":"agent-developers","approval_required":true,'
    '"safety_flags":[]}';
const String _canonicalMoltbookHeartbeat =
    '{"schema_version":1,'
    '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
    '"contract_kind":"moltbook_ambassador_heartbeat_plan",'
    '"observed_at_utc":"2026-07-29T10:00:00.000Z",'
    '"priority":"inspect_feed",'
    '"reason":"Verified candidates are available.",'
    '"candidate_post_ids":["post-1"],'
    '"publish_allowed":false,"human_review_required":true,'
    '"safety_flags":["remote_content_untrusted","no_external_effect"]}';
const String _canonicalMoltbookEngagement =
    '{"schema_version":1,'
    '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
    '"contract_kind":"moltbook_ambassador_engagement_plan",'
    '"observed_at_utc":"2026-07-29T10:00:00.000Z",'
    '"action_class":"reply_draft","target_post_id":"post-1",'
    '"target_comment_id":"comment-1",'
    '"reason":"A reviewed reply draft is eligible.",'
    '"publish_allowed":false,"human_review_required":true,'
    '"safety_flags":["remote_content_untrusted","no_external_effect",'
    '"ai_text_not_generated","follow_requires_longitudinal_evidence"]}';
const String _hexA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hexB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _canonicalMoltbookDelegatedReply =
    '{"schema_version":1,'
    '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
    '"contract_kind":"moltbook_ambassador_delegated_reply_authorization",'
    '"target_post_id":"post-1","target_comment_id":"comment-1",'
    '"engagement_plan_hash_hex":"$_hexA",'
    '"reply_draft_hash_hex":"$_hexB",'
    '"policy_version":1,"max_daily_writes":3,"writes_today":1,'
    '"min_interval_minutes":30,'
    '"observed_at_utc":"2026-07-31T18:00:00.000Z",'
    '"publish_allowed":true,"human_review_required":false,'
    '"safety_flags":["exact_reply_draft_bound","engagement_plan_bound"]}';
final String _moltbookDraftHash =
    sha256.convert(utf8.encode(_canonicalMoltbookDraft)).toString();
final String _moltbookHeartbeatHash =
    sha256.convert(utf8.encode(_canonicalMoltbookHeartbeat)).toString();
final String _moltbookEngagementHash =
    sha256.convert(utf8.encode(_canonicalMoltbookEngagement)).toString();
final String _moltbookDelegatedReplyHash =
    sha256.convert(utf8.encode(_canonicalMoltbookDelegatedReply)).toString();

String _hex(String character) => List<String>.filled(64, character).join();
