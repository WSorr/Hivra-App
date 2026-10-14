import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  test('source note replacement clears the old multiline editing value', () {
    final sourceNotes = TextEditingController(
      text: 'Old first line\nOld second line',
    );
    addTearDown(sourceNotes.dispose);

    replaceMoltbookPublicSourceNotes(
      controller: sourceNotes,
      text: 'New first line\nNew second line',
    );

    expect(sourceNotes.text, 'New first line\nNew second line');
    expect(sourceNotes.selection, const TextSelection.collapsed(offset: 30));
    expect(sourceNotes.value.composing, TextRange.empty);
  });

  testWidgets('source notes semantics replaces the controller value', (
    WidgetTester tester,
  ) async {
    final sourceNotes = TextEditingController(text: 'Old line\nOld detail');
    addTearDown(sourceNotes.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: moltbookPublicSourceNotesField(
            controller: sourceNotes,
            onSetText:
                (text) => replaceMoltbookPublicSourceNotes(
                  controller: sourceNotes,
                  text: text,
                ),
          ),
        ),
      ),
    );

    final labeledNodes = find.bySemanticsLabel('Public source notes');
    final node = <SemanticsNode>[
      for (var index = 0; index < labeledNodes.evaluate().length; index++)
        tester.getSemantics(labeledNodes.at(index)),
    ].firstWhere(
      (candidate) =>
          candidate.getSemanticsData().hasAction(SemanticsAction.setText),
    );
    node.owner!.performAction(
      node.id,
      SemanticsAction.setText,
      'New line\nNew detail',
    );
    await tester.pump();

    expect(sourceNotes.text, 'New line\nNew detail');
    semantics.dispose();
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
