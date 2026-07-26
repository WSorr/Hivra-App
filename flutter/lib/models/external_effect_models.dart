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
  final int attemptCount;
  final int revision;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final ExternalEffectReceipt? receipt;

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
    required this.attemptCount,
    required this.revision,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    required this.receipt,
  });

  factory ExternalEffectOperation.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported external effect schema');
    }
    final rawReceipt = json['receipt'];
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
      approvalEvidenceHashHex: json['approval_evidence_hash_hex']?.toString(),
      attemptCount:
          json['attempt_count'] is int ? json['attempt_count'] as int : -1,
      revision: json['revision'] is int ? json['revision'] as int : -1,
      createdAtUtc: json['created_at_utc']?.toString() ?? '',
      updatedAtUtc: json['updated_at_utc']?.toString() ?? '',
      lastErrorCode: json['last_error_code']?.toString(),
      lastErrorMessage: json['last_error_message']?.toString(),
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
    'attempt_count': attemptCount,
    'revision': revision,
    'created_at_utc': createdAtUtc,
    'updated_at_utc': updatedAtUtc,
    'last_error_code': lastErrorCode,
    'last_error_message': lastErrorMessage,
    'receipt': receipt?.toJson(),
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
    if (attemptCount < 0 || revision < 0) {
      throw const FormatException(
        'attempt_count and revision must be non-negative',
      );
    }
    _validateUtc('created_at_utc', createdAtUtc);
    _validateUtc('updated_at_utc', updatedAtUtc);
    if (lastErrorCode != null) {
      _validateIdentifier('last_error_code', lastErrorCode!);
    }
    if (lastErrorMessage != null) {
      _validateBounded('last_error_message', lastErrorMessage!, 1, 1000);
    }
    receipt?.validate();
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
  final String operationId;
  final String providerId;
  final String accountBindingId;
  final String effectKind;
  final String canonicalPayloadJson;
  final String payloadHashHex;

  const ExternalEffectAdapterRequest({
    required this.operationId,
    required this.providerId,
    required this.accountBindingId,
    required this.effectKind,
    required this.canonicalPayloadJson,
    required this.payloadHashHex,
  });
}

class ExternalEffectAdapterResult {
  final ExternalEffectAdapterStatus status;
  final ExternalEffectReceipt? receipt;
  final String? errorCode;
  final String? errorMessage;

  const ExternalEffectAdapterResult({
    required this.status,
    this.receipt,
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
