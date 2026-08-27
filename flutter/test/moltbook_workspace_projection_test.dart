import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/moltbook_provider_models.dart';
import 'package:hivra_app/screens/moltbook_ambassador_screen.dart';

void main() {
  group('MoltbookWorkspaceProjection', () {
    test('gives an active effect priority over every new proposal path', () {
      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.waiting,
        cycleSummary: null,
        observing: false,
        proposing: false,
        delivering: false,
        hasVerification: false,
        hasRecoverableEffect: true,
        hasQueuedEffect: true,
        hasReplyDraft: true,
        hasLocalDraft: true,
        proposedCount: 2,
        publishedCount: 1,
        challengedCount: 0,
        blockedCount: 0,
      );

      expect(projection.nextAction, MoltbookWorkspaceNextAction.reconcile);
      expect(projection.canCancelQueuedEffect, isFalse);
    });

    testWidgets('queued publication exposes independent cancel action', (
      tester,
    ) async {
      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.idle,
        cycleSummary: null,
        observing: false,
        proposing: false,
        delivering: false,
        hasVerification: false,
        hasRecoverableEffect: false,
        hasQueuedEffect: true,
        hasReplyDraft: false,
        hasLocalDraft: true,
        proposedCount: 1,
        publishedCount: 1,
        challengedCount: 0,
        blockedCount: 0,
      );
      var publishCount = 0;
      var cancelCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoltbookWorkflowCard(
              projection: projection,
              writePolicy: MoltbookAmbassadorConfiguration.approvalAssisted,
              triggerPolicy: MoltbookAmbassadorConfiguration.triggerOnDemand,
              busy: false,
              onNextAction: () => publishCount += 1,
              onCancelQueuedEffect: () => cancelCount += 1,
              onStop: null,
            ),
          ),
        ),
      );

      expect(projection.canCancelQueuedEffect, isTrue);
      expect(find.text('Publish approved effect'), findsOneWidget);
      expect(find.text('Cancel approved effect'), findsOneWidget);

      await tester.tap(find.text('Cancel approved effect'));
      await tester.pump();

      expect(cancelCount, 1);
      expect(publishCount, 0);
    });

    test('verification is the only next action for challenged effect', () {
      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.idle,
        cycleSummary: null,
        observing: false,
        proposing: false,
        delivering: true,
        hasVerification: true,
        hasRecoverableEffect: true,
        hasQueuedEffect: true,
        hasReplyDraft: true,
        hasLocalDraft: true,
        proposedCount: 1,
        publishedCount: 0,
        challengedCount: 1,
        blockedCount: 0,
      );

      expect(projection.nextAction, MoltbookWorkspaceNextAction.verify);
      expect(projection.phase, MoltbookWorkspaceCyclePhase.delivering);
    });

    test('local prepared reply is reviewed before another cycle runs', () {
      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.waiting,
        cycleSummary: null,
        observing: false,
        proposing: false,
        delivering: false,
        hasVerification: false,
        hasRecoverableEffect: false,
        hasQueuedEffect: false,
        hasReplyDraft: true,
        hasLocalDraft: false,
        proposedCount: 1,
        publishedCount: 0,
        challengedCount: 0,
        blockedCount: 0,
      );

      expect(projection.nextAction, MoltbookWorkspaceNextAction.reviewReply);
      expect(projection.proposedCount, 1);
    });

    test('history-only failure does not replace the local draft action', () {
      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.waiting,
        cycleSummary: null,
        observing: false,
        proposing: false,
        delivering: false,
        hasVerification: false,
        hasRecoverableEffect: false,
        hasQueuedEffect: false,
        hasReplyDraft: false,
        hasLocalDraft: true,
        proposedCount: 1,
        publishedCount: 10,
        challengedCount: 0,
        blockedCount: 1,
      );

      expect(projection.nextAction, MoltbookWorkspaceNextAction.reviewDraft);
      expect(projection.blockedCount, 1);
    });

    test('projects cycle evidence without inventing effect counts', () {
      final summary = MoltbookCycleSummary(
        ownerCapsuleHex: 'a' * 64,
        accountBindingId: 'account-1',
        startedAtUtc: '2026-08-01T10:00:00.000Z',
        completedAtUtc: '2026-08-01T10:00:01.000Z',
        inspectedCount: 24,
        candidateCount: 3,
        reconciledCount: 1,
        challengedCount: 1,
        blockedCount: 2,
        heartbeatPlan: MoltbookHeartbeatPlan(
          observedAtUtc: '2026-08-01T10:00:00.000Z',
          priority: 'review_feed',
          reason: 'Three eligible candidates',
          candidatePostIds: const <String>['post-1', 'post-2', 'post-3'],
          publishAllowed: false,
          humanReviewRequired: true,
          safetyFlags: const <String>[],
          planHashHex: 'b' * 64,
          canonicalPlanJson: '{}',
        ),
        checkpoint: const MoltbookFeedCheckpoint.empty(),
      );

      final projection = MoltbookWorkspaceProjection.resolve(
        connected: true,
        enabled: true,
        triggerPhase: MoltbookCycleTriggerPhase.waiting,
        cycleSummary: summary,
        observing: false,
        proposing: false,
        delivering: false,
        hasVerification: false,
        hasRecoverableEffect: false,
        hasQueuedEffect: false,
        hasReplyDraft: false,
        hasLocalDraft: false,
        proposedCount: 0,
        publishedCount: 4,
        challengedCount: 1,
        blockedCount: 2,
      );

      expect(projection.phase, MoltbookWorkspaceCyclePhase.idle);
      expect(projection.nextAction, MoltbookWorkspaceNextAction.runCycle);
      expect(projection.readCount, 24);
      expect(projection.eligibleCount, 3);
      expect(projection.proposedCount, 0);
      expect(projection.publishedCount, 4);
      expect(projection.challengedCount, 1);
      expect(projection.blockedCount, 2);
    });

    test(
      'disabled workspace stays stopped and does not deliver queued work',
      () {
        final projection = MoltbookWorkspaceProjection.resolve(
          connected: true,
          enabled: false,
          triggerPhase: MoltbookCycleTriggerPhase.stopped,
          cycleSummary: null,
          observing: false,
          proposing: false,
          delivering: false,
          hasVerification: false,
          hasRecoverableEffect: false,
          hasQueuedEffect: true,
          hasReplyDraft: false,
          hasLocalDraft: false,
          proposedCount: 0,
          publishedCount: 0,
          challengedCount: 0,
          blockedCount: 0,
        );

        expect(projection.phase, MoltbookWorkspaceCyclePhase.stopped);
        expect(projection.nextAction, MoltbookWorkspaceNextAction.none);
      },
    );
  });
}
