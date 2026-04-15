import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_source_catalog_service.dart';

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

void main() {
  late Directory tempDocsDir;
  late HttpServer server;
  late WasmPluginRegistryService registry;
  late WasmPluginSourceCatalogService service;

  final packageBytes = _zipBytes(
    files: {
      'plugin/manifest.json': jsonEncode(
        {
          'schema': 'hivra.plugin.manifest',
          'version': 1,
          'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
          'contract': {'kind': 'temperature_tomorrow_liechtenstein'},
          'runtime': {
            'abi': 'hivra_host_abi_v1',
            'entry_export': 'hivra_entry_v1',
          },
          'capabilities': ['consensus_guard.read'],
        },
      ),
      'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
    },
  );
  final packageSha256Hex = sha256.convert(packageBytes).toString();
  final mismatchPluginPackageBytes = _zipBytes(
    files: {
      'plugin/manifest.json': jsonEncode(
        {
          'schema': 'hivra.plugin.manifest',
          'version': 1,
          'plugin_id': 'hivra.contract.capsule-chat.v1',
          'contract': {'kind': 'capsule_chat'},
          'runtime': {
            'abi': 'hivra_host_abi_v1',
            'entry_export': 'hivra_entry_v1',
          },
          'capabilities': ['capsule.chat.post'],
        },
      ),
      'plugin/module.wasm': const <int>[0, 97, 115, 109, 1, 0, 0, 0],
    },
  );

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('hivra_source_cat_');
    registry = WasmPluginRegistryService(
      dataDirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
    service = WasmPluginSourceCatalogService(registry: registry);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/catalog.json') {
        final downloadUrl =
            'http://127.0.0.1:${server.port}/packages/demo-plugin.zip';
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              {
                'schema': 'hivra.plugin.catalog',
                'version': 1,
                'source_id': 'wsorr.hivra.plugins',
                'source_name': 'Hivra Plugins',
                'entries': [
                  {
                    'id': 'temperature-li-tomorrow',
                    'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
                    'display_name': 'Temperature Tomorrow LI',
                    'version': '0.1.0',
                    'download_url': downloadUrl,
                    'package_kind': 'zip',
                    'sha256_hex': packageSha256Hex,
                  }
                ],
              },
            ),
          );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/packages/demo-plugin.zip') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..add(packageBytes);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('fetchCatalog parses valid remote catalog', () async {
    final url = 'http://127.0.0.1:${server.port}/catalog.json';
    final catalog = await service.fetchCatalog(catalogUrl: url);

    expect(catalog.sourceId, 'wsorr.hivra.plugins');
    expect(catalog.sourceName, 'Hivra Plugins');
    expect(catalog.entries.length, 1);
    expect(
      catalog.entries.first.pluginId,
      'hivra.contract.temperature-li.tomorrow.v1',
    );
  });

  test('installFromSourceEntry downloads and installs plugin package',
      () async {
    final url = 'http://127.0.0.1:${server.port}/catalog.json';
    final catalog = await service.fetchCatalog(catalogUrl: url);

    final record = await service.installFromSourceEntry(catalog.entries.first);

    expect(record.packageKind, 'zip');
    expect(record.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
    expect(record.contractKind, 'temperature_tomorrow_liechtenstein');
  });

  test('supports local file catalog and file package URLs', () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/local-plugin.zip';
    File(packagePath).writeAsBytesSync(packageBytes, flush: true);

    final catalogPath = '${tempDocsDir.path}/plugin_catalog.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'temperature-local',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Temperature Local',
              'version': '0.1.0',
              'download_url': File(packagePath).uri.toString(),
              'package_kind': 'zip',
              'sha256_hex': packageSha256Hex,
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);

    final record = await service.installFromSourceEntry(catalog.entries.first);
    expect(record.pluginId, 'hivra.contract.temperature-li.tomorrow.v1');
  });

  test('fetchCatalogWithFallback loads local catalog when remote fails',
      () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/local-fallback.zip';
    File(packagePath).writeAsBytesSync(packageBytes, flush: true);

    final localCatalogPath = '${tempDocsDir.path}/plugin_catalog_fallback.json';
    File(localCatalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'fallback-local',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Temperature Local Fallback',
              'version': '0.1.0',
              'download_url': File(packagePath).uri.toString(),
              'package_kind': 'zip',
              'sha256_hex': packageSha256Hex,
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalogWithFallback(
      primaryCatalogUrl: 'http://127.0.0.1:1/not-available.json',
      localCatalogPathOverride: localCatalogPath,
    );

    expect(catalog.sourceId, 'local.hivra.plugins');
    expect(catalog.entries.length, 1);
  });

  test('installFromSourceEntry fails when sha256 mismatches', () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/bad-hash-plugin.zip';
    File(packagePath).writeAsBytesSync(packageBytes, flush: true);

    final entry = WasmPluginSourceCatalogEntry(
      id: 'bad-hash',
      pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
      displayName: 'Bad Hash',
      version: '0.1.0',
      downloadUrl: File(packagePath).uri.toString(),
      packageKind: 'zip',
      sha256Hex:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );

    await expectLater(
      () => service.installFromSourceEntry(entry),
      throwsA(isA<FormatException>()),
    );
  });

  test('fetchCatalog rejects invalid sha256_hex shape', () async {
    final badCatalogPath = '${tempDocsDir.path}/plugin_catalog_bad_sha.json';
    File(badCatalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'bad-sha-shape',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Bad SHA Shape',
              'version': '0.1.0',
              'download_url': 'file:///tmp/any.zip',
              'package_kind': 'zip',
              'sha256_hex': 'not-a-sha',
            }
          ],
        },
      ),
      flush: true,
    );

    await expectLater(
      () => service.fetchCatalog(catalogUrl: badCatalogPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('fetchCatalog filters unsupported download_url schemes', () async {
    final catalogPath =
        '${tempDocsDir.path}/plugin_catalog_bad_url_scheme.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'valid-http',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Valid HTTP',
              'version': '0.1.0',
              'download_url': 'https://example.com/plugin.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'bad-ftp',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Bad FTP',
              'version': '0.1.0',
              'download_url': 'ftp://example.com/plugin.zip',
              'package_kind': 'zip',
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-http');
  });

  test('fetchCatalog deduplicates entries by id preserving first', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_dup_id.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'dup-id',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'First',
              'version': '0.1.0',
              'download_url': 'https://example.com/first.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'dup-id',
              'plugin_id': 'hivra.contract.capsule-chat.v1',
              'display_name': 'Second',
              'version': '0.2.0',
              'download_url': 'https://example.com/second.zip',
              'package_kind': 'zip',
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.displayName, 'First');
    expect(catalog.entries.first.version, '0.1.0');
  });

  test('fetchCatalog filters entries with invalid plugin_id shape', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_bad_plugin_id.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'valid-id-shape',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Valid Plugin Id',
              'version': '0.1.0',
              'download_url': 'https://example.com/valid.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'bad-id-shape',
              'plugin_id': 'temperature-li.tomorrow',
              'display_name': 'Bad Plugin Id',
              'version': '0.1.0',
              'download_url': 'https://example.com/bad.zip',
              'package_kind': 'zip',
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-id-shape');
  });

  test('fetchCatalog filters entries with invalid version shape', () async {
    final catalogPath = '${tempDocsDir.path}/plugin_catalog_bad_version.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'valid-version-shape',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Valid Version',
              'version': '0.1.0',
              'download_url': 'https://example.com/valid.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'bad-version-shape',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Bad Version',
              'version': 'v0.1',
              'download_url': 'https://example.com/bad.zip',
              'package_kind': 'zip',
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 1);
    expect(catalog.entries.first.id, 'valid-version-shape');
  });

  test(
      'fetchCatalog deduplicates entries by plugin_id + version + package_kind',
      () async {
    final catalogPath =
        '${tempDocsDir.path}/plugin_catalog_dup_plugin_ver.json';
    File(catalogPath).writeAsStringSync(
      jsonEncode(
        {
          'schema': 'hivra.plugin.catalog',
          'version': 1,
          'source_id': 'local.hivra.plugins',
          'source_name': 'Local Hivra Plugins',
          'entries': [
            {
              'id': 'entry-a',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'First',
              'version': '0.1.0',
              'download_url': 'https://example.com/first.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'entry-b',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Second same plugin/version',
              'version': '0.1.0',
              'download_url': 'https://example.com/second.zip',
              'package_kind': 'zip',
            },
            {
              'id': 'entry-c',
              'plugin_id': 'hivra.contract.temperature-li.tomorrow.v1',
              'display_name': 'Different version',
              'version': '0.2.0',
              'download_url': 'https://example.com/third.zip',
              'package_kind': 'zip',
            }
          ],
        },
      ),
      flush: true,
    );

    final catalog = await service.fetchCatalog(catalogUrl: catalogPath);
    expect(catalog.entries.length, 2);
    expect(catalog.entries[0].id, 'entry-a');
    expect(catalog.entries[1].id, 'entry-c');
  });

  test('installFromSourceEntry rolls back on metadata mismatch', () async {
    final sourceDir = Directory('${tempDocsDir.path}/source')..createSync();
    final packagePath = '${sourceDir.path}/metadata-mismatch-plugin.zip';
    File(packagePath).writeAsBytesSync(mismatchPluginPackageBytes, flush: true);

    final entry = WasmPluginSourceCatalogEntry(
      id: 'metadata-mismatch',
      pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
      displayName: 'Expected Temperature Plugin',
      version: '0.1.0',
      downloadUrl: File(packagePath).uri.toString(),
      packageKind: 'zip',
      sha256Hex: sha256.convert(mismatchPluginPackageBytes).toString(),
    );

    await expectLater(
      () => service.installFromSourceEntry(entry),
      throwsA(isA<FormatException>()),
    );

    final installed = await registry.loadPlugins();
    expect(installed, isEmpty);
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
