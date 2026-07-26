import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/models/moltbook_ambassador_models.dart';
import 'package:hivra_app/models/plugin_contract_ids.dart';
import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/moltbook_ambassador_configuration_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  late Directory home;
  late CapsuleFileStore files;
  late MoltbookAmbassadorConfigurationStore store;
  var activeRoot = _rootA;

  setUp(() async {
    activeRoot = _rootA;
    home = await Directory.systemTemp.createTemp('hivra_moltbook_config_test_');
    final dirs = UserVisibleDataDirectoryService(homeOverride: home.path);
    files = CapsuleFileStore(
      dirs: dirs,
      atomicWrites: const AtomicFileWriteService(),
    );
    store = MoltbookAmbassadorConfigurationStore(
      fileStore: files,
      readActiveCapsuleRootHex: () => activeRoot,
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('saves and loads configuration only for the active capsule', () async {
    final configuration = MoltbookAmbassadorConfiguration(
      agentName: 'Hivra Notes',
      agentDescription: 'Public technical notes about Hivra.',
      personaSummary: 'Explain verified public changes without hype.',
      allowedTopics: const <String>['hivra-development'],
      approvalMode: MoltbookAmbassadorConfiguration.approvalAssisted,
      enabled: true,
    );

    await store.save(configuration);
    expect((await store.load()).agentName, 'Hivra Notes');

    activeRoot = _rootB;
    expect(
      (await store.load()).agentName,
      MoltbookAmbassadorConfiguration.defaults().agentName,
    );
  });

  test('persists only public profile and policy fields', () async {
    await store.save(MoltbookAmbassadorConfiguration.defaults());
    final capsuleDir = await files.capsuleDirForHex(_rootA);
    final raw = await files.readPluginState(
      capsuleDir,
      'hivra.contract.moltbook-ambassador.v1',
      'configuration.v1.json',
    );

    expect(raw, isNotNull);
    expect(raw, contains('agent_name'));
    expect(raw, contains('approval_mode'));
    expect(raw, isNot(contains('api_key')));
    expect(raw, isNot(contains('seed')));
    expect(raw, isNot(contains('private_key')));
  });

  test('rejects invalid autonomous approval mode', () {
    expect(
      () => MoltbookAmbassadorConfiguration.fromJson(<String, dynamic>{
        'schema_version': 1,
        'plugin_id': moltbookAmbassadorPluginId,
        'agent_name': 'agent',
        'agent_description': 'description',
        'persona_summary': 'summary',
        'allowed_topics': <String>['hivra-development'],
        'approval_mode': 'autonomous',
        'enabled': true,
      }),
      throwsFormatException,
    );
  });

  test('projects a validated host draft result without changing semantics', () {
    final preview = MoltbookDraftPreview.fromHostResult(_validDraftResult());

    expect(preview.title, 'Hivra development update');
    expect(preview.approvalRequired, isTrue);
    expect(preview.safetyFlags, isEmpty);
  });

  test('rejects a host draft without the manual approval gate', () {
    expect(
      () => MoltbookDraftPreview.fromHostResult(<String, dynamic>{
        'schema_version': 1,
        'plugin_id': moltbookAmbassadorPluginId,
        'contract_kind': 'moltbook_ambassador_draft',
        'approval_required': false,
      }),
      throwsFormatException,
    );
  });

  test(
    'does not replace a malformed persisted configuration with defaults',
    () async {
      final capsuleDir = await files.capsuleDirForHex(_rootA, create: true);
      await files.writePluginState(
        capsuleDir,
        moltbookAmbassadorPluginId,
        'configuration.v1.json',
        '{"schema_version":1,"plugin_id":"wrong"}',
      );

      expect(store.load(), throwsFormatException);
    },
  );

  test('deletes only the active capsule configuration', () async {
    await store.save(MoltbookAmbassadorConfiguration.defaults());
    await store.delete();

    expect(
      (await store.load()).agentName,
      MoltbookAmbassadorConfiguration.defaults().agentName,
    );
  });
}

Map<String, dynamic> _validDraftResult() {
  const canonical =
      '{"schema_version":1,'
      '"plugin_id":"hivra.contract.moltbook-ambassador.v1",'
      '"contract_kind":"moltbook_ambassador_draft",'
      '"bulletin_id":"release-v1.0.3-test14",'
      '"release_tag":"v1.0.3-test14",'
      '"category":"hivra-development",'
      '"title":"Hivra development update",'
      '"body":"A public Hivra development fact.",'
      '"audience":"agent-developers",'
      '"approval_required":true,'
      '"safety_flags":[]}';
  return <String, dynamic>{
    'schema_version': 1,
    'plugin_id': moltbookAmbassadorPluginId,
    'contract_kind': 'moltbook_ambassador_draft',
    'bulletin_id': 'release-v1.0.3-test14',
    'release_tag': 'v1.0.3-test14',
    'category': 'hivra-development',
    'title': 'Hivra development update',
    'body': 'A public Hivra development fact.',
    'audience': 'agent-developers',
    'approval_required': true,
    'safety_flags': <String>[],
    'draft_hash_hex': sha256.convert(canonical.codeUnits).toString(),
    'canonical_draft_json': canonical,
  };
}

const String _rootA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _rootB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
