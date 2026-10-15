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

    await tester.enterText(find.byType(TextField), 'New line\nNew detail');
    await tester.pump();

    expect(sourceNotes.text, 'New line\nNew detail');
  });

  testWidgets('native source notes input reaches the canonical sink', (
    WidgetTester tester,
  ) async {
    final sourceNotes = TextEditingController();
    final sink = <String>[];
    addTearDown(sourceNotes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: moltbookPublicSourceNotesField(
            controller: sourceNotes,
            onSetText: sink.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Live source note');
    await tester.pump();

    expect(sourceNotes.text, 'Live source note');
    expect(sink, <String>['Live source note']);
  });

  testWidgets('reviewed body semantics replaces the exact WASM input value', (
    WidgetTester tester,
  ) async {
    final body = TextEditingController(text: 'Old body');
    addTearDown(body.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: moltbookReviewedTextField(
            semanticsKey: 'reviewed-body',
            label: 'Reviewed post body',
            controller: body,
            minLines: 4,
            maxLines: 10,
            onSetText:
                (text) =>
                    replaceMoltbookTextController(controller: body, text: text),
          ),
        ),
      ),
    );

    const replacement =
        'The reviewed body now reaches the installed WASM plugin exactly.';
    await tester.enterText(find.byType(TextField), replacement);
    await tester.pump();

    expect(body.text, replacement);
    expect(body.selection, TextSelection.collapsed(offset: replacement.length));
    expect(body.value.composing, TextRange.empty);
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
