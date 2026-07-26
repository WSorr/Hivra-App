import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/external_effect_models.dart';
import 'capsule_file_store.dart';

typedef ExternalEffectAdapterResolver =
    ExternalEffectAdapter? Function(String providerId);

class ExternalEffectService {
  static const String _journalFileName = 'external_effects.v1.json';
  static const int _journalSchemaVersion = 1;
  static const int _maxJournalOperations = 1000;
  static const int _terminalRetentionTarget = 800;
  static final Map<String, Future<ExternalEffectOperation>> _inFlight =
      <String, Future<ExternalEffectOperation>>{};
  static final Map<String, Future<void>> _journalTails =
      <String, Future<void>>{};

  final String? Function() _readActiveCapsuleRootHex;
  final ExternalEffectAdapterResolver _resolveAdapter;
  final CapsuleFileStore _fileStore;
  final DateTime Function() _clock;

  ExternalEffectService({
    required String? Function() readActiveCapsuleRootHex,
    required ExternalEffectAdapterResolver resolveAdapter,
    CapsuleFileStore fileStore = const CapsuleFileStore(),
    DateTime Function()? clock,
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _resolveAdapter = resolveAdapter,
       _fileStore = fileStore,
       _clock = clock ?? DateTime.now;

  Future<ExternalEffectOperation> prepare({
    required String operationId,
    required String pluginId,
    required String providerId,
    required String accountBindingId,
    required String effectKind,
    required String canonicalPayloadJson,
  }) {
    final ownerHex = _requireActiveOwner();
    _validateCanonicalPayload(canonicalPayloadJson);
    final payloadHashHex =
        sha256.convert(utf8.encode(canonicalPayloadJson)).toString();
    final now = _now();
    final proposed = ExternalEffectOperation(
      ownerCapsuleHex: ownerHex,
      operationId: operationId,
      pluginId: pluginId,
      providerId: providerId,
      accountBindingId: accountBindingId,
      effectKind: effectKind,
      canonicalPayloadJson: canonicalPayloadJson,
      payloadHashHex: payloadHashHex,
      state: ExternalEffectState.prepared,
      approvalEvidenceHashHex: null,
      attemptCount: 0,
      revision: 0,
      createdAtUtc: now,
      updatedAtUtc: now,
      lastErrorCode: null,
      lastErrorMessage: null,
      receipt: null,
    );
    proposed.validate();
    return _withJournalLock(ownerHex, pluginId, () async {
      final operations = await _load(ownerHex, pluginId);
      final existing = _find(operations, operationId);
      if (existing != null) {
        if (!_sameSemanticEffect(existing, proposed)) {
          throw StateError(
            'External effect operation id is already bound to another effect',
          );
        }
        return existing;
      }
      _pruneTerminalOperations(operations);
      if (operations.length >= _maxJournalOperations) {
        throw StateError(
          'External effect journal is full of non-terminal operations',
        );
      }
      operations.add(proposed);
      await _save(ownerHex, pluginId, operations);
      return proposed;
    });
  }

  Future<ExternalEffectOperation> approve({
    required String pluginId,
    required String operationId,
    required String approvalEvidenceHashHex,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(approvalEvidenceHashHex)) {
      throw const FormatException(
        'approvalEvidenceHashHex must be 64 lowercase hex',
      );
    }
    final ownerHex = _requireActiveOwner();
    return _transition(
      ownerHex: ownerHex,
      pluginId: pluginId,
      operationId: operationId,
      allowedStates: const <ExternalEffectState>{ExternalEffectState.prepared},
      idempotentStates: const <ExternalEffectState>{
        ExternalEffectState.approved,
        ExternalEffectState.queued,
        ExternalEffectState.delivering,
        ExternalEffectState.unresolved,
        ExternalEffectState.succeeded,
      },
      update: (current) {
        if (current.approvalEvidenceHashHex != null &&
            current.approvalEvidenceHashHex != approvalEvidenceHashHex) {
          throw StateError('External effect approval evidence changed');
        }
        return _copy(
          current,
          state: ExternalEffectState.approved,
          approvalEvidenceHashHex: approvalEvidenceHashHex,
          clearError: true,
        );
      },
      validateIdempotent: (current) {
        if (current.approvalEvidenceHashHex != approvalEvidenceHashHex) {
          throw StateError('External effect approval evidence changed');
        }
      },
    );
  }

  Future<ExternalEffectOperation> enqueue({
    required String pluginId,
    required String operationId,
  }) {
    final ownerHex = _requireActiveOwner();
    return _transition(
      ownerHex: ownerHex,
      pluginId: pluginId,
      operationId: operationId,
      allowedStates: const <ExternalEffectState>{ExternalEffectState.approved},
      idempotentStates: const <ExternalEffectState>{
        ExternalEffectState.queued,
        ExternalEffectState.delivering,
        ExternalEffectState.unresolved,
        ExternalEffectState.succeeded,
      },
      update:
          (current) => _copy(
            current,
            state: ExternalEffectState.queued,
            clearError: true,
          ),
    );
  }

  Future<ExternalEffectOperation> cancel({
    required String pluginId,
    required String operationId,
  }) {
    final ownerHex = _requireActiveOwner();
    return _transition(
      ownerHex: ownerHex,
      pluginId: pluginId,
      operationId: operationId,
      allowedStates: const <ExternalEffectState>{
        ExternalEffectState.prepared,
        ExternalEffectState.approved,
        ExternalEffectState.queued,
      },
      idempotentStates: const <ExternalEffectState>{
        ExternalEffectState.cancelled,
      },
      update:
          (current) => _copy(
            current,
            state: ExternalEffectState.cancelled,
            clearError: true,
          ),
    );
  }

  Future<ExternalEffectOperation> process({
    required String pluginId,
    required String operationId,
  }) {
    final ownerHex = _requireActiveOwner();
    final key = '$ownerHex::$pluginId::$operationId';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _processOwned(
      ownerHex: ownerHex,
      pluginId: pluginId,
      operationId: operationId,
    );
    _inFlight[key] = future;
    return future.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<List<ExternalEffectOperation>> list({required String pluginId}) {
    final ownerHex = _requireActiveOwner();
    return _withJournalLock(
      ownerHex,
      pluginId,
      () => _load(ownerHex, pluginId),
    );
  }

  Future<ExternalEffectOperation> _processOwned({
    required String ownerHex,
    required String pluginId,
    required String operationId,
  }) async {
    var current = await _readRequired(ownerHex, pluginId, operationId);
    if (current.state.isTerminal) return current;
    final adapter = _resolveAdapter(current.providerId);
    if (adapter == null) {
      throw StateError(
        'No external effect adapter for provider ${current.providerId}',
      );
    }

    if (current.state == ExternalEffectState.delivering) {
      final deliveringRevision = current.revision;
      current = await _replace(
        ownerHex,
        pluginId,
        operationId,
        expectedState: ExternalEffectState.delivering,
        expectedRevision: deliveringRevision,
        update:
            (value) => _copy(
              value,
              state: ExternalEffectState.unresolved,
              lastErrorCode: 'restart_during_delivery',
              lastErrorMessage:
                  'Delivery outcome must be reconciled after interruption',
            ),
      );
    }

    if (current.state == ExternalEffectState.unresolved) {
      final unresolvedRevision = current.revision;
      final reconciliation = await _callAdapter(
        () => adapter.reconcile(_request(current)),
      );
      reconciliation.validate();
      if (reconciliation.status == ExternalEffectAdapterStatus.notFound) {
        current = await _replace(
          ownerHex,
          pluginId,
          operationId,
          expectedState: ExternalEffectState.unresolved,
          expectedRevision: unresolvedRevision,
          update:
              (value) => _copy(
                value,
                state: ExternalEffectState.queued,
                clearError: true,
              ),
        );
      } else {
        return _applyAdapterResult(
          ownerHex,
          pluginId,
          operationId,
          reconciliation,
          expectedState: ExternalEffectState.unresolved,
          expectedRevision: unresolvedRevision,
        );
      }
    }

    if (current.state != ExternalEffectState.queued) {
      throw StateError(
        'External effect ${current.operationId} is ${current.state.wireName}',
      );
    }

    final queuedRevision = current.revision;
    current = await _replace(
      ownerHex,
      pluginId,
      operationId,
      expectedState: ExternalEffectState.queued,
      expectedRevision: queuedRevision,
      update:
          (value) => _copy(
            value,
            state: ExternalEffectState.delivering,
            attemptCount: value.attemptCount + 1,
            clearError: true,
          ),
    );
    final delivery = await _callAdapter(
      () => adapter.deliver(_request(current)),
    );
    delivery.validate();
    return _applyAdapterResult(
      ownerHex,
      pluginId,
      operationId,
      delivery,
      expectedState: ExternalEffectState.delivering,
      expectedRevision: current.revision,
    );
  }

  Future<ExternalEffectAdapterResult> _callAdapter(
    Future<ExternalEffectAdapterResult> Function() call,
  ) async {
    try {
      final result = await call();
      return ExternalEffectAdapterResult(
        status: result.status,
        receipt: result.receipt,
        errorCode: result.errorCode,
        errorMessage:
            result.errorMessage == null
                ? null
                : _boundedError(result.errorMessage!),
      );
    } on TimeoutException catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'timeout',
        errorMessage: _boundedError(
          error.message ?? 'Provider outcome is unresolved',
        ),
      );
    } catch (error) {
      return ExternalEffectAdapterResult(
        status: ExternalEffectAdapterStatus.unresolved,
        errorCode: 'adapter_exception',
        errorMessage: _boundedError(error.toString()),
      );
    }
  }

  Future<ExternalEffectOperation> _applyAdapterResult(
    String ownerHex,
    String pluginId,
    String operationId,
    ExternalEffectAdapterResult result, {
    required ExternalEffectState expectedState,
    required int expectedRevision,
  }) {
    return _replace(
      ownerHex,
      pluginId,
      operationId,
      expectedState: expectedState,
      expectedRevision: expectedRevision,
      update: (current) {
        switch (result.status) {
          case ExternalEffectAdapterStatus.succeeded:
            final receipt = result.receipt!;
            if (receipt.operationId != current.operationId ||
                receipt.providerId != current.providerId) {
              throw const FormatException(
                'Adapter receipt does not match external effect operation',
              );
            }
            return _copy(
              current,
              state: ExternalEffectState.succeeded,
              receipt: receipt,
              clearError: true,
            );
          case ExternalEffectAdapterStatus.notFound:
          case ExternalEffectAdapterStatus.unresolved:
          case ExternalEffectAdapterStatus.retryableFailure:
            return _copy(
              current,
              state: ExternalEffectState.unresolved,
              lastErrorCode: result.errorCode ?? result.status.name,
              lastErrorMessage: _boundedError(
                result.errorMessage ?? 'Provider outcome is unresolved',
              ),
            );
          case ExternalEffectAdapterStatus.terminalFailure:
            return _copy(
              current,
              state: ExternalEffectState.terminalFailure,
              lastErrorCode: result.errorCode ?? 'terminal_failure',
              lastErrorMessage: _boundedError(
                result.errorMessage ?? 'Provider rejected the effect',
              ),
            );
        }
      },
    );
  }

  Future<ExternalEffectOperation> _transition({
    required String ownerHex,
    required String pluginId,
    required String operationId,
    required Set<ExternalEffectState> allowedStates,
    required Set<ExternalEffectState> idempotentStates,
    required ExternalEffectOperation Function(ExternalEffectOperation) update,
    void Function(ExternalEffectOperation)? validateIdempotent,
  }) {
    return _withJournalLock(ownerHex, pluginId, () async {
      final operations = await _load(ownerHex, pluginId);
      final index = _indexOf(operations, operationId);
      final current = operations[index];
      if (idempotentStates.contains(current.state)) {
        validateIdempotent?.call(current);
        return current;
      }
      if (!allowedStates.contains(current.state)) {
        throw StateError(
          'Invalid external effect transition from ${current.state.wireName}',
        );
      }
      final next = update(current);
      next.validate();
      operations[index] = next;
      await _save(ownerHex, pluginId, operations);
      return next;
    });
  }

  Future<ExternalEffectOperation> _replace(
    String ownerHex,
    String pluginId,
    String operationId, {
    required ExternalEffectState expectedState,
    required int expectedRevision,
    required ExternalEffectOperation Function(ExternalEffectOperation) update,
  }) {
    return _withJournalLock(ownerHex, pluginId, () async {
      final operations = await _load(ownerHex, pluginId);
      final index = _indexOf(operations, operationId);
      final current = operations[index];
      if (current.state != expectedState ||
          current.revision != expectedRevision) {
        return current;
      }
      final next = update(current);
      next.validate();
      operations[index] = next;
      await _save(ownerHex, pluginId, operations);
      return next;
    });
  }

  Future<ExternalEffectOperation> _readRequired(
    String ownerHex,
    String pluginId,
    String operationId,
  ) {
    return _withJournalLock(ownerHex, pluginId, () async {
      final operations = await _load(ownerHex, pluginId);
      return operations[_indexOf(operations, operationId)];
    });
  }

  Future<List<ExternalEffectOperation>> _load(
    String ownerHex,
    String pluginId,
  ) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(ownerHex);
    final raw = await _fileStore.readPluginState(
      capsuleDir,
      pluginId,
      _journalFileName,
    );
    if (raw == null) return <ExternalEffectOperation>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schema_version'] != _journalSchemaVersion ||
        decoded['owner_capsule_hex'] != ownerHex ||
        decoded['plugin_id'] != pluginId ||
        decoded['operations'] is! List) {
      throw const FormatException('Invalid external effect journal');
    }
    final operations =
        (decoded['operations'] as List).map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Invalid external effect journal operation',
            );
          }
          return ExternalEffectOperation.fromJson(
            Map<String, dynamic>.from(value),
          );
        }).toList();
    if (operations.length > _maxJournalOperations) {
      throw const FormatException(
        'External effect journal exceeds its bounded capacity',
      );
    }
    if (operations.any(
      (operation) =>
          operation.ownerCapsuleHex != ownerHex ||
          operation.pluginId != pluginId,
    )) {
      throw const FormatException('External effect journal scope mismatch');
    }
    for (final operation in operations) {
      _validateCanonicalPayload(operation.canonicalPayloadJson);
      final actualHash =
          sha256
              .convert(utf8.encode(operation.canonicalPayloadJson))
              .toString();
      if (actualHash != operation.payloadHashHex) {
        throw const FormatException(
          'External effect journal payload hash mismatch',
        );
      }
    }
    final ids = operations.map((operation) => operation.operationId).toSet();
    if (ids.length != operations.length) {
      throw const FormatException('External effect journal has duplicate ids');
    }
    return operations;
  }

  Future<void> _save(
    String ownerHex,
    String pluginId,
    List<ExternalEffectOperation> operations,
  ) async {
    final capsuleDir = await _fileStore.capsuleDirForHex(
      ownerHex,
      create: true,
    );
    final payload = <String, dynamic>{
      'schema_version': _journalSchemaVersion,
      'owner_capsule_hex': ownerHex,
      'plugin_id': pluginId,
      'operations': operations
          .map((operation) => operation.toJson())
          .toList(growable: false),
    };
    await _fileStore.writePluginState(
      capsuleDir,
      pluginId,
      _journalFileName,
      jsonEncode(payload),
    );
  }

  Future<T> _withJournalLock<T>(
    String ownerHex,
    String pluginId,
    Future<T> Function() action,
  ) {
    final key = '$ownerHex::$pluginId';
    final previous = _journalTails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _journalTails[key] = completer.future;
    return () async {
      await previous.catchError((_) {});
      try {
        return await action();
      } finally {
        completer.complete();
        if (identical(_journalTails[key], completer.future)) {
          _journalTails.remove(key);
        }
      }
    }();
  }

  void _validateCanonicalPayload(String value) {
    if (utf8.encode(value).length > 65536) {
      throw const FormatException(
        'canonicalPayloadJson exceeds 65536 UTF-8 bytes',
      );
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('canonicalPayloadJson must be a JSON object');
    }
  }

  void _pruneTerminalOperations(List<ExternalEffectOperation> operations) {
    if (operations.length < _maxJournalOperations) return;
    var index = 0;
    while (operations.length > _terminalRetentionTarget &&
        index < operations.length) {
      if (operations[index].state.isTerminal) {
        operations.removeAt(index);
      } else {
        index += 1;
      }
    }
  }

  String _boundedError(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'External provider error';
    return normalized.length <= 1000
        ? normalized
        : normalized.substring(0, 1000);
  }

  ExternalEffectOperation _copy(
    ExternalEffectOperation current, {
    required ExternalEffectState state,
    String? approvalEvidenceHashHex,
    int? attemptCount,
    String? lastErrorCode,
    String? lastErrorMessage,
    ExternalEffectReceipt? receipt,
    bool clearError = false,
  }) {
    return ExternalEffectOperation(
      ownerCapsuleHex: current.ownerCapsuleHex,
      operationId: current.operationId,
      pluginId: current.pluginId,
      providerId: current.providerId,
      accountBindingId: current.accountBindingId,
      effectKind: current.effectKind,
      canonicalPayloadJson: current.canonicalPayloadJson,
      payloadHashHex: current.payloadHashHex,
      state: state,
      approvalEvidenceHashHex:
          approvalEvidenceHashHex ?? current.approvalEvidenceHashHex,
      attemptCount: attemptCount ?? current.attemptCount,
      revision: current.revision + 1,
      createdAtUtc: current.createdAtUtc,
      updatedAtUtc: _now(),
      lastErrorCode: clearError ? null : lastErrorCode ?? current.lastErrorCode,
      lastErrorMessage:
          clearError ? null : lastErrorMessage ?? current.lastErrorMessage,
      receipt: receipt,
    );
  }

  ExternalEffectAdapterRequest _request(ExternalEffectOperation operation) {
    return ExternalEffectAdapterRequest(
      operationId: operation.operationId,
      providerId: operation.providerId,
      accountBindingId: operation.accountBindingId,
      effectKind: operation.effectKind,
      canonicalPayloadJson: operation.canonicalPayloadJson,
      payloadHashHex: operation.payloadHashHex,
    );
  }

  bool _sameSemanticEffect(
    ExternalEffectOperation first,
    ExternalEffectOperation second,
  ) {
    return first.ownerCapsuleHex == second.ownerCapsuleHex &&
        first.operationId == second.operationId &&
        first.pluginId == second.pluginId &&
        first.providerId == second.providerId &&
        first.accountBindingId == second.accountBindingId &&
        first.effectKind == second.effectKind &&
        first.payloadHashHex == second.payloadHashHex;
  }

  ExternalEffectOperation? _find(
    List<ExternalEffectOperation> operations,
    String operationId,
  ) {
    for (final operation in operations) {
      if (operation.operationId == operationId) return operation;
    }
    return null;
  }

  int _indexOf(List<ExternalEffectOperation> operations, String operationId) {
    final index = operations.indexWhere(
      (operation) => operation.operationId == operationId,
    );
    if (index < 0) {
      throw StateError('External effect operation not found');
    }
    return index;
  }

  String _requireActiveOwner() {
    final value = _readActiveCapsuleRootHex()?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('Active capsule identity is unavailable');
    }
    return value;
  }

  String _now() => _clock().toUtc().toIso8601String();
}
