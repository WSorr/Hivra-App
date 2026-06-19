import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'consensus_processor.dart';
import 'plugin_host_api_service.dart';
import 'plugin_host_contract_handler.dart';

const String bingxFuturesTradingPluginId =
    'hivra.contract.bingx-futures-trading.v1';
const String bingxFuturesContractKind = 'bingx_futures_order_intent';
const String placeBingxFuturesOrderIntentMethod =
    'place_bingx_futures_order_intent';
const String capsuleChatPluginId = 'hivra.contract.capsule-chat.v1';
const String postCapsuleChatMethod = 'post_capsule_chat_message';

typedef PluginConsensusSignableReader = ConsensusSignableResult Function(
  String peerHex,
);
typedef BingxConsensusSignableReader = PluginConsensusSignableReader;

class CapsuleChatPluginContractHandler implements PluginHostContractHandler {
  final PluginConsensusSignableReader _readSignable;

  const CapsuleChatPluginContractHandler({
    required PluginConsensusSignableReader readSignable,
  }) : _readSignable = readSignable;

  @override
  String get pluginId => capsuleChatPluginId;

  @override
  String get contractKind => 'capsule_chat';

  @override
  Set<String> get methods => const <String>{postCapsuleChatMethod};

  @override
  bool get requiresExternalRuntime => true;

  @override
  Set<String> requiredCapabilities(String method) =>
      const <String>{'consensus_guard.read'};

  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) {
    return _consensusPreflight(
      request: request,
      readSignable: _readSignable,
    );
  }

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    final peerHex = request.args['peer_hex']?.toString().trim().toLowerCase();
    if (peerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_args',
        message: 'peer_hex must be a 64-char lowercase hex',
      );
    }
    if (runtimeInvoke == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_invoke_unavailable',
        message: 'WASM semantic result is required',
      );
    }
    if (runtimeInvoke.semanticStatus == PluginHostApiStatus.rejected) {
      return PluginHostContractResult.rejected(
        code: runtimeInvoke.semanticErrorCode ?? 'plugin_rejected',
        message:
            runtimeInvoke.semanticErrorMessage ?? 'Plugin rejected the request',
      );
    }
    final semantic = runtimeInvoke.semanticResult;
    final canonicalJson = semantic?['canonical_json']?.toString() ?? '';
    final envelopeHashHex = semantic?['envelope_hash_hex']?.toString() ?? '';
    final envelope = _validatedCanonicalObject(
      canonicalJson: canonicalJson,
      expectedHashHex: envelopeHashHex,
      expectedPluginId: pluginId,
      expectedContractKind: 'capsule_chat_direct',
      expectedPeerHex: peerHex,
    );
    if (envelope == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_result_invalid',
        message: 'WASM chat envelope integrity check failed',
      );
    }
    return PluginHostContractResult.executed(<String, dynamic>{
      ...envelope,
      'envelope_hash_hex': envelopeHashHex,
      'canonical_envelope_json': canonicalJson,
    });
  }
}

class BingxFuturesPluginContractHandler implements PluginHostContractHandler {
  final BingxConsensusSignableReader _readSignable;

  const BingxFuturesPluginContractHandler({
    required BingxConsensusSignableReader readSignable,
  }) : _readSignable = readSignable;

  @override
  String get pluginId => bingxFuturesTradingPluginId;

  @override
  String get contractKind => bingxFuturesContractKind;

  @override
  Set<String> get methods => const <String>{placeBingxFuturesOrderIntentMethod};

  @override
  bool get requiresExternalRuntime => true;

  @override
  Set<String> requiredCapabilities(String method) => const <String>{
        'consensus_guard.read',
        'exchange.trade.bingx.futures',
      };

  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) {
    return _consensusPreflight(
      request: request,
      readSignable: _readSignable,
    );
  }

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    final args = request.args;
    final peerHex = args['peer_hex']?.toString().trim().toLowerCase();
    if (peerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_args',
        message: 'peer_hex must be a 64-char lowercase hex',
      );
    }
    if (runtimeInvoke == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_invoke_unavailable',
        message: 'WASM semantic result is required',
      );
    }
    if (runtimeInvoke.semanticStatus == PluginHostApiStatus.rejected) {
      return PluginHostContractResult.rejected(
        code: runtimeInvoke.semanticErrorCode ?? 'plugin_rejected',
        message:
            runtimeInvoke.semanticErrorMessage ?? 'Plugin rejected the request',
      );
    }
    final semantic = runtimeInvoke.semanticResult;
    final canonicalJson = semantic?['canonical_json']?.toString() ?? '';
    final intentHashHex = semantic?['intent_hash_hex']?.toString() ?? '';
    final intent = _validatedCanonicalObject(
      canonicalJson: canonicalJson,
      expectedHashHex: intentHashHex,
      expectedPluginId: pluginId,
      expectedContractKind: contractKind,
      expectedPeerHex: peerHex,
    );
    if (intent == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_result_invalid',
        message: 'WASM canonical intent integrity check failed',
      );
    }
    return PluginHostContractResult.executed(<String, dynamic>{
      ...intent,
      'intent_hash_hex': intentHashHex,
      'canonical_intent_json': canonicalJson,
      'market_snapshot_hash_hex': _optional(args, 'market_snapshot_hash_hex'),
      'feature_hash_hex': _optional(args, 'feature_hash_hex'),
      'tvh_decision_hash_hex': _optional(args, 'tvh_decision_hash_hex'),
      'live_decision_hash_hex': _optional(args, 'live_decision_hash_hex'),
    });
  }

  String? _optional(Map<String, dynamic> args, String key) =>
      args[key]?.toString().trim();
}

PluginHostContractResult? _consensusPreflight({
  required PluginHostApiRequest request,
  required PluginConsensusSignableReader readSignable,
}) {
  final peerHex = request.args['peer_hex']?.toString().trim().toLowerCase();
  if (peerHex == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
    return const PluginHostContractResult.rejected(
      code: 'invalid_args',
      message: 'peer_hex must be a 64-char lowercase hex',
    );
  }
  final signable = readSignable(peerHex);
  if (!signable.isSignable) {
    return PluginHostContractResult.blocked(signable.blockingFacts);
  }
  return null;
}

Map<String, dynamic>? _validatedCanonicalObject({
  required String canonicalJson,
  required String expectedHashHex,
  required String expectedPluginId,
  required String expectedContractKind,
  required String expectedPeerHex,
}) {
  if (canonicalJson.isEmpty ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHashHex) ||
      sha256.convert(utf8.encode(canonicalJson)).toString() !=
          expectedHashHex) {
    return null;
  }
  try {
    final decoded = jsonDecode(canonicalJson);
    if (decoded is! Map) return null;
    final value = Map<String, dynamic>.from(decoded);
    if (value['plugin_id'] != expectedPluginId ||
        value['contract_kind'] != expectedContractKind ||
        value['peer_hex'] != expectedPeerHex) {
      return null;
    }
    return value;
  } catch (_) {
    return null;
  }
}
