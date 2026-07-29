import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/plugin_contract_ids.dart';
import 'capsule_scoped_secret_vault.dart';
import 'moltbook_connection_service.dart';
import 'moltbook_provider_adapter.dart';

class MoltbookExternalEffectAdapter implements ExternalEffectAdapter {
  static const String effectKind = 'moltbook.post.create';

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
      final response = await _provider.createPost(
        apiKey: apiKey,
        submoltName: payload.submoltName,
        title: payload.title,
        content: payload.content,
      );
      final postId = _postId(response);
      if (_verificationRequired(response)) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'verification_required',
          errorMessage:
              'Moltbook created hidden content that requires verification',
          requiredAction: _requiredAction(response, postId),
        );
      }
      if (postId == null) {
        return const ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'receipt_missing',
          errorMessage:
              'Moltbook accepted the request without a verifiable post id',
        );
      }
      return _success(request, postId);
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
        if (content.contains(payload.operationMarker) &&
            title == payload.title) {
          final postId = _stringId(post['id'] ?? post['post_id']);
          if (postId != null) return _success(request, postId);
        }
      }

      // Absence in a bounded remote window does not prove that POST failed.
      return const ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'receipt_not_observed',
        errorMessage:
            'No matching receipt is visible yet; automatic resubmission is blocked',
      );
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
      _validateRequest(request);
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
          verification['content_type'] != 'post' ||
          contentId != action.providerReferenceId) {
        return ExternalEffectAdapterResult(
          status: ExternalEffectAdapterStatus.unresolved,
          errorCode: 'verification_rejected',
          errorMessage: 'Moltbook did not accept the verification answer',
          requiredAction: action,
        );
      }
      return _success(request, contentId!);
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

  _MoltbookPostPayload _validateRequest(ExternalEffectAdapterRequest request) {
    request.validate();
    if (request.providerId != MoltbookConnectionService.providerId ||
        request.pluginId != moltbookAmbassadorPluginId ||
        request.effectKind != effectKind) {
      throw const FormatException('Unsupported Moltbook external effect');
    }
    final decoded = jsonDecode(request.canonicalPayloadJson);
    if (decoded is! Map) {
      throw const FormatException('Moltbook effect payload must be an object');
    }
    return _MoltbookPostPayload.fromJson(
      Map<String, dynamic>.from(decoded),
      operationId: request.operationId,
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

  static String? _postId(Map<String, dynamic> response) {
    final raw = response['post'] ?? response['data'];
    if (raw is Map) {
      return _stringId(raw['id'] ?? raw['post_id']);
    }
    return _stringId(response['post_id']);
  }

  static bool _verificationRequired(Map<String, dynamic> response) {
    if (response['verification_required'] == true ||
        response['verification'] is Map) {
      return true;
    }
    final rawPost = response['post'] ?? response['data'];
    if (rawPost is! Map) return false;
    final post = Map<String, dynamic>.from(rawPost);
    final verificationStatus =
        post['verification_status']?.toString().trim().toLowerCase();
    return post['verification_required'] == true ||
        post['verification'] is Map ||
        verificationStatus == 'pending';
  }

  static ExternalEffectRequiredAction? _requiredAction(
    Map<String, dynamic> response,
    String? postId,
  ) {
    final rawPost = response['post'] ?? response['data'];
    if (postId == null || rawPost is! Map) return null;
    final post = Map<String, dynamic>.from(rawPost);
    final rawVerification = post['verification'];
    if (rawVerification is! Map) return null;
    final verification = Map<String, dynamic>.from(rawVerification);
    final code = verification['verification_code']?.toString().trim() ?? '';
    final prompt = verification['challenge_text']?.toString().trim() ?? '';
    final expiresAt = verification['expires_at']?.toString().trim() ?? '';
    if (code.isEmpty || prompt.isEmpty || expiresAt.isEmpty) return null;
    try {
      final action = ExternalEffectRequiredAction(
        kind: 'numeric_challenge',
        providerReferenceId: postId,
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

  static String? _stringId(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty || normalized.length > 256 ? null : normalized;
  }
}

class _MoltbookPostPayload {
  final String accountName;
  final String submoltName;
  final String title;
  final String content;
  final String operationMarker;

  const _MoltbookPostPayload({
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
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported Moltbook post payload schema');
    }
    final payload = _MoltbookPostPayload(
      accountName: _required(json, 'account_name', 128),
      submoltName: _required(json, 'submolt_name', 128),
      title: _required(json, 'title', 300),
      content: _required(json, 'content', 40000),
      operationMarker: _required(json, 'operation_marker', 256),
    );
    if (!MoltbookPublicationContract.matchesApprovedContent(
      operationId: operationId,
      operationMarker: payload.operationMarker,
      content: payload.content,
    )) {
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
