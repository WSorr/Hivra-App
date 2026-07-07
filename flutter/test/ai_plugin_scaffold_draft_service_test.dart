import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_plugin_scaffold_draft_service.dart';

void main() {
  group('AiPluginScaffoldDraftService', () {
    late Directory tempRepo;

    setUp(() async {
      tempRepo = await Directory.systemTemp.createTemp('hivra-plugin-draft-');
      await Directory('${tempRepo.path}/contracts').create(recursive: true);
      await Directory('${tempRepo.path}/plugins').create(recursive: true);
      await File('${tempRepo.path}/contracts/plugin_host_api_v1.md')
          .writeAsString('host api');
      await File('${tempRepo.path}/plugins/README.md').writeAsString('plugins');
    });

    tearDown(() async {
      if (await tempRepo.exists()) {
        await tempRepo.delete(recursive: true);
      }
    });

    test('creates draft-only plugin skeleton in plugin repo boundary',
        () async {
      const service = AiPluginScaffoldDraftService();

      final report = await service.createDraft(
        AiPluginScaffoldDraftRequest(
          pluginRepoRootPath: tempRepo.path,
          pluginId: 'hivra.contract.demo-agent.v1',
          purpose: 'Test deterministic demo agent.',
          contractKind: 'demo_agent',
          hostApiVersion: 'plugin_host_api_v1',
          capabilities: const <String>['consensus_guard.read'],
        ),
      );

      expect(report.pluginId, 'hivra.contract.demo-agent.v1');
      expect(report.buildSkipped, isTrue);
      expect(report.installSkipped, isTrue);
      expect(report.catalogUpdateSkipped, isTrue);
      expect(report.signingSkipped, isTrue);
      expect(report.gitSkipped, isTrue);
      expect(
        report.createdRelativePaths,
        <String>[
          'plugins/drafts/hivra_contract_demo_agent_v1/Cargo.toml',
          'plugins/drafts/hivra_contract_demo_agent_v1/README.md',
          'plugins/drafts/hivra_contract_demo_agent_v1/manifest.json',
          'plugins/drafts/hivra_contract_demo_agent_v1/src/lib.rs',
          'plugins/drafts/hivra_contract_demo_agent_v1/tests/golden_vectors.json',
        ],
      );

      final manifest = jsonDecode(await File(
        '${report.draftRootPath}/manifest.json',
      ).readAsString()) as Map<String, dynamic>;
      expect(manifest['schema'], 'hivra.plugin.manifest');
      expect(manifest['plugin_id'], 'hivra.contract.demo-agent.v1');
      expect(manifest['release_version'], '0.1.0-draft');
      expect(manifest['capabilities'], <String>['consensus_guard.read']);
      expect(
        await File('${tempRepo.path}/catalog/plugin_catalog.json').exists(),
        isFalse,
      );
      expect(await Directory('${tempRepo.path}/dist').exists(), isFalse);

      final libRs = await File('${report.draftRootPath}/src/lib.rs')
          .readAsString();
      expect(libRs, contains('Draft placeholder'));
      expect(libRs, isNot(contains('TODO')));
    });

    test('rejects non-plugin repository boundary', () async {
      final badRoot = await Directory.systemTemp.createTemp('hivra-app-root-');
      addTearDown(() async {
        if (await badRoot.exists()) {
          await badRoot.delete(recursive: true);
        }
      });
      const service = AiPluginScaffoldDraftService();

      await expectLater(
        service.createDraft(
          AiPluginScaffoldDraftRequest(
            pluginRepoRootPath: badRoot.path,
            pluginId: 'hivra.contract.demo-agent.v1',
            purpose: 'no boundary',
            contractKind: 'demo_agent',
            hostApiVersion: 'plugin_host_api_v1',
            capabilities: const <String>['consensus_guard.read'],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects duplicate draft instead of overwriting', () async {
      const service = AiPluginScaffoldDraftService();
      final request = AiPluginScaffoldDraftRequest(
        pluginRepoRootPath: tempRepo.path,
        pluginId: 'hivra.contract.demo-agent.v1',
        purpose: 'Test deterministic demo agent.',
        contractKind: 'demo_agent',
        hostApiVersion: 'plugin_host_api_v1',
        capabilities: const <String>['consensus_guard.read'],
      );

      await service.createDraft(request);

      await expectLater(
        service.createDraft(request),
        throwsA(isA<StateError>()),
      );
    });
  });
}
