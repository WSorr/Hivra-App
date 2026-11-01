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
          handlers: const [],
          resolveRuntimeBinding:
              (_) async => const PluginRuntimeBinding.externalPackage(
                packageId: 'raw',
                packageVersion: '1',
                packageKind: 'wasm',
                contractKind: pluginWorkspaceContractKind,
                capabilities: ['workspace.render', 'workspace.continue'],
              ),
          resolveRuntimeInvoke: (_, _) async {
            calls++;
            return null;
          },
        );
        final response = await host.executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'example.package',
            method: pluginWorkspaceMethod,
            args: {},
          ),
        );
        expect(response.errorCode, 'runtime_binding_invalid');
        await expectLater(
          host.captureRuntimeAuthorization(
            pluginId: 'example.package',
            method: pluginWorkspaceMethod,
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

    for (final initialCapture in [true, false]) {
      test(
        'Chat authorization rejects replacement during consensus await: $initialCapture',
        () async {
          var replaceDuringRead = initialCapture;
          var replaced = false;
          final host = PluginHostApiService(
            handlers: [
              CapsuleChatPluginContractHandler(
                readSignable: _signable,
                readAttestedSignable: (peer) async {
                  if (replaceDuringRead) replaced = true;
                  return _signable(peer);
                },
              ),
            ],
            resolveRuntimeBinding:
                (_) async => PluginRuntimeBinding.externalPackage(
                  packageId: replaced ? 'replacement' : 'original',
                  packageVersion: '1',
                  packageKind: 'zip',
                  packageDigestHex: 'a' * 64,
                  contractKind: capsuleChatContractKind,
                  capabilities: const ['consensus_guard.read'],
                ),
          );
          Future<Future<void> Function()> capture() =>
              host.captureRuntimeAuthorization(
                pluginId: capsuleChatPluginId,
                method: postCapsuleChatMethod,
                args: {'peer_hex': _peerHex},
              );
          if (initialCapture) {
            await expectLater(capture(), throwsStateError);
          } else {
            final authorize = await capture();
            replaceDuringRead = true;
            await expectLater(authorize(), throwsStateError);
          }
        },
      );
    }

    for (final change in ['remove', 'replace', 'raw', 'revoke', 'reorder']) {
      test(
        'runtime result respects package authority after await: $change',
        () async {
          var completed = false;
          final host = PluginHostApiService(
            handlers: [
              CapsuleChatPluginContractHandler(readSignable: _signable),
            ],
            resolveRuntimeBinding: (_) async {
              if (completed && change == 'remove') {
                return const PluginRuntimeBinding.hostFallback();
              }
              return PluginRuntimeBinding.externalPackage(
                packageVersion: '1.0.0',
                packageId:
                    completed && change == 'replace'
                        ? 'new-package'
                        : 'original-package',
                packageKind: completed && change == 'raw' ? 'wasm' : 'zip',
                packageDigestHex: 'a' * 64,
                contractKind: capsuleChatContractKind,
                capabilities:
                    completed && change == 'revoke'
                        ? ['consensus_guard.read']
                        : completed && change == 'reorder'
                        ? ['network.http', 'consensus_guard.read']
                        : ['consensus_guard.read', 'network.http'],
              );
            },
            resolveRuntimeInvoke: (_, _) async {
              completed = true;
              return _chatRuntimeEvidence();
            },
          );
          final response = await host.executeWithRuntimeHook(
            PluginHostApiRequest(
              schemaVersion: 1,
              pluginId: capsuleChatPluginId,
              method: postCapsuleChatMethod,
              args: _validChatArgs(),
            ),
          );
          if (change == 'reorder') {
            expect(response.status, PluginHostApiStatus.executed);
            expect(response.result?['message_text'], 'hello');
          } else {
            expect(response.status, PluginHostApiStatus.rejected);
            expect(response.errorCode, 'runtime_binding_changed');
            expect(response.result, isNull);
          }
        },
      );
    }

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

    test(
      'retired named service methods have no executable host handler',
      () async {
        var calls = 0;
        final host = PluginHostApiService(
          handlers: [],
          resolveRuntimeBinding:
              (_) async => const PluginRuntimeBinding.externalPackage(
                packageId: 'old-package',
                packageVersion: '0.7.3',
                packageKind: 'zip',
                packageDigestHex:
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                contractKind: 'moltbook_ambassador_draft',
                capabilities: ['content.draft.prepare'],
              ),
          resolveRuntimeInvoke: (_, _) async {
            calls++;
            return null;
          },
        );
        final response = await host.executeWithRuntimeHook(
          const PluginHostApiRequest(
            schemaVersion: 1,
            pluginId: 'hivra.contract.moltbook-ambassador.v1',
            method: 'prepare_moltbook_draft',
            args: {},
          ),
        );
        expect(response.status, PluginHostApiStatus.rejected);
        expect(calls, 0);
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
                  _ => null,
                },
                capabilities: <String>[
                  if (pluginId == capsuleChatPluginId) 'consensus_guard.read',
                ],
              ),
        ),
    resolveRuntimeInvoke:
        (request, _) => Future<PluginRuntimeInvokeEvidence>.sync(() {
          onRuntimeInvoke?.call();
          return runtimeInvoke ??
              switch (request.pluginId) {
                capsuleChatPluginId => _chatRuntimeEvidence(),
                _ => _chatRuntimeEvidence(),
              };
        }),
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
String _hex(String character) => List<String>.filled(64, character).join();
