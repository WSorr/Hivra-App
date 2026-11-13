import 'dart:async';
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
  Uint8List? rootOwner;
  Uint8List owner = Uint8List.fromList(List.filled(32, 0xaa));
  String? ledger;
  String? projection;
  @override
  Uint8List? capsuleRuntimeOwnerPublicKey() => Uint8List.fromList(owner);
  @override
  Uint8List? capsuleRootPublicKey() =>
      rootOwner ?? capsuleRuntimeOwnerPublicKey();
  @override
  Uint8List? capsuleNostrPublicKey() => nostrKey;
  @override
  bool setApplicationStorageRoot(String path) => true;
  @override
  String? exportLedger() => ledger;
  @override
  String? exportCapsuleStateJson() => projection;
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

class _DelayedSnapshotStore extends CapsuleFileStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  final laterWriteCompleted = Completer<void>();

  _DelayedSnapshotStore({required super.dirs});

  @override
  Future<void> writeLedgerSnapshot(
    Directory dir, {
    required String ledgerJson,
    required String backupJson,
    String? coreProjectionJson,
  }) async {
    final first = !entered.isCompleted;
    if (first) {
      entered.complete();
      await release.future;
    }
    await super.writeLedgerSnapshot(
      dir,
      ledgerJson: ledgerJson,
      backupJson: backupJson,
      coreProjectionJson: coreProjectionJson,
    );
    if (!first && !laterWriteCompleted.isCompleted) {
      laterWriteCompleted.complete();
    }
  }
}

class _SwitchingSnapshotStore extends CapsuleFileStore {
  void Function()? switchOwner;

  _SwitchingSnapshotStore({required super.dirs, required this.switchOwner});

  @override
  Future<Directory> docsDirectory() async {
    final directory = await super.docsDirectory();
    final change = switchOwner;
    switchOwner = null;
    change?.call();
    return directory;
  }
}

class _FailingSnapshotBackupStore extends CapsuleFileStore {
  bool failBackup = true;

  _FailingSnapshotBackupStore({required super.dirs});

  @override
  Future<void> writeBackup(Directory dir, String backupJson) {
    if (failBackup) {
      failBackup = false;
      throw const FileSystemException('simulated snapshot backup failure');
    }
    return super.writeBackup(dir, backupJson);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final seed = Uint8List.fromList(List.filled(32, 0xaa));
  final owner = 'aa' * 32;
  const plugin = 'hivra.test.backup.v1';
  final ledger = jsonEncode({'owner': List.filled(32, 0xaa), 'events': []});
  String snapshot(int count, {int ownerByte = 0xaa, String? hash}) =>
      jsonEncode({
        'owner': List.filled(32, ownerByte),
        'events': List.generate(count, (i) => {'sequence': i}),
        'last_hash': hash ?? '$count',
      });
  String projection(int count) =>
      jsonEncode({'version': count, 'ledger_hash': '$count', 'slots': []});
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

  // Existing full-state v3 archive compatibility, not the new export writer.
  Future<Map<String, String>> legacyPackages() async => {
    plugin: base64Encode(await (await package('1.0.0')).readAsBytes()),
  };

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
  test(
    'foreground snapshot retains its exported owner across Capsule switch',
    () async {
      final otherOwner = 'bb' * 32;
      final first = await dst.capsuleDirForHex(owner, create: true);
      final second = await dst.capsuleDirForHex(otherOwner, create: true);
      await dst.writeLedger(first, snapshot(1));
      await dst.writeLedger(second, snapshot(2, ownerByte: 0xbb));
      await dst.writeState(first, {'isGenesis': true, 'isNeste': false});
      await dst.writeState(second, {'isGenesis': false, 'isNeste': true});
      final index = CapsuleIndexStore(dirs: dstDirs);
      await index.upsert(owner, isGenesis: true, isNeste: false);
      await index.upsert(otherOwner, isGenesis: false, isNeste: true);
      await index.setActive(otherOwner);
      bindings.ledger = snapshot(3);
      bindings.projection = projection(3);
      final switching = _SwitchingSnapshotStore(
        dirs: dstDirs,
        switchOwner: () {
          bindings.owner = Uint8List.fromList(List.filled(32, 0xbb));
          bindings.ledger = snapshot(2, ownerByte: 0xbb);
          bindings.projection = projection(2);
        },
      );
      final persistence = CapsulePersistenceService.forTesting(
        dirs: dstDirs,
        seedStore: seeds(dstDirs, dstSecure),
        fileStore: switching,
      );

      expect(await persistence.persistLedgerSnapshot(bindings), isTrue);

      final reopened = CapsuleFileStore(dirs: dstDirs);
      expect(await reopened.readLedger(second), snapshot(2, ownerByte: 0xbb));
      expect(await reopened.readLedger(first), snapshot(3));
      expect(
        (await reopened.readState(first))!['coreProjection'],
        jsonDecode(projection(3)),
      );
      final savedIndex = await index.read();
      expect(savedIndex.activePubKeyHex, otherOwner);
      expect(savedIndex.capsules[owner]!.isGenesis, isTrue);
      expect(savedIndex.capsules[owner]!.isNeste, isFalse);
      expect(savedIndex.capsules[otherOwner]!.isGenesis, isFalse);
    },
  );
  for (final foregroundFirst in [false, true]) {
    test(
      'delayed ${foregroundFirst ? 'foreground' : 'worker'} snapshot cannot replace newer durable history',
      () async {
        final directory = await dst.capsuleDirForHex(owner, create: true);
        await dst.writeLedgerSnapshot(
          directory,
          ledgerJson: snapshot(1),
          backupJson: CapsuleBackupCodec.encodeBackupEnvelope(
            ledgerJson: snapshot(1),
            isGenesis: false,
            isNeste: true,
          ),
          coreProjectionJson: projection(1),
        );
        final delayed = _DelayedSnapshotStore(dirs: dstDirs);
        addTearDown(() {
          if (!delayed.release.isCompleted) delayed.release.complete();
        });
        final persistence = CapsulePersistenceService.forTesting(
          dirs: dstDirs,
          seedStore: seeds(dstDirs, dstSecure),
          fileStore: delayed,
        );
        final anotherInstance = CapsulePersistenceService.forTesting(
          dirs: dstDirs,
          seedStore: seeds(dstDirs, dstSecure),
          fileStore: delayed,
        );
        bindings.ledger = snapshot(foregroundFirst ? 2 : 3);
        bindings.projection = projection(foregroundFirst ? 2 : 3);
        final older =
            foregroundFirst
                ? persistence.persistLedgerSnapshot(bindings)
                : persistence.persistLedgerSnapshotForCapsuleHex(
                  owner,
                  snapshot(2),
                  capsuleStateJson: projection(2),
                );
        await delayed.entered.future;
        final newer =
            foregroundFirst
                ? anotherInstance.persistLedgerSnapshotForCapsuleHex(
                  owner,
                  snapshot(3),
                  capsuleStateJson: projection(3),
                )
                : anotherInstance.persistLedgerSnapshot(bindings);
        // Give an uncoordinated writer a chance to commit while the first
        // storage operation is held. A serialized writer remains queued; the
        // timer only releases the test fault and is not a timing assertion.
        await Future.any([
          delayed.laterWriteCompleted.future,
          Future<void>.delayed(const Duration(seconds: 1)),
        ]);
        delayed.release.complete();
        expect(await Future.wait([older, newer]), [true, true]);

        final reopened = CapsuleFileStore(dirs: dstDirs);
        expect(await reopened.readLedger(directory), snapshot(3));
        expect(
          CapsuleBackupCodec.tryExtractLedgerJson(
            (await reopened.readBackup(directory))!,
          ),
          snapshot(3),
        );
        expect(
          (await reopened.readState(directory))!['coreProjection'],
          jsonDecode(projection(3)),
        );
      },
    );
  }
  test(
    'failed snapshot backup retains latest Ledger and allows retry',
    () async {
      final directory = await dst.capsuleDirForHex(owner, create: true);
      await dst.writeLedgerSnapshot(
        directory,
        ledgerJson: snapshot(1),
        backupJson: CapsuleBackupCodec.encodeBackupEnvelope(
          ledgerJson: snapshot(1),
          isGenesis: false,
          isNeste: true,
        ),
        coreProjectionJson: projection(1),
      );
      final persistence = CapsulePersistenceService.forTesting(
        dirs: dstDirs,
        seedStore: seeds(dstDirs, dstSecure),
        fileStore: _FailingSnapshotBackupStore(dirs: dstDirs),
      );
      await expectLater(
        persistence.persistLedgerSnapshotForCapsuleHex(owner, snapshot(3)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await dst.readLedger(directory), snapshot(3));
      final oldBackup = await dst.readBackup(directory);
      expect(CapsuleBackupCodec.tryExtractLedgerJson(oldBackup!), snapshot(1));
      expect(
        await persistence.persistLedgerSnapshotForCapsuleHex(
          owner,
          snapshot(2),
        ),
        isFalse,
      );
      expect(await dst.readLedger(directory), snapshot(3));
      expect(await dst.readBackup(directory), oldBackup);
      expect(
        await persistence.persistLedgerSnapshotForCapsuleHex(
          owner,
          snapshot(3),
          capsuleStateJson: projection(3),
        ),
        isTrue,
      );
      expect(
        CapsuleBackupCodec.tryExtractLedgerJson(
          (await dst.readBackup(directory))!,
        ),
        snapshot(3),
      );
      expect(
        await persistence.persistLedgerSnapshotForCapsuleHex(
          owner,
          snapshot(4),
          capsuleStateJson: projection(4),
        ),
        isTrue,
      );
      final reopened = CapsuleFileStore(dirs: dstDirs);
      expect(await reopened.readLedger(directory), snapshot(4));
      expect(
        CapsuleBackupCodec.tryExtractLedgerJson(
          (await reopened.readBackup(directory))!,
        ),
        snapshot(4),
      );
      expect(
        (await reopened.readState(directory))!['coreProjection'],
        jsonDecode(projection(4)),
      );
    },
  );
  test(
    'snapshot comparison retains newer and conflicting equal history',
    () async {
      expect(
        await importer.persistLedgerSnapshotForCapsuleHex(owner, snapshot(3)),
        isTrue,
      );
      final directory = await dst.capsuleDirForHex(owner);
      final savedBackup = await dst.readBackup(directory);
      for (final incoming in [snapshot(2), snapshot(3, hash: 'fork')]) {
        expect(
          await importer.persistLedgerSnapshotForCapsuleHex(owner, incoming),
          isFalse,
        );
        expect(await dst.readLedger(directory), snapshot(3));
        expect(await dst.readBackup(directory), savedBackup);
      }
      expect(
        await importer.persistLedgerSnapshotForCapsuleHex(owner, snapshot(3)),
        isTrue,
      );
      expect(await dst.readLedger(directory), snapshot(3));
    },
  );
  test(
    'foreground snapshot without an exported owner cannot replace history',
    () async {
      final directory = await dst.capsuleDirForHex(owner, create: true);
      await dst.writeLedger(directory, snapshot(3));
      bindings.ledger = '{broken export';
      await expectLater(
        importer.persistLedgerSnapshot(bindings),
        throwsFormatException,
      );
      expect(await dst.readLedger(directory), snapshot(3));
      for (final incoming in ['{}', '[]']) {
        bindings.ledger = incoming;
        expect(await importer.persistLedgerSnapshot(bindings), isFalse);
        expect(await dst.readLedger(directory), snapshot(3));
      }
    },
  );
  test(
    'foreground snapshot retains legacy identity metadata at its origin',
    () async {
      final directory = await dst.capsuleDirForHex(owner, create: true);
      await dst.writeLedger(directory, snapshot(1));
      final index = CapsuleIndexStore(dirs: dstDirs);
      await index.upsert(owner, identityMode: 'mixed_or_unknown');
      bindings.rootOwner = Uint8List.fromList(List.filled(32, 0xbb));
      bindings.nostrKey = Uint8List.fromList(List.filled(32, 0xaa));
      bindings.ledger = snapshot(2);
      bindings.projection = projection(2);

      expect(await importer.persistLedgerSnapshot(bindings), isTrue);

      expect(await dst.readLedger(directory), snapshot(2));
      expect(
        (await index.read()).capsules[owner]!.identityMode,
        'legacy_nostr_owner',
      );
    },
  );
  test(
    'app size and package lifecycle cannot enlarge or block Core backup',
    () async {
      final dir = await src.capsuleDirForHex(owner, create: true);
      await src.writeLedger(dir, ledger);
      await src.writeState(dir, {'isGenesis': true, 'isNeste': false});
      await seeds(srcDirs, srcSecure).storeSeed(owner, seed);
      const proof = '{"version":1,"attestations":[]}';
      await src.writePairConsensusAttestations(dir, proof);
      final baseline = '${stand.path}/baseline.json';
      await exporter.exportCapsuleBackupToPath(owner, baseline);

      // Sparse files exceed even the former archive bounds. They are never read.
      final chat = src.chatTimelineFile(dir);
      final handle = await chat.open(mode: FileMode.write);
      await handle.truncate(256 * 1024 * 1024);
      await handle.close();
      await src.writePluginState(
        dir,
        plugin,
        'workspace.v1.json',
        'private drone state',
      );
      await src.writeDeliveryOutbox(dir, 'unresolved local delivery');
      await src.writeContactLabels(dir, '{"peer":"local label"}');
      final installed = await srcPackages.installPluginFromFile(
        await package('1.0.0'),
      );
      await expectLater(
        srcPackages.removePlugin(
          installed.id,
          cleanup: () async {
            throw StateError('removal is still draining');
          },
        ),
        throwsStateError,
      );
      final path = '${stand.path}/core.json';
      await exporter.exportCapsuleBackupToPath(owner, path);
      final raw = await File(path).readAsString();
      expect(raw.length, lessThan(4096));
      final opened = (await CapsuleBackupCodec.tryDecodeBackup(raw, seed))!;
      final before =
          (await CapsuleBackupCodec.tryDecodeBackup(
            await File(baseline).readAsString(),
            seed,
          ))!;
      // Export timestamps may vary in fractional precision; Core contents and
      // the size budget, rather than ciphertext length equality, are invariant.
      expect(jsonDecode(opened.ledgerJson), jsonDecode(before.ledgerJson));
      expect(
        [opened.isGenesis, opened.isNeste],
        [before.isGenesis, before.isNeste],
      );
      expect(opened.files, isEmpty);
      expect(opened.packages, isEmpty);
      expect(await chat.length(), 256 * 1024 * 1024);
      expect(
        await src.readPluginState(dir, plugin, 'workspace.v1.json'),
        'private drone state',
      );
      expect(await src.readDeliveryOutbox(dir), 'unresolved local delivery');

      // The active-Capsule and selector export entry points share this boundary.
      bindings.ledger = ledger;
      final activePath = '${stand.path}/active.json';
      await exporter.exportBackupEnvelopeToPath(bindings, activePath, seed);
      final active =
          (await CapsuleBackupCodec.tryDecodeBackup(
            await File(activePath).readAsString(),
            seed,
          ))!;
      expect(active.files, opened.files);
      expect(active.packages, isEmpty);

      expect(await restore(raw), owner);
      final restarted = CapsuleFileStore(dirs: dstDirs);
      final restored = await restarted.capsuleDirForHex(owner);
      expect(await restarted.readLedger(restored), ledger);
      expect(await restarted.readPairConsensusAttestations(restored), isNull);
      expect(await src.readPairConsensusAttestations(dir), proof);
      expect((await restarted.readState(restored))!['isNeste'], false);
      expect(await restarted.readChatTimeline(restored), isNull);
      expect(await restarted.readDeliveryOutbox(restored), isNull);
      expect(
        await restarted.readPluginState(restored, plugin, 'workspace.v1.json'),
        isNull,
      );
      expect(await dstPackages.loadPlugins(), isEmpty);
      expect(await seeds(dstDirs, dstSecure).loadSeed(owner), seed);
      expect(
        (await CapsuleIndexStore(dirs: dstDirs).read()).activePubKeyHex,
        owner,
      );
    },
  );

  test('Core recovery is independent of a broken package registry', () async {
    final plugins = await dstPackages.pluginsDirectory();
    await plugins.create(recursive: true);
    final registry = File('${plugins.path}/registry.json');
    await registry.writeAsString('{broken application registry');
    expect(await restore(await backup()), owner);
    expect(await dst.readLedger(await dst.capsuleDirForHex(owner)), ledger);
    expect(await registry.readAsString(), '{broken application registry');
  });

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
  test('corrupt contact cards do not block Core activation', () async {
    final index = CapsuleIndexStore(dirs: dstDirs);
    await index.upsert(owner, identityMode: 'root_owner');
    bindings.nostrKey = Uint8List.fromList(List.filled(32, 0xbb));
    final cards = File(
      '${(await dstDirs.rootDirectory(create: true)).path}/capsule_contact_cards.json',
    );
    await cards.writeAsString('{broken contact book');
    await importer.persistAfterCreate(
      hivra: bindings,
      seed: seed,
      isGenesis: false,
      isNeste: true,
    );
    expect((await index.read()).activePubKeyHex, owner);
    expect(await cards.readAsString(), '{broken contact book');
  });
  test(
    'read-only legacy v3 recovery retains archived app state and packages',
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
      final raw = await backup(
        files: {
          'plugin_state/$plugin/workspace.v1.json': base64Encode(
            utf8.encode(opaque),
          ),
          'plugin_state/$plugin/custom.snapshot': base64Encode(
            utf8.encode('opaque package format'),
          ),
          CapsuleFileStore.chatTimelineFileName: base64Encode(
            utf8.encode('already encrypted timeline'),
          ),
          CapsuleFileStore.contactLabelsFileName: base64Encode(
            utf8.encode('{"peer":"Test peer"}'),
          ),
        },
        packages: await legacyPackages(),
      );
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

  for (final format in ['v2', 'v1', 'raw']) {
    Future<String> oldBackup() async => switch (format) {
      'v2' => File('test/fixtures/capsule_backup_v2.json').readAsString(),
      'v1' => Future.value(
        CapsuleBackupCodec.encodeBackupEnvelope(
          ledgerJson: ledger,
          isGenesis: true,
          isNeste: false,
        ),
      ),
      _ => Future.value(ledger),
    };
    final oldSeed =
        format == 'v2' ? Uint8List.fromList(List.filled(32, 7)) : seed;
    final oldOwner = format == 'v2' ? '07' * 32 : owner;
    Future<String?> restoreOld(String raw) => importer
        .importCapsuleFromBackupJson(raw, seed: oldSeed, hivra: bindings);

    test(
      '$format recovery needs seed and native validation before writing',
      () async {
        final raw = await oldBackup();
        expect(
          await importer.importCapsuleFromBackupJson(raw, hivra: bindings),
          isNull,
        );
        expect(
          await importer.importCapsuleFromBackupJson(raw, seed: oldSeed),
          isNull,
        );
        expect(await (await dst.capsuleDirForHex(oldOwner)).exists(), false);
        expect(dstSecure.values, isEmpty);
      },
    );

    test('$format recovery never overwrites existing Capsule data', () async {
      final dir = await dst.capsuleDirForHex(oldOwner, create: true);
      await dst.writeLedger(dir, 'current truth');
      await dst.writeChatTimeline(dir, 'retained local messages');
      await expectLater(restoreOld(await oldBackup()), throwsStateError);
      expect(await dst.readLedger(dir), 'current truth');
      expect(await dst.readChatTimeline(dir), 'retained local messages');
      expect(dstSecure.values, isEmpty);
    });

    test(
      '$format recovery validates Ledger before publishing anything',
      () async {
        bindings.valid = false;
        expect(await restoreOld(await oldBackup()), isNull);
        expect(bindings.validations, 1);
        expect(await (await dst.capsuleDirForHex(oldOwner)).exists(), false);
        expect(
          (await CapsuleIndexStore(dirs: dstDirs).read()).capsules,
          isEmpty,
        );
        expect(dstSecure.values, isEmpty);
      },
    );

    test(
      '$format failed recovery rolls back and retries through the same owner',
      () async {
        final raw = await oldBackup();
        dstSecure.failWrite = true;
        await expectLater(restoreOld(raw), throwsStateError);
        expect(await (await dst.capsuleDirForHex(oldOwner)).exists(), false);
        expect(
          (await CapsuleIndexStore(dirs: dstDirs).read()).capsules,
          isEmpty,
        );
        expect(dstSecure.values, isEmpty);
        dstSecure.failWrite = false;
        expect(await restoreOld(raw), oldOwner);
        final reopened = CapsuleFileStore(dirs: dstDirs);
        final dir = await reopened.capsuleDirForHex(oldOwner);
        expect(
          await reopened.readLedger(dir),
          (await CapsuleBackupCodec.tryDecodeBackup(raw, oldSeed))!.ledgerJson,
        );
        expect(await reopened.readChatTimeline(dir), isNull);
        expect(await seeds(dstDirs, dstSecure).loadSeed(oldOwner), oldSeed);
      },
    );
  }
  test(
    'package conflict retains installed version and other Capsule',
    () async {
      await srcPackages.installPluginFromFile(await package('1.0.0'));
      await dstPackages.installPluginFromFile(await package('2.0.0'));
      final other = await dst.capsuleDirForHex('bb' * 32, create: true);
      await dst.writeLedger(other, 'unrelated Ledger');
      await expectLater(
        restore(await backup(packages: await legacyPackages())),
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
      final raw = await backup(packages: await legacyPackages());
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
    'Core export does not traverse operational relationship evidence',
    () async {
      final dir = await src.capsuleDirForHex(owner, create: true);
      await src.writeLedger(dir, ledger);
      await seeds(srcDirs, srcSecure).storeSeed(owner, seed);
      final outside = File('${stand.path}/outside-proof')
        ..writeAsStringSync('unrelated evidence');
      final link = Link(src.pairConsensusAttestationsFile(dir).path);
      await link.create(outside.path);
      final path = '${stand.path}/core-without-evidence.json';
      await exporter.exportCapsuleBackupToPath(owner, path);
      final opened =
          (await CapsuleBackupCodec.tryDecodeBackup(
            await File(path).readAsString(),
            seed,
          ))!;
      expect(opened.files, isEmpty);
      expect(opened.packages, isEmpty);
      expect(await link.target(), outside.path);
      expect(await outside.readAsString(), 'unrelated evidence');
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
      restore(await backup(packages: await legacyPackages())),
      throwsStateError,
    );
    expect(dstSecure.values, before);
    expect(await (await dst.capsuleDirForHex(owner)).exists(), false);
  });
}
