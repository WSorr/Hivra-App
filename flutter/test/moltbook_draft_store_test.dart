import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/moltbook_draft_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late MoltbookDraftStore store;
  var activeRoot = _rootA;

  setUp(() async {
    activeRoot = _rootA;
    home = await Directory.systemTemp.createTemp('hivra_moltbook_drafts_');
    files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: home.path),
      atomicWrites: const AtomicFileWriteService(),
    );
    store = MoltbookDraftStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('persists drafts only for the active capsule', () async {
    await store.save(_preview());
    expect(await store.load(), hasLength(1));

    activeRoot = _rootB;
    expect(await store.load(), isEmpty);

    activeRoot = _rootA;
    expect((await store.load()).single.preview.title, 'Hivra update');
  });

  test('deduplicates repeated canonical draft hashes', () async {
    await store.save(_preview());
    await store.save(_preview());

    expect(await store.load(), hasLength(1));
  });

  test('deletes only the selected local draft', () async {
    final preview = _preview();
    await store.save(preview);
    await store.delete(preview.draftHashHex);

    expect(await store.load(), isEmpty);
  });

  test('deletes a set of completed local drafts atomically', () async {
    final first = _preview();
    final second = _preview(title: 'Second update');
    final retained = _preview(title: 'Retained update');
    await store.save(first);
    await store.save(second);
    await store.save(retained);

    await store.deleteAll(<String>{first.draftHashHex, second.draftHashHex});

    final drafts = await store.load();
    expect(drafts, hasLength(1));
    expect(drafts.single.preview.draftHashHex, retained.draftHashHex);
  });

  test('fails closed on malformed persisted draft state', () async {
    final capsuleDir = await files.capsuleDirForHex(_rootA, create: true);
    await files.writePluginState(
      capsuleDir,
      moltbookAmbassadorPluginId,
      'drafts.v1.json',
      '{"schema_version":1,"plugin_id":"wrong","drafts":[]}',
    );

    expect(store.load(), throwsFormatException);
  });
}

MoltbookDraftPreview _preview({String title = 'Hivra update'}) {
  final canonical =
      '{"schema_version":1,'
      '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
      '"contract_kind":"moltbook_ambassador_draft",'
      '"bulletin_id":"development-note",'
      '"release_tag":"development",'
      '"category":"hivra-development",'
      '"title":"$title",'
      '"body":"A public Hivra fact.",'
      '"audience":"agent-developers",'
      '"approval_required":true,'
      '"safety_flags":[]}';
  return MoltbookDraftPreview.fromHostResult(<String, dynamic>{
    ...(jsonDecode(canonical) as Map<String, dynamic>),
    'draft_hash_hex': sha256.convert(utf8.encode(canonical)).toString(),
    'canonical_draft_json': canonical,
  });
}

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
