import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/wasm_plugin_package_preflight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const service = WasmPluginPackagePreflightService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'hivra_wasm_plugin_preflight_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts valid wasm binary package', () async {
    final file = File('${tempDir.path}/valid.wasm');
    await file.writeAsBytes(
      const <int>[0, 97, 115, 109, 1, 0, 0, 0],
      flush: true,
    );

    final preflight = await service.inspect(file);

    expect(preflight.packageKind, 'wasm');
    expect(preflight.pluginId, isNull);
    expect(preflight.capabilities, isEmpty);
  });

  test('rejects wasm package with invalid header', () async {
    final file = File('${tempDir.path}/invalid.wasm');
    await file.writeAsBytes(
      const <int>[0, 97, 115, 109, 0, 0, 0, 0],
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts valid zip package with manifest and wasm module', () async {
    final file = File('${tempDir.path}/valid.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'contract': {'kind': 'temperature_tomorrow_liechtenstein'},
              'capabilities': [
                'oracle.read.mock_weather',
                'consensus_guard.read'
              ],
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final preflight = await service.inspect(file);

    expect(preflight.packageKind, 'zip');
    expect(preflight.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
    expect(preflight.contractKind, 'temperature_tomorrow_liechtenstein');
    expect(
      preflight.capabilities,
      ['consensus_guard.read', 'oracle.read.mock_weather'],
    );
  });

  test('rejects non-list capabilities field in manifest', () async {
    final file = File('${tempDir.path}/bad_capabilities.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'capabilities': 'not-a-list',
            },
          ),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package without manifest', () async {
    final file = File('${tempDir.path}/missing_manifest.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects zip package without wasm module', () async {
    final file = File('${tempDir.path}/missing_wasm.zip');
    await file.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode(
            {
              'schema': 'hivra.plugin.manifest',
              'version': 1,
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
            },
          ),
        },
      ),
      flush: true,
    );

    expect(
      () => service.inspect(file),
      throwsA(isA<FormatException>()),
    );
  });
}

List<int> _zipBytes({required Map<String, Object> files}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final content = entry.value;
    final bytes = switch (content) {
      List<int> _ => content,
      String _ => utf8.encode(content),
      _ => throw ArgumentError('Unsupported zip content type for ${entry.key}'),
    };
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('Failed to encode zip test archive');
  }
  return encoded;
}
