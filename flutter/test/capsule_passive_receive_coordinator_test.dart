import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/capsule_chat_models.dart';
import 'package:hivra_app/services/capsule_passive_receive_coordinator.dart';
import 'package:hivra_app/services/consensus_attestation_sync_service.dart';
import 'package:hivra_app/services/invitation_intent_handler.dart';

const _capsuleA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _capsuleB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test('automatic triggers join one poll and one capability drain', () async {
    final ingressGate = Completer<InvitationIntentResult>();
    var ingressCalls = 0;
    var attestationDrains = 0;
    var chatDrains = 0;
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) {
        ingressCalls += 1;
        return ingressGate.future;
      },
      drainAttestations: () async {
        attestationDrains += 1;
        return _emptyAttestations;
      },
      drainChat: () async {
        chatDrains += 1;
        return _emptyChat;
      },
    );

    final launch = coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
    );
    final screen = coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.screenActivation,
    );

    expect(identical(launch, screen), isTrue);
    expect(ingressCalls, 1);
    ingressGate.complete(_okIngress);
    await Future.wait(<Future<CapsulePassiveReceiveResult>>[launch, screen]);

    expect(attestationDrains, 1);
    expect(chatDrains, 1);
  });

  test('manual trigger queues at most one forced follow-up', () async {
    final firstIngress = Completer<InvitationIntentResult>();
    final manualFlags = <bool>[];
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) {
        manualFlags.add(manualRetry);
        if (manualFlags.length == 1) return firstIngress.future;
        return Future<InvitationIntentResult>.value(_okIngress);
      },
    );

    final passive = coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.resume,
    );
    final firstManual = coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.manual,
      manualRetry: true,
    );
    final secondManual = coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.manual,
      manualRetry: true,
    );

    expect(identical(firstManual, secondManual), isTrue);
    firstIngress.complete(_okIngress);
    await Future.wait(<Future<CapsulePassiveReceiveResult>>[
      passive,
      firstManual,
      secondManual,
    ]);

    expect(manualFlags, <bool>[false, true]);
  });

  test('one operation polls before both capability drains', () async {
    final order = <String>[];
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) async {
        order.add('poll');
        return _okIngress;
      },
      drainAttestations: () async {
        order.add('attestations');
        return _emptyAttestations;
      },
      drainChat: () async {
        order.add('chat');
        return _emptyChat;
      },
    );

    await coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.periodic,
    );

    expect(order, <String>['poll', 'attestations', 'chat']);
  });

  test('one capability drain failure does not skip the next drain', () async {
    var chatDrains = 0;
    final coordinator = _coordinator(
      drainAttestations: () => throw StateError('corrupt attestation inbox'),
      drainChat: () async {
        chatDrains += 1;
        return _emptyChat;
      },
    );

    final result = await coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.periodic,
    );

    expect(result.attestations.code, -1005);
    expect(chatDrains, 1);
    expect(result.chat.code, 0);
  });

  test('manual full receive uses the same coordinator path', () async {
    var quickCalls = 0;
    var fullCalls = 0;
    bool? fullManualRetry;
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) async {
        quickCalls += 1;
        return _okIngress;
      },
      fullIngress: (capsuleHex, {required manualRetry}) async {
        fullCalls += 1;
        fullManualRetry = manualRetry;
        return _okIngress;
      },
    );

    await coordinator.trigger(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.manual,
      quick: false,
      manualRetry: true,
    );

    expect(quickCalls, 0);
    expect(fullCalls, 1);
    expect(fullManualRetry, isTrue);
  });

  test('pause cancels the delayed foreground follow-up', () async {
    var ingressCalls = 0;
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) async {
        ingressCalls += 1;
        return _okIngress;
      },
    );

    await coordinator.activateForeground(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
      followUpDelay: const Duration(milliseconds: 10),
    );
    coordinator.pauseForeground();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(ingressCalls, 1);
  });

  test('foreground periodic polling stops on pause', () async {
    var ingressCalls = 0;
    final coordinator = _coordinator(
      foregroundPollInterval: const Duration(milliseconds: 10),
      quickIngress: (capsuleHex, {required manualRetry}) async {
        ingressCalls += 1;
        return _okIngress;
      },
    );

    await coordinator.activateForeground(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    coordinator.pauseForeground();
    final callsAtPause = ingressCalls;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(callsAtPause, greaterThanOrEqualTo(2));
    expect(ingressCalls, callsAtPause);
  });

  test('connectivity restoration is cooldown-coalesced', () async {
    var ingressCalls = 0;
    final coordinator = _coordinator(
      connectivityCooldown: const Duration(minutes: 1),
      quickIngress: (capsuleHex, {required manualRetry}) async {
        ingressCalls += 1;
        return _okIngress;
      },
    );
    await coordinator.activateForeground(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
    );

    final first = await coordinator.notifyConnectivityRestored(
      capsuleHex: _capsuleA,
    );
    final second = await coordinator.notifyConnectivityRestored(
      capsuleHex: _capsuleA,
    );
    coordinator.pauseForeground();

    expect(first, isNotNull);
    expect(second, isNull);
    expect(ingressCalls, 2);
  });

  test('connectivity cooldown does not cross Capsule scope', () async {
    var ingressCalls = 0;
    final coordinator = _coordinator(
      connectivityCooldown: const Duration(minutes: 1),
      quickIngress: (capsuleHex, {required manualRetry}) async {
        ingressCalls += 1;
        return _okIngress;
      },
    );
    await coordinator.activateForeground(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
    );
    expect(
      await coordinator.notifyConnectivityRestored(capsuleHex: _capsuleA),
      isNotNull,
    );
    await coordinator.activateForeground(
      capsuleHex: _capsuleB,
      reason: CapsulePassiveReceiveReason.resume,
    );

    final capsuleB = await coordinator.notifyConnectivityRestored(
      capsuleHex: _capsuleB,
    );
    coordinator.pauseForeground();

    expect(capsuleB, isNotNull);
    expect(ingressCalls, 4);
  });

  test('Capsule switch invalidates the previous delayed follow-up', () async {
    final callsByCapsule = <String, int>{};
    final coordinator = _coordinator(
      quickIngress: (capsuleHex, {required manualRetry}) async {
        callsByCapsule.update(
          capsuleHex,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        return _okIngress;
      },
    );

    await coordinator.activateForeground(
      capsuleHex: _capsuleA,
      reason: CapsulePassiveReceiveReason.launch,
      followUpDelay: const Duration(milliseconds: 10),
    );
    await coordinator.activateForeground(
      capsuleHex: _capsuleB,
      reason: CapsulePassiveReceiveReason.resume,
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    coordinator.pauseForeground();

    expect(callsByCapsule[_capsuleA], 1);
    expect(callsByCapsule[_capsuleB], 1);
  });
}

CapsulePassiveReceiveCoordinator _coordinator({
  PassiveInvitationReceive? quickIngress,
  PassiveInvitationReceive? fullIngress,
  PassiveAttestationDrain? drainAttestations,
  PassiveChatDrain? drainChat,
  Duration foregroundPollInterval =
      CapsulePassiveReceiveCoordinator.defaultForegroundPollInterval,
  Duration connectivityCooldown = const Duration(seconds: 8),
}) {
  return CapsulePassiveReceiveCoordinator.withRunners(
    quickIngress:
        quickIngress ??
        (capsuleHex, {required manualRetry}) async => _okIngress,
    fullIngress:
        fullIngress ?? (capsuleHex, {required manualRetry}) async => _okIngress,
    drainAttestations: drainAttestations ?? () async => _emptyAttestations,
    drainChat: drainChat ?? () async => _emptyChat,
    foregroundPollInterval: foregroundPollInterval,
    connectivityCooldown: connectivityCooldown,
  );
}

const _okIngress = InvitationIntentResult(code: 0, message: 'ok');
const _emptyAttestations = ConsensusAttestationReceiveResult(
  code: 0,
  errorMessage: null,
  receivedCount: 0,
  storedCount: 0,
  rejectedCount: 0,
);
const _emptyChat = CapsuleChatDeliveryReceiveResult(
  code: 0,
  errorMessage: null,
  droppedByConsensus: 0,
  messages: <CapsuleChatInboxMessage>[],
  tradeSignals: <CapsuleTradeSignalInboxMessage>[],
);
