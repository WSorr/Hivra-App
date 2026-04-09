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
  static const Set<int> _softSendDeliveryCodes = <int>{
    -5,
    -7,
    -11,
    -12,
    -13,
    -14,
  };
  static const Set<int> _softAcceptDeliveryCodes = <int>{
    -6,
    -7,
    -11,
    -12,
    -13,
    -14,
  };
  static final Map<String, Future<InvitationIntentResult>>
      _quickFetchInFlightByCapsule = <String, Future<InvitationIntentResult>>{};
  static final Map<String, DateTime> _lastQuickFetchAtByCapsule =
      <String, DateTime>{};

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
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    final workerResult =
        await _requireActions().sendInvitation(toPubkey, starterSlot);
    final code = workerResult.code;
    final hasWorkerLedger = (workerResult.ledgerJson?.isNotEmpty ?? false);
    final localPendingRecorded =
        hasWorkerLedger && _softSendDeliveryCodes.contains(code);
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
    if (localPendingRecorded) {
      return InvitationIntentResult(
        code: 0,
        message:
            '${_delivery.sendFailureMessage(code)} Local pending invitation is recorded.$diagnostics',
      );
    }
    return InvitationIntentResult(
      code: code,
      message: '${_delivery.sendFailureMessage(code)}$diagnostics',
    );
  }

  Future<InvitationIntentResult> fetchInvitations() async {
    final workerResult = await (_fetchInvitationsAction?.call() ??
        _requireActions().fetchInvitations());
    final code = workerResult.code;
    await _expireOverdueOutgoingInvitationsIfNeeded();
    return InvitationIntentResult(
      code: code,
      message: code >= 0
          ? _delivery.fetchSuccessMessage(code)
          : _delivery.receiveFailureMessage(code),
    );
  }

  Future<InvitationIntentResult> fetchInvitationsQuick() async {
    final capsuleHex = _activeCapsuleHex();
    final inFlight = _quickFetchInFlightByCapsule[capsuleHex];
    if (inFlight != null) {
      return inFlight;
    }

    final lastQuickFetchAt = _lastQuickFetchAtByCapsule[capsuleHex];
    if (lastQuickFetchAt != null &&
        DateTime.now().difference(lastQuickFetchAt) < _quickFetchCooldown) {
      await _expireOverdueOutgoingInvitationsIfNeeded();
      return const InvitationIntentResult(
        code: 0,
        message: 'Skipped duplicate quick fetch',
      );
    }

    final operation = _fetchInvitationsQuickUncached();
    _quickFetchInFlightByCapsule[capsuleHex] = operation;
    try {
      final result = await operation;
      _lastQuickFetchAtByCapsule[capsuleHex] = DateTime.now();
      return result;
    } finally {
      _quickFetchInFlightByCapsule.remove(capsuleHex);
    }
  }

  Future<InvitationIntentResult> _fetchInvitationsQuickUncached() async {
    final workerResult = await (_fetchInvitationsQuickAction?.call() ??
        _requireActions().fetchInvitationsQuick());
    final code = workerResult.code;
    await _expireOverdueOutgoingInvitationsIfNeeded();
    return InvitationIntentResult(
      code: code,
      message: code >= 0
          ? _delivery.fetchSuccessMessage(code)
          : _delivery.receiveFailureMessage(code),
    );
  }

  Future<InvitationIntentResult> acceptInvitation(
    Uint8List invitationId,
    Uint8List fromPubkey,
  ) async {
    final workerResult =
        await _requireActions().acceptInvitation(invitationId, fromPubkey);
    final code = workerResult.code;
    final hasWorkerLedger = (workerResult.ledgerJson?.isNotEmpty ?? false);
    final localAcceptanceRecorded =
        hasWorkerLedger && _softAcceptDeliveryCodes.contains(code);
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
    if (localAcceptanceRecorded) {
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

  Future<InvitationIntentResult> rejectInvitation(Invitation invitation) async {
    final invitationId = _decodeB64_32(invitation.id);
    if (invitationId == null) {
      return const InvitationIntentResult(
        code: -1,
        message: 'Invalid invitation id',
      );
    }

    final reason = _rejectReasonForInvitation(invitation);
    final workerResult =
        await _requireActions().rejectInvitation(invitationId, reason);
    final code = workerResult.code;
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    return InvitationIntentResult(
      code: code == 0 ? 0 : -1,
      message: code == 0
          ? 'Invitation rejected'
          : 'Failed to reject invitation$diagnostics',
    );
  }

  Future<InvitationIntentResult> cancelInvitation(
      String invitationIdB64) async {
    final invitationId = _decodeB64_32(invitationIdB64);
    if (invitationId == null) {
      return const InvitationIntentResult(
        code: -1,
        message: 'Invalid invitation id',
      );
    }

    final ok = await _requireActions().cancelInvitation(invitationId);
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
}
