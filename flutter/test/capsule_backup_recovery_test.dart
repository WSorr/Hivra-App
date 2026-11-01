import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/ffi/hivra_bindings.dart';
import 'package:hivra_app/services/capsule_backup_codec.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_index_store.dart';
import 'package:hivra_app/services/capsule_persistence_service.dart';
import 'package:hivra_app/services/capsule_seed_store.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final Map<String, int> readCounts = <String, int>{};
  bool failDelete = false;
  bool failWrite = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrite) throw StateError('secure storage unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCounts[key] = (readCounts[key] ?? 0) + 1;
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDelete) throw Exception('secure storage delete unavailable');
    values.remove(key);
  }
}

class _Bindings implements HivraBindings {
  bool valid = true;
  int validations = 0;
  Uint8List? nostrKey;
  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() =>
      Uint8List.fromList(List.filled(32, 0xaa));
  @override
  Uint8List? capsuleRootPublicKey() => capsuleRuntimeOwnerPublicKey();
  @override
  bool setApplicationStorageRoot(String path) => true;
  @override
  String? exportLedger() => null;
  @override
  Uint8List? seedRootPublicKey(Uint8List seed) => seed;
  @override
  Uint8List? seedNostrPublicKey(Uint8List seed) => nostrKey ?? seed;
  @override
  bool validateBackupLedger(String json, Uint8List seed) {
    validations++;
    return valid;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final seed = Uint8List.fromList(List.filled(32, 0xaa));
  final owner = 'aa' * 32;
  const plugin = 'hivra.test.backup.v1';
  final ledger = jsonEncode({'owner': List.filled(32, 0xaa), 'events': []});
  late Directory stand;
  late UserVisibleDataDirectoryService srcDirs, dstDirs;
  late CapsuleFileStore src, dst;
  late _FakeSecureStorage srcSecure, dstSecure;
  late CapsulePersistenceService exporter, importer;
  late WasmPluginRegistryService srcPackages, dstPackages;
  late _Bindings bindings;
  CapsuleSeedStore seeds(
    UserVisibleDataDirectoryService d,
    FlutterSecureStorage s,
  ) => CapsuleSeedStore(dirs: d, secureStorage: s);
  CapsulePersistenceService persistence(
    UserVisibleDataDirectoryService d,
    FlutterSecureStorage s,
  ) => CapsulePersistenceService.forTesting(dirs: d, seedStore: seeds(d, s));
  Future<File> package(String version) async {
    final zip = Archive();
    final manifest = utf8.encode(
      jsonEncode({
        'schema': 'hivra.plugin.manifest',
        'version': 1,
        'release_version': version,
        'plugin_id': plugin,
        'contract': {'kind': 'transactional_demo'},
        'runtime': {
          'abi': 'hivra_host_abi_v2',
          'entry_export': 'hivra_evaluate_v1',
        },
        'capabilities': ['content.draft.prepare'],
      }),
    );
    zip.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    zip.addFile(ArchiveFile('module.wasm', 8, [0, 97, 115, 109, 1, 0, 0, 0]));
    return File('${stand.path}/package-$version.zip')
      ..writeAsBytesSync(ZipEncoder().encode(zip)!);
  }

  Future<String> backup({
    Map<String, String>? files,
    Map<String, String>? packages,
  }) => CapsuleBackupCodec.encodeEncryptedBackupEnvelope(
    ledgerJson: ledger,
    seed: seed,
    isGenesis: true,
    isNeste: false,
    files: files ?? {},
    packages: packages ?? {},
  );
  Future<String?> restore(String raw) =>
      importer.importCapsuleFromBackupJson(raw, seed: seed, hivra: bindings);
  setUp(() async {
    stand = await Directory.systemTemp.createTemp(
      'hivra-complete-backup-test-',
    );
    srcDirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: '${stand.path}/source',
      homeOverride: '${stand.path}/source-home',
    );
    dstDirs = UserVisibleDataDirectoryService(
      runtimeRootOverride: '${stand.path}/target',
      homeOverride: '${stand.path}/target-home',
    );
    src = CapsuleFileStore(dirs: srcDirs);
    dst = CapsuleFileStore(dirs: dstDirs);
    srcSecure = _FakeSecureStorage();
    dstSecure = _FakeSecureStorage();
    exporter = persistence(srcDirs, srcSecure);
    importer = persistence(dstDirs, dstSecure);
    srcPackages = WasmPluginRegistryService(dataDirs: srcDirs);
    dstPackages = WasmPluginRegistryService(dataDirs: dstDirs);
    bindings = _Bindings();
  });
  tearDown(() async => stand.delete(recursive: true));
  test('recovering a new Capsule never unlocks unrelated seeds', () async {
    final index = CapsuleIndexStore(dirs: dstDirs);
    for (final byte in [0xbb, 0xcc, 0xdd]) {
      final foreign = byte.toRadixString(16) * 32;
      await index.upsert(foreign, identityMode: 'root_owner');
      dstSecure.values['hivra.seed.$foreign'] = base64Encode(
        List.filled(32, byte),
      );
    }
    await importer.persistAfterCreate(
      hivra: bindings,
      seed: seed,
      isGenesis: false,
      isNeste: true,
    );
    expect(dstSecure.readCounts.keys, everyElement('hivra.seed.$owner'));
    final saved = await index.read();
    expect(saved.activePubKeyHex, owner);
    expect(saved.capsules.length, 4);
  });

  test(
    'recovery recognizes an existing public owner without reading its old seed',
    () async {
      final index = CapsuleIndexStore(dirs: dstDirs);
      await index.upsert(owner, identityMode: 'root_owner');
      await importer.persistAfterCreate(
        hivra: bindings,
        seed: seed,
        isGenesis: false,
        isNeste: true,
      );
      expect((await index.read()).capsules.keys, [owner]);
      expect(dstSecure.readCounts.keys, everyElement('hivra.seed.$owner'));
    },
  );
  test(
    'recovery reuses the matching legacy public owner without a seed scan',
    () async {
      final index = CapsuleIndexStore(dirs: dstDirs);
      final legacy = 'bb' * 32;
      bindings.nostrKey = Uint8List.fromList(List.filled(32, 0xbb));
      await index.upsert(legacy, identityMode: 'legacy_nostr_owner');
      await index.upsert('cc' * 32, identityMode: 'root_owner');
      await importer.persistAfterCreate(
        hivra: bindings,
        seed: seed,
        isGenesis: false,
        isNeste: true,
      );
      final saved = await index.read();
      expect(saved.activePubKeyHex, legacy);
      expect(saved.capsules.keys, unorderedEquals([legacy, 'cc' * 32]));
      expect(dstSecure.readCounts.keys, everyElement('hivra.seed.$legacy'));
    },
  );
  test(
    'full encrypted recovery retains Capsule, opaque package state and packages across restart/replacement',
    () async {
      final dir = await src.capsuleDirForHex(owner, create: true);
      await src.writeLedger(dir, ledger);
      await src.writeState(dir, {'isGenesis': true, 'isNeste': false});
      await seeds(srcDirs, srcSecure).storeSeed(owner, seed);
      srcSecure.values['provider-token'] = 'DO-NOT-EXPORT-PROVIDER-TOKEN';
      await File('${dir.path}/seed.json').writeAsString('DO-NOT-EXPORT-SEED');
      await File(
        '${dir.path}/credentials.json',
      ).writeAsString('DO-NOT-EXPORT-SSH-KEY');
      final foreign = await src.capsuleDirForHex('bb' * 32, create: true);
      await src.writePluginState(
        foreign,
        plugin,
        'workspace.v1.json',
        '{"foreign":true}',
      );
      const opaque =
          '{"replacement_payload":{"unfamiliar_shape":[7,{"hello":"world"}]}}';
      await src.writePluginState(dir, plugin, 'workspace.v1.json', opaque);
      await src.writePluginState(
        dir,
        plugin,
        'custom.snapshot',
        'opaque package format',
      );
      await src.writeChatTimeline(dir, 'already encrypted timeline');
      await src.writeContactLabels(dir, '{"peer":"Test peer"}');
      await srcPackages.installPluginFromFile(await package('1.0.0'));
      final path = '${stand.path}/export.json';
      await exporter.exportCapsuleBackupToPath(owner, path);
      final raw = await File(path).readAsString();
      expect(jsonDecode(raw)['version'], 3);
      for (final secret in ['DO-NOT-EXPORT', opaque, owner]) {
        expect(raw.contains(secret), false);
      }
      final opened = (await CapsuleBackupCodec.tryDecodeBackup(raw, seed))!;
      expect(
        opened.files!.keys,
        unorderedEquals([
          'plugin_state/$plugin/workspace.v1.json',
          'plugin_state/$plugin/custom.snapshot',
          CapsuleFileStore.chatTimelineFileName,
          CapsuleFileStore.contactLabelsFileName,
        ]),
      );
      expect(opened.packages!.keys, [plugin]);
      expect(await restore(raw), owner);
      final restarted = CapsuleFileStore(dirs: dstDirs);
      final restored = await restarted.capsuleDirForHex(owner);
      expect(await restarted.readLedger(restored), ledger);
      expect(
        await restarted.readPluginState(restored, plugin, 'workspace.v1.json'),
        opaque,
      );
      expect(
        await restarted.readPluginState(restored, plugin, 'custom.snapshot'),
        'opaque package format',
      );
      expect(
        await restarted.readChatTimeline(restored),
        'already encrypted timeline',
      );
      expect(
        await restarted.readContactLabels(restored),
        '{"peer":"Test peer"}',
      );
      expect((await restarted.readState(restored))!['isNeste'], false);
      expect(
        (await WasmPluginRegistryService(dataDirs: dstDirs).loadPlugins())
            .single
            .pluginVersion,
        '1.0.0',
      );
      expect(
        (await CapsuleIndexStore(dirs: dstDirs).read()).activePubKeyHex,
        owner,
      );
      expect(await seeds(dstDirs, dstSecure).loadSeed(owner), seed);
      expect(dstSecure.values.keys, ['hivra.seed.$owner']);
      await dstPackages.installPluginFromFile(await package('2.0.0'));
      expect(
        await restarted.readPluginState(restored, plugin, 'workspace.v1.json'),
        opaque,
      );
      expect((await dstPackages.loadPlugins()).single.pluginVersion, '2.0.0');
    },
  );
  test(
    'recovery expires host grant and preserves remote custody/effect evidence',
    () async {
      final grant = {
        'version': 1,
        'owner': owner,
        'plugin_id': plugin,
        'revision': 5,
        'allow_new_entries': true,
        'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 600000,
        'settings': <String, dynamic>{},
        'scope': {
          'account_id': 'e' * 64,
          'action': 'refresh',
          'interval_seconds': 60,
          'symbol': 'LDO-USDT',
          'max_margin': 10,
          'max_stop_percent': 10,
        },
        'package_id': 'old-package',
        'package_digest': 'c' * 64,
        'executor': 'vps',
        'executor_id': 'd' * 64,
      };
      final raw = await backup(
        files: {
          'plugin_state/$plugin/workspace-execution.v1.json': base64Encode(
            utf8.encode(jsonEncode(grant)),
          ),
          'plugin_state/$plugin/external_effects.v1.json': base64Encode(
            utf8.encode('{"receipt":"retained"}'),
          ),
        },
      );
      expect(await restore(raw), owner);
      final dir = await dst.capsuleDirForHex(owner);
      final control = jsonDecode(
        (await dst.readPluginState(
          dir,
          plugin,
          'workspace-execution.v1.json',
        ))!,
      );
      expect(control['expires_at_ms'], 0);
      expect(control['allow_new_entries'], false);
      expect(control['executor'], 'vps');
      expect(control['executor_id'], 'd' * 64);
      expect(
        await dst.readPluginState(dir, plugin, 'external_effects.v1.json'),
        '{"receipt":"retained"}',
      );
    },
  );
  for (final path in [
    '../escaped.json',
    'plugin_state/../escaped.json',
    'capsule_seeds.json',
    'credentials.json',
    '/tmp/escape',
    'plugin_state/x/../../escape',
  ]) {
    test(
      'authenticated backup rejects unsafe or credential path $path',
      () async {
        await expectLater(
          restore(
            await backup(
              files: {
                path: base64Encode([1, 2, 3]),
              },
            ),
          ),
          throwsFormatException,
        );
        expect(await seeds(dstDirs, dstSecure).hasStoredSeed(owner), false);
        expect(await dstPackages.loadPlugins(), isEmpty);
      },
    );
  }
  test(
    'wrong seed, tampered ciphertext and invalid Ledger never create Capsule',
    () async {
      final raw = await backup();
      expect(
        await importer.importCapsuleFromBackupJson(
          raw,
          seed: Uint8List(32),
          hivra: bindings,
        ),
        isNull,
      );
      final changed = jsonDecode(raw);
      final cipher = changed['cipher'];
      final bytes = base64Decode(cipher['ciphertext']);
      bytes[0] ^= 1;
      cipher['ciphertext'] = base64Encode(bytes);
      expect(await restore(jsonEncode(changed)), isNull);
      expect(bindings.validations, 0);
      bindings.valid = false;
      expect(await restore(raw), isNull);
      expect(await (await dst.capsuleDirForHex(owner)).exists(), false);
      expect(dstSecure.values, isEmpty);
    },
  );
  test('existing Capsule cannot be rolled back by stale backup', () async {
    final dir = await dst.capsuleDirForHex(owner, create: true);
    await dst.writeLedger(dir, 'current truth');
    await expectLater(restore(await backup()), throwsStateError);
    expect(await dst.readLedger(dir), 'current truth');
    expect(dstSecure.values, isEmpty);
  });
  test(
    'package conflict retains installed version and other Capsule',
    () async {
      await srcPackages.installPluginFromFile(await package('1.0.0'));
      await dstPackages.installPluginFromFile(await package('2.0.0'));
      final other = await dst.capsuleDirForHex('bb' * 32, create: true);
      await dst.writeLedger(other, 'unrelated Ledger');
      await expectLater(
        restore(await backup(packages: await srcPackages.snapshotForBackup())),
        throwsStateError,
      );
      expect((await dstPackages.loadPlugins()).single.pluginVersion, '2.0.0');
      expect(await dst.readLedger(other), 'unrelated Ledger');
      expect(await (await dst.capsuleDirForHex(owner)).exists(), false);
    },
  );
  test(
    'secure storage failure rolls back Capsule/packages/index/stage and allows retry',
    () async {
      await srcPackages.installPluginFromFile(await package('1.0.0'));
      final raw = await backup(packages: await srcPackages.snapshotForBackup());
      dstSecure.failWrite = true;
      await expectLater(restore(raw), throwsStateError);
      expect(await dstPackages.loadPlugins(), isEmpty);
      expect(await (await dst.capsuleDirForHex(owner)).exists(), false);
      expect((await CapsuleIndexStore(dirs: dstDirs).read()).capsules, isEmpty);
      expect(
        await Directory(
          '${stand.path}/target',
        ).list().where((e) => e.path.contains('.backup-import-')).isEmpty,
        true,
      );
      dstSecure.failWrite = false;
      expect(await restore(raw), owner);
    },
  );
  test(
    'symlinked package state fails instead of omission or traversal',
    () async {
      final dir = await src.capsuleDirForHex(owner, create: true);
      await Directory('${dir.path}/plugin_state').create();
      final outside = Directory('${stand.path}/outside')..createSync();
      await Link('${dir.path}/plugin_state/$plugin').create(outside.path);
      await expectLater(src.snapshotForBackup(dir), throwsStateError);
    },
  );
  test(
    'restart retries one interrupted staged import without stale data',
    () async {
      final root = await dstDirs.rootDirectory(create: true);
      final stage = Directory('${root.path}/.backup-import-$owner');
      await stage.create();
      await File('${stage.path}/partial').writeAsString('unfinished');
      await seeds(dstDirs, dstSecure).storeSeed(owner, seed);
      importer = persistence(dstDirs, dstSecure);
      expect(await restore(await backup()), owner);
      expect(await stage.exists(), false);
      final recovered = await dst.capsuleDirForHex(owner);
      expect(await File('${recovered.path}/partial').exists(), false);
      expect(await dst.readLedger(recovered), ledger);
    },
  );
  test(
    'empty runtime may restore with its existing matching platform seed',
    () async {
      await seeds(dstDirs, dstSecure).storeSeed(owner, seed);
      final before = Map<String, String>.from(dstSecure.values);
      expect(await restore(await backup()), owner);
      expect(dstSecure.values, before);
      expect(await (await dst.capsuleDirForHex(owner)).exists(), true);
    },
  );

  test('failed recovery never removes a preexisting platform seed', () async {
    await seeds(dstDirs, dstSecure).storeSeed(owner, seed);
    final before = Map<String, String>.from(dstSecure.values);
    await srcPackages.installPluginFromFile(await package('1.0.0'));
    await dstPackages.installPluginFromFile(await package('2.0.0'));
    await expectLater(
      restore(await backup(packages: await srcPackages.snapshotForBackup())),
      throwsStateError,
    );
    expect(dstSecure.values, before);
    expect(await (await dst.capsuleDirForHex(owner)).exists(), false);
  });
}
