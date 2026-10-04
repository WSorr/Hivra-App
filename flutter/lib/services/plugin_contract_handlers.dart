import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/consensus_models.dart';
import '../models/plugin_contract_ids.dart';
import '../models/plugin_host_api_models.dart';
import 'plugin_host_contract_handler.dart';

typedef PluginConsensusSignableReader =
    ConsensusSignableResult Function(String peerHex);
typedef PluginConsensusAsyncSignableReader =
    Future<ConsensusSignableResult> Function(String peerHex);

class PluginWorkspaceContractHandler implements PluginHostContractHandler {
  @override
  final String pluginId;

  const PluginWorkspaceContractHandler({required this.pluginId});

  @override
  String get contractKind => pluginWorkspaceContractKind;
  @override
  Set<String> get methods => const {pluginWorkspaceMethod};
  @override
  bool get requiresExternalRuntime => true;
  @override
  Set<String> requiredCapabilities(String method) => const {
    'workspace.render',
    'workspace.continue',
    'state.plugin.read_write',
  };
  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) => null;
  @override
  Future<PluginHostContractResult?> preflightAsync(
    PluginHostApiRequest request,
  ) async => null;

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
    if (runtimeInvoke == null) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_invoke_unavailable',
        message: 'Installed WASM is required',
      );
    }
    if (runtimeInvoke.semanticStatus != PluginHostApiStatus.executed) {
      return PluginHostContractResult.rejected(
        code: runtimeInvoke.semanticErrorCode ?? 'plugin_rejected',
        message:
            runtimeInvoke.semanticErrorMessage ?? 'Plugin rejected the action',
      );
    }
    final result = runtimeInvoke.semanticResult;
    try {
      if (result == null ||
          result['state'] is! Map ||
          utf8.encode(jsonEncode(result['state'])).length > 32 * 1024) {
        throw const FormatException('Invalid bounded plugin state');
      }
      validateView(Map<String, dynamic>.from(result['view'] as Map));
      final requests = result['requests'] as List;
      if (requests.length > 7 || requests.any((r) => r is! Map)) {
        throw const FormatException('Invalid bounded plugin requests');
      }
      final resume = result['resume_action'];
      if (resume != null &&
          (resume is! String ||
              !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(resume) ||
              requests.isEmpty ||
              requests.any(
                (r) =>
                    !const {
                      'market.candles.read',
                      'account.snapshot.read',
                      'order.snapshot.read',
                    }.contains(r['kind']) ||
                    r['scope'] == 'open',
              ))) {
        throw const FormatException('Invalid bounded workspace continuation');
      }
      return PluginHostContractResult.executed(result);
    } catch (_) {
      return const PluginHostContractResult.rejected(
        code: 'invalid_workspace',
        message: 'Plugin returned an invalid workspace',
      );
    }
  }

  static void validateView(Map<String, dynamic> view) {
    if (utf8.encode(jsonEncode(view)).length > 16 * 1024 ||
        view['title'] is! String ||
        (view['title'] as String).isEmpty ||
        view['message'] is! String ||
        (view['summary'] != null && view['summary'] is! String) ||
        (view['details_title'] != null &&
            (view['details_title'] is! String ||
                (view['details_title'] as String).isEmpty ||
                (view['details_title'] as String).length > 128)) ||
        view['details'] is! String) {
      throw const FormatException('Invalid workspace text');
    }
    final fields = view['fields'] as List;
    if (view['confirmation'] != null &&
        (view['confirmation'] is! Map ||
            !const {
              'order.entry.place',
              'order.entry.cancel',
              'position.exit.place',
            }.contains((view['confirmation'] as Map)['kind']) ||
            (view['confirmation'] as Map)['provider'] != 'bingx' ||
            (view['confirmation'] as Map)['plan'] is! Map ||
            ((view['confirmation'] as Map)['kind'] == 'order.entry.cancel' &&
                ((view['confirmation'] as Map)['order_id'] is! String ||
                    !RegExp(
                      r'^[1-9][0-9]{0,29}$',
                    ).hasMatch((view['confirmation'] as Map)['order_id']))))) {
      throw const FormatException('Invalid order confirmation');
    }
    final actions = view['actions'] as List;
    final columns = view['columns'] as List;
    final rows = view['rows'] as List;
    if (fields.length > 8 ||
        actions.length > 4 ||
        columns.length > 6 ||
        (rows.isNotEmpty && columns.isEmpty) ||
        rows.length > 64 ||
        columns.any((c) => c is! String) ||
        rows.any(
          (r) =>
              r is! List ||
              r.length != columns.length ||
              r.any((c) => c is! String),
        )) {
      throw const FormatException('Invalid workspace size or table');
    }
    final ids = <String>{};
    for (final field in fields) {
      if (field is! Map ||
          field['id'] is! String ||
          field['label'] is! String ||
          !ids.add(field['id'] as String) ||
          (field['advanced'] != null && field['advanced'] is! bool) ||
          !const {
            'text',
            'integer',
            'number',
            'choice',
          }.contains(field['type']) ||
          !(field['value'] is String || field['value'] is num)) {
        throw const FormatException('Invalid workspace field');
      }
      if (field['type'] == 'choice' &&
          (field['value'] is! String ||
              field['source'] is! Map ||
              (field['source'] as Map)['kind'] != 'market.instruments.read' ||
              (field['source'] as Map)['provider'] != 'bingx')) {
        throw const FormatException('Invalid workspace choice source');
      }
    }
    ids.clear();
    for (final action in actions) {
      if (action is! Map ||
          action['id'] is! String ||
          action['label'] is! String ||
          (action['host'] != null &&
              !const {
                'bingx.account.connect',
                'bingx.order.submit',
                'workspace.start',
                'workspace.stop',
              }.contains(action['host'])) ||
          !ids.add(action['id'] as String)) {
        throw const FormatException('Invalid workspace action');
      }
    }
  }
}

class CapsuleChatPluginContractHandler implements PluginHostContractHandler {
  final PluginConsensusSignableReader _readSignable;
  final PluginConsensusAsyncSignableReader? _readAttestedSignable;

  const CapsuleChatPluginContractHandler({
    required PluginConsensusSignableReader readSignable,
    PluginConsensusAsyncSignableReader? readAttestedSignable,
  }) : _readSignable = readSignable,
       _readAttestedSignable = readAttestedSignable;

  @override
  String get pluginId => capsuleChatPluginId;

  @override
  String get contractKind => capsuleChatContractKind;

  @override
  Set<String> get methods => const <String>{postCapsuleChatMethod};

  @override
  bool get requiresExternalRuntime => true;

  @override
  Set<String> requiredCapabilities(String method) => const <String>{
    'consensus_guard.read',
  };

  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) {
    return _consensusPreflight(request: request, readSignable: _readSignable);
  }

  @override
  Future<PluginHostContractResult?> preflightAsync(
    PluginHostApiRequest request,
  ) {
    return _consensusPreflightAsync(
      request: request,
      readSignable: _readAttestedSignable,
      fallbackReadSignable: _readSignable,
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
    final expectedMessageId =
        request.args['client_message_id']?.toString().trim() ?? '';
    final expectedCreatedAtUtc =
        request.args['created_at_utc']?.toString().trim() ?? '';
    final messageText = envelope['message_text'];
    if (expectedMessageId.isEmpty ||
        expectedCreatedAtUtc.isEmpty ||
        envelope['client_message_id'] != expectedMessageId ||
        envelope['created_at_utc'] != expectedCreatedAtUtc ||
        messageText is! String ||
        messageText != messageText.trim() ||
        messageText.isEmpty ||
        utf8.encode(messageText).length > 1024) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_result_invalid',
        message: 'WASM chat envelope request binding failed',
      );
    }
    return PluginHostContractResult.executed(<String, dynamic>{
      ...envelope,
      'envelope_hash_hex': envelopeHashHex,
      'canonical_envelope_json': canonicalJson,
    });
  }
}

PluginHostContractResult? _consensusPreflight({
  required PluginHostApiRequest request,
  required PluginConsensusSignableReader readSignable,
  bool allowSoloWhenPeerMissing = false,
}) {
  final peerHex =
      request.args['peer_hex']?.toString().trim().toLowerCase() ?? '';
  if (peerHex.isEmpty && allowSoloWhenPeerMissing) {
    return null;
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
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

class MoltbookAmbassadorPluginContractHandler
    implements PluginHostContractHandler {
  const MoltbookAmbassadorPluginContractHandler();

  @override
  String get pluginId => moltbookAmbassadorPluginId;

  @override
  String get contractKind => moltbookAmbassadorContractKind;

  @override
  Set<String> get methods => const <String>{
    prepareMoltbookDraftMethod,
    planMoltbookHeartbeatMethod,
    planMoltbookEngagementMethod,
    prepareMoltbookReplyMethod,
    authorizeMoltbookDelegatedReplyMethod,
  };

  @override
  bool get requiresExternalRuntime => true;

  @override
  Set<String> requiredCapabilities(String method) => switch (method) {
    planMoltbookHeartbeatMethod => const <String>{'content.feed.plan'},
    planMoltbookEngagementMethod => const <String>{'content.engagement.plan'},
    prepareMoltbookReplyMethod => const <String>{'content.reply.prepare'},
    authorizeMoltbookDelegatedReplyMethod => const <String>{
      'content.reply.delegate',
    },
    _ => const <String>{'content.draft.prepare'},
  };

  @override
  PluginHostContractResult? preflight(PluginHostApiRequest request) => null;

  @override
  Future<PluginHostContractResult?> preflightAsync(
    PluginHostApiRequest request,
  ) async => null;

  @override
  PluginHostContractResult execute(
    PluginHostApiRequest request, {
    PluginRuntimeInvokeEvidence? runtimeInvoke,
  }) {
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
            runtimeInvoke.semanticErrorMessage ?? 'Plugin rejected the draft',
      );
    }
    final semantic = runtimeInvoke.semanticResult;
    final canonicalJson = semantic?['canonical_json']?.toString() ?? '';
    if (request.method == planMoltbookHeartbeatMethod) {
      final planHashHex = semantic?['plan_hash_hex']?.toString() ?? '';
      final plan = _validatedCanonicalObject(
        canonicalJson: canonicalJson,
        expectedHashHex: planHashHex,
        expectedPluginId: pluginId,
        expectedContractKind: 'moltbook_ambassador_heartbeat_plan',
        expectedPeerHex: null,
      );
      if (plan == null ||
          plan['publish_allowed'] != false ||
          plan['human_review_required'] != true ||
          plan['candidate_post_ids'] is! List ||
          plan['safety_flags'] is! List) {
        return const PluginHostContractResult.rejected(
          code: 'runtime_result_invalid',
          message: 'WASM ambassador heartbeat safety gate failed',
        );
      }
      final planningScope = request.args['planning_scope'];
      if (planningScope == 'public_change' &&
          (plan['priority'] != 'public_change' ||
              plan['candidate_post_ids'] is! List ||
              (plan['candidate_post_ids'] as List).length > 1 ||
              plan['safety_flags'] is! List ||
              !(plan['safety_flags'] as List).contains(
                'public_change_selection_only',
              ))) {
        return const PluginHostContractResult.rejected(
          code: 'runtime_result_invalid',
          message: 'WASM public-change selection gate failed',
        );
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        ...plan,
        'plan_hash_hex': planHashHex,
        'canonical_plan_json': canonicalJson,
      });
    }
    if (request.method == planMoltbookEngagementMethod) {
      final planHashHex = semantic?['plan_hash_hex']?.toString() ?? '';
      final plan = _validatedCanonicalObject(
        canonicalJson: canonicalJson,
        expectedHashHex: planHashHex,
        expectedPluginId: pluginId,
        expectedContractKind: 'moltbook_ambassador_engagement_plan',
        expectedPeerHex: null,
      );
      if (plan == null ||
          plan['publish_allowed'] != false ||
          plan['human_review_required'] != true ||
          plan['action_class'] is! String ||
          plan['target_post_id'] is! String ||
          plan['safety_flags'] is! List) {
        return const PluginHostContractResult.rejected(
          code: 'runtime_result_invalid',
          message: 'WASM ambassador engagement safety gate failed',
        );
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        ...plan,
        'plan_hash_hex': planHashHex,
        'canonical_plan_json': canonicalJson,
      });
    }
    if (request.method == prepareMoltbookReplyMethod) {
      final draftHashHex = semantic?['draft_hash_hex']?.toString() ?? '';
      final reply = _validatedCanonicalObject(
        canonicalJson: canonicalJson,
        expectedHashHex: draftHashHex,
        expectedPluginId: pluginId,
        expectedContractKind: 'moltbook_ambassador_reply_draft',
        expectedPeerHex: null,
      );
      if (reply == null ||
          reply['approval_required'] != true ||
          reply['target_post_id'] is! String ||
          reply['body'] is! String ||
          reply['safety_flags'] is! List) {
        return const PluginHostContractResult.rejected(
          code: 'runtime_result_invalid',
          message: 'WASM ambassador reply integrity or approval gate failed',
        );
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        ...reply,
        'draft_hash_hex': draftHashHex,
        'canonical_draft_json': canonicalJson,
      });
    }
    if (request.method == authorizeMoltbookDelegatedReplyMethod) {
      final authorizationHashHex =
          semantic?['authorization_hash_hex']?.toString() ?? '';
      final authorization = _validatedCanonicalObject(
        canonicalJson: canonicalJson,
        expectedHashHex: authorizationHashHex,
        expectedPluginId: pluginId,
        expectedContractKind:
            'moltbook_ambassador_delegated_reply_authorization',
        expectedPeerHex: null,
      );
      if (authorization == null ||
          authorization['publish_allowed'] != true ||
          authorization['human_review_required'] != false ||
          authorization['target_post_id'] is! String ||
          authorization['target_comment_id'] is! String ||
          authorization['engagement_plan_hash_hex'] is! String ||
          authorization['reply_draft_hash_hex'] is! String ||
          authorization['safety_flags'] is! List) {
        return const PluginHostContractResult.rejected(
          code: 'runtime_result_invalid',
          message: 'WASM delegated reply authorization gate failed',
        );
      }
      return PluginHostContractResult.executed(<String, dynamic>{
        ...authorization,
        'authorization_hash_hex': authorizationHashHex,
        'canonical_authorization_json': canonicalJson,
      });
    }
    final draftHashHex = semantic?['draft_hash_hex']?.toString() ?? '';
    final draft = _validatedCanonicalObject(
      canonicalJson: canonicalJson,
      expectedHashHex: draftHashHex,
      expectedPluginId: pluginId,
      expectedContractKind: contractKind,
      expectedPeerHex: null,
    );
    if (draft == null || draft['approval_required'] != true) {
      return const PluginHostContractResult.rejected(
        code: 'runtime_result_invalid',
        message: 'WASM ambassador draft integrity or approval gate failed',
      );
    }
    return PluginHostContractResult.executed(<String, dynamic>{
      ...draft,
      'draft_hash_hex': draftHashHex,
      'canonical_draft_json': canonicalJson,
    });
  }
}

Future<PluginHostContractResult?> _consensusPreflightAsync({
  required PluginHostApiRequest request,
  required PluginConsensusAsyncSignableReader? readSignable,
  required PluginConsensusSignableReader fallbackReadSignable,
  bool allowSoloWhenPeerMissing = false,
}) async {
  final peerHex =
      request.args['peer_hex']?.toString().trim().toLowerCase() ?? '';
  if (peerHex.isEmpty && allowSoloWhenPeerMissing) {
    return null;
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(peerHex)) {
    return const PluginHostContractResult.rejected(
      code: 'invalid_args',
      message: 'peer_hex must be a 64-char lowercase hex',
    );
  }
  final signable =
      readSignable == null
          ? fallbackReadSignable(peerHex)
          : await readSignable(peerHex);
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
  required String? expectedPeerHex,
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
        value['contract_kind'] != expectedContractKind) {
      return null;
    }
    if (expectedPeerHex != null && value['peer_hex'] != expectedPeerHex) {
      return null;
    }
    return value;
  } catch (_) {
    return null;
  }
}
