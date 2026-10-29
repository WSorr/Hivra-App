import 'dart:convert';

enum ExternalEffectState {
  prepared,
  approved,
  queued,
  delivering,
  unresolved,
  succeeded,
  terminalFailure,
  cancelled;

  String get wireName => switch (this) {
    ExternalEffectState.terminalFailure => 'terminal_failure',
    _ => name,
  };

  bool get isTerminal =>
      this == ExternalEffectState.succeeded ||
      this == ExternalEffectState.terminalFailure ||
      this == ExternalEffectState.cancelled;

  static ExternalEffectState fromWire(String value) {
    return ExternalEffectState.values.firstWhere(
      (state) => state.wireName == value,
      orElse:
          () =>
              throw FormatException(
                'Unsupported external effect state: $value',
              ),
    );
  }
}

enum ExternalEffectAdapterStatus {
  succeeded,
  notFound,
  unresolved,
  retryableFailure,
  terminalFailure,
}

class ExternalEffectReceipt {
  final String operationId;
  final String providerId;
  final String providerReceiptId;
  final String evidenceHashHex;
  final String receivedAtUtc;

  const ExternalEffectReceipt({
    required this.operationId,
    required this.providerId,
    required this.providerReceiptId,
    required this.evidenceHashHex,
    required this.receivedAtUtc,
  });

  factory ExternalEffectReceipt.fromJson(Map<String, dynamic> json) {
    final receipt = ExternalEffectReceipt(
      operationId: json['operation_id']?.toString() ?? '',
      providerId: json['provider_id']?.toString() ?? '',
      providerReceiptId: json['provider_receipt_id']?.toString() ?? '',
      evidenceHashHex: json['evidence_hash_hex']?.toString() ?? '',
      receivedAtUtc: json['received_at_utc']?.toString() ?? '',
    );
    receipt.validate();
    return receipt;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operation_id': operationId,
    'provider_id': providerId,
    'provider_receipt_id': providerReceiptId,
    'evidence_hash_hex': evidenceHashHex,
    'received_at_utc': receivedAtUtc,
  };

  void validate() {
    _validateIdentifier('operation_id', operationId);
    _validateIdentifier('provider_id', providerId);
    _validateBounded('provider_receipt_id', providerReceiptId, 1, 256);
    _validateHash('evidence_hash_hex', evidenceHashHex);
    _validateUtc('received_at_utc', receivedAtUtc);
  }
}

class ExternalEffectRequiredAction {
  static const int schemaVersion = 1;

  final String kind;
  final String providerReferenceId;
  final String actionToken;
  final String prompt;
  final String expiresAtUtc;

  const ExternalEffectRequiredAction({
    required this.kind,
    required this.providerReferenceId,
    required this.actionToken,
    required this.prompt,
    required this.expiresAtUtc,
  });

  factory ExternalEffectRequiredAction.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException(
        'Unsupported external effect required-action schema',
      );
    }
    final action = ExternalEffectRequiredAction(
      kind: json['kind']?.toString() ?? '',
      providerReferenceId: json['provider_reference_id']?.toString() ?? '',
      actionToken: json['action_token']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      expiresAtUtc: json['expires_at_utc']?.toString() ?? '',
    );
    action.validate();
    return action;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'kind': kind,
    'provider_reference_id': providerReferenceId,
    'action_token': actionToken,
    'prompt': prompt,
    'expires_at_utc': expiresAtUtc,
  };

  void validate() {
    _validateIdentifier('required_action.kind', kind);
    _validateBounded(
      'required_action.provider_reference_id',
      providerReferenceId,
      1,
      256,
    );
    _validateBounded('required_action.action_token', actionToken, 1, 1024);
    _validateBounded('required_action.prompt', prompt, 1, 4000);
    _validateUtc('required_action.expires_at_utc', expiresAtUtc);
  }
}

class ExternalEffectOperation {
  static const int schemaVersion = 1;

  final String ownerCapsuleHex;
  final String operationId;
  final String pluginId;
  final String providerId;
  final String accountBindingId;
  final String effectKind;
  final String canonicalPayloadJson;
  final String payloadHashHex;
  final ExternalEffectState state;
  final String? approvalEvidenceHashHex;
  final String? approvedAtUtc;
  final int attemptCount;
  final int revision;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? providerReferenceId;
  final ExternalEffectRequiredAction? requiredAction;
  final ExternalEffectReceipt? receipt;
  final String? completedGroup;
  final String? retainUntilUtc;

  const ExternalEffectOperation({
    required this.ownerCapsuleHex,
    required this.operationId,
    required this.pluginId,
    required this.providerId,
    required this.accountBindingId,
    required this.effectKind,
    required this.canonicalPayloadJson,
    required this.payloadHashHex,
    required this.state,
    required this.approvalEvidenceHashHex,
    this.approvedAtUtc,
    required this.attemptCount,
    required this.revision,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    this.providerReferenceId,
    required this.requiredAction,
    required this.receipt,
    this.completedGroup,
    this.retainUntilUtc,
  });

  factory ExternalEffectOperation.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported external effect schema');
    }
    final rawRequiredAction = json['required_action'];
    final rawReceipt = json['receipt'];
    final approvalEvidenceHashHex =
        json['approval_evidence_hash_hex']?.toString();
    final updatedAtUtc = json['updated_at_utc']?.toString() ?? '';
    final approvedAtUtc =
        json['approved_at_utc']?.toString() ??
        (approvalEvidenceHashHex == null ? null : updatedAtUtc);
    final operation = ExternalEffectOperation(
      ownerCapsuleHex: json['owner_capsule_hex']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      pluginId: json['plugin_id']?.toString() ?? '',
      providerId: json['provider_id']?.toString() ?? '',
      accountBindingId: json['account_binding_id']?.toString() ?? '',
      effectKind: json['effect_kind']?.toString() ?? '',
      canonicalPayloadJson: json['canonical_payload_json']?.toString() ?? '',
      payloadHashHex: json['payload_hash_hex']?.toString() ?? '',
      state: ExternalEffectState.fromWire(json['state']?.toString() ?? ''),
      approvalEvidenceHashHex: approvalEvidenceHashHex,
      approvedAtUtc: approvedAtUtc,
      attemptCount:
          json['attempt_count'] is int ? json['attempt_count'] as int : -1,
      revision: json['revision'] is int ? json['revision'] as int : -1,
      createdAtUtc: json['created_at_utc']?.toString() ?? '',
      updatedAtUtc: updatedAtUtc,
      lastErrorCode: json['last_error_code']?.toString(),
      lastErrorMessage: json['last_error_message']?.toString(),
      providerReferenceId: json['provider_reference_id']?.toString(),
      completedGroup: json['completed_group']?.toString(),
      retainUntilUtc: json['retain_until_utc']?.toString(),
      requiredAction:
          rawRequiredAction is Map
              ? ExternalEffectRequiredAction.fromJson(
                Map<String, dynamic>.from(rawRequiredAction),
              )
              : null,
      receipt:
          rawReceipt is Map
              ? ExternalEffectReceipt.fromJson(
                Map<String, dynamic>.from(rawReceipt),
              )
              : null,
    );
    operation.validate();
    return operation;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'owner_capsule_hex': ownerCapsuleHex,
    'operation_id': operationId,
    'plugin_id': pluginId,
    'provider_id': providerId,
    'account_binding_id': accountBindingId,
    'effect_kind': effectKind,
    'canonical_payload_json': canonicalPayloadJson,
    'payload_hash_hex': payloadHashHex,
    'state': state.wireName,
    'approval_evidence_hash_hex': approvalEvidenceHashHex,
    'approved_at_utc': approvedAtUtc,
    'attempt_count': attemptCount,
    'revision': revision,
    'created_at_utc': createdAtUtc,
    'updated_at_utc': updatedAtUtc,
    'last_error_code': lastErrorCode,
    'last_error_message': lastErrorMessage,
    'provider_reference_id': providerReferenceId,
    'required_action': requiredAction?.toJson(),
    'receipt': receipt?.toJson(),
    if (completedGroup != null) 'completed_group': completedGroup,
    if (retainUntilUtc != null) 'retain_until_utc': retainUntilUtc,
  };

  void validate() {
    _validateCapsuleHex(ownerCapsuleHex);
    _validateIdentifier('operation_id', operationId);
    _validatePluginId(pluginId);
    _validateIdentifier('provider_id', providerId);
    _validateIdentifier('account_binding_id', accountBindingId);
    _validateIdentifier('effect_kind', effectKind);
    _validateBounded('canonical_payload_json', canonicalPayloadJson, 2, 65536);
    _validateHash('payload_hash_hex', payloadHashHex);
    if (approvalEvidenceHashHex != null) {
      _validateHash('approval_evidence_hash_hex', approvalEvidenceHashHex!);
    }
    _validateUtc('created_at_utc', createdAtUtc);
    _validateUtc('updated_at_utc', updatedAtUtc);
    if (completedGroup != null || retainUntilUtc != null) {
      if (completedGroup == null ||
          retainUntilUtc == null ||
          !state.isTerminal) {
        throw const FormatException('Only completed effects may be compacted');
      }
      _validateIdentifier('completed_group', completedGroup!);
      _validateUtc('retain_until_utc', retainUntilUtc!);
    }
    if (approvedAtUtc != null) {
      _validateUtc('approved_at_utc', approvedAtUtc!);
      if (approvalEvidenceHashHex == null) {
        throw const FormatException(
          'approved_at_utc requires approval evidence',
        );
      }
      final approvedAt = DateTime.parse(approvedAtUtc!);
      if (approvedAt.isBefore(DateTime.parse(createdAtUtc)) ||
          approvedAt.isAfter(DateTime.parse(updatedAtUtc))) {
        throw const FormatException(
          'approved_at_utc must be within the operation lifetime',
        );
      }
    }
    if (attemptCount < 0 || revision < 0) {
      throw const FormatException(
        'attempt_count and revision must be non-negative',
      );
    }
    if (lastErrorCode != null) {
      _validateIdentifier('last_error_code', lastErrorCode!);
    }
    if (lastErrorMessage != null) {
      _validateBounded('last_error_message', lastErrorMessage!, 1, 1000);
    }
    if (providerReferenceId != null) {
      _validateBounded('provider_reference_id', providerReferenceId!, 1, 256);
    }
    receipt?.validate();
    requiredAction?.validate();
    if (requiredAction != null && state != ExternalEffectState.unresolved) {
      throw const FormatException(
        'Only an unresolved external effect may require provider action',
      );
    }
    if (receipt != null &&
        (receipt!.operationId != operationId ||
            receipt!.providerId != providerId)) {
      throw const FormatException(
        'External effect receipt does not match its operation',
      );
    }
    if (state == ExternalEffectState.succeeded && receipt == null) {
      throw const FormatException('Succeeded external effect requires receipt');
    }
    if (state != ExternalEffectState.succeeded && receipt != null) {
      throw const FormatException(
        'Only a succeeded external effect may contain a receipt',
      );
    }
  }
}

class ExternalEffectAdapterRequest {
  final String ownerCapsuleHex;
  final String operationId;
  final String pluginId;
  final String providerId;
  final String accountBindingId;
  final String effectKind;
  final String canonicalPayloadJson;
  final String payloadHashHex;
  final String? providerReferenceId;
  final String? lastErrorCode;

  const ExternalEffectAdapterRequest({
    required this.ownerCapsuleHex,
    required this.operationId,
    required this.pluginId,
    required this.providerId,
    required this.accountBindingId,
    required this.effectKind,
    required this.canonicalPayloadJson,
    required this.payloadHashHex,
    this.providerReferenceId,
    this.lastErrorCode,
  });

  void validate() {
    _validateCapsuleHex(ownerCapsuleHex);
    _validateIdentifier('operation_id', operationId);
    _validatePluginId(pluginId);
    _validateIdentifier('provider_id', providerId);
    _validateIdentifier('account_binding_id', accountBindingId);
    _validateIdentifier('effect_kind', effectKind);
    _validateBounded('canonical_payload_json', canonicalPayloadJson, 2, 65536);
    _validateHash('payload_hash_hex', payloadHashHex);
    if (lastErrorCode != null) {
      _validateIdentifier('last_error_code', lastErrorCode!);
    }
    if (providerReferenceId != null) {
      _validateBounded('provider_reference_id', providerReferenceId!, 1, 256);
    }
  }
}

class ExternalEffectAdapterResult {
  final ExternalEffectAdapterStatus status;
  final ExternalEffectReceipt? receipt;
  final ExternalEffectRequiredAction? requiredAction;
  final bool requiredActionResolved;
  final String? providerReferenceId;
  final String? errorCode;
  final String? errorMessage;

  const ExternalEffectAdapterResult({
    required this.status,
    this.receipt,
    this.requiredAction,
    this.requiredActionResolved = false,
    this.providerReferenceId,
    this.errorCode,
    this.errorMessage,
  });

  void validate() {
    if (status == ExternalEffectAdapterStatus.succeeded && receipt == null) {
      throw const FormatException('Succeeded adapter result requires receipt');
    }
    if (status != ExternalEffectAdapterStatus.succeeded && receipt != null) {
      throw const FormatException(
        'Non-success adapter result cannot contain receipt',
      );
    }
    requiredAction?.validate();
    if (requiredAction != null &&
        status != ExternalEffectAdapterStatus.unresolved) {
      throw const FormatException(
        'Only an unresolved adapter result may require provider action',
      );
    }
    if (requiredActionResolved && requiredAction != null) {
      throw const FormatException(
        'A resolved provider action cannot remain required',
      );
    }
    if (requiredActionResolved &&
        status != ExternalEffectAdapterStatus.unresolved) {
      throw const FormatException(
        'A resolved provider action may only await reconciliation',
      );
    }
    if (providerReferenceId != null) {
      _validateBounded('provider_reference_id', providerReferenceId!, 1, 256);
    }
    if (errorCode != null) {
      _validateIdentifier('error_code', errorCode!);
    }
    if (errorMessage != null) {
      _validateBounded('error_message', errorMessage!, 1, 1000);
    }
  }
}

abstract interface class ExternalEffectAdapter {
  Future<ExternalEffectAdapterResult> deliver(
    ExternalEffectAdapterRequest request,
  );

  Future<ExternalEffectAdapterResult> reconcile(
    ExternalEffectAdapterRequest request,
  );

  Future<ExternalEffectAdapterResult> resolveRequiredAction(
    ExternalEffectAdapterRequest request,
    ExternalEffectRequiredAction action,
    String response,
  );
}

void _validateCapsuleHex(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('owner_capsule_hex must be 64 lowercase hex');
  }
}

void _validatePluginId(String value) {
  if (!RegExp(r'^[a-z0-9][a-z0-9.-]{0,127}$').hasMatch(value)) {
    throw const FormatException('plugin_id is invalid');
  }
}

void _validateIdentifier(String field, String value) {
  if (!RegExp(r'^[a-z0-9][a-z0-9._:-]{0,255}$').hasMatch(value)) {
    throw FormatException('$field is invalid');
  }
}

void _validateHash(String field, String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$field must be 64 lowercase hex');
  }
}

void _validateBounded(String field, String value, int min, int max) {
  final length = value.trim().length;
  if (length < min || length > max) {
    throw FormatException('$field must contain $min..$max characters');
  }
}

void _validateUtc(String field, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be an ISO-8601 UTC timestamp');
  }
}

/// One deadline/revocation predicate for app, headless runner and custody checks.
/// A null deadline is explicit owner authorization until revocation; zero is ended.
bool workspaceExecutionIsActive(Map control, {int? nowMs}) {
  final deadline = control['expires_at_ms'];
  return control['revoked'] != true &&
      control.containsKey('expires_at_ms') &&
      (deadline == null ||
          (deadline is int &&
              deadline > (nowMs ?? DateTime.now().millisecondsSinceEpoch)));
}

void validateWorkspaceExecutionControl(
  dynamic control,
  String owner,
  String pluginId,
) {
  if (control is! Map ||
      control['version'] != 1 ||
      control['owner'] != owner ||
      control['plugin_id'] != pluginId ||
      control['revision'] is! int ||
      control['revision'] <= 0 ||
      control['allow_new_entries'] is! bool ||
      !control.containsKey('expires_at_ms') ||
      (control['expires_at_ms'] != null &&
          (control['expires_at_ms'] is! int ||
              control['expires_at_ms'] < 0 ||
              control['expires_at_ms'] > 8640000000000000)) ||
      (control.containsKey('revoked') && control['revoked'] is! bool) ||
      ((control['revoked'] == true || control['expires_at_ms'] == 0) &&
          control['allow_new_entries'] == true) ||
      control['settings'] is! Map ||
      control['scope'] is! Map ||
      control['package_id'] is! String ||
      (control['package_id'] as String).isEmpty ||
      (control['package_id'] as String).length > 128 ||
      control['package_digest'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(control['package_digest']) ||
      !{'local', 'vps'}.contains(control['executor'] ?? 'local') ||
      (control['executor'] == 'vps' &&
          (control['executor_id'] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(control['executor_id']))) ||
      ['handoff_id', 'handoff_digest'].any(
        (key) =>
            control[key] != null &&
            (control[key] is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(control[key])),
      )) {
    throw StateError(
      'Execution grant is unreadable; no cycle or effect admitted',
    );
  }
  final settings = control['settings'] as Map;
  if (settings.length > 8 ||
      utf8.encode(jsonEncode(settings)).length > 2048 ||
      settings.values.any((v) => v is! String && v is! num)) {
    throw StateError('Execution settings are invalid');
  }
  validateWorkspaceExecutionSchedule(
    Map<String, dynamic>.from(control['scope'] as Map),
  );
}

void validateWorkspaceExecutionSchedule(Map<String, dynamic> scope) {
  if (scope.length != 6 ||
      scope['account_id'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(scope['account_id']) ||
      scope['symbol'] is! String ||
      (scope['symbol'] as String).length > 64 ||
      !RegExp(r'^[A-Z0-9]+-USDT$').hasMatch(scope['symbol']) ||
      scope['action'] is! String ||
      !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(scope['action']) ||
      scope['interval_seconds'] is! int ||
      scope['interval_seconds'] < 30 ||
      scope['interval_seconds'] > 3600 ||
      scope['max_margin'] is! num ||
      !scope['max_margin'].isFinite ||
      scope['max_margin'] <= 0 ||
      scope['max_stop_percent'] is! num ||
      !scope['max_stop_percent'].isFinite ||
      scope['max_stop_percent'] <= 0 ||
      scope['max_stop_percent'] > 100) {
    throw StateError('Invalid bounded execution scope');
  }
}

/// Recovery retains remote custody and evidence, never a live permission lease.
Map<String, dynamic> sealWorkspaceExecutionForRecovery(
  Map<String, dynamic> control,
  String owner,
  String pluginId,
) {
  validateWorkspaceExecutionControl(control, owner, pluginId);
  return {...control, 'expires_at_ms': 0, 'allow_new_entries': false};
}
