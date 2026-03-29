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
  final InvitationActionsService _actions;
  final InvitationDeliveryService _delivery;
  final CapsuleStateManager _stateManager;
  final LedgerViewService _ledgerView;

  InvitationIntentHandler({
    required InvitationActionsService actions,
    required InvitationDeliveryService delivery,
    required CapsuleStateManager stateManager,
    required LedgerViewService ledgerView,
  })  : _actions = actions,
        _delivery = delivery,
        _stateManager = stateManager,
        _ledgerView = ledgerView;

  List<Invitation> loadInvitations() => _ledgerView.loadInvitations();

  Future<InvitationIntentResult> sendInvitation(
    Uint8List toPubkey,
    int starterSlot,
  ) async {
    final workerResult = await _actions.sendInvitation(toPubkey, starterSlot);
    final code = workerResult.code;
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    return InvitationIntentResult(
      code: code,
      message: code == 0
          ? _delivery.invitationSentMessage()
          : '${_delivery.sendFailureMessage(code)}$diagnostics',
    );
  }

  Future<InvitationIntentResult> fetchInvitations() async {
    final workerResult = await _actions.fetchInvitations();
    final code = workerResult.code;
    return InvitationIntentResult(
      code: code,
      message: code >= 0
          ? _delivery.fetchSuccessMessage(code)
          : _delivery.receiveFailureMessage(code),
    );
  }

  Future<InvitationIntentResult> fetchInvitationsQuick() async {
    final workerResult = await _actions.fetchInvitationsQuick();
    final code = workerResult.code;
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
        await _actions.acceptInvitation(invitationId, fromPubkey);
    final code = workerResult.code;
    final lastError = workerResult.lastError?.trim();
    final diagnostics = lastError != null && lastError.isNotEmpty
        ? ' [code: $code; ffi: $lastError]'
        : ' [code: $code]';
    return InvitationIntentResult(
      code: code,
      message: code == 0
          ? 'Invitation accepted'
          : '${_delivery.acceptFailureMessage(code)}$diagnostics',
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
    final workerResult = await _actions.rejectInvitation(invitationId, reason);
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

    final ok = await _actions.cancelInvitation(invitationId);
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
    _stateManager.refreshWithFullState();
    final state = _stateManager.state;
    final hasEmptySlot = state.starterSlots.any((slot) => !slot.occupied);
    return hasEmptySlot ? 0 : 1;
  }
}
