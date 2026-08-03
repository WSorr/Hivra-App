import 'dart:async';

import '../models/capsule_chat_models.dart';
import 'capsule_chat_delivery_service.dart';
import 'consensus_attestation_sync_service.dart';
import 'invitation_intent_handler.dart';
import 'ui_event_log_service.dart';

enum CapsulePassiveReceiveReason {
  launch,
  resume,
  connectivity,
  periodic,
  screenActivation,
  postSend,
  manual,
  followUp,
}

class CapsulePassiveReceiveResult {
  final String capsuleHex;
  final CapsulePassiveReceiveReason reason;
  final InvitationIntentResult ingress;
  final ConsensusAttestationReceiveResult attestations;
  final CapsuleChatDeliveryReceiveResult chat;

  const CapsulePassiveReceiveResult({
    required this.capsuleHex,
    required this.reason,
    required this.ingress,
    required this.attestations,
    required this.chat,
  });
}

typedef PassiveReceiveResultListener =
    FutureOr<void> Function(CapsulePassiveReceiveResult result);
typedef PassiveReceivePostProjection =
    FutureOr<void> Function(CapsulePassiveReceiveResult result);
typedef PassiveInvitationReceive =
    Future<InvitationIntentResult> Function(
      String capsuleHex, {
      required bool manualRetry,
    });
typedef PassiveAttestationDrain =
    Future<ConsensusAttestationReceiveResult> Function();
typedef PassiveChatDrain = Future<CapsuleChatDeliveryReceiveResult> Function();
typedef PassiveReceiveLogger =
    Future<void> Function(String event, String details);

abstract interface class CapsulePassiveReceivePort {
  Future<CapsulePassiveReceiveResult> trigger({
    required String capsuleHex,
    required CapsulePassiveReceiveReason reason,
    bool quick = true,
    bool manualRetry = false,
  });
}

class CapsulePassiveReceiveCoordinator implements CapsulePassiveReceivePort {
  static final _ProcessReceiveCoalescer _processCoalescer =
      _ProcessReceiveCoalescer();
  static const Duration defaultForegroundPollInterval = Duration(seconds: 15);

  final PassiveInvitationReceive _quickIngress;
  final PassiveInvitationReceive _fullIngress;
  final PassiveAttestationDrain _drainAttestations;
  final PassiveChatDrain _drainChat;
  final _ProcessReceiveCoalescer _coalescer;
  final PassiveReceivePostProjection? _postProjection;
  final PassiveReceiveLogger? _log;
  final Duration _foregroundPollInterval;
  final Duration _connectivityCooldown;

  Timer? _periodicTimer;
  Timer? _followUpTimer;
  String? _foregroundCapsuleHex;
  final Map<String, DateTime> _lastConnectivityTriggerAt = <String, DateTime>{};
  PassiveReceiveResultListener? _resultListener;

  CapsulePassiveReceiveCoordinator({
    required InvitationIntentHandler invitations,
    required ConsensusAttestationSyncService attestations,
    required CapsuleChatDeliveryService chat,
    PassiveReceivePostProjection? postProjection,
    UiEventLogService uiLog = const UiEventLogService(),
    Duration foregroundPollInterval = defaultForegroundPollInterval,
    Duration connectivityCooldown = const Duration(seconds: 8),
    Object? testScope,
  }) : _quickIngress =
           ((capsuleHex, {required manualRetry}) =>
               invitations.fetchInvitationsQuick(
                 capsuleHex: capsuleHex,
                 manualRetry: manualRetry,
               )),
       _fullIngress =
           ((capsuleHex, {required manualRetry}) =>
               invitations.fetchInvitations(
                 capsuleHex: capsuleHex,
                 manualRetry: manualRetry,
               )),
       _drainAttestations = attestations.drainAndStore,
       _drainChat = chat.drainAndFilter,
       _postProjection = postProjection,
       _log = uiLog.log,
       _foregroundPollInterval = foregroundPollInterval,
       _connectivityCooldown = connectivityCooldown,
       _coalescer =
           testScope == null ? _processCoalescer : _ProcessReceiveCoalescer();

  CapsulePassiveReceiveCoordinator.withRunners({
    required PassiveInvitationReceive quickIngress,
    required PassiveInvitationReceive fullIngress,
    required PassiveAttestationDrain drainAttestations,
    required PassiveChatDrain drainChat,
    PassiveReceivePostProjection? postProjection,
    PassiveReceiveLogger? log,
    Duration foregroundPollInterval = defaultForegroundPollInterval,
    Duration connectivityCooldown = const Duration(seconds: 8),
  }) : _quickIngress = quickIngress,
       _fullIngress = fullIngress,
       _drainAttestations = drainAttestations,
       _drainChat = drainChat,
       _postProjection = postProjection,
       _log = log,
       _foregroundPollInterval = foregroundPollInterval,
       _connectivityCooldown = connectivityCooldown,
       _coalescer = _ProcessReceiveCoalescer();

  void setResultListener(PassiveReceiveResultListener? listener) {
    _resultListener = listener;
  }

  Future<CapsulePassiveReceiveResult> activateForeground({
    required String capsuleHex,
    required CapsulePassiveReceiveReason reason,
    Duration? followUpDelay,
  }) {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    _foregroundCapsuleHex = normalized;
    _periodicTimer?.cancel();
    _followUpTimer?.cancel();
    _periodicTimer = Timer.periodic(_foregroundPollInterval, (_) {
      final active = _foregroundCapsuleHex;
      if (active == null) return;
      unawaited(
        trigger(
          capsuleHex: active,
          reason: CapsulePassiveReceiveReason.periodic,
          quick: true,
        ),
      );
    });
    if (followUpDelay != null) {
      _scheduleFollowUp(normalized, followUpDelay);
    }
    return trigger(capsuleHex: normalized, reason: reason, quick: true);
  }

  Future<CapsulePassiveReceiveResult?> notifyConnectivityRestored({
    required String capsuleHex,
    Duration followUpDelay = const Duration(seconds: 5),
  }) async {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    if (_foregroundCapsuleHex != normalized) return null;
    final now = DateTime.now();
    final last = _lastConnectivityTriggerAt[normalized];
    if (last != null && now.difference(last) < _connectivityCooldown) {
      return null;
    }
    _lastConnectivityTriggerAt[normalized] = now;
    _scheduleFollowUp(normalized, followUpDelay);
    return trigger(
      capsuleHex: normalized,
      reason: CapsulePassiveReceiveReason.connectivity,
      quick: true,
    );
  }

  void pauseForeground() {
    _foregroundCapsuleHex = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _followUpTimer?.cancel();
    _followUpTimer = null;
  }

  @override
  Future<CapsulePassiveReceiveResult> trigger({
    required String capsuleHex,
    required CapsulePassiveReceiveReason reason,
    bool quick = true,
    bool manualRetry = false,
  }) {
    final normalized = _normalizeCapsuleHex(capsuleHex);
    return _coalescer.run(
      capsuleHex: normalized,
      manualRetry: manualRetry,
      operation:
          () => _runOne(
            capsuleHex: normalized,
            reason: reason,
            quick: quick,
            manualRetry: manualRetry,
          ),
    );
  }

  void _scheduleFollowUp(String capsuleHex, Duration delay) {
    _followUpTimer?.cancel();
    _followUpTimer = Timer(delay, () {
      if (_foregroundCapsuleHex != capsuleHex) return;
      unawaited(
        trigger(
          capsuleHex: capsuleHex,
          reason: CapsulePassiveReceiveReason.followUp,
          quick: true,
        ),
      );
    });
  }

  Future<CapsulePassiveReceiveResult> _runOne({
    required String capsuleHex,
    required CapsulePassiveReceiveReason reason,
    required bool quick,
    required bool manualRetry,
  }) async {
    InvitationIntentResult ingress;
    try {
      ingress =
          quick
              ? await _quickIngress(capsuleHex, manualRetry: manualRetry)
              : await _fullIngress(capsuleHex, manualRetry: manualRetry);
    } catch (error) {
      ingress = InvitationIntentResult(
        code: -1005,
        message: 'Passive transport ingress failed: $error',
      );
    }
    ConsensusAttestationReceiveResult attestations;
    try {
      attestations = await _drainAttestations();
    } catch (error) {
      attestations = ConsensusAttestationReceiveResult(
        code: -1005,
        errorMessage: 'Attestation inbox drain failed: $error',
        receivedCount: 0,
        storedCount: 0,
        rejectedCount: 0,
      );
    }
    CapsuleChatDeliveryReceiveResult chat;
    try {
      chat = await _drainChat();
    } catch (error) {
      chat = CapsuleChatDeliveryReceiveResult(
        code: -1005,
        errorMessage: 'Chat inbox drain failed: $error',
        droppedByConsensus: 0,
        messages: const <CapsuleChatInboxMessage>[],
        tradeSignals: const <CapsuleTradeSignalInboxMessage>[],
      );
    }
    final result = CapsulePassiveReceiveResult(
      capsuleHex: capsuleHex,
      reason: reason,
      ingress: ingress,
      attestations: attestations,
      chat: chat,
    );
    final log = _log;
    if (log != null) {
      unawaited(
        log(
          'transport.passive_receive',
          'reason=${reason.name} capsule=$capsuleHex ingress=${ingress.code} '
              'attestation=${attestations.code}/${attestations.storedCount} '
              'chat=${chat.code}/${chat.messages.length} '
              'trade=${chat.tradeSignals.length}',
        ),
      );
    }
    final postProjection = _postProjection;
    if (postProjection != null) {
      _runDetached('post_projection', () => postProjection(result));
    }
    final listener = _resultListener;
    if (listener != null) {
      _runDetached('result_listener', () => listener(result));
    }
    return result;
  }

  void _runDetached(String stage, FutureOr<void> Function() operation) {
    unawaited(
      Future<void>.sync(operation).catchError((Object error) async {
        final log = _log;
        if (log != null) {
          await log(
            'transport.passive_receive.callback_error',
            'stage=$stage error=$error',
          );
        }
      }),
    );
  }

  String _normalizeCapsuleHex(String capsuleHex) {
    final normalized = capsuleHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        capsuleHex,
        'capsuleHex',
        'must be 64 hex chars',
      );
    }
    return normalized;
  }
}

class _ProcessReceiveCoalescer {
  final Map<String, _CapsuleReceiveState> _states =
      <String, _CapsuleReceiveState>{};

  Future<CapsulePassiveReceiveResult> run({
    required String capsuleHex,
    required bool manualRetry,
    required Future<CapsulePassiveReceiveResult> Function() operation,
  }) {
    final state = _states.putIfAbsent(capsuleHex, _CapsuleReceiveState.new);
    final active = state.active;
    if (active != null) {
      if (!manualRetry || state.activeIsManual) return active;
      final pending = state.pendingManual;
      if (pending != null) return pending.completer.future;
      final next = _PendingManualReceive(operation);
      state.pendingManual = next;
      return next.completer.future;
    }
    return _start(
      capsuleHex: capsuleHex,
      state: state,
      manualRetry: manualRetry,
      operation: operation,
    );
  }

  Future<CapsulePassiveReceiveResult> _start({
    required String capsuleHex,
    required _CapsuleReceiveState state,
    required bool manualRetry,
    required Future<CapsulePassiveReceiveResult> Function() operation,
  }) {
    final active = Future<CapsulePassiveReceiveResult>.sync(operation);
    state.active = active;
    state.activeIsManual = manualRetry;
    active.then(
      (_) => _advance(capsuleHex, state),
      onError: (Object error, StackTrace stackTrace) {
        _advance(capsuleHex, state);
      },
    );
    return active;
  }

  void _advance(String capsuleHex, _CapsuleReceiveState state) {
    state.active = null;
    state.activeIsManual = false;
    final pending = state.pendingManual;
    state.pendingManual = null;
    if (pending == null) {
      _states.remove(capsuleHex);
      return;
    }
    final followUp = _start(
      capsuleHex: capsuleHex,
      state: state,
      manualRetry: true,
      operation: pending.operation,
    );
    followUp.then(
      pending.completer.complete,
      onError: pending.completer.completeError,
    );
  }
}

class _CapsuleReceiveState {
  Future<CapsulePassiveReceiveResult>? active;
  bool activeIsManual = false;
  _PendingManualReceive? pendingManual;
}

class _PendingManualReceive {
  final Future<CapsulePassiveReceiveResult> Function() operation;
  final Completer<CapsulePassiveReceiveResult> completer =
      Completer<CapsulePassiveReceiveResult>();

  _PendingManualReceive(this.operation);
}
