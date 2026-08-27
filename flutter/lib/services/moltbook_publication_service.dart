import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/moltbook_provider_models.dart';
import '../models/plugin_contract_ids.dart';
import 'external_effect_service.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_external_effect_adapter.dart';

class MoltbookPublicationService {
  static const String personFirstRuntimeSubmoltName =
      moltbookPersonFirstRuntimeSubmoltName;
  static const String personFirstRuntimeSubmoltDisplayName =
      moltbookPersonFirstRuntimeSubmoltDisplayName;
  static const String personFirstRuntimeSubmoltDescription =
      moltbookPersonFirstRuntimeSubmoltDescription;
  static const String defaultSubmolt = 'general';
  static const String replyActionClass = 'reply_draft';
  static final Map<String, Future<void>> _engagementTails =
      <String, Future<void>>{};

  final ExternalEffectService _effects;
  final Future<MoltbookConnectionBinding?> Function() _loadBinding;

  MoltbookPublicationService({
    required MoltbookConnectionService connection,
    required ExternalEffectService effects,
  }) : _effects = effects,
       _loadBinding = connection.loadBinding;

  MoltbookPublicationService.withBindingLoader({
    required ExternalEffectService effects,
    required Future<MoltbookConnectionBinding?> Function() loadBinding,
  }) : _effects = effects,
       _loadBinding = loadBinding;

  Future<ExternalEffectOperation> prepare({
    required MoltbookDraftPreview draft,
    required String submoltName,
  }) async {
    final binding = await _loadBinding();
    if (binding == null) {
      throw StateError('Connect a Moltbook account before publication');
    }
    if (!binding.isClaimed || !binding.isActive) {
      throw StateError('Moltbook account must be claimed and active');
    }
    final submolt = submoltName.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(submolt)) {
      throw const FormatException('Invalid Moltbook submolt name');
    }
    final semanticId =
        sha256
            .convert(
              utf8.encode(
                '${binding.accountId}\n$submolt\n${draft.draftHashHex}',
              ),
            )
            .toString();
    final operationId = 'moltbook-post-$semanticId';
    final marker = MoltbookPublicationContract.operationMarker(operationId);
    final attribution = MoltbookPublicationContract.attribution();
    final content = '${draft.body.trimRight()}\n\n$attribution';
    final ownerHex = _effects.activeOwnerCapsuleHex;
    final publicEffectKey = _postEffectKey(
      accountBindingId: binding.accountId,
      accountName: binding.accountName,
      submoltName: submolt,
      title: draft.title,
      content: content,
    );
    final canonicalPayload = jsonEncode(<String, dynamic>{
      'schema_version': 2,
      'account_name': binding.accountName,
      'submolt_name': submolt,
      'title': draft.title,
      'content': content,
      'operation_marker': marker,
      'source_draft_hash_hex': draft.draftHashHex,
    });
    return _withEngagementLock('$ownerHex::post::$publicEffectKey', () async {
      _requireSameOwner(ownerHex);
      final existing = (await list())
          .where(
            (operation) =>
                operation.state != ExternalEffectState.cancelled &&
                _postEffectKeyForOperation(operation) == publicEffectKey,
          )
          .toList(growable: false);
      final succeeded = existing
          .where(
            (operation) => operation.state == ExternalEffectState.succeeded,
          )
          .toList(growable: false);
      if (succeeded.length > 1) {
        throw StateError(
          'Moltbook post has conflicting succeeded publication effects',
        );
      }
      if (succeeded.isNotEmpty) return succeeded.single;
      if (existing.length > 1) {
        throw StateError('Moltbook post has conflicting publication effects');
      }
      if (existing.isNotEmpty) {
        final operation = existing.single;
        if (operation.state == ExternalEffectState.terminalFailure) {
          throw StateError(
            'The exact Moltbook post has an unresolved delivery history; '
            'change the reviewed text before preparing another effect',
          );
        }
        return operation;
      }
      _requireSameOwner(ownerHex);
      return _effects.prepare(
        operationId: operationId,
        pluginId: moltbookAmbassadorPluginId,
        providerId: MoltbookConnectionService.providerId,
        accountBindingId: binding.accountId,
        effectKind: MoltbookExternalEffectAdapter.effectKind,
        canonicalPayloadJson: canonicalPayload,
      );
    });
  }

  Future<ExternalEffectOperation> preparePersonFirstRuntimeCommunity() async {
    final binding = await _loadBinding();
    if (binding == null) {
      throw StateError(
        'Connect a Moltbook account before creating a community',
      );
    }
    if (!binding.isClaimed || !binding.isActive) {
      throw StateError('Moltbook account must be claimed and active');
    }
    final ownerHex = _effects.activeOwnerCapsuleHex;
    final canonicalPayload = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'name': personFirstRuntimeSubmoltName,
      'display_name': personFirstRuntimeSubmoltDisplayName,
      'description': personFirstRuntimeSubmoltDescription,
    });
    final semanticId =
        sha256
            .convert(
              utf8.encode('$ownerHex\n${binding.accountId}\n$canonicalPayload'),
            )
            .toString();
    final operationId = 'moltbook-submolt-$semanticId';
    return _withEngagementLock(
      '$ownerHex::submolt::$personFirstRuntimeSubmoltName',
      () async {
        _requireSameOwner(ownerHex);
        return _effects.prepare(
          operationId: operationId,
          pluginId: moltbookAmbassadorPluginId,
          providerId: MoltbookConnectionService.providerId,
          accountBindingId: binding.accountId,
          effectKind: MoltbookExternalEffectAdapter.submoltEffectKind,
          canonicalPayloadJson: canonicalPayload,
        );
      },
    );
  }

  Future<ExternalEffectOperation> prepareReply({
    required MoltbookReplyDraftPreview draft,
  }) async {
    final binding = await _loadBinding();
    if (binding == null) {
      throw StateError('Connect a Moltbook account before replying');
    }
    if (!binding.isClaimed || !binding.isActive) {
      throw StateError('Moltbook account must be claimed and active');
    }
    final ownerHex = _effects.activeOwnerCapsuleHex;
    final engagementId = replyEngagementId(
      ownerCapsuleHex: ownerHex,
      accountBindingId: binding.accountId,
      postId: draft.targetPostId,
      parentCommentId: draft.targetCommentId,
    );
    final semanticId =
        sha256
            .convert(
              utf8.encode(
                '${binding.accountId}\n'
                '${draft.targetPostId}\n'
                '${draft.targetCommentId ?? ""}\n'
                '${draft.draftHashHex}',
              ),
            )
            .toString();
    final operationId = 'moltbook-comment-$semanticId';
    final marker = MoltbookPublicationContract.operationMarker(operationId);
    final canonicalPayload = jsonEncode(<String, dynamic>{
      'schema_version': 2,
      'engagement_id': engagementId,
      'account_name': binding.accountName,
      'post_id': draft.targetPostId,
      'parent_comment_id': draft.targetCommentId,
      'content': draft.body,
      'operation_marker': marker,
      'source_draft_hash_hex': draft.draftHashHex,
      'engagement_plan_hash_hex': draft.engagementPlanHashHex,
    });
    final lockKey = '$ownerHex::$engagementId';
    return _withEngagementLock(lockKey, () async {
      _requireSameOwner(ownerHex);
      final matching = await findReplyOperations(
        accountBindingId: binding.accountId,
        postId: draft.targetPostId,
        parentCommentId: draft.targetCommentId,
      );
      final blocking = matching
          .where(
            (operation) =>
                !operation.state.isTerminal ||
                operation.state == ExternalEffectState.succeeded,
          )
          .toList(growable: false);
      if (blocking.length > 1) {
        throw StateError(
          'Moltbook engagement has conflicting active publication effects',
        );
      }
      if (blocking.isNotEmpty) {
        final existing = blocking.single;
        if (existing.state == ExternalEffectState.succeeded) {
          throw StateError('Moltbook engagement is already published');
        }
        if (_sameReplyDraft(existing, draft)) return existing;
        throw StateError(
          'Moltbook engagement already has an active immutable reply',
        );
      }
      _requireSameOwner(ownerHex);
      return _effects.prepare(
        operationId: operationId,
        pluginId: moltbookAmbassadorPluginId,
        providerId: MoltbookConnectionService.providerId,
        accountBindingId: binding.accountId,
        effectKind: MoltbookExternalEffectAdapter.commentEffectKind,
        canonicalPayloadJson: canonicalPayload,
      );
    });
  }

  Future<List<ExternalEffectOperation>> findReplyOperations({
    required String accountBindingId,
    required String postId,
    required String? parentCommentId,
  }) async {
    final ownerHex = _effects.activeOwnerCapsuleHex;
    final expectedId = replyEngagementId(
      ownerCapsuleHex: ownerHex,
      accountBindingId: accountBindingId,
      postId: postId,
      parentCommentId: parentCommentId,
    );
    final operations = await _effects.list(
      pluginId: moltbookAmbassadorPluginId,
    );
    return operations
        .where(
          (operation) =>
              operation.effectKind ==
                  MoltbookExternalEffectAdapter.commentEffectKind &&
              operation.accountBindingId == accountBindingId &&
              _replyEngagementId(operation) == expectedId,
        )
        .toList(growable: false);
  }

  Future<bool> isReplyTargetUnavailable({
    required String accountBindingId,
    required String postId,
    required String parentCommentId,
  }) async {
    final matching = await findReplyOperations(
      accountBindingId: accountBindingId,
      postId: postId,
      parentCommentId: parentCommentId,
    );
    return matching.isNotEmpty;
  }

  Future<ExternalEffectOperation> approveAndQueue(
    ExternalEffectOperation operation,
  ) async {
    _validateMoltbookOperation(operation);
    await _assertNoReplyConflict(operation);
    final approvalKind =
        operation.effectKind == MoltbookExternalEffectAdapter.submoltEffectKind
            ? 'permanent_community_creation'
            : 'permanent_publication';
    final evidenceHash =
        sha256
            .convert(
              utf8.encode(
                jsonEncode(<String, dynamic>{
                  'schema_version': 1,
                  'approval_kind': approvalKind,
                  'operation_id': operation.operationId,
                  'provider_id': operation.providerId,
                  'account_binding_id': operation.accountBindingId,
                  'payload_hash_hex': operation.payloadHashHex,
                  'permanence_acknowledged': true,
                }),
              ),
            )
            .toString();
    if (canReauthorizeRejectedDelivery(operation)) {
      return _effects.reauthorizeRejectedDelivery(
        pluginId: moltbookAmbassadorPluginId,
        operationId: operation.operationId,
        approvalEvidenceHashHex: evidenceHash,
      );
    }
    await _effects.approve(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
      approvalEvidenceHashHex: evidenceHash,
    );
    return _effects.enqueue(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
    );
  }

  static bool canReauthorizeRejectedDelivery(
    ExternalEffectOperation operation,
  ) {
    return operation.state == ExternalEffectState.terminalFailure &&
        operation.approvalEvidenceHashHex != null &&
        operation.receipt == null &&
        operation.requiredAction == null &&
        operation.attemptCount > 0 &&
        const <String>{
          'credential_rejected',
          'permission_rejected',
        }.contains(operation.lastErrorCode);
  }

  Future<ExternalEffectOperation> approveDelegatedReplyAndQueue({
    required ExternalEffectOperation operation,
    required MoltbookDelegatedReplyAuthorization authorization,
  }) async {
    validateDelegatedReplyBinding(operation, authorization);
    await _assertNoReplyConflict(operation);
    await _effects.approve(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
      approvalEvidenceHashHex: authorization.authorizationHashHex,
    );
    return _effects.enqueue(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operation.operationId,
    );
  }

  Future<ExternalEffectOperation> process(String operationId) async {
    final operation = await _operationById(operationId);
    await _assertNoReplyConflict(operation);
    return _effects.process(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
    );
  }

  Future<ExternalEffectOperation> reconcileOnly(
    String operationId, {
    String? providerReferenceId,
  }) {
    return _effects.reconcileOnly(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
      providerReferenceId: providerReferenceId,
    );
  }

  static bool canManuallyReconcileTerminalFailure(
    ExternalEffectOperation operation,
  ) {
    return operation.state == ExternalEffectState.terminalFailure &&
        operation.receipt == null &&
        operation.attemptCount > 0 &&
        const <String>{
          'http_400',
          'required_action_expired',
          'verification_expired',
        }.contains(operation.lastErrorCode);
  }

  static bool requiresReconciliation(ExternalEffectOperation operation) {
    if (operation.state == ExternalEffectState.unresolved &&
        operation.requiredAction == null) {
      return true;
    }
    return canManuallyReconcileTerminalFailure(operation) &&
        operation.providerReferenceId != null;
  }

  static Set<String> supersededPostFailureIds(
    Iterable<ExternalEffectOperation> operations,
  ) {
    final succeededKeys = <String>{};
    for (final operation in operations) {
      if (operation.state == ExternalEffectState.succeeded &&
          operation.receipt != null &&
          operation.effectKind ==
              MoltbookExternalEffectAdapter.postEffectKind) {
        succeededKeys.add(_postEffectKeyForOperation(operation));
      }
    }
    return operations
        .where(
          (operation) =>
              operation.state == ExternalEffectState.terminalFailure &&
              operation.effectKind ==
                  MoltbookExternalEffectAdapter.postEffectKind &&
              succeededKeys.contains(_postEffectKeyForOperation(operation)),
        )
        .map((operation) => operation.operationId)
        .toSet();
  }

  Future<ExternalEffectOperation> resolveVerification({
    required String operationId,
    required String answer,
  }) {
    return _effects.resolveRequiredAction(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
      response: answer,
    );
  }

  Future<List<ExternalEffectOperation>> list() {
    return _effects.list(pluginId: moltbookAmbassadorPluginId);
  }

  Future<ExternalEffectOperation> cancel(String operationId) {
    return _effects.cancel(
      pluginId: moltbookAmbassadorPluginId,
      operationId: operationId,
    );
  }

  static Map<String, dynamic> decodePayload(ExternalEffectOperation operation) {
    _validateMoltbookOperation(operation);
    final decoded = jsonDecode(operation.canonicalPayloadJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid Moltbook publication payload');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static bool isPersonFirstRuntimeCommunityOperation(
    ExternalEffectOperation operation,
  ) {
    if (operation.effectKind !=
        MoltbookExternalEffectAdapter.submoltEffectKind) {
      return false;
    }
    final payload = decodePayload(operation);
    return payload['name'] == personFirstRuntimeSubmoltName &&
        payload['display_name'] == personFirstRuntimeSubmoltDisplayName &&
        payload['description'] == personFirstRuntimeSubmoltDescription;
  }

  static String? succeededPostDraftHash(ExternalEffectOperation operation) {
    if (operation.state != ExternalEffectState.succeeded ||
        operation.effectKind != MoltbookExternalEffectAdapter.postEffectKind) {
      return null;
    }
    final value = decodePayload(operation)['source_draft_hash_hex'];
    if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException(
        'Succeeded Moltbook post has an invalid source draft hash',
      );
    }
    return value;
  }

  static String replyEngagementId({
    required String ownerCapsuleHex,
    required String accountBindingId,
    required String postId,
    required String? parentCommentId,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'capsule_root': ownerCapsuleHex.trim().toLowerCase(),
      'plugin_id': moltbookAmbassadorPluginId,
      'provider_id': MoltbookConnectionService.providerId,
      'provider_account_id': accountBindingId.trim(),
      'post_id': postId.trim(),
      'action_class': replyActionClass,
      'parent_comment_id_or_root':
          parentCommentId?.trim().isNotEmpty == true
              ? parentCommentId!.trim()
              : 'root',
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Uri? publishedPostUri(ExternalEffectOperation operation) {
    final receipt = operation.receipt;
    if (operation.state != ExternalEffectState.succeeded ||
        receipt == null ||
        receipt.providerId != MoltbookConnectionService.providerId) {
      return null;
    }
    if (!const <String>{
      MoltbookExternalEffectAdapter.postEffectKind,
      MoltbookExternalEffectAdapter.commentEffectKind,
    }.contains(operation.effectKind)) {
      return null;
    }
    final payload = decodePayload(operation);
    final postId =
        operation.effectKind == MoltbookExternalEffectAdapter.commentEffectKind
            ? payload['post_id']?.toString().trim() ?? ''
            : receipt.providerReceiptId.trim();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(postId)) {
      return null;
    }
    return Uri.https('www.moltbook.com', '/post/$postId');
  }

  static void validateDelegatedReplyBinding(
    ExternalEffectOperation operation,
    MoltbookDelegatedReplyAuthorization authorization,
  ) {
    _validateMoltbookOperation(operation);
    if (operation.effectKind !=
        MoltbookExternalEffectAdapter.commentEffectKind) {
      throw const FormatException('Delegation permits Moltbook replies only');
    }
    if (authorization.targetCommentId == null) {
      throw const FormatException(
        'Delegated reply requires an exact parent comment',
      );
    }
    final payload = decodePayload(operation);
    if (payload['post_id'] != authorization.targetPostId ||
        payload['parent_comment_id'] != authorization.targetCommentId ||
        payload['source_draft_hash_hex'] != authorization.replyDraftHashHex ||
        payload['engagement_plan_hash_hex'] !=
            authorization.engagementPlanHashHex) {
      throw const FormatException(
        'Delegated authorization does not bind this exact reply effect',
      );
    }
  }

  static void _validateMoltbookOperation(ExternalEffectOperation operation) {
    operation.validate();
    if (operation.pluginId != moltbookAmbassadorPluginId ||
        operation.providerId != MoltbookConnectionService.providerId ||
        !const <String>{
          MoltbookExternalEffectAdapter.postEffectKind,
          MoltbookExternalEffectAdapter.commentEffectKind,
          MoltbookExternalEffectAdapter.submoltEffectKind,
        }.contains(operation.effectKind)) {
      throw const FormatException('Operation is not a Moltbook publication');
    }
  }

  Future<ExternalEffectOperation> _operationById(String operationId) async {
    final operations = await list();
    return operations.firstWhere(
      (operation) => operation.operationId == operationId,
      orElse: () => throw StateError('Moltbook publication was not found'),
    );
  }

  Future<void> _assertNoReplyConflict(ExternalEffectOperation operation) async {
    if (operation.effectKind !=
        MoltbookExternalEffectAdapter.commentEffectKind) {
      return;
    }
    final payload = decodePayload(operation);
    final matching = await findReplyOperations(
      accountBindingId: operation.accountBindingId,
      postId: payload['post_id']?.toString() ?? '',
      parentCommentId: payload['parent_comment_id']?.toString(),
    );
    final blocking = matching
        .where(
          (candidate) =>
              !candidate.state.isTerminal ||
              candidate.state == ExternalEffectState.succeeded,
        )
        .toList(growable: false);
    if (blocking.length > 1 ||
        (blocking.length == 1 &&
            blocking.single.operationId != operation.operationId)) {
      throw StateError(
        'Moltbook engagement has conflicting active publication effects',
      );
    }
  }

  static String _replyEngagementId(ExternalEffectOperation operation) {
    final payload = decodePayload(operation);
    final schemaVersion = payload['schema_version'];
    final postId = payload['post_id'];
    final parentCommentId = payload['parent_comment_id'];
    if ((schemaVersion != 1 && schemaVersion != 2) ||
        postId is! String ||
        postId.trim().isEmpty ||
        (parentCommentId != null && parentCommentId is! String)) {
      throw const FormatException('Invalid Moltbook reply target in journal');
    }
    final derived = replyEngagementId(
      ownerCapsuleHex: operation.ownerCapsuleHex,
      accountBindingId: operation.accountBindingId,
      postId: postId,
      parentCommentId: parentCommentId as String?,
    );
    final embedded = payload['engagement_id'];
    if ((schemaVersion == 2 && embedded is! String) ||
        (embedded != null && embedded != derived)) {
      throw const FormatException('Moltbook engagement identity mismatch');
    }
    return derived;
  }

  static bool _sameReplyDraft(
    ExternalEffectOperation operation,
    MoltbookReplyDraftPreview draft,
  ) {
    final payload = decodePayload(operation);
    return payload['source_draft_hash_hex'] == draft.draftHashHex &&
        payload['engagement_plan_hash_hex'] == draft.engagementPlanHashHex &&
        payload['content'] == draft.body;
  }

  static String _postEffectKeyForOperation(ExternalEffectOperation operation) {
    _validateMoltbookOperation(operation);
    if (operation.effectKind != MoltbookExternalEffectAdapter.postEffectKind) {
      return '';
    }
    final payload = decodePayload(operation);
    return _postEffectKey(
      accountBindingId: operation.accountBindingId,
      accountName: payload['account_name']?.toString() ?? '',
      submoltName: payload['submolt_name']?.toString() ?? '',
      title: payload['title']?.toString() ?? '',
      content: payload['content']?.toString() ?? '',
    );
  }

  static String _postEffectKey({
    required String accountBindingId,
    required String accountName,
    required String submoltName,
    required String title,
    required String content,
  }) {
    final canonical = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'provider_id': MoltbookConnectionService.providerId,
      'account_binding_id': accountBindingId,
      'account_name': accountName,
      'submolt_name': submoltName,
      'title': title,
      'content': content,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  void _requireSameOwner(String ownerHex) {
    if (_effects.activeOwnerCapsuleHex != ownerHex) {
      throw StateError('Active Capsule changed during Moltbook preparation');
    }
  }

  static Future<T> _withEngagementLock<T>(
    String key,
    Future<T> Function() action,
  ) {
    final previous = _engagementTails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _engagementTails[key] = completer.future;
    return () async {
      await previous.catchError((_) {});
      try {
        return await action();
      } finally {
        completer.complete();
        if (identical(_engagementTails[key], completer.future)) {
          _engagementTails.remove(key);
        }
      }
    }();
  }
}
