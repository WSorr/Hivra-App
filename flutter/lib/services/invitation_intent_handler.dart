import 'dart:convert';
import 'dart:typed_data';

import '../models/invitation.dart';
import 'capsule_state_manager.dart';
import 'invitation_actions_service.dart';
import 'invitation_delivery_service.dart';
import 'ledger_view_service.dart';

class InvitationIntentResult {
  final int code;
  final String message;

  const InvitationIntentResult({
    required this.code,
    required this.message,
  });

  bool get isSuccess => code == 0;
}

class InvitationIntentHandler {
  static const Duration _quickFetchCooldown = Duration(seconds: 8);
  static const Duration _sendPendingRecencyWindow = Duration(seconds: 10);
  static const Duration _sendPostFailureProbeTimeout = Duration(seconds: 2);
  static const Set<int> _softSendDeliveryCodes = <int>{
    -5,
    -7,
    -11,
    -12,
    -13,
    -14,
  };
  static const Set<int> _sendDeliveryProbeCodes = <int>{
    ..._softSendDeliveryCodes,
    -1003,
  };
  static const Set<int> _softAcceptDeliveryCodes = <int>{
    -6,
    -7,
    -11,
    -12,
    -13,
    -14,
  };
  static const Set<int> _softRejectDeliveryCodes = <int>{
    -5,
    -6,
    -11,
    -12,
    -13,
    -14,
  };
  static final Map<String, Future<InvitationIntentResult>>
      _quickFetchInFlightByCapsule = <String, Future<InvitationIntentResult>>{};
  static final Map<String, DateTime> _lastQuickFetchAtByCapsule =
      <String, DateTime>{};
  static final Map<String, Future<InvitationIntentResult>>
      _sendInFlightByIntentKey = <String, Future<InvitationIntentResult>>{};

  final InvitationActionsService? _actions;
  final InvitationDeliveryService _delivery;
  final CapsuleStateManager? _stateManager;
  final LedgerViewService? _ledgerView;
  final List<Invitation> Function()? _invitationsLoader;
  final Future<InvitationWorkerResult> Function()? _fetchInvitationsAction;
  final Future<InvitationWorkerResult> Function()? _fetchInvitationsQuickAction;
  final String Function()? _activeCapsuleHexResolver;

  InvitationIntentHandler({
    InvitationActionsService? actions,
    required InvitationDeliveryService delivery,
    CapsuleStateManager? stateManager,
    LedgerViewService? ledgerView,
    List<Invitation> Function()? invitationsLoader,
    Future<InvitationWorkerResult> Function()? fetchInvitationsAction,
    Future<InvitationWorkerResult> Function()? fetchInvitationsQuickAction,
    String Function()? activeCapsuleHexResolver,
  })  : _actions = actions,
        _delivery = delivery,
        _stateManager = stateManager,
        _ledgerView = ledgerView,
        _invitationsLoader = invitationsLoader,
        _fetchInvitationsAction = fetchInvitationsAction,
        _fetchInvitationsQuickAction = fetchInvitationsQuickAction,
        _activeCapsuleHexResolver = activeCapsuleHexResolver;

  List<Invitation> loadInvitations() =>
      _invitationsLoader?.call() ??
      _ledgerView?.loadInvitations() ??
      const <Invitation>[];

  Future<InvitationIntentResult> sendInvitation(
      Uint8List toPubkey, int starterSlot,
      {String? capsuleHex}) async {
    final effectiveCapsuleHex = _capsuleHex(explicitCapsuleHex: capsuleHex);
    final operationCapsuleHex =
        _isUnknownCapsuleKey(effectiveCapsuleHex) ? null : effectiveCapsuleHex;
    if (_isUnknownCapsuleKey(effectiveCapsuleHex)) {
      return _sendInvitationUncached(
        toPubkey,
        starterSlot,
        capsuleHex: operationCapsuleHex,
      );
    }
    final sendKey = _sendInFlightKey(
      capsuleHex: effectiveCapsuleHex,
      toPubkey: toPubkey,
      starterSlot: starterSlot,
    );
    final inFlight = _sendInFlightByIntentKey[sendKey];
    if (inFlight != null) {
      return inFlight;
    }

    final operation = _sendInvitationUncached(
      toPubkey,
      starterSlot,
      capsuleHex: operationCapsuleHex,
    );
    _sendInFlightByIntentKey[sendKey] = operation;
    try {
      return await operation;
    } finally {
      _sendInFlightByIntentKey.remove(sendKey);
    }
  }

  Future<InvitationIntentResult> _sendInvitationUncached(
      Uint8List toPubkey, int starterSlot,
      {String? capsuleHex}) async {
    final sendStartedAt = DateTime.now();
    final minPendingSentAt = sendStartedAt.subtract(_sendPendingRecencyWindow);
    final recipientPubkeyB64 = base64.encode(toPubkey);
    final pendingIdsBeforeSend = _pendingOutgoingInvitationIds(
      toPubkeyB64: recipientPubkeyB64,
      starterSlot: starterSlot,
    );
    final workerResult = await _requireActions().sendInvitation(
      toPubkey,
      starterSlot,
      capsuleHex: capsuleHex,
    );
    final code = workerResult.code;
    final hasWorkerLedger = (workerResult.ledgerJson?.isNotEmpty ?? false);
    final localPendingRecorded = hasWorkerLedger &&
        _softSendDeliveryCodes.contains(code) &&
        _hasNewPendingOutgoingInvitation(
          toPubkeyB64: recipientPubkeyB64,
          starterSlot: starterSlot,
          previousPendingIds: pendingIdsBeforeSend,
          minSentAt: minPendingSentAt,
        );
    final localPendingProjectedAfterFailure = !localPendingRecorded &&
        code != 0 &&
        _hasNewPendingOutgoingInvitation(
          toPubkeyB64: recipientPubkeyB64,
          starterSlot: starterSlot,
          previousPendingIds: pendingIdsBeforeSend,
          minSentAt: minPendingSentAt,
        );
    final localPendingConfirmedAfterFetch = !localPendingRecorded &&
        code != 0 &&
        _sendDeliveryProbeCodes.contains(code) &&
        await _confirmPendingOutgoingByQuickFetchBounded(
          capsuleHex: capsuleHex,
          toPubkeyB64: recipientPubkeyB64,
          starterSlot: starterSlot,
          previousPendingIds: pendingIdsBeforeSend,
          minSentAt: minPendingSentAt,
        );
    final localPendingSource = localPendingRecorded
        ? 'worker'
        : localPendingConfirmedAfterFetch
            ? 'quick_fetch'
            : null;
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    if (code == 0) {
      return InvitationIntentResult(
        code: 0,
        message: _delivery.invitationSentMessage(),
      );
    }
    if (localPendingRecorded || localPendingConfirmedAfterFetch) {
      return InvitationIntentResult(
        code: 0,
        message:
            '${_delivery.sendFailureMessage(code)} Local pending invitation is recorded (source: $localPendingSource).$diagnostics',
      );
    }
    if (localPendingProjectedAfterFailure) {
      return InvitationIntentResult(
        code: code,
        message:
            '${_delivery.sendFailureMessage(code)} Pending invitation appeared in local projection but was not confirmed.$diagnostics',
      );
    }
    return InvitationIntentResult(
      code: code,
      message: '${_delivery.sendFailureMessage(code)}$diagnostics',
    );
  }

  String _sendInFlightKey({
    required String capsuleHex,
    required Uint8List toPubkey,
    required int starterSlot,
  }) {
    return '$capsuleHex|$starterSlot|${base64.encode(toPubkey)}';
  }

  Future<InvitationIntentResult> fetchInvitations({String? capsuleHex}) async {
    final operationCapsuleHex = _capsuleHexOrNull(
      explicitCapsuleHex: capsuleHex,
    );
    final workerResult = await (_fetchInvitationsAction?.call() ??
        _requireActions().fetchInvitations(capsuleHex: operationCapsuleHex));
    final code = workerResult.code;
    await _expireOverdueOutgoingInvitationsIfNeeded();
    final diagnostics = _receiveDiagnostics(workerResult);
    return InvitationIntentResult(
      code: code,
      message: code >= 0
          ? _delivery.fetchSuccessMessage(code)
          : '${_delivery.receiveFailureMessage(code)}$diagnostics',
    );
  }

  Future<InvitationIntentResult> fetchInvitationsQuick({
    String? capsuleHex,
  }) async {
    final operationCapsuleHex = _capsuleHex(
      explicitCapsuleHex: capsuleHex,
    );
    final isUnknownCapsule = _isUnknownCapsuleKey(operationCapsuleHex);
    if (isUnknownCapsule) {
      // Do not dedupe/cooldown unknown capsule identity: at startup or during
      // capsule switches this placeholder key can alias different capsules.
      return _fetchInvitationsQuickUncached();
    }

    final inFlight = _quickFetchInFlightByCapsule[operationCapsuleHex];
    if (inFlight != null) {
      return inFlight;
    }

    final lastQuickFetchAt = _lastQuickFetchAtByCapsule[operationCapsuleHex];
    if (lastQuickFetchAt != null &&
        DateTime.now().difference(lastQuickFetchAt) < _quickFetchCooldown) {
      await _expireOverdueOutgoingInvitationsIfNeeded();
      return const InvitationIntentResult(
        code: 0,
        message: 'Skipped duplicate quick fetch',
      );
    }

    final operation = _fetchInvitationsQuickUncached(
      capsuleHex: operationCapsuleHex,
    );
    _quickFetchInFlightByCapsule[operationCapsuleHex] = operation;
    try {
      final result = await operation;
      if (result.code >= 0) {
        _lastQuickFetchAtByCapsule[operationCapsuleHex] = DateTime.now();
      }
      return result;
    } finally {
      _quickFetchInFlightByCapsule.remove(operationCapsuleHex);
    }
  }

  Future<InvitationIntentResult> _fetchInvitationsQuickUncached({
    String? capsuleHex,
  }) async {
    final operationCapsuleHex = _capsuleHexOrNull(
      explicitCapsuleHex: capsuleHex,
    );
    final workerResult = await (_fetchInvitationsQuickAction?.call() ??
        _requireActions()
            .fetchInvitationsQuick(capsuleHex: operationCapsuleHex));
    final code = workerResult.code;
    await _expireOverdueOutgoingInvitationsIfNeeded();
    final diagnostics = _receiveDiagnostics(workerResult);
    return InvitationIntentResult(
      code: code,
      message: code >= 0
          ? _delivery.fetchSuccessMessage(code)
          : '${_delivery.receiveFailureMessage(code)}$diagnostics',
    );
  }

  String _receiveDiagnostics(InvitationWorkerResult workerResult) {
    final code = workerResult.code;
    final lastError = workerResult.lastError?.trim();
    if (lastError != null && lastError.isNotEmpty) {
      return ' [code: $code; ffi: $lastError]';
    }
    return ' [code: $code]';
  }

  Future<InvitationIntentResult> acceptInvitation(
      Uint8List invitationId, Uint8List fromPubkey,
      {String? capsuleHex}) async {
    final invitationIdB64 = base64.encode(invitationId);
    final operationCapsuleHex =
        _capsuleHexOrNull(explicitCapsuleHex: capsuleHex);
    var localInvitation = _findInvitationById(invitationIdB64);
    if (localInvitation == null) {
      final syncCode =
          await _syncInvitationsForAccept(capsuleHex: operationCapsuleHex);
      if (syncCode >= 0) {
        localInvitation = _findInvitationById(invitationIdB64);
      }
    }
    if (localInvitation == null) {
      return const InvitationIntentResult(
        code: -8,
        message: 'Invitation is not available in active capsule ledger',
      );
    }
    if (localInvitation.status != InvitationStatus.pending) {
      return const InvitationIntentResult(
        code: 0,
        message: 'Invitation already resolved',
      );
    }
    if (!localInvitation.isIncoming) {
      return const InvitationIntentResult(
        code: -1,
        message: 'Only incoming invitations can be accepted',
      );
    }

    final actions = _requireActions();

    var workerResult = await actions.acceptInvitation(
      invitationId,
      fromPubkey,
      capsuleHex: operationCapsuleHex,
    );
    if (workerResult.code == -8) {
      var refreshResult = await actions.fetchInvitationsQuick(
        capsuleHex: operationCapsuleHex,
      );
      if (refreshResult.code == -1003) {
        refreshResult = await actions.fetchInvitations(
          capsuleHex: operationCapsuleHex,
        );
      }
      if (refreshResult.code >= 0) {
        final refreshedInvitation = _findInvitationById(invitationIdB64);
        final canRetry = refreshedInvitation != null &&
            refreshedInvitation.isIncoming &&
            refreshedInvitation.status == InvitationStatus.pending;
        if (canRetry) {
          workerResult = await actions.acceptInvitation(
            invitationId,
            fromPubkey,
            capsuleHex: operationCapsuleHex,
          );
        }
      }
    }
    final code = workerResult.code;
    final hasWorkerLedger = (workerResult.ledgerJson?.isNotEmpty ?? false);
    final localAcceptanceRecorded =
        hasWorkerLedger && _softAcceptDeliveryCodes.contains(code);
    final localAcceptedAfterFailure = !localAcceptanceRecorded &&
        code != 0 &&
        _isInvitationLocallyAccepted(invitationIdB64);
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    if (code == 0) {
      return const InvitationIntentResult(
        code: 0,
        message: 'Invitation accepted',
      );
    }
    if (localAcceptanceRecorded || localAcceptedAfterFailure) {
      return InvitationIntentResult(
        code: 0,
        message:
            '${_delivery.acceptFailureMessage(code)} Local acceptance is recorded.$diagnostics',
      );
    }
    return InvitationIntentResult(
      code: code,
      message: '${_delivery.acceptFailureMessage(code)}$diagnostics',
    );
  }

  Future<int> _syncInvitationsForAccept({String? capsuleHex}) async {
    final quickResult = await (_fetchInvitationsQuickAction?.call() ??
        _requireActions().fetchInvitationsQuick(capsuleHex: capsuleHex));
    var code = quickResult.code;
    if (code == -1003) {
      final fullResult = await (_fetchInvitationsAction?.call() ??
          _requireActions().fetchInvitations(capsuleHex: capsuleHex));
      code = fullResult.code;
    }
    if (code >= 0) {
      await _expireOverdueOutgoingInvitationsIfNeeded();
    }
    return code;
  }

  Future<InvitationIntentResult> rejectInvitation(
    Invitation invitation, {
    String? capsuleHex,
  }) async {
    final localInvitation = _findInvitationById(invitation.id);
    if (localInvitation != null) {
      if (localInvitation.status != InvitationStatus.pending) {
        return const InvitationIntentResult(
          code: 0,
          message: 'Invitation already resolved',
        );
      }
      if (!localInvitation.isIncoming) {
        return const InvitationIntentResult(
          code: -1,
          message: 'Only incoming invitations can be rejected',
        );
      }
    }

    final invitationId = _decodeB64_32(invitation.id);
    if (invitationId == null) {
      return const InvitationIntentResult(
        code: -1,
        message: 'Invalid invitation id',
      );
    }

    final reason = _rejectReasonForInvitation(invitation);
    final workerResult = await _requireActions().rejectInvitation(
      invitationId,
      reason,
      capsuleHex: _capsuleHexOrNull(explicitCapsuleHex: capsuleHex),
    );
    final code = workerResult.code;
    final hasWorkerLedger = (workerResult.ledgerJson?.isNotEmpty ?? false);
    final localRejectionRecorded =
        hasWorkerLedger && _softRejectDeliveryCodes.contains(code);
    final localTerminalAfterFailure = !localRejectionRecorded &&
        code != 0 &&
        _isInvitationLocallyTerminal(invitation.id);
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    return InvitationIntentResult(
      code: (code == 0 || localRejectionRecorded || localTerminalAfterFailure)
          ? 0
          : -1,
      message: code == 0
          ? 'Invitation rejected'
          : (localRejectionRecorded || localTerminalAfterFailure)
              ? '${_delivery.rejectFailureMessage(code)} Local rejection is recorded.$diagnostics'
              : '${_delivery.rejectFailureMessage(code)}$diagnostics',
    );
  }

  Future<InvitationIntentResult> cancelInvitation(
    String invitationIdB64, {
    String? capsuleHex,
  }) async {
    final invitationId = _decodeB64_32(invitationIdB64);
    if (invitationId == null) {
      return const InvitationIntentResult(
        code: -1,
        message: 'Invalid invitation id',
      );
    }

    final ok = await _requireActions().cancelInvitation(
      invitationId,
      capsuleHex: _capsuleHexOrNull(explicitCapsuleHex: capsuleHex),
    );
    return InvitationIntentResult(
      code: ok ? 0 : -1,
      message: ok ? 'Invitation canceled' : 'Failed to cancel invitation',
    );
  }

  Uint8List? _decodeB64_32(String value) {
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  int _rejectReasonForInvitation(Invitation invitation) {
    final manager = _stateManager;
    if (manager == null) return 1;
    manager.refreshWithFullState();
    final state = manager.state;
    final hasEmptySlot = state.starterSlots.any((slot) => !slot.occupied);
    return hasEmptySlot ? 0 : 1;
  }

  String _activeCapsuleHex() {
    final resolved = _activeCapsuleHexResolver?.call();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    final manager = _stateManager;
    if (manager == null) return 'unknown';
    manager.refreshWithFullState();
    final bytes = manager.state.publicKey;
    if (bytes.isEmpty) return 'unknown';
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  InvitationActionsService _requireActions() {
    final actions = _actions;
    if (actions != null) return actions;
    throw StateError('Invitation actions are not configured');
  }

  bool _isUnknownCapsuleKey(String capsuleHex) {
    final normalized = capsuleHex.trim().toLowerCase();
    return normalized.isEmpty || normalized == 'unknown';
  }

  String? _activeCapsuleHexOrNull() {
    final capsuleHex = _activeCapsuleHex();
    return _isUnknownCapsuleKey(capsuleHex) ? null : capsuleHex;
  }

  String _capsuleHex({String? explicitCapsuleHex}) {
    final normalized = _normalizeExplicitCapsuleHex(explicitCapsuleHex);
    if (normalized != null) {
      return normalized;
    }
    return _activeCapsuleHex();
  }

  String? _capsuleHexOrNull({String? explicitCapsuleHex}) {
    final normalized = _normalizeExplicitCapsuleHex(explicitCapsuleHex);
    if (normalized != null) {
      return normalized;
    }
    return _activeCapsuleHexOrNull();
  }

  String? _normalizeExplicitCapsuleHex(String? capsuleHex) {
    final normalized = capsuleHex?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final hex32 = RegExp(r'^[0-9a-f]{64}$');
    if (!hex32.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  Future<void> _expireOverdueOutgoingInvitationsIfNeeded() async {
    final actions = _actions;
    if (actions == null) {
      return;
    }

    final now = DateTime.now();
    final overdueOutgoingPending = loadInvitations()
        .where((invitation) =>
            invitation.isOutgoing &&
            invitation.expiresAt != null &&
            invitation.expiresAt!.isBefore(now) &&
            _isLocallyOverdueButNotLedgerFinalized(invitation))
        .toList(growable: false);
    if (overdueOutgoingPending.isEmpty) {
      return;
    }

    for (final invitation in overdueOutgoingPending) {
      final invitationId = _decodeB64_32(invitation.id);
      if (invitationId == null) {
        continue;
      }
      final ok = await actions.cancelInvitation(invitationId);
      if (!ok) continue;
    }
  }

  bool _isLocallyOverdueButNotLedgerFinalized(Invitation invitation) {
    if (invitation.status == InvitationStatus.pending) {
      return true;
    }

    if (invitation.status != InvitationStatus.expired) {
      return false;
    }

    // Projection marks overdue outgoing invitations as `expired` even before
    // a ledger InvitationExpired event exists. In that synthetic state
    // respondedAt equals expiresAt. We should append a real expiration event.
    final respondedAt = invitation.respondedAt;
    final expiresAt = invitation.expiresAt;
    if (respondedAt == null || expiresAt == null) {
      return false;
    }
    return respondedAt == expiresAt;
  }

  bool _isInvitationLocallyTerminal(String invitationId) {
    final local = _findInvitationById(invitationId);
    if (local == null) {
      return false;
    }
    return local.status != InvitationStatus.pending;
  }

  bool _isInvitationLocallyAccepted(String invitationId) {
    final local = _findInvitationById(invitationId);
    if (local == null) {
      return false;
    }
    return local.status == InvitationStatus.accepted;
  }

  Set<String> _pendingOutgoingInvitationIds({
    required String toPubkeyB64,
    required int starterSlot,
    DateTime? minSentAt,
  }) {
    final ids = <String>{};
    for (final invitation in loadInvitations()) {
      if (!invitation.isOutgoing) {
        continue;
      }
      if (invitation.status != InvitationStatus.pending) {
        continue;
      }
      if (invitation.toPubkey != toPubkeyB64) {
        continue;
      }
      if (invitation.starterSlot != starterSlot) {
        continue;
      }
      if (minSentAt != null && invitation.sentAt.isBefore(minSentAt)) {
        continue;
      }
      ids.add(invitation.id);
    }
    return ids;
  }

  bool _hasNewPendingOutgoingInvitation({
    required String toPubkeyB64,
    required int starterSlot,
    required Set<String> previousPendingIds,
    DateTime? minSentAt,
  }) {
    final currentIds = _pendingOutgoingInvitationIds(
      toPubkeyB64: toPubkeyB64,
      starterSlot: starterSlot,
      minSentAt: minSentAt,
    );
    for (final id in currentIds) {
      if (!previousPendingIds.contains(id)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmPendingOutgoingByQuickFetch({
    String? capsuleHex,
    required String toPubkeyB64,
    required int starterSlot,
    required Set<String> previousPendingIds,
    DateTime? minSentAt,
  }) async {
    final workerResult = await (_fetchInvitationsQuickAction?.call() ??
        _requireActions().fetchInvitationsQuick(capsuleHex: capsuleHex));
    if (workerResult.code < 0) {
      return false;
    }
    await _expireOverdueOutgoingInvitationsIfNeeded();
    return _hasNewPendingOutgoingInvitation(
      toPubkeyB64: toPubkeyB64,
      starterSlot: starterSlot,
      previousPendingIds: previousPendingIds,
      minSentAt: minSentAt,
    );
  }

  Future<bool> _confirmPendingOutgoingByQuickFetchBounded({
    String? capsuleHex,
    required String toPubkeyB64,
    required int starterSlot,
    required Set<String> previousPendingIds,
    DateTime? minSentAt,
  }) {
    final probe = _confirmPendingOutgoingByQuickFetch(
      capsuleHex: capsuleHex,
      toPubkeyB64: toPubkeyB64,
      starterSlot: starterSlot,
      previousPendingIds: previousPendingIds,
      minSentAt: minSentAt,
    );
    return probe.timeout(
      _sendPostFailureProbeTimeout,
      onTimeout: () => false,
    );
  }

  Invitation? _findInvitationById(String invitationId) {
    for (final invitation in loadInvitations()) {
      if (invitation.id == invitationId) {
        return invitation;
      }
    }
    return null;
  }
}
