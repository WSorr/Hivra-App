import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/screens/moltbook_ambassador_screen.dart';
import 'package:hivra_app/services/moltbook_public_change_feed_store.dart';

void main() {
  test('recorded public change resets manual input to a fresh source id', () {
    final bulletinId = TextEditingController(text: 'development-note');
    final sourceNotes = TextEditingController(text: 'One confirmed fact.');
    addTearDown(bulletinId.dispose);
    addTearDown(sourceNotes.dispose);

    resetMoltbookPublicChangeInput(
      bulletinIdController: bulletinId,
      publicSourceNotesController: sourceNotes,
      recordedAt: DateTime.utc(2026, 9, 12, 14, 2, 16, 104, 926),
    );

    expect(bulletinId.text, 'change-1789221736104926');
    expect(sourceNotes.text, isEmpty);
  });

  test('queued public change replaces stale manual draft identity', () {
    final bulletinId = TextEditingController(text: 'development-note');
    final category = TextEditingController(text: 'general');
    final title = TextEditingController();
    final body = TextEditingController();
    final facts = TextEditingController();
    addTearDown(bulletinId.dispose);
    addTearDown(category.dispose);
    addTearDown(title.dispose);
    addTearDown(body.dispose);
    addTearDown(facts.dispose);

    const sourceId = 'hivra-chat-workspace-2026-08-14';
    const changeFacts = <String>['Chat workspace now projects live messages.'];
    final change = MoltbookPublicChange(
      sourceId: sourceId,
      category: 'hivra-development',
      facts: changeFacts,
      commitmentHashHex: MoltbookPublicChangeFeedStore.commitmentFor(
        sourceId: sourceId,
        category: 'hivra-development',
        facts: changeFacts,
      ),
      recordedAtUtc: DateTime.utc(2026, 8, 14),
    );
    const proposal = MoltbookPublicBulletinProposal(
      title: 'Chat delivery is now easier to follow',
      body: 'The workspace projects new messages into an open conversation.',
      facts: <String>['AI paraphrase must not replace the confirmed fact.'],
      providerLabel: 'Gemini',
      model: 'test-model',
    );

    bindMoltbookPublicChangeProposal(
      change: change,
      proposal: proposal,
      bulletinIdController: bulletinId,
      categoryController: category,
      titleController: title,
      bodyController: body,
      factsController: facts,
    );

    expect(bulletinId.text, sourceId);
    expect(category.text, 'hivra-development');
    expect(title.text, proposal.title);
    expect(body.text, proposal.body);
    expect(facts.text, changeFacts.single);
  });
}
