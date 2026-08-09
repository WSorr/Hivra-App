import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_scoped_secret_vault.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_provider_adapter.dart';

class MoltbookExternalEffectAdapter implements ExternalEffectAdapter {
  static const String postEffectKind = 'moltbook.post.create';
  static const String commentEffectKind = 'moltbook.comment.create';
  static const String effectKind = postEffectKind;

  final CapsuleScopedSecretVault _secretVault;
  final MoltbookProviderAdapter _provider;
  final DateTime Function() _clock;

  const MoltbookExternalEffectAdapter({
    required CapsuleScopedSecretVault secretVault,
    required MoltbookProviderAdapter provider,
    DateTime Function() clock = DateTime.now,
  }) : _secretVault = secretVault,
       _provider = provider,
       _clock = clock;

  @override
  Future<ExternalEffectAdapterResult> deliver(
    ExternalEffectAdapterRequest request,
  ) async {
    try {
      final payload = _validateRequest(request);
      final apiKey = await _loadCredential(request);
      final response = switch (payload) {
        _MoltbookPostPayload post => await _provider.createPost(
          apiKey: apiKey,
          submoltName: post.submoltName,
          title: post.title,
          content: post.content,
        ),
        _MoltbookCommentPayload comment => await _provider.createComment(
          apiKey: apiKey,
          postId: comment.postId,
          parentCommentId: comment.parentCommentId,
          content: comment.content,
        ),
      };
      final contentId = _contentId(response, payload);
      if (_verificationRequired(response)) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'verification_required',
          errorMessage:
              'Moltbook created hidden content that requires verification',
          requiredAction: _requiredAction(response, contentId),
          providerReferenceId: contentId,
        );
      }
      if (contentId == null) {
        return const ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'receipt_missing',
          errorMessage:
              'Moltbook accepted the request without a verifiable content id',
        );
      }
      return _success(request, contentId);
    } on MoltbookProviderException catch (error) {
      return _providerFailure(error);
    } on FormatException catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'invalid_effect_payload',
        errorMessage: error.message,
      );
    } on StateError catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'credential_unavailable',
        errorMessage: error.message,
      );
    }
  }

  @override
  Future<ExternalEffectAdapterResult> reconcile(
    ExternalEffectAdapterRequest request,
  ) async {
    try {
      final payload = _validateRequest(request);
      final apiKey = await _loadCredential(request);
      return switch (payload) {
        _MoltbookPostPayload post => await _reconcilePost(
          request,
          apiKey,
          post,
        ),
        _MoltbookCommentPayload comment => await _reconcileComment(
          request,
          apiKey,
          comment,
        ),
      };
    } on MoltbookProviderException catch (error) {
      return _providerFailure(error);
    } on FormatException catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'invalid_effect_payload',
        errorMessage: error.message,
      );
    } on StateError catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'credential_unavailable',
        errorMessage: error.message,
      );
    }
  }

  @override
  Future<ExternalEffectAdapterResult> resolveRequiredAction(
    ExternalEffectAdapterRequest request,
    ExternalEffectRequiredAction action,
    String response,
  ) async {
    try {
      final payload = _validateRequest(request);
      action.validate();
      if (action.kind != 'numeric_challenge') {
        throw const FormatException('Unsupported Moltbook required action');
      }
      final expiry = DateTime.parse(action.expiresAtUtc).toUtc();
      if (!_clock().toUtc().isBefore(expiry)) {
        return const ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.terminalFailure,
          errorCode: 'verification_expired',
          errorMessage:
              'Moltbook verification expired; blind publication retry is blocked',
        );
      }
      final answer = _normalizeNumericAnswer(response);
      final apiKey = await _loadCredential(request);
      final verification = await _provider.verifyContent(
        apiKey: apiKey,
        verificationCode: action.actionToken,
        answer: answer,
      );
      final contentId = _stringId(verification['content_id']);
      if (verification['success'] != true ||
          verification['content_type'] != payload.providerContentType ||
          contentId != action.providerReferenceId) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'verification_rejected',
          errorMessage: 'Moltbook did not accept the verification answer',
          requiredAction: action,
        );
      }
      final verifiedContentId = contentId!;
      // A successful challenge response is not proof that the content became
      // publicly visible. Re-observe the provider before minting a receipt.
      try {
        final reconciliation = switch (payload) {
          _MoltbookPostPayload post => await _reconcilePostById(
            request,
            apiKey,
            post,
            verifiedContentId,
          ),
          _MoltbookCommentPayload comment => await _reconcileComment(
            request,
            apiKey,
            comment,
          ),
        };
        return _afterResolvedRequiredAction(
          reconciliation,
          providerReferenceId: verifiedContentId,
        );
      } on MoltbookProviderException catch (error) {
        return _afterResolvedRequiredAction(
          _providerFailure(error),
          providerReferenceId: verifiedContentId,
        );
      }
    } on MoltbookProviderException catch (error) {
      if (error.code == 'provider_rejected' &&
          _clock().toUtc().isBefore(DateTime.parse(action.expiresAtUtc))) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'verification_rejected',
          errorMessage: error.message,
          requiredAction: action,
        );
      }
      return _providerFailure(error);
    } on FormatException catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'invalid_verification_answer',
        errorMessage: error.message,
        requiredAction: action,
      );
    } on StateError catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.terminalFailure,
        errorCode: 'credential_unavailable',
        errorMessage: error.message,
      );
    }
  }

  Future<String> _loadCredential(ExternalEffectAdapterRequest request) async {
    final value = await _secretVault.loadSecret(
      capsuleHex: request.ownerCapsuleHex,
      pluginId: request.pluginId,
      providerId: request.providerId,
      accountId: request.accountBindingId,
      secretName: MoltbookConnectionService.secretName,
    );
    if (value == null || value.trim().isEmpty) {
      throw StateError('Moltbook credential is unavailable for this Capsule');
    }
    return value;
  }

  _MoltbookPayload _validateRequest(ExternalEffectAdapterRequest request) {
    request.validate();
    if (request.providerId != MoltbookConnectionService.providerId ||
        request.pluginId != moltbookAmbassadorPluginId) {
      throw const FormatException('Unsupported Moltbook external effect');
    }
    final decoded = jsonDecode(request.canonicalPayloadJson);
    if (decoded is! Map) {
      throw const FormatException('Moltbook effect payload must be an object');
    }
    final json = Map<String, dynamic>.from(decoded);
    return switch (request.effectKind) {
      postEffectKind => _MoltbookPostPayload.fromJson(
        json,
        operationId: request.operationId,
      ),
      commentEffectKind => _MoltbookCommentPayload.fromJson(
        json,
        operationId: request.operationId,
      ),
      _ => throw const FormatException('Unsupported Moltbook effect kind'),
    };
  }

  Future<ExternalEffectAdapterResult> _reconcilePost(
    ExternalEffectAdapterRequest request,
    String apiKey,
    _MoltbookPostPayload payload,
  ) async {
    final providerReferenceId = request.providerReferenceId;
    if (providerReferenceId != null) {
      try {
        return await _reconcilePostById(
          request,
          apiKey,
          payload,
          providerReferenceId,
        );
      } on MoltbookProviderException catch (error) {
        if (error.code != 'http_400') rethrow;
      }
    }
    return _reconcilePostFromProfile(request, apiKey, payload);
  }

  Future<ExternalEffectAdapterResult> _reconcilePostFromProfile(
    ExternalEffectAdapterRequest request,
    String apiKey,
    _MoltbookPostPayload payload,
  ) async {
    final profile = await _provider.observeProfile(
      apiKey: apiKey,
      accountName: payload.accountName,
    );
    final recentPosts = profile['recentPosts'];
    if (recentPosts is! List) {
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'reconciliation_window_unavailable',
        errorMessage:
            'Moltbook profile did not expose a recent-post reconciliation window',
      );
    }
    for (final rawPost in recentPosts) {
      if (rawPost is! Map) continue;
      final post = Map<String, dynamic>.from(rawPost);
      final content = post['content']?.toString() ?? '';
      final title = post['title']?.toString() ?? '';
      final matches =
          payload.schemaVersion == 1
              ? content.contains(payload.operationMarker) &&
                  title == payload.title
              : content == payload.content && title == payload.title;
      if (matches && _isVerifiedPublicPost(post)) {
        final postId = _stringId(post['id'] ?? post['post_id']);
        if (postId != null) return _success(request, postId);
      }
    }
    return _receiptNotObserved();
  }

  Future<ExternalEffectAdapterResult> _reconcilePostById(
    ExternalEffectAdapterRequest request,
    String apiKey,
    _MoltbookPostPayload payload,
    String postId,
  ) async {
    final post = await _provider.observePost(apiKey, postId: postId);
    final matches =
        post.authorName == payload.accountName &&
        post.submoltName == payload.submoltName &&
        post.title == payload.title &&
        post.content == payload.content;
    if (!matches || !post.isVerified || post.isSpam) {
      return _receiptNotObserved();
    }
    return _success(request, post.postId);
  }

  Future<ExternalEffectAdapterResult> _reconcileComment(
    ExternalEffectAdapterRequest request,
    String apiKey,
    _MoltbookCommentPayload payload,
  ) async {
    final conversation = await _provider.observeConversation(
      apiKey,
      postId: payload.postId,
    );
    for (final comment in conversation.comments) {
      if (comment.authorName == payload.accountName &&
          comment.parentCommentId == payload.parentCommentId &&
          comment.content == payload.content) {
        return _success(request, comment.commentId);
      }
    }
    return _receiptNotObserved();
  }

  static ExternalEffectAdapterResult _receiptNotObserved() {
    // Absence in a bounded remote window does not prove that POST failed.
    return const ExternalEffectAdapterResult(
      status: ExternalEffectAdapterStatus.unresolved,
      errorCode: 'receipt_not_observed',
      errorMessage:
          'No matching receipt is visible yet; automatic resubmission is blocked',
    );
  }

  static ExternalEffectAdapterResult _afterResolvedRequiredAction(
    ExternalEffectAdapterResult result, {
    required String providerReferenceId,
  }) {
    if (result.status == ExternalEffectAdapterStatus.succeeded) return result;
    return ExternalEffectAdapterResult(
      status: ExternalEffectAdapterStatus.unresolved,
      requiredActionResolved: true,
      providerReferenceId: result.providerReferenceId ?? providerReferenceId,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    );
  }

  ExternalEffectAdapterResult _success(
    ExternalEffectAdapterRequest request,
    String postId,
  ) {
    final evidenceHash =
        sha256
            .convert(
              utf8.encode(
                '${request.operationId}\n$postId\n${request.payloadHashHex}',
              ),
            )
            .toString();
    return ExternalEffectAdapterResult(
      status: ExternalEffectAdapterStatus.succeeded,
      receipt: ExternalEffectReceipt(
        operationId: request.operationId,
        providerId: request.providerId,
        providerReceiptId: postId,
        evidenceHashHex: evidenceHash,
        receivedAtUtc: _clock().toUtc().toIso8601String(),
      ),
    );
  }

  ExternalEffectAdapterResult _providerFailure(
    MoltbookProviderException error,
  ) {
    final status =
        error.code == 'timeout' || error.code == 'network_error'
            ? ExternalEffectAdapterStatus.unresolved
            : error.retryable
            ? ExternalEffectAdapterStatus.retryableFailure
            : ExternalEffectAdapterStatus.terminalFailure;
    return ExternalEffectAdapterResult(
      status: status,
      errorCode: error.code,
      errorMessage: error.message,
    );
  }

  static String? _contentId(
    Map<String, dynamic> response,
    _MoltbookPayload payload,
  ) {
    final raw =
        response[payload.providerContentType] ??
        response['data'] ??
        response['content'];
    if (raw is Map) {
      return _stringId(raw['id'] ?? raw['${payload.providerContentType}_id']);
    }
    return _stringId(response['${payload.providerContentType}_id']);
  }

  static bool _verificationRequired(Map<String, dynamic> response) {
    if (response['verification_required'] == true ||
        response['verification'] is Map) {
      return true;
    }
    final rawContent =
        response['post'] ?? response['comment'] ?? response['data'];
    if (rawContent is! Map) return false;
    final content = Map<String, dynamic>.from(rawContent);
    final verificationStatus =
        content['verification_status']?.toString().trim().toLowerCase();
    return content['verification_required'] == true ||
        content['verification'] is Map ||
        verificationStatus == 'pending';
  }

  static ExternalEffectRequiredAction? _requiredAction(
    Map<String, dynamic> response,
    String? contentId,
  ) {
    final rawContent =
        response['post'] ?? response['comment'] ?? response['data'];
    if (contentId == null || rawContent is! Map) return null;
    final content = Map<String, dynamic>.from(rawContent);
    final rawVerification = content['verification'];
    if (rawVerification is! Map) return null;
    final verification = Map<String, dynamic>.from(rawVerification);
    final code = verification['verification_code']?.toString().trim() ?? '';
    final prompt = verification['challenge_text']?.toString().trim() ?? '';
    final expiresAt = verification['expires_at']?.toString().trim() ?? '';
    if (code.isEmpty || prompt.isEmpty || expiresAt.isEmpty) return null;
    try {
      final action = ExternalEffectRequiredAction(
        kind: 'numeric_challenge',
        providerReferenceId: contentId,
        actionToken: code,
        prompt: prompt,
        expiresAtUtc: DateTime.parse(expiresAt).toUtc().toIso8601String(),
      );
      action.validate();
      return action;
    } catch (_) {
      return null;
    }
  }

  static String _normalizeNumericAnswer(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final number = double.tryParse(normalized);
    if (number == null ||
        !number.isFinite ||
        !RegExp(r'^[-+]?\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
      throw const FormatException(
        'Verification answer must be a number with at most 2 decimal places',
      );
    }
    return number.toStringAsFixed(2);
  }

  static bool _isVerifiedPublicPost(Map<String, dynamic> post) {
    final verificationStatus =
        post['verification_status']?.toString().trim().toLowerCase();
    return verificationStatus == 'verified' && post['is_spam'] == false;
  }

  static String? _stringId(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty || normalized.length > 256 ? null : normalized;
  }
}

sealed class _MoltbookPayload {
  String get accountName;
  String get content;
  String get providerContentType;
}

class _MoltbookPostPayload implements _MoltbookPayload {
  final int schemaVersion;
  @override
  final String accountName;
  final String submoltName;
  final String title;
  @override
  final String content;
  final String operationMarker;

  @override
  String get providerContentType => 'post';

  const _MoltbookPostPayload({
    required this.schemaVersion,
    required this.accountName,
    required this.submoltName,
    required this.title,
    required this.content,
    required this.operationMarker,
  });

  factory _MoltbookPostPayload.fromJson(
    Map<String, dynamic> json, {
    required String operationId,
  }) {
    const allowedFields = <String>{
      'schema_version',
      'account_name',
      'submolt_name',
      'title',
      'content',
      'operation_marker',
      'source_draft_hash_hex',
    };
    if (json.keys.any((field) => !allowedFields.contains(field))) {
      throw const FormatException(
        'Moltbook post payload contains unsupported fields',
      );
    }
    final schemaVersion = json['schema_version'];
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw const FormatException('Unsupported Moltbook post payload schema');
    }
    final payload = _MoltbookPostPayload(
      schemaVersion: schemaVersion as int,
      accountName: _required(json, 'account_name', 128),
      submoltName: _required(json, 'submolt_name', 128),
      title: _required(json, 'title', 300),
      content: _required(json, 'content', 40000),
      operationMarker: _required(json, 'operation_marker', 256),
    );
    final expectedMarker = MoltbookPublicationContract.operationMarker(
      operationId,
    );
    final markerMatches =
        payload.schemaVersion == 1
            ? MoltbookPublicationContract.matchesLegacyApprovedContent(
              operationId: operationId,
              operationMarker: payload.operationMarker,
              content: payload.content,
            )
            : payload.operationMarker == expectedMarker &&
                !payload.content.contains(payload.operationMarker) &&
                payload.content.endsWith(
                  MoltbookPublicationContract.attribution(),
                );
    if (!markerMatches) {
      throw const FormatException('Moltbook operation marker mismatch');
    }
    if (!RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$',
    ).hasMatch(payload.submoltName)) {
      throw const FormatException('Invalid Moltbook submolt name');
    }
    return payload;
  }

  static String _required(Map<String, dynamic> json, String field, int max) {
    final value = json[field];
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw FormatException('Invalid Moltbook post field: $field');
    }
    return value;
  }
}

class _MoltbookCommentPayload implements _MoltbookPayload {
  @override
  final String accountName;
  final String postId;
  final String? parentCommentId;
  @override
  final String content;
  final String operationMarker;

  const _MoltbookCommentPayload({
    required this.accountName,
    required this.postId,
    required this.parentCommentId,
    required this.content,
    required this.operationMarker,
  });

  @override
  String get providerContentType => 'comment';

  factory _MoltbookCommentPayload.fromJson(
    Map<String, dynamic> json, {
    required String operationId,
  }) {
    const allowedFields = <String>{
      'schema_version',
      'engagement_id',
      'account_name',
      'post_id',
      'parent_comment_id',
      'content',
      'operation_marker',
      'source_draft_hash_hex',
      'engagement_plan_hash_hex',
    };
    if (json.keys.any((field) => !allowedFields.contains(field))) {
      throw const FormatException(
        'Moltbook comment payload contains unsupported fields',
      );
    }
    final schemaVersion = json['schema_version'];
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw const FormatException(
        'Unsupported Moltbook comment payload schema',
      );
    }
    if (schemaVersion == 2 &&
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(json['engagement_id']?.toString() ?? '')) {
      throw const FormatException('Invalid Moltbook engagement identity');
    }
    final rawParent = json['parent_comment_id'];
    if (rawParent != null && rawParent is! String) {
      throw const FormatException('Invalid Moltbook comment parent');
    }
    final payload = _MoltbookCommentPayload(
      accountName: _MoltbookPostPayload._required(json, 'account_name', 128),
      postId: _MoltbookPostPayload._required(json, 'post_id', 256),
      parentCommentId:
          rawParent == null || rawParent.trim().isEmpty
              ? null
              : rawParent.trim(),
      content: _MoltbookPostPayload._required(json, 'content', 2000),
      operationMarker: _MoltbookPostPayload._required(
        json,
        'operation_marker',
        256,
      ),
    );
    final idPattern = RegExp(r'^[A-Za-z0-9-]{1,256}$');
    if (!idPattern.hasMatch(payload.postId) ||
        (payload.parentCommentId != null &&
            !idPattern.hasMatch(payload.parentCommentId!)) ||
        payload.operationMarker !=
            MoltbookPublicationContract.operationMarker(operationId) ||
        payload.content.contains(payload.operationMarker)) {
      throw const FormatException('Invalid Moltbook comment effect payload');
    }
    return payload;
  }
}
