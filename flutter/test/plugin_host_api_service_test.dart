import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/consensus_processor.dart';
import 'package:hivra_app/services/plugin_contract_handlers.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_host_contract_handler.dart';

void main() {
  group('PluginHostApiService', () {
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

    test('executes plugin-owned futures intent with runtime hook', () async {
      final response = await _service().executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: bingxFuturesTradingPluginId,
          method: placeBingxFuturesOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.executed);
      expect(response.result?['plugin_id'], bingxFuturesTradingPluginId);
      expect(response.result?['symbol'], 'BTC-USDT');
      expect(response.result?['intent_hash_hex'], _intentHash);
      expect(
        response.result?['market_snapshot_hash_hex'],
        _hex('1'),
      );
    });

    test('returns plugin semantic rejection unchanged', () async {
      final response = await _service(
        runtimeInvoke: _runtimeEvidence(
          status: PluginHostApiStatus.rejected,
          result: null,
          errorCode: 'invalid_args',
          errorMessage: 'quantity_decimal must be > 0',
        ),
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: bingxFuturesTradingPluginId,
          method: placeBingxFuturesOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.rejected);
      expect(response.errorCode, 'invalid_args');
    });

    test('blocks futures execution before accepting semantic result', () async {
      var runtimeInvokeCount = 0;
      final response = await _service(
        readSignable: (_) => const ConsensusSignableResult(
          preview: null,
          blockingFacts: <ConsensusBlockingFact>[
            ConsensusBlockingFact(code: 'pending_remote_break'),
          ],
        ),
        onRuntimeInvoke: () => runtimeInvokeCount += 1,
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: bingxFuturesTradingPluginId,
          method: placeBingxFuturesOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.status, PluginHostApiStatus.blocked);
      expect(response.blockingFacts.first.code, 'pending_remote_break');
      expect(runtimeInvokeCount, 0);
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

    test('rejects external trading runtime without contract kind', () async {
      final response = await _service(
        runtimeBinding: const PluginRuntimeBinding.externalPackage(
          packageId: 'pkg',
          packageVersion: '0.2.0',
          packageKind: 'zip',
          runtimeModulePath: 'plugin/module.wasm',
          contractKind: null,
          capabilities: <String>[
            'consensus_guard.read',
            'exchange.trade.bingx.futures',
          ],
        ),
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: bingxFuturesTradingPluginId,
          method: placeBingxFuturesOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.errorCode, 'runtime_contract_kind_mismatch');
    });

    test('rejects external trading runtime without capabilities', () async {
      final response = await _service(
        runtimeBinding: const PluginRuntimeBinding.externalPackage(
          packageId: 'pkg',
          packageVersion: '0.2.0',
          packageKind: 'zip',
          runtimeModulePath: 'plugin/module.wasm',
          contractKind: bingxFuturesContractKind,
        ),
      ).executeWithRuntimeHook(
        PluginHostApiRequest(
          schemaVersion: 1,
          pluginId: bingxFuturesTradingPluginId,
          method: placeBingxFuturesOrderIntentMethod,
          args: _validBingxArgs(),
        ),
      );

      expect(response.errorCode, 'runtime_capability_mismatch');
    });
  });
}

PluginHostApiService _service({
  BingxConsensusSignableReader readSignable = _signable,
  PluginRuntimeBinding? runtimeBinding,
  PluginRuntimeInvokeEvidence? runtimeInvoke,
  void Function()? onRuntimeInvoke,
}) {
  return PluginHostApiService(
    handlers: <PluginHostContractHandler>[
      BingxFuturesPluginContractHandler(readSignable: readSignable),
      CapsuleChatPluginContractHandler(
        readSignable: readSignable,
      ),
    ],
    resolveRuntimeBinding: (pluginId) => Future<PluginRuntimeBinding>.value(
      runtimeBinding ??
          PluginRuntimeBinding.externalPackage(
            packageId: 'pkg-futures-1',
            packageVersion: '0.2.0',
            packageKind: 'zip',
            packageDigestHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            runtimeAbi: 'hivra_host_abi_v2',
            runtimeEntryExport: 'hivra_evaluate_v1',
            runtimeModulePath: 'plugin/module.wasm',
            contractKind: pluginId == capsuleChatPluginId
                ? 'capsule_chat'
                : bingxFuturesContractKind,
            capabilities: <String>[
              'consensus_guard.read',
              if (pluginId != capsuleChatPluginId)
                'exchange.trade.bingx.futures',
            ],
          ),
    ),
    resolveRuntimeInvoke: (request, __) =>
        Future<PluginRuntimeInvokeEvidence>.sync(() {
      onRuntimeInvoke?.call();
      return runtimeInvoke ??
          (request.pluginId == capsuleChatPluginId
              ? _chatRuntimeEvidence()
              : _runtimeEvidence());
    }),
  );
}

PluginRuntimeInvokeEvidence _chatRuntimeEvidence() {
  final hash = sha256.convert(utf8.encode(_canonicalChat)).toString();
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('e'),
    invokeDigestHex: _hex('f'),
    semanticStatus: PluginHostApiStatus.executed,
    semanticResult: <String, dynamic>{
      'canonical_json': _canonicalChat,
      'envelope_hash_hex': hash,
    },
    semanticErrorCode: null,
    semanticErrorMessage: null,
  );
}

PluginRuntimeInvokeEvidence _runtimeEvidence({
  PluginHostApiStatus status = PluginHostApiStatus.executed,
  Map<String, dynamic>? result,
  String? errorCode,
  String? errorMessage,
}) {
  return PluginRuntimeInvokeEvidence(
    mode: 'wasmi_v1',
    modulePath: 'plugin/module.wasm',
    moduleSelection: 'manifest_module_path',
    moduleDigestHex: _hex('b'),
    invokeDigestHex: _hex('c'),
    semanticStatus: status,
    semanticResult: result ??
        <String, dynamic>{
          'canonical_json': _canonicalIntent,
          'intent_hash_hex': _intentHash,
        },
    semanticErrorCode: errorCode,
    semanticErrorMessage: errorMessage,
  );
}

ConsensusSignableResult _signable(String _) => const ConsensusSignableResult(
      preview: ConsensusPreview(
        peerHex: _peerHex,
        peerLabel: 'peer',
        invitationCount: 1,
        relationshipCount: 1,
        hashHex:
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        canonicalJson: '{}',
        blockingFacts: <ConsensusBlockingFact>[],
      ),
      blockingFacts: <ConsensusBlockingFact>[],
    );

Map<String, dynamic> _validBingxArgs() => <String, dynamic>{
      'peer_hex': _peerHex,
      'client_order_id': 'ord-1',
      'symbol': 'BTC-USDT',
      'side': 'buy',
      'order_type': 'limit',
      'quantity_decimal': '0.01',
      'limit_price_decimal': '60000',
      'time_in_force': 'GTC',
      'created_at_utc': '2026-01-01T00:00:00Z',
      'market_snapshot_hash_hex': _hex('1'),
      'feature_hash_hex': _hex('2'),
      'tvh_decision_hash_hex': _hex('3'),
      'live_decision_hash_hex': _hex('4'),
    };

Map<String, dynamic> _validChatArgs() => <String, dynamic>{
      'peer_hex': _peerHex,
      'client_message_id': 'msg-1',
      'message_text': 'hello',
      'created_at_utc': '2026-01-01T00:00:00Z',
    };

const String _peerHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _canonicalIntent =
    '{"schema_version":1,"plugin_id":"hivra.contract.bingx-futures-trading.v1",'
    '"contract_kind":"bingx_futures_order_intent",'
    '"peer_hex":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",'
    '"client_order_id":"ord-1","symbol":"BTC-USDT","side":"buy",'
    '"order_type":"limit","quantity_decimal":"0.01",'
    '"limit_price_decimal":"60000","time_in_force":"GTC",'
    '"entry_mode":"direct","zone_side":null,"zone_low_decimal":null,'
    '"zone_high_decimal":null,"zone_price_rule":null,'
    '"trigger_price_decimal":null,"stop_loss_decimal":null,'
    '"take_profit_decimal":null,"created_at_utc":"2026-01-01T00:00:00Z",'
    '"strategy_tag":null}';
const String _canonicalChat =
    '{"schema_version":1,"plugin_id":"hivra.contract.capsule-chat.v1",'
    '"contract_kind":"capsule_chat_direct",'
    '"peer_hex":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",'
    '"client_message_id":"msg-1","message_text":"hello",'
    '"created_at_utc":"2026-01-01T00:00:00Z"}';
final String _intentHash =
    sha256.convert(utf8.encode(_canonicalIntent)).toString();

String _hex(String character) => List<String>.filled(64, character).join();
