import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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
