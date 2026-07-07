import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/services/ai_developer_workspace_service.dart';
import 'package:hivra_app/services/ai_plugin_audit_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_service.dart';

void main() {
  group('AiPluginAuditService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hivra-plugin-audit-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('audits installed plugin package digest deterministically', () async {
      final package = File('${tempDir.path}/plugin.zip');
      await package.writeAsBytes(<int>[1, 2, 3, 4]);
      final service = AiPluginAuditService(
        registry: _FakeRegistry(
          dir: tempDir,
          records: <WasmPluginRecord>[
            _record(storedFileName: 'plugin.zip'),
          ],
        ),
      );

      final first = await service.auditInstalledPlugins();
      final second = await service.auditInstalledPlugins();

      expect(first.reportHashHex, second.reportHashHex);
      expect(first.statusLabel, 'Healthy');
      expect(first.entries.single.packageDigestHex,
          sha256.convert(<int>[1, 2, 3, 4]).toString());
      expect(first.findings, isEmpty);
    });

    test('flags runtime and capability drift', () async {
      final package = File('${tempDir.path}/bad.zip');
      await package.writeAsBytes(<int>[9, 9, 9]);
      final service = AiPluginAuditService(
        registry: _FakeRegistry(
          dir: tempDir,
          records: <WasmPluginRecord>[
            _record(
              storedFileName: 'bad.zip',
              runtimeAbi: 'old_abi',
              capabilities: <String>['wild.network'],
            ),
          ],
        ),
      );

      final report = await service.auditInstalledPlugins();

      expect(report.statusLabel, 'Critical');
      expect(
        report.findings.map((finding) => finding.title),
        containsAll(<String>[
          'Runtime ABI mismatch',
          'Unsupported capability declared',
        ]),
      );
    });

    test('audits selected plugin source evidence without granting capabilities',
        () {
      const service = AiPluginAuditService();

      final first = service.auditSelectedSourceContext(
        context: _selectedPluginSourceContext(
          manifestText: _validManifest(),
          runtimeText: 'export ${WasmPluginRuntimeService.requiredEntryExport}',
          catalogText: _validCatalog(),
        ),
        expectedPluginId: 'hivra.contract.demo.v1',
      );
      final second = service.auditSelectedSourceContext(
        context: _selectedPluginSourceContext(
          manifestText: _validManifest(),
          runtimeText: 'export ${WasmPluginRuntimeService.requiredEntryExport}',
          catalogText: _validCatalog(),
        ),
        expectedPluginId: 'hivra.contract.demo.v1',
      );

      expect(first.reportHashHex, second.reportHashHex);
      expect(first.statusLabel, 'Healthy');
      expect(first.canGrantCapabilities, isFalse);
      expect(
        first.snippets.expand((snippet) => snippet.evidenceKinds),
        containsAll(<String>[
          'manifest',
          'runtime_entry_export',
          'catalog',
        ]),
      );
    });

    test('flags selected source drift and unsupported source capabilities', () {
      const service = AiPluginAuditService();

      final report = service.auditSelectedSourceContext(
        context: _selectedPluginSourceContext(
          manifestText: _validManifest(
            pluginId: 'hivra.contract.other.v1',
            capabilities: <String>['wild.network'],
            runtimeAbi: 'old_abi',
          ),
          runtimeText: 'no host entry here',
          catalogText: '{"schema":"hivra.plugin.catalog","entries":[]}',
        ),
        expectedPluginId: 'hivra.contract.demo.v1',
      );

      expect(report.statusLabel, 'Critical');
      expect(report.canGrantCapabilities, isFalse);
      expect(
        report.findings.map((finding) => finding.title),
        containsAll(<String>[
          'Plugin source id does not match expected plugin',
          'Manifest runtime ABI mismatch',
          'Unsupported capability declared',
          'Runtime entry evidence is missing',
          'Catalog digest/signature evidence is missing',
        ]),
      );
    });
  });
}

WasmPluginRecord _record({
  required String storedFileName,
  String runtimeAbi = WasmPluginRuntimeService.requiredRuntimeAbi,
  List<String> capabilities = const <String>['consensus_guard.read'],
}) {
  return WasmPluginRecord(
    id: 'plugin-record',
    displayName: 'Demo Plugin',
    originalFileName: storedFileName,
    storedFileName: storedFileName,
    sizeBytes: 4,
    installedAtIso: '2026-07-05T00:00:00Z',
    packageKind: 'zip',
    pluginId: 'hivra.contract.demo.v1',
    pluginVersion: '0.1.0',
    contractKind: 'demo',
    runtimeAbi: runtimeAbi,
    runtimeEntryExport: WasmPluginRuntimeService.requiredEntryExport,
    runtimeModulePath: 'plugin/module.wasm',
    capabilities: capabilities,
  );
}

class _FakeRegistry extends WasmPluginRegistryService {
  final Directory dir;
  final List<WasmPluginRecord> records;

  const _FakeRegistry({
    required this.dir,
    required this.records,
  });

  @override
  Future<Directory> pluginsDirectory({bool create = false}) async => dir;

  @override
  Future<List<WasmPluginRecord>> loadPlugins() async => records;
}

AiDeveloperWorkspaceSelectedContext _selectedPluginSourceContext({
  required String manifestText,
  required String runtimeText,
  required String catalogText,
}) {
  return AiDeveloperWorkspaceSelectedContext(
    schemaVersion: 1,
    snippets: <AiDeveloperWorkspaceSnippet>[
      _snippet('plugins/demo/manifest.json', manifestText),
      _snippet('plugins/demo/src/lib.rs', runtimeText),
      _snippet('catalog/plugin_catalog.json', catalogText),
    ],
    findings: const <AiDeveloperWorkspaceFinding>[],
    contextHashHex: 'source-context',
  );
}

AiDeveloperWorkspaceSnippet _snippet(String relativePath, String text) {
  return AiDeveloperWorkspaceSnippet(
    rootPath: '/repo',
    relativePath: relativePath,
    sizeBytes: text.length,
    sha256Hex: sha256.convert(text.codeUnits).toString(),
    text: text,
  );
}

String _validManifest({
  String pluginId = 'hivra.contract.demo.v1',
  String runtimeAbi = WasmPluginRuntimeService.requiredRuntimeAbi,
  List<String> capabilities = const <String>['consensus_guard.read'],
}) {
  return '''
{
  "schema": "hivra.plugin.manifest",
  "version": 1,
  "release_version": "0.1.0",
  "plugin_id": "$pluginId",
  "capabilities": ${jsonList(capabilities)},
  "runtime": {
    "abi": "$runtimeAbi",
    "entry_export": "${WasmPluginRuntimeService.requiredEntryExport}",
    "module_path": "plugin/module.wasm"
  }
}
''';
}

String _validCatalog() {
  return '''
{
  "schema": "hivra.plugin.catalog",
  "version": 2,
  "entries": [
    {
      "id": "demo",
      "sha256_hex": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  ],
  "signatures": [
    {
      "algorithm": "ed25519",
      "key_id": "demo",
      "signature_hex": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  ]
}
''';
}

String jsonList(List<String> values) {
  return '[${values.map((value) => '"$value"').join(', ')}]';
}
