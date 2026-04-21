import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import '../models/invitation.dart';
import '../widgets/invitation_card.dart';
import '../services/app_runtime_service.dart';
import '../services/invitation_delivery_service.dart';
import '../services/invitation_intent_handler.dart';
import '../services/relationship_service.dart';
import '../services/ui_event_log_service.dart';
import '../services/ui_feedback_service.dart';
import '../utils/hivra_id_format.dart';
import '../utils/peer_identity_format.dart';

class InvitationUiBuckets {
  final List<Invitation> incomingPending;
  final List<Invitation> outgoingPending;
  final List<Invitation> history;

  const InvitationUiBuckets({
    required this.incomingPending,
    required this.outgoingPending,
    required this.history,
  });
}

@visibleForTesting
InvitationUiBuckets bucketInvitationsForUi(
  List<Invitation> invitations,
  Set<String> locallyResolvedIncomingIds,
) {
  final incomingPending = invitations
      .where((inv) =>
          inv.isIncoming &&
          inv.status == InvitationStatus.pending &&
          !locallyResolvedIncomingIds.contains(inv.id))
      .toList();

  final outgoingPending = invitations
      .where((inv) => inv.isOutgoing && inv.status == InvitationStatus.pending)
      .toList();

  final history = invitations
      .where((inv) => inv.status != InvitationStatus.pending)
      .toList();

  return InvitationUiBuckets(
    incomingPending: incomingPending,
    outgoingPending: outgoingPending,
    history: history,
  );
}

@visibleForTesting
bool shouldRetainLocalResolvedIncoming(InvitationIntentResult result) =>
    result.isSuccess;

@visibleForTesting
({bool silent, bool quick}) mergeQueuedInvitationFetchRequest({
  required bool queuedSilent,
  required bool queuedQuick,
  required bool incomingSilent,
  required bool incomingQuick,
}) =>
    (
      silent: queuedSilent && incomingSilent,
      quick: queuedQuick && incomingQuick,
    );

@visibleForTesting
Set<String> pruneLocallyResolvedIncomingIds({
  required Set<String> resolvedIds,
  required List<Invitation> projectedInvitations,
}) {
  final pendingIncomingIds = projectedInvitations
      .where((inv) => inv.isIncoming && inv.status == InvitationStatus.pending)
      .map((inv) => inv.id)
      .toSet();
  final nonPendingIncomingOrOtherIds = projectedInvitations
      .where(
          (inv) => !(inv.isIncoming && inv.status == InvitationStatus.pending))
      .map((inv) => inv.id)
      .toSet();

  final kept = <String>{};
  for (final id in resolvedIds) {
    if (pendingIncomingIds.contains(id)) {
      kept.add(id);
      continue;
    }
    if (nonPendingIncomingOrOtherIds.contains(id)) {
      continue;
    }
    // Drop suppression when id is absent from projection.
    // Source of truth is ledger projection: if the invitation later reappears
    // as pending, it should be visible/actionable again.
  }
  return kept;
}

class InvitationsScreen extends StatefulWidget {
  final AppRuntimeService runtime;
  final String activeCapsuleHex;
  final int ledgerVersion;
  final Future<void> Function()? onLedgerChanged;

  const InvitationsScreen({
    super.key,
    required this.runtime,
    required this.activeCapsuleHex,
    required this.ledgerVersion,
    this.onLedgerChanged,
  });

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final InvitationDeliveryService _delivery = const InvitationDeliveryService();
  final UiEventLogService _uiLog = const UiEventLogService();
  late final InvitationIntentHandler _intents;
  late final RelationshipService _relationships;
  List<Invitation> _invitations = [];
  bool _isFetchingDeliveries = false;
  String? _processingId;
  String? _processingAction;
  bool _hasQueuedFetchRequest = false;
  bool _queuedFetchSilent = true;
  bool _queuedFetchQuick = true;
  final Set<String> _locallyResolvedIncomingIds = <String>{};
  Map<String, String> _peerRootKeyByTransportB64 = const <String, String>{};
  int _invitationLoadGeneration = 0;

  bool _isOperationForActiveCapsule(String capturedCapsuleHex) =>
      capturedCapsuleHex == widget.activeCapsuleHex;

  @override
  void initState() {
    super.initState();
    _intents = widget.runtime.invitationIntents;
    _relationships = widget.runtime.buildRelationshipService();
    _loadInvitations();
    unawaited(_fetchInvitationDeliveries(silent: true, quick: true));
  }

  @override
  void didUpdateWidget(covariant InvitationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final capsuleChanged =
        widget.activeCapsuleHex != oldWidget.activeCapsuleHex;
    final ledgerChanged = widget.ledgerVersion != oldWidget.ledgerVersion;
    if (!capsuleChanged && !ledgerChanged) {
      return;
    }

    if (capsuleChanged) {
      _resetTransientStateForCapsuleSwitch();
      unawaited(_fetchInvitationDeliveries(silent: true, quick: true));
    }
    unawaited(_loadInvitations());
  }

  Future<void> _loadInvitations() async {
    final capturedCapsuleHex = widget.activeCapsuleHex;
    final loadGeneration = ++_invitationLoadGeneration;
    final invitations = _intents.loadInvitations(
      capsuleHex: capturedCapsuleHex,
    );
    final peerRoots = await _loadPeerRootKeys(invitations);
    final nextResolved = pruneLocallyResolvedIncomingIds(
      resolvedIds: _locallyResolvedIncomingIds,
      projectedInvitations: invitations,
    );
    if (!mounted ||
        loadGeneration != _invitationLoadGeneration ||
        !_isOperationForActiveCapsule(capturedCapsuleHex)) {
      return;
    }
    setState(() {
      _invitations = invitations;
      _peerRootKeyByTransportB64 = peerRoots;
      _locallyResolvedIncomingIds
        ..clear()
        ..addAll(nextResolved);
    });
  }

  void _resetTransientStateForCapsuleSwitch() {
    if (!mounted) return;
    setState(() {
      _invitationLoadGeneration += 1;
      _invitations = <Invitation>[];
      _isFetchingDeliveries = false;
      _processingId = null;
      _processingAction = null;
      _hasQueuedFetchRequest = false;
      _queuedFetchSilent = true;
      _queuedFetchQuick = true;
      _locallyResolvedIncomingIds.clear();
      _peerRootKeyByTransportB64 = const <String, String>{};
    });
  }

  Future<Map<String, String>> _loadPeerRootKeys(
    List<Invitation> invitations,
  ) async {
    return _relationships.loadPeerRootKeysForInvitations(invitations);
  }

  String _peerTransportB64(Invitation invitation) => invitation.isIncoming
      ? invitation.fromPubkey
      : (invitation.toPubkey ?? '');

  String? _peerRootKey(Invitation invitation) {
    final peerTransport = _peerTransportB64(invitation);
    if (peerTransport.isEmpty) return null;
    final root = _peerRootKeyByTransportB64[peerTransport];
    if (root == null || root.isEmpty) return null;
    return root;
  }

  String _peerDisplayName(Invitation invitation) {
    return PeerIdentityFormat.displayName(
      transportPubkeyB64: _peerTransportB64(invitation),
      rootCapsuleKey: _peerRootKey(invitation),
    );
  }

  String _peerIdentityHint(Invitation invitation) {
    return PeerIdentityFormat.identityHint(
      transportPubkeyB64: _peerTransportB64(invitation),
      rootCapsuleKey: _peerRootKey(invitation),
    );
  }

  Future<void> _refreshAfterLedgerMutation() async {
    await _loadInvitations();
    await widget.onLedgerChanged?.call();
  }

  Future<InvitationIntentResult> _sendInvitationAsync(
    Uint8List pubkey,
    int slot,
  ) async {
    final operationCapsuleHex = widget.activeCapsuleHex;
    final recipientTransportB64 = base64.encode(pubkey);
    final startedAt = DateTime.now();
    InvitationIntentResult? sendResult;
    try {
      unawaited(_uiLog.log(
        'invitations.send.request',
        'slot=$slot peer=${HivraIdFormat.short(HivraIdFormat.formatCapsuleKeyBytes(pubkey))}',
      ));
      final result = await _intents.sendInvitation(
        pubkey,
        slot,
        capsuleHex: operationCapsuleHex,
      );
      sendResult = result;
      unawaited(_uiLog.log(
        'invitations.send.result',
        'slot=$slot code=${result.code} message=${result.message}',
      ));
      if (!_isOperationForActiveCapsule(operationCapsuleHex)) {
        unawaited(_uiLog.log(
          'invitations.send.stale_drop',
          'slot=$slot opCapsule=$operationCapsuleHex activeCapsule=${widget.activeCapsuleHex}',
        ));
        return result;
      }
      if (result.isSuccess) {
        var projectedPending = _intents
            .loadInvitations(capsuleHex: operationCapsuleHex)
            .where((invitation) =>
                invitation.isOutgoing &&
                invitation.status == InvitationStatus.pending &&
                invitation.starterSlot == slot &&
                invitation.toPubkey == recipientTransportB64)
            .toList(growable: false);
        unawaited(_uiLog.log(
          'invitations.send.ledger_projection',
          'slot=$slot pendingMatches=${projectedPending.length} capsule=$operationCapsuleHex',
        ));
        if (projectedPending.isEmpty) {
          final quickResult = await _intents.fetchInvitationsQuick(
            capsuleHex: operationCapsuleHex,
          );
          projectedPending = _intents
              .loadInvitations(capsuleHex: operationCapsuleHex)
              .where((invitation) =>
                  invitation.isOutgoing &&
                  invitation.status == InvitationStatus.pending &&
                  invitation.starterSlot == slot &&
                  invitation.toPubkey == recipientTransportB64)
              .toList(growable: false);
          unawaited(_uiLog.log(
            'invitations.send.ledger_projection.retry',
            'slot=$slot quickFetchCode=${quickResult.code} pendingMatches=${projectedPending.length} capsule=$operationCapsuleHex',
          ));
        }
        if (mounted) {
          await _refreshAfterLedgerMutation();
        }
        final normalizedResultMessage = result.message.toLowerCase();
        final locallyRecordedOnly =
            normalizedResultMessage.contains('local invitation is recorded') ||
                normalizedResultMessage.contains(
                  'local pending invitation is recorded',
                );
        final ledgerProjected = projectedPending.isNotEmpty;
        final message = locallyRecordedOnly
            ? 'Invitation recorded locally. Relay delivery is retrying in background.'
            : ledgerProjected
                ? 'Invitation sent. Receiver should see it after refresh.'
                : 'Send returned success, but pending is not projected yet. Refresh Invitations to verify ledger projection.';
        if (mounted) {
          await _showUserMessage(message, source: 'invitations.send');
        }
        return result;
      }
      if (mounted) {
        await _showUserMessage(result.message, source: 'invitations.send');
      }
      return result;
    } catch (error, stackTrace) {
      final message = 'Failed to send invitation: $error';
      unawaited(_uiLog.log('invitations.send.error', '$message\n$stackTrace'));
      if (mounted) {
        await _showUserMessage(message, source: 'invitations.send');
      }
      return InvitationIntentResult(code: -1, message: message);
    } finally {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      unawaited(_uiLog.log(
        'invitations.send.finally',
        'slot=$slot elapsedMs=$elapsedMs resultCode=${sendResult?.code ?? 'none'} widgetMounted=$mounted',
      ));
    }
  }

  Future<void> _fetchInvitationDeliveries({
    bool silent = false,
    bool quick = false,
  }) async {
    final operationCapsuleHex = widget.activeCapsuleHex;
    if (_isFetchingDeliveries || _processingId != null) {
      _queueFetchRequest(silent: silent, quick: quick);
      return;
    }

    setState(() => _isFetchingDeliveries = true);
    InvitationIntentResult result = const InvitationIntentResult(
      code: -1003,
      message: 'Fetch timed out',
    );

    try {
      result = quick
          ? await _intents.fetchInvitationsQuick(
              capsuleHex: operationCapsuleHex,
            )
          : await _intents.fetchInvitations(
              capsuleHex: operationCapsuleHex,
            );
    } finally {
      if (mounted) {
        setState(() => _isFetchingDeliveries = false);
      }
    }

    if (!mounted) return;
    if (!_isOperationForActiveCapsule(operationCapsuleHex)) {
      unawaited(_uiLog.log(
        'invitations.fetch.stale_drop',
        'silent=$silent quick=$quick opCapsule=$operationCapsuleHex activeCapsule=${widget.activeCapsuleHex}',
      ));
      return;
    }

    if (result.code >= 0) {
      await _refreshAfterLedgerMutation();
      if (!mounted) return;
      if (!silent || result.code > 0) {
        await _showUserMessage(result.message, source: 'invitations.fetch');
      } else {
        unawaited(_uiLog.log('invitations.fetch.silent', result.message));
      }
      await _drainQueuedFetchRequestIfNeeded();
      return;
    }

    if (!silent) {
      await _showUserMessage(result.message, source: 'invitations.fetch');
      await _drainQueuedFetchRequestIfNeeded();
      return;
    }
    unawaited(_uiLog.log('invitations.fetch.silent.error', result.message));
    await _drainQueuedFetchRequestIfNeeded();
  }

  Future<void> _acceptInvitation(Invitation invitation) async {
    final operationCapsuleHex = widget.activeCapsuleHex;
    if (_processingId != null) return;
    if (_locallyResolvedIncomingIds.contains(invitation.id)) return;
    setState(() {
      _processingId = invitation.id;
      _processingAction = 'accept';
      _locallyResolvedIncomingIds.add(invitation.id);
    });
    UiFeedbackService.dismissCurrent(context);

    final invitationId = _decodeB64_32(invitation.id);
    final fromPubkey = _decodeB64_32(invitation.fromPubkey);
    var retainLocallyResolved = false;
    var processingReleased = false;
    try {
      if (invitationId == null || fromPubkey == null) {
        _releaseInvitationProcessing(
          invitation.id,
          retainLocallyResolved: false,
        );
        processingReleased = true;
        await _showUserMessage(
          _delivery.acceptFailureMessage(-1),
          source: 'invitations.accept',
        );
        return;
      }

      final result = await _intents.acceptInvitation(
        invitationId,
        fromPubkey,
        capsuleHex: operationCapsuleHex,
      );
      retainLocallyResolved = shouldRetainLocalResolvedIncoming(result);
      _releaseInvitationProcessing(
        invitation.id,
        retainLocallyResolved: retainLocallyResolved,
      );
      processingReleased = true;
      if (!_isOperationForActiveCapsule(operationCapsuleHex)) {
        return;
      }
      await _refreshAfterLedgerMutation();
      if (mounted) {
        await _showUserMessage(result.message, source: 'invitations.accept');
      }
    } finally {
      if (!processingReleased) {
        _releaseInvitationProcessing(
          invitation.id,
          retainLocallyResolved: retainLocallyResolved,
        );
      }
    }
  }

  Future<void> _rejectInvitation(Invitation invitation) async {
    final operationCapsuleHex = widget.activeCapsuleHex;
    if (_processingId != null) return;
    if (_locallyResolvedIncomingIds.contains(invitation.id)) return;

    // Show confirmation dialog for empty slot case
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Invitation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If you reject with an empty slot, the sender\'s starter will be BURNED permanently.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final rejectDiagnostics = _buildRejectDiagnostics(invitation);
    unawaited(_uiLog.log('invitations.reject.plan', rejectDiagnostics));

    setState(() {
      _processingId = invitation.id;
      _processingAction = 'reject';
      _locallyResolvedIncomingIds.add(invitation.id);
    });
    UiFeedbackService.dismissCurrent(context);

    var retainLocallyResolved = false;
    var processingReleased = false;
    try {
      unawaited(
        _uiLog.log(
          'invitations.reject.request',
          'invitationId=${invitation.id} from=${invitation.fromPubkey}',
        ),
      );
      final result = await _intents.rejectInvitation(
        invitation,
        capsuleHex: operationCapsuleHex,
      );
      unawaited(
        _uiLog.log(
          'invitations.reject.result',
          'code=${result.code} message=${result.message}',
        ),
      );
      retainLocallyResolved = shouldRetainLocalResolvedIncoming(result);
      _releaseInvitationProcessing(
        invitation.id,
        retainLocallyResolved: retainLocallyResolved,
      );
      processingReleased = true;
      if (!_isOperationForActiveCapsule(operationCapsuleHex)) {
        return;
      }
      await _refreshAfterLedgerMutation();
      if (mounted) {
        await _showUserMessage(result.message, source: 'invitations.reject');
      }
    } catch (error, stackTrace) {
      unawaited(
        _uiLog.log(
          'invitations.reject.error',
          '$error\n$stackTrace',
        ),
      );
      rethrow;
    } finally {
      unawaited(
        _uiLog.log(
          'invitations.reject.finally',
          'processingReleased=$processingReleased retainLocallyResolved=$retainLocallyResolved',
        ),
      );
      if (!processingReleased) {
        _releaseInvitationProcessing(
          invitation.id,
          retainLocallyResolved: retainLocallyResolved,
        );
      }
    }
  }

  void _releaseInvitationProcessing(
    String invitationId, {
    required bool retainLocallyResolved,
  }) {
    if (!mounted || _processingId != invitationId) {
      return;
    }
    setState(() {
      _processingId = null;
      _processingAction = null;
      if (!retainLocallyResolved) {
        _locallyResolvedIncomingIds.remove(invitationId);
      }
    });
    unawaited(_drainQueuedFetchRequestIfNeeded());
  }

  String _buildRejectDiagnostics(Invitation invitation) {
    widget.runtime.stateManager.refreshWithFullState();
    final state = widget.runtime.stateManager.state;
    final matchingSlots = state.starterSlots
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.occupied &&
              entry.value.kind == invitation.kind.displayName,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    final emptySlots = state.starterSlots
        .asMap()
        .entries
        .where((entry) => !entry.value.occupied)
        .map((entry) => entry.key)
        .toList(growable: false);

    final hasEmptySlot = emptySlots.isNotEmpty;
    final reason = hasEmptySlot ? 0 : 1;
    final invitationKey = invitation.id.length > 10
        ? invitation.id.substring(0, 10)
        : invitation.id;

    return 'inv=$invitationKey kind=${invitation.kind.displayName} '
        'matchingSlots=$matchingSlots emptySlots=$emptySlots reason=$reason';
  }

  Future<void> _cancelInvitation(Invitation invitation) async {
    final operationCapsuleHex = widget.activeCapsuleHex;
    if (_processingId != null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Invitation?'),
        content: const Text('This will unlock your starter.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() {
      _processingId = invitation.id;
      _processingAction = 'cancel';
    });
    UiFeedbackService.dismissCurrent(context);

    var processingReleased = false;
    try {
      final result = await _intents.cancelInvitation(
        invitation.id,
        capsuleHex: operationCapsuleHex,
      );
      _releaseCancelProcessing(invitation.id);
      processingReleased = true;
      if (!_isOperationForActiveCapsule(operationCapsuleHex)) {
        return;
      }
      await _refreshAfterLedgerMutation();
      if (mounted) {
        await _showUserMessage(result.message, source: 'invitations.cancel');
      }
    } finally {
      if (!processingReleased) {
        _releaseCancelProcessing(invitation.id);
      }
    }
  }

  void _releaseCancelProcessing(String invitationId) {
    if (!mounted || _processingId != invitationId) {
      return;
    }
    setState(() {
      _processingId = null;
      _processingAction = null;
    });
    unawaited(_drainQueuedFetchRequestIfNeeded());
  }

  void _queueFetchRequest({
    required bool silent,
    required bool quick,
  }) {
    if (!_hasQueuedFetchRequest) {
      _hasQueuedFetchRequest = true;
      _queuedFetchSilent = silent;
      _queuedFetchQuick = quick;
      return;
    }
    final merged = mergeQueuedInvitationFetchRequest(
      queuedSilent: _queuedFetchSilent,
      queuedQuick: _queuedFetchQuick,
      incomingSilent: silent,
      incomingQuick: quick,
    );
    _queuedFetchSilent = merged.silent;
    _queuedFetchQuick = merged.quick;
  }

  Future<void> _drainQueuedFetchRequestIfNeeded() async {
    if (!_hasQueuedFetchRequest ||
        _isFetchingDeliveries ||
        _processingId != null ||
        !mounted) {
      return;
    }
    final silent = _queuedFetchSilent;
    final quick = _queuedFetchQuick;
    _hasQueuedFetchRequest = false;
    _queuedFetchSilent = true;
    _queuedFetchQuick = true;
    await _fetchInvitationDeliveries(
      silent: silent,
      quick: quick,
    );
  }

  void _showSendInvitationDialog() {
    final controller = TextEditingController();
    widget.runtime.stateManager.refreshWithFullState();
    final state = widget.runtime.stateManager.state;
    final lockedSlots = state.lockedStarterSlots;
    final availableSlots = <int>[
      for (var i = 0; i < 5; i++)
        if (i < state.starterSlots.length &&
            state.starterSlots[i].occupied &&
            !lockedSlots.contains(i))
          i,
    ];
    int? selectedSlot = availableSlots.isNotEmpty ? availableSlots.first : null;
    String? formError;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Send Invitation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Recipient Public Key',
                    hintText: 'h... / npub / nostr hex / base64',
                    border: OutlineInputBorder(),
                    errorText: formError,
                  ),
                  maxLines: 2,
                  onChanged: (_) {
                    if (formError != null) {
                      setModalState(() => formError = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Starter:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                if (availableSlots.isEmpty && lockedSlots.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded,
                          color: Colors.orange),
                      title: Text('No active starters'),
                      subtitle: Text(
                          'You need at least one active starter to send invitations.'),
                    ),
                  )
                else if (availableSlots.isEmpty && lockedSlots.isNotEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_clock, color: Colors.orange),
                      title: Text('Starters are locked'),
                      subtitle: Text(
                          'Invitations lock starters for 24h. Cancel to unlock early.'),
                    ),
                  )
                else
                  ...availableSlots.map((slot) {
                    final kind = state.starterSlots[slot].kind;
                    final color = _starterColor(kind);
                    final selected = selectedSlot == slot;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setModalState(() => selectedSlot = slot),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected ? color : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(kind),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Slot ${slot + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                if (lockedSlots.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._lockedSlotRows(lockedSlots),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selectedSlot == null || isSending
                        ? null
                        : () async {
                            setModalState(() {
                              isSending = true;
                              formError = null;
                            });
                            final input = controller.text.trim();
                            final selfRootKey =
                                widget.runtime.capsuleRootPublicKey();
                            final selfNostrKey =
                                widget.runtime.capsuleNostrPublicKey();
                            final resolution =
                                await _delivery.resolveRecipientAddress(
                              input,
                              selfRootKey: selfRootKey,
                              selfNostrKey: selfNostrKey,
                            );
                            final slot = selectedSlot;
                            if (!resolution.isSuccess || slot == null) {
                              setModalState(
                                () {
                                  formError = resolution.errorMessage ??
                                      'Could not resolve recipient address';
                                  isSending = false;
                                },
                              );
                              return;
                            }
                            final result = await _sendInvitationAsync(
                              resolution.transportRecipient!,
                              slot,
                            );
                            if (!sheetContext.mounted) return;
                            if (!result.isSuccess) {
                              setModalState(() {
                                formError = result.message;
                                isSending = false;
                              });
                              return;
                            }
                            FocusScope.of(sheetContext).unfocus();
                            Navigator.of(sheetContext).pop();
                          },
                    icon: const Icon(Icons.send),
                    label: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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

  Future<void> _showUserMessage(
    String message, {
    required String source,
  }) async {
    final text = message.trim();
    if (text.isEmpty) return;
    UiFeedbackService.showSnackBar(
      context,
      text,
      source: source,
      duration: const Duration(seconds: 3),
      enableCopy: false,
    );
  }

  List<Widget> _lockedSlotRows(Set<int> lockedSlots) {
    widget.runtime.stateManager.refreshWithFullState();
    final state = widget.runtime.stateManager.state;
    return lockedSlots.map((slot) {
      final kind = slot < state.starterSlots.length
          ? state.starterSlots[slot].kind
          : 'Unknown';
      final color = _starterColor(kind);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(Icons.lock, size: 16, color: color),
            const SizedBox(width: 8),
            Text('Slot ${slot + 1} ($kind) locked'),
            const Spacer(),
            const Text('Cancel to unlock',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }).toList();
  }

  Color _starterColor(String kind) {
    switch (kind) {
      case 'Juice':
        return Colors.orange;
      case 'Spark':
        return Colors.red;
      case 'Seed':
        return Colors.green;
      case 'Pulse':
        return Colors.blue;
      case 'Kick':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets =
        bucketInvitationsForUi(_invitations, _locallyResolvedIncomingIds);
    final incomingPending = buckets.incomingPending;
    final outgoingPending = buckets.outgoingPending;
    final history = buckets.history;

    return RefreshIndicator(
      onRefresh: _fetchInvitationDeliveries,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'Send invitation',
                icon: const Icon(Icons.add),
                onPressed: _showSendInvitationDialog,
              ),
            ],
          ),
          _sectionHeader('Incoming', incomingPending.length),
          const SizedBox(height: 8),
          if (incomingPending.isEmpty)
            _emptySectionCard(
              icon: Icons.inbox_outlined,
              title: 'No incoming invitations',
              subtitle: 'Incoming requests will appear here.',
            )
          else
            ...incomingPending.map((inv) => InvitationCard(
                  invitation: inv,
                  peerDisplayOverride: _peerDisplayName(inv),
                  peerIdentityHint: _peerIdentityHint(inv),
                  onAccept: _locallyResolvedIncomingIds.contains(inv.id)
                      ? null
                      : () => _acceptInvitation(inv),
                  onReject: _locallyResolvedIncomingIds.contains(inv.id)
                      ? null
                      : () => _rejectInvitation(inv),
                  isLoading: _processingId == inv.id,
                  loadingAction:
                      _processingId == inv.id ? _processingAction : null,
                )),
          const SizedBox(height: 20),
          _sectionHeader('Outgoing', outgoingPending.length),
          const SizedBox(height: 8),
          if (outgoingPending.isEmpty)
            _emptySectionCard(
              icon: Icons.outbox_outlined,
              title: 'No outgoing invitations',
              subtitle:
                  'Send invitations manually using recipient public keys.',
              onTap: _showSendInvitationDialog,
            )
          else
            ...outgoingPending.map((inv) => InvitationCard(
                  invitation: inv,
                  peerDisplayOverride: _peerDisplayName(inv),
                  peerIdentityHint: _peerIdentityHint(inv),
                  onCancel: () => _cancelInvitation(inv),
                  isLoading: _processingId == inv.id,
                  loadingAction:
                      _processingId == inv.id ? _processingAction : null,
                )),
          const SizedBox(height: 20),
          _sectionHeader('History', history.length),
          const SizedBox(height: 8),
          if (history.isEmpty)
            _emptySectionCard(
              icon: Icons.history,
              title: 'No invitation history',
              subtitle:
                  'Accepted, rejected, and expired invitations appear here.',
            )
          else
            ...history.map((inv) => InvitationCard(
                  invitation: inv,
                  peerDisplayOverride: _peerDisplayName(inv),
                  peerIdentityHint: _peerIdentityHint(inv),
                  isLoading: _processingId == inv.id,
                  loadingAction:
                      _processingId == inv.id ? _processingAction : null,
                )),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _emptySectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade500),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
