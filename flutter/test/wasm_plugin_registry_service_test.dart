import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/atomic_file_write_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';

class _TestUserVisibleDataDirectoryService
    extends UserVisibleDataDirectoryService {
  final Directory _root;

  const _TestUserVisibleDataDirectoryService(this._root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await _root.exists()) {
      await _root.create(recursive: true);
    }
    return _root;
  }

  @override
  Future<Directory> pluginsDirectory({bool create = false}) async {
    final dir = Directory('${_root.path}/Plugins');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

class _BlockingRegistryWriteService extends AtomicFileWriteService {
  final Completer<void> firstRegistryWriteStarted = Completer<void>();
  final Completer<void> _releaseFirstRegistryWrite = Completer<void>();
  bool _blocked = false;

  void release() => _releaseFirstRegistryWrite.complete();

  @override
  Future<void> writeString(File target, String contents) async {
    if (!_blocked && target.path.endsWith('/registry.json')) {
      _blocked = true;
      firstRegistryWriteStarted.complete();
      await _releaseFirstRegistryWrite.future;
    }
    await super.writeString(target, contents);
  }
}

class _FailingRegistryWriteService extends AtomicFileWriteService {
  bool failNextRegistryWrite = false;

  @override
  Future<void> writeString(File target, String contents) async {
    if (failNextRegistryWrite && target.path.endsWith('/registry.json')) {
      failNextRegistryWrite = false;
      throw FileSystemException('Injected registry write failure', target.path);
    }
    await super.writeString(target, contents);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDocsDir;
  late WasmPluginRegistryService service;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp(
      'hivra_wasm_registry_test_',
    );
    service = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('loadPlugins returns empty when registry is missing', () async {
    final records = await service.loadPlugins();
    expect(records, isEmpty);
  });

  test(
    'loadPlugins ignores malformed entries and sorts by installedAt desc',
    () async {
      final pluginsDir = await service.pluginsDirectory(create: true);
      await File(
        '${pluginsDir.path}/old.wasm',
      ).writeAsString('old', flush: true);
      await File(
        '${pluginsDir.path}/new.wasm',
      ).writeAsString('new', flush: true);
      final registry = File('${pluginsDir.path}/registry.json');
      await registry.writeAsString(
        jsonEncode([
          {
            'id': 'old',
            'displayName': 'Old',
            'originalFileName': 'old.wasm',
            'storedFileName': 'old.wasm',
            'sizeBytes': 1,
            'installedAtIso': '2026-03-29T10:00:00Z',
          },
          'bad-entry',
          {
            'id': 'new',
            'displayName': 'New',
            'originalFileName': 'new.wasm',
            'storedFileName': 'new.wasm',
            'sizeBytes': 2,
            'installedAtIso': '2026-03-29T12:00:00Z',
          },
        ]),
        flush: true,
      );

      final records = await service.loadPlugins();

      expect(records.map((r) => r.id).toList(), ['new', 'old']);
    },
  );

  test('install and remove plugin keeps registry and files in sync', () async {
    final sourceFile = File('${tempDocsDir.path}/demo_plugin.wasm');
    await sourceFile.writeAsBytes(const <int>[
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
    ], flush: true);

    final installed = await service.installPluginFromFile(sourceFile);
    expect(installed.originalFileName, 'demo_plugin.wasm');

    final pluginsDir = await service.pluginsDirectory();
    final storedFile = File('${pluginsDir.path}/${installed.storedFileName}');
    expect(await storedFile.exists(), isTrue);

    final loaded = await service.loadPlugins();
    expect(loaded.any((record) => record.id == installed.id), isTrue);

    await service.removePlugin(installed.id);
    expect(await storedFile.exists(), isFalse);
    expect(
      (await service.loadPlugins()).any((record) => record.id == installed.id),
      isFalse,
    );
  });

  test('stores manifest metadata for zip package install', () async {
    final sourceFile = File('${tempDocsDir.path}/demo_contract.zip');
    await sourceFile.writeAsBytes(
      _zipBytes(
        files: {
          'plugin/manifest.json': jsonEncode({
            'schema': 'hivra.plugin.manifest',
            'version': 1,
            'release_version': '0.1.0',
            'plugin_id': 'hivra.contract.bingx-futures-trading.v1',
            'contract': {'kind': 'bingx_futures_order_intent'},
            'runtime': {
              'abi': 'hivra_host_abi_v2',
              'entry_export': 'hivra_evaluate_v1',
              'module_path': 'plugin/module.wasm',
            },
            'capabilities': [
              'consensus_guard.read',
              'exchange.trade.bingx.futures',
            ],
          }),
          'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
        },
      ),
      flush: true,
    );

    final installed = await service.installPluginFromFile(sourceFile);

    expect(installed.packageKind, 'zip');
    expect(installed.pluginId, 'hivra.contract.bingx-futures-trading.v1');
    expect(installed.pluginVersion, '0.1.0');
    expect(installed.contractKind, 'bingx_futures_order_intent');
    expect(installed.runtimeAbi, 'hivra_host_abi_v2');
    expect(installed.runtimeEntryExport, 'hivra_evaluate_v1');
    expect(installed.runtimeModulePath, 'plugin/module.wasm');
    expect(installed.capabilities, [
      'consensus_guard.read',
      'exchange.trade.bingx.futures',
    ]);

    final loaded = await service.loadPlugins();
    expect(loaded, isNotEmpty);
    expect(loaded.first.packageKind, 'zip');
    expect(loaded.first.pluginId, 'hivra.contract.bingx-futures-trading.v1');
  });

  test(
    'reinstalls same plugin_id + version without creating duplicates',
    () async {
      Future<File> createPackage(String name) async {
        final sourceFile = File('${tempDocsDir.path}/$name');
        await sourceFile.writeAsBytes(
          _zipBytes(
            files: {
              'plugin/manifest.json': jsonEncode({
                'schema': 'hivra.plugin.manifest',
                'version': 1,
                'release_version': '0.1.0',
                'plugin_id': 'hivra.contract.bingx-futures-trading.v1',
                'contract': {'kind': 'bingx_futures_order_intent'},
                'runtime': {
                  'abi': 'hivra_host_abi_v2',
                  'entry_export': 'hivra_evaluate_v1',
                },
                'capabilities': [
                  'exchange.read.bingx.market',
                  'exchange.trade.bingx.futures',
                ],
              }),
              'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
            },
          ),
          flush: true,
        );
        return sourceFile;
      }

      final first = await service.installPluginFromFile(
        await createPackage('bingx-a-0.1.0.zip'),
      );
      final pluginsDir = await service.pluginsDirectory();
      final firstStored = File('${pluginsDir.path}/${first.storedFileName}');
      expect(await firstStored.exists(), isTrue);

      final second = await service.installPluginFromFile(
        await createPackage('bingx-b-0.1.0.zip'),
      );
      final secondStored = File('${pluginsDir.path}/${second.storedFileName}');
      expect(await secondStored.exists(), isTrue);
      expect(await firstStored.exists(), isFalse);

      final records = await service.loadPlugins();
      final samePlugin =
          records
              .where(
                (r) =>
                    r.pluginId == 'hivra.contract.bingx-futures-trading.v1' &&
                    r.pluginVersion == '0.1.0',
              )
              .toList();
      expect(samePlugin.length, 1);
      expect(samePlugin.first.id, second.id);
    },
  );

  test(
    'installing a newer version replaces the active plugin package',
    () async {
      Future<File> createPackage(String version) async {
        final sourceFile = File('${tempDocsDir.path}/demo-$version.zip');
        await sourceFile.writeAsBytes(
          _zipBytes(
            files: {
              'plugin/manifest.json': jsonEncode({
                'schema': 'hivra.plugin.manifest',
                'version': 1,
                'release_version': version,
                'plugin_id': 'hivra.contract.demo.v1',
                'contract': {'kind': 'demo'},
                'runtime': {
                  'abi': 'hivra_host_abi_v2',
                  'entry_export': 'hivra_evaluate_v1',
                },
                'capabilities': ['content.draft.prepare'],
              }),
              'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
            },
          ),
          flush: true,
        );
        return sourceFile;
      }

      final oldRecord = await service.installPluginFromFile(
        await createPackage('0.4.0'),
      );
      final pluginsDir = await service.pluginsDirectory();
      final oldFile = File('${pluginsDir.path}/${oldRecord.storedFileName}');

      final newRecord = await service.installPluginFromFile(
        await createPackage('0.5.0'),
      );
      final records = await service.loadPlugins();

      expect(
        records.where((record) => record.pluginId == 'hivra.contract.demo.v1'),
        hasLength(1),
      );
      expect(records.first.pluginVersion, '0.5.0');
      expect(await oldFile.exists(), isFalse);
      expect(
        await File('${pluginsDir.path}/${newRecord.storedFileName}').exists(),
        isTrue,
      );
    },
  );

  test('serializes concurrent installs across registry instances', () async {
    final firstSource = File('${tempDocsDir.path}/first.wasm');
    final secondSource = File('${tempDocsDir.path}/second.wasm');
    await firstSource.writeAsBytes(_wasmBytes, flush: true);
    await secondSource.writeAsBytes(_wasmBytes, flush: true);
    final blockingWrites = _BlockingRegistryWriteService();
    final firstService = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      atomicWrites: blockingWrites,
    );
    final secondService = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );

    final firstInstall = firstService.installPluginFromFile(firstSource);
    await blockingWrites.firstRegistryWriteStarted.future;
    final secondInstall = secondService.installPluginFromFile(secondSource);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    blockingWrites.release();
    await Future.wait([firstInstall, secondInstall]);

    final installed = await service.loadPlugins();
    expect(installed, hasLength(2));
    expect(
      installed.map((record) => record.originalFileName),
      containsAll(<String>['first.wasm', 'second.wasm']),
    );
  });

  test('failed update preserves the active record and package', () async {
    final oldSource = await _createPluginPackage(tempDocsDir, version: '0.4.0');
    final oldRecord = await service.installPluginFromFile(oldSource);
    final pluginsDir = await service.pluginsDirectory();
    final oldStoredFile = File(
      '${pluginsDir.path}/${oldRecord.storedFileName}',
    );
    final failingWrites = _FailingRegistryWriteService();
    final failingService = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      atomicWrites: failingWrites,
    );
    failingWrites.failNextRegistryWrite = true;

    await expectLater(
      () => failingService.installPluginFromFile(
        _createPluginPackageSync(tempDocsDir, version: '0.5.0'),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final installed = await service.loadPlugins();
    expect(installed, hasLength(1));
    expect(installed.single.id, oldRecord.id);
    expect(installed.single.pluginVersion, '0.4.0');
    expect(await oldStoredFile.exists(), isTrue);
  });

  test('failed remove preserves the active record and package', () async {
    final source = File('${tempDocsDir.path}/remove-me.wasm');
    await source.writeAsBytes(_wasmBytes, flush: true);
    final record = await service.installPluginFromFile(source);
    final pluginsDir = await service.pluginsDirectory();
    final storedFile = File('${pluginsDir.path}/${record.storedFileName}');
    final failingWrites = _FailingRegistryWriteService();
    final failingService = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      atomicWrites: failingWrites,
    );
    failingWrites.failNextRegistryWrite = true;

    await expectLater(
      () => failingService.removePlugin(record.id),
      throwsA(isA<FileSystemException>()),
    );

    final installed = await service.loadPlugins();
    expect(installed.map((entry) => entry.id), contains(record.id));
    expect(await storedFile.exists(), isTrue);
  });

  test('loadPlugins removes interrupted package and temp orphans', () async {
    final pluginsDir = await service.pluginsDirectory(create: true);
    final orphanPackage = File('${pluginsDir.path}/orphan.zip');
    final orphanTemp = File('${pluginsDir.path}/registry.json.tmp.123.456');
    await orphanPackage.writeAsString('orphan', flush: true);
    await orphanTemp.writeAsString('temp', flush: true);

    expect(await service.loadPlugins(), isEmpty);
    expect(await orphanPackage.exists(), isFalse);
    expect(await orphanTemp.exists(), isFalse);
  });

  test(
    'loadPlugins self-heals duplicate plugin_id records across versions',
    () async {
      final pluginsDir = await service.pluginsDirectory(create: true);
      final staleFile = File('${pluginsDir.path}/stale.zip');
      final freshFile = File('${pluginsDir.path}/fresh.zip');
      await staleFile.writeAsString('stale', flush: true);
      await freshFile.writeAsString('fresh', flush: true);

      final registry = File('${pluginsDir.path}/registry.json');
      await registry.writeAsString(
        jsonEncode([
          {
            'id': 'fresh-id',
            'displayName': 'BingX',
            'originalFileName': 'bingx_futures_test_plugin-0.2.0.zip',
            'storedFileName': 'fresh.zip',
            'sizeBytes': 10,
            'installedAtIso': '2026-04-09T12:00:00Z',
            'packageKind': 'zip',
            'pluginId': 'hivra.contract.bingx-futures-trading.v1',
            'pluginVersion': '0.2.0',
          },
          {
            'id': 'stale-id',
            'displayName': 'BingX',
            'originalFileName': 'bingx_futures_test_plugin-0.1.0.zip',
            'storedFileName': 'stale.zip',
            'sizeBytes': 11,
            'installedAtIso': '2026-04-09T11:00:00Z',
            'packageKind': 'zip',
            'pluginId': 'hivra.contract.bingx-futures-trading.v1',
            'pluginVersion': '0.1.0',
          },
        ]),
        flush: true,
      );

      final records = await service.loadPlugins();
      expect(records.length, 1);
      expect(records.first.id, 'fresh-id');
      expect(await staleFile.exists(), isFalse);
      expect(await freshFile.exists(), isTrue);
    },
  );

  test(
    'loadPlugins prunes records with missing stored package files',
    () async {
      final pluginsDir = await service.pluginsDirectory(create: true);
      final presentFile = File('${pluginsDir.path}/present.zip');
      await presentFile.writeAsString('present', flush: true);

      final registry = File('${pluginsDir.path}/registry.json');
      await registry.writeAsString(
        jsonEncode([
          {
            'id': 'present-id',
            'displayName': 'Present',
            'originalFileName': 'present.zip',
            'storedFileName': 'present.zip',
            'sizeBytes': 10,
            'installedAtIso': '2026-04-10T12:00:00Z',
            'packageKind': 'zip',
            'pluginId': 'hivra.contract.bingx-futures-trading.v1',
            'pluginVersion': '0.1.0',
          },
          {
            'id': 'missing-id',
            'displayName': 'Missing',
            'originalFileName': 'missing.zip',
            'storedFileName': 'missing.zip',
            'sizeBytes': 10,
            'installedAtIso': '2026-04-10T11:00:00Z',
            'packageKind': 'zip',
            'pluginId': 'hivra.contract.capsule-chat.v1',
            'pluginVersion': '0.1.0',
          },
        ]),
        flush: true,
      );

      final loaded = await service.loadPlugins();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'present-id');

      final repairedRegistry =
          jsonDecode(await registry.readAsString()) as List<dynamic>;
      expect(repairedRegistry.length, 1);
      expect(
        (repairedRegistry.first as Map<String, dynamic>)['id'],
        'present-id',
      );
    },
  );
}

const List<int> _wasmBytes = <int>[0, 97, 115, 109, 1, 0, 0, 0];

Future<File> _createPluginPackage(
  Directory root, {
  required String version,
}) async {
  final file = _createPluginPackageSync(root, version: version);
  await file.parent.create(recursive: true);
  return file;
}

File _createPluginPackageSync(Directory root, {required String version}) {
  final file = File('${root.path}/transactional-demo-$version.zip');
  file.writeAsBytesSync(
    _zipBytes(
      files: {
        'plugin/manifest.json': jsonEncode({
          'schema': 'hivra.plugin.manifest',
          'version': 1,
          'release_version': version,
          'plugin_id': 'hivra.contract.transactional-demo.v1',
          'contract': {'kind': 'transactional_demo'},
          'runtime': {
            'abi': 'hivra_host_abi_v2',
            'entry_export': 'hivra_evaluate_v1',
          },
          'capabilities': ['content.draft.prepare'],
        }),
        'plugin/module.wasm': _wasmBytes,
      },
    ),
    flush: true,
  );
  return file;
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
