import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/bingx_futures_market_snapshot_models.dart';
import 'package:hivra_app/models/bingx_futures_order_tracking_models.dart';
import 'package:hivra_app/models/external_effect_models.dart';
import 'package:hivra_app/services/bingx_futures_remote_runner_identity_service.dart';
import 'package:hivra_app/services/bingx_futures_remote_runner_provisioning_service.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

void main() {
  const capsuleHex =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const accountHash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('bootstrap cleanup selects only stale own regular transfers', () {
    final now = DateTime.utc(2026, 9, 25, 12);
    final old =
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
    final recent =
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    const transfer = '0123456789abcdef01234567';
    SftpName entry(
      String filename, {
      int userId = 0,
      required int modifiedAt,
      bool symlink = false,
    }) => SftpName(
      filename: filename,
      longname: filename,
      attr: SftpFileAttrs(
        userID: userId,
        modifyTime: modifiedAt,
        mode: SftpFileMode.value(symlink ? 0xa1ff : 0x81a4),
      ),
    );

    expect(
      DartSshBingxFuturesRemoteRunnerHostPort.staleTransferPaths(
        entries: [
          entry('hivra-runner-$capsuleHex-$transfer.tar.gz', modifiedAt: old),
          entry(
            'hivra-runner-bootstrap-$capsuleHex-$transfer.sh',
            modifiedAt: old,
          ),
          entry(
            'hivra-runner-$capsuleHex-aaaaaaaaaaaaaaaaaaaaaaaa.tar.gz',
            modifiedAt: recent,
          ),
          entry('hivra-runner-$accountHash-$transfer.tar.gz', modifiedAt: old),
          entry(
            'hivra-runner-$capsuleHex-bbbbbbbbbbbbbbbbbbbbbbbb.tar.gz',
            modifiedAt: old,
            symlink: true,
          ),
          entry(
            'hivra-runner-$capsuleHex-cccccccccccccccccccccccc.tar.gz',
            modifiedAt: old,
            userId: 1000,
          ),
          entry(
            'hivra-runner-$capsuleHex-not-a-transfer.tar.gz',
            modifiedAt: old,
          ),
        ],
        profileId: capsuleHex,
        nowUtc: now,
      ),
      [
        '/tmp/hivra-runner-$capsuleHex-$transfer.tar.gz',
        '/tmp/hivra-runner-bootstrap-$capsuleHex-$transfer.sh',
      ],
    );
    expect(
      () => DartSshBingxFuturesRemoteRunnerHostPort.staleTransferPaths(
        entries: const [],
        profileId: '../other',
        nowUtc: now,
      ),
      throwsFormatException,
    );
  });

  test('embedded bundle loader authenticates both executable assets', () async {
    final archive = Uint8List.fromList(utf8.encode('runner archive'));
    final control = Uint8List.fromList(utf8.encode('#!/bin/sh\nexit 0\n'));
    final assets = _MemoryAssetBundle(archive: archive, control: control);

    final bundle =
        await BingxFuturesEmbeddedRunnerBundleLoader(assets: assets).load();
    expect(bundle.archiveBytes, archive);
    expect(bundle.controlBytes, control);

    assets.control[0] ^= 1;
    await expectLater(
      BingxFuturesEmbeddedRunnerBundleLoader(assets: assets).load(),
      throwsFormatException,
    );
  });

  test('bundle upgrade normalizes failed or boot-enabled session first', () {
    final script = const DartSshBingxFuturesRemoteRunnerHostPort()
        .buildBootstrapScriptForTesting(
          profileId: 'a' * 64,
          sshPublicKeyLine: 'ssh-ed25519 AAAA test',
          controlBytes: Uint8List.fromList(utf8.encode('#!/bin/sh\n')),
        );

    final activeCheck = script.indexOf(
      'systemctl show -p ActiveState --value '
      'hivra-trading-deterministic-session.service',
    );
    final pause = script.indexOf('--pause-prepared-session-service');
    final upgrade = script.indexOf('--upgrade-disabled');
    final initialize = script.indexOf('--initialize-disabled', upgrade);
    final export = script.indexOf('--export-anchor', initialize);

    expect(activeCheck, greaterThanOrEqualTo(0));
    expect(pause, greaterThan(activeCheck));
    expect(upgrade, greaterThan(pause));
    expect(upgrade, greaterThanOrEqualTo(0));
    expect(initialize, greaterThan(upgrade));
    expect(export, greaterThan(initialize));
    expect(
      script,
      contains(
        'Remote Runner update requires the current session to be paused or finished',
      ),
    );
    expect(script, contains('failed)'));
    expect(
      script.indexOf('failed)'),
      lessThan(script.indexOf('--pause-prepared-session-service')),
    );
  });

  test(
    'bootstrap stores only scoped SSH identity after authenticated anchor',
    () async {
      final temp = await Directory.systemTemp.createTemp('hivra-runner-setup-');
      addTearDown(() => temp.delete(recursive: true));
      final files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
      );
      final secureStorage = _FakeSecureStorage();
      final vault = CapsuleScopedSecretVault(secureStorage: secureStorage);
      final host = _FakeHostPort();
      final identity = BingxFuturesRemoteRunnerIdentityService(
        readActiveCapsuleRootHex: () => capsuleHex,
        files: files,
      );
      final service = BingxFuturesRemoteRunnerProvisioningService(
        activeCapsuleRootHex: () => capsuleHex,
        identity: identity,
        profiles: BingxFuturesRemoteRunnerProfileStore(
          activeCapsuleRootHex: () => capsuleHex,
          files: files,
        ),
        secrets: vault,
        bundleLoader: BingxFuturesEmbeddedRunnerBundleLoader(
          assets: _MemoryAssetBundle(),
        ),
        host: host,
      );

      final profile = await service.bootstrap(
        host: 'runner.example',
        port: 22,
        rootUsername: 'root',
        rootPassword: 'one-time-password',
        accountBindingHashHex: accountHash,
        confirmHostKey: (_, _) async => true,
      );

      expect(profile.capsuleHex, capsuleHex);
      expect(profile.accountBindingHashHex, accountHash);
      expect(host.receivedPassword, 'one-time-password');
      expect(await service.loadProfiles(), hasLength(1));
      final secureWire = secureStorage.values.values.single;
      expect(secureWire, contains('OPENSSH'));
      expect(secureWire, isNot(contains('one-time-password')));
      expect(await identity.loadVerifiedBinding(), isNotNull);
      expect(host.statusCalls, 1);

      final exactReplay = await service.bootstrap(
        host: 'runner.example',
        port: 22,
        rootUsername: 'root',
        rootPassword: 'not-used-again',
        accountBindingHashHex: accountHash,
        confirmHostKey: (_, _) async => true,
      );
      expect(exactReplay.profileId, profile.profileId);
      expect(host.bootstrapCalls, 2);
      expect(host.statusCalls, 2);
      secureStorage.readKeys.clear();

      await expectLater(
        service.bootstrap(
          host: 'runner.example',
          port: 22,
          rootUsername: 'root',
          rootPassword: 'one-time-password',
          accountBindingHashHex: 'c' * 64,
          confirmHostKey: (_, _) async => true,
        ),
        throwsStateError,
      );
      expect(host.bootstrapCalls, 2);

      await expectLater(
        service.deploySession(
          profile: profile,
          accountBindingHashHex: 'c' * 64,
          canonicalSessionJson: '{}',
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        throwsStateError,
      );
      expect(host.deployCalls, 0);
      await expectLater(service.resume(profile), throwsStateError);
      expect(host.resumeCalls, 0);

      const sessionOperationId =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final canonicalSessionJson = jsonEncode(<String, dynamic>{
        'operation_id': sessionOperationId,
        'runner_key_id': profile.runnerKeyId,
        'strategy_policy': <String, dynamic>{
          'runner_build_id':
              BingxFuturesRemoteMandateAdmission.deterministicRunnerBuildId,
          'strategy_version': bingxLiquidityStrategyVersion,
        },
      });
      await expectLater(
        service.deploySession(
          profile: profile,
          accountBindingHashHex: accountHash,
          canonicalSessionJson: canonicalSessionJson,
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        throwsStateError,
      );
      expect(host.deployCalls, 0);
      final compatibleProfile = BingxFuturesRemoteRunnerProfile(
        profileId: profile.profileId,
        capsuleHex: profile.capsuleHex,
        accountBindingHashHex: profile.accountBindingHashHex,
        host: profile.host,
        port: profile.port,
        sshUsername: profile.sshUsername,
        hostKeyAlgorithm: profile.hostKeyAlgorithm,
        hostKeyFingerprint: profile.hostKeyFingerprint,
        runnerKeyId: profile.runnerKeyId,
        runnerBuildId:
            BingxFuturesRemoteMandateAdmission.deterministicRunnerBuildId,
        createdAtUtc: profile.createdAtUtc,
      );
      await service.deploySession(
        profile: compatibleProfile,
        accountBindingHashHex: accountHash,
        canonicalSessionJson: canonicalSessionJson,
        apiKey: 'key',
        apiSecret: 'secret',
      );
      expect(await service.loadActiveSession(profile), canonicalSessionJson);
      expect(await service.resume(profile), 'resumed');
      expect(host.resumeCalls, 1);
      expect(secureStorage.readKeys, isEmpty);

      final operation = _completedEffectOperation();
      final legacyWire = operation.toJson()..remove('approved_at_utc');
      host.completedEffectsRaw = jsonEncode(<dynamic>[legacyWire]);
      final restored = await service.completedSessionEffects(
        profile: profile,
        sessionOperationId: sessionOperationId,
      );
      expect(restored, hasLength(1));
      expect(restored.single.operationId, operation.operationId);
      expect(restored.single.approvedAtUtc, operation.updatedAtUtc);

      host.completedEffectsRaw = jsonEncode(<dynamic>[
        <String, dynamic>{...legacyWire, 'unexpected': true},
      ]);
      await expectLater(
        service.completedSessionEffects(
          profile: profile,
          sessionOperationId: sessionOperationId,
        ),
        throwsFormatException,
      );

      expect(
        await service.revokeSession(
          profile: profile,
          canonicalRevocationJson: '{"signed":"revocation"}',
        ),
        'revoked',
      );
      expect(host.revokeCalls, 1);
      expect(await service.loadActiveSession(profile), isNull);

      expect(await service.remove(profile), 'removed');
      expect(host.removeCalls, 1);
      expect(await service.loadProfiles(), isEmpty);
      expect(await identity.loadVerifiedBinding(), isNull);
      expect(secureStorage.values, isEmpty);
    },
  );

  test('interrupted bootstrap retains only the retry identity', () async {
    final temp = await Directory.systemTemp.createTemp('hivra-runner-reject-');
    addTearDown(() => temp.delete(recursive: true));
    final files = CapsuleFileStore(
      dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
    );
    final secureStorage = _FakeSecureStorage();
    final service = BingxFuturesRemoteRunnerProvisioningService(
      activeCapsuleRootHex: () => capsuleHex,
      identity: BingxFuturesRemoteRunnerIdentityService(
        readActiveCapsuleRootHex: () => capsuleHex,
        files: files,
      ),
      profiles: BingxFuturesRemoteRunnerProfileStore(
        activeCapsuleRootHex: () => capsuleHex,
        files: files,
      ),
      secrets: CapsuleScopedSecretVault(secureStorage: secureStorage),
      bundleLoader: BingxFuturesEmbeddedRunnerBundleLoader(
        assets: _MemoryAssetBundle(),
      ),
      host: _FakeHostPort(rejectWhenConfirmationFails: true),
    );

    await expectLater(
      service.bootstrap(
        host: 'runner.example',
        port: 22,
        rootUsername: 'root',
        rootPassword: 'one-time-password',
        accountBindingHashHex: accountHash,
        confirmHostKey: (_, _) async => false,
      ),
      throwsStateError,
    );
    expect(await service.loadProfiles(), isEmpty);
    expect(secureStorage.values, hasLength(1));
    expect(secureStorage.values.values.single, contains('OPENSSH'));
    expect(
      secureStorage.values.values.single,
      isNot(contains('one-time-password')),
    );
  });

  test(
    'bootstrap is not persisted until restricted control succeeds',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'hivra-runner-status-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final files = CapsuleFileStore(
        dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
      );
      final secureStorage = _FakeSecureStorage();
      final identity = BingxFuturesRemoteRunnerIdentityService(
        readActiveCapsuleRootHex: () => capsuleHex,
        files: files,
      );
      final service = BingxFuturesRemoteRunnerProvisioningService(
        activeCapsuleRootHex: () => capsuleHex,
        identity: identity,
        profiles: BingxFuturesRemoteRunnerProfileStore(
          activeCapsuleRootHex: () => capsuleHex,
          files: files,
        ),
        secrets: CapsuleScopedSecretVault(secureStorage: secureStorage),
        bundleLoader: BingxFuturesEmbeddedRunnerBundleLoader(
          assets: _MemoryAssetBundle(),
        ),
        host: _FakeHostPort(rejectStatus: true),
      );

      await expectLater(
        service.bootstrap(
          host: 'runner.example',
          port: 22,
          rootUsername: 'root',
          rootPassword: 'one-time-password',
          accountBindingHashHex: accountHash,
          confirmHostKey: (_, _) async => true,
        ),
        throwsStateError,
      );

      expect(await service.loadProfiles(), isEmpty);
      expect(await identity.loadVerifiedBinding(), isNull);
      expect(secureStorage.values.values.single, contains('OPENSSH'));
    },
  );
}

ExternalEffectOperation _completedEffectOperation() {
  const operationId =
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
  const providerId = 'bingx-futures';
  const updatedAtUtc = '2026-09-11T12:00:01.000Z';
  const canonicalPayloadJson = '{}';
  return ExternalEffectOperation(
    ownerCapsuleHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    operationId: operationId,
    pluginId: 'hivra.contract.bingx-futures-trading.v1',
    providerId: providerId,
    accountBindingId:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    effectKind: 'place-exact-order',
    canonicalPayloadJson: canonicalPayloadJson,
    payloadHashHex:
        sha256.convert(utf8.encode(canonicalPayloadJson)).toString(),
    state: ExternalEffectState.succeeded,
    approvalEvidenceHashHex:
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    approvedAtUtc: updatedAtUtc,
    attemptCount: 1,
    revision: 1,
    createdAtUtc: '2026-09-11T12:00:00.000Z',
    updatedAtUtc: updatedAtUtc,
    lastErrorCode: null,
    lastErrorMessage: null,
    providerReferenceId: 'provider-order-1',
    requiredAction: null,
    receipt: const ExternalEffectReceipt(
      operationId: operationId,
      providerId: providerId,
      providerReceiptId: 'provider-order-1',
      evidenceHashHex:
          '1111111111111111111111111111111111111111111111111111111111111111',
      receivedAtUtc: updatedAtUtc,
    ),
  )..validate();
}

class _MemoryAssetBundle extends CachingAssetBundle {
  Uint8List archive;
  Uint8List control;
  late final String _archiveHash;
  late final int _archiveSize;
  late final String _controlHash;
  late final int _controlSize;

  _MemoryAssetBundle({Uint8List? archive, Uint8List? control})
    : archive = archive ?? Uint8List.fromList(utf8.encode('runner archive')),
      control =
          control ?? Uint8List.fromList(utf8.encode('#!/bin/sh\nexit 0\n')) {
    _archiveHash = sha256.convert(this.archive).toString();
    _archiveSize = this.archive.length;
    _controlHash = sha256.convert(this.control).toString();
    _controlSize = this.control.length;
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes =
        key == 'assets/runner/runner-bundle-linux-x64.tar.gz'
            ? archive
            : key == 'assets/runner/runner-control'
            ? control
            : throw StateError('Unknown asset: $key');
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != 'assets/runner/runner-bundle-release.json') {
      throw StateError('Unknown asset: $key');
    }
    return jsonEncode(<String, dynamic>{
      'schema_version': 'hivra-embedded-runner-release-v1',
      'target': 'linux/x64',
      'archive_asset': 'assets/runner/runner-bundle-linux-x64.tar.gz',
      'archive_sha256': _archiveHash,
      'archive_size': _archiveSize,
      'control_asset': 'assets/runner/runner-control',
      'control_sha256': _controlHash,
      'control_size': _controlSize,
      'source_commit': 'd' * 40,
    });
  }
}

class _FakeHostPort implements BingxFuturesRemoteRunnerHostPort {
  final bool rejectWhenConfirmationFails;
  final bool rejectStatus;
  String? receivedPassword;
  int deployCalls = 0;
  int bootstrapCalls = 0;
  int removeCalls = 0;
  int resumeCalls = 0;
  int revokeCalls = 0;
  int statusCalls = 0;
  String completedEffectsRaw = '[]';

  @override
  Future<String> completedSessionEffects({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String sessionOperationId,
  }) async => completedEffectsRaw;

  _FakeHostPort({
    this.rejectWhenConfirmationFails = false,
    this.rejectStatus = false,
  });

  @override
  Future<BingxFuturesRemoteRunnerBootstrapResult> bootstrap({
    required String host,
    required int port,
    required String rootUsername,
    required String rootPassword,
    required String profileId,
    required String sshPublicKeyLine,
    required BingxFuturesEmbeddedRunnerBundle bundle,
    required ConfirmRemoteHostKey confirmHostKey,
  }) async {
    bootstrapCalls += 1;
    receivedPassword = rootPassword;
    final accepted = await confirmHostKey(
      'ssh-ed25519',
      'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    if (!accepted && rejectWhenConfirmationFails) {
      throw StateError('VPS host key was not accepted.');
    }
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/trading_shadow_evidence_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return BingxFuturesRemoteRunnerBootstrapResult(
      hostKeyAlgorithm: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      runnerPublicKeyText:
          '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8\n',
      runnerEvidenceBytes: Uint8List.fromList(
        utf8.encode(fixture['expected_wire_utf8'] as String),
      ),
    );
  }

  @override
  Future<String> deploySession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalSessionJson,
    required String apiKey,
    required String apiSecret,
  }) async {
    deployCalls += 1;
    return 'PASS prepare\nPASS activate\nHIVRA_REMOTE_RUNNER_APPLY_OK=1';
  }

  @override
  Future<String> pause({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) async => 'paused';

  @override
  Future<String> resume({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) async {
    resumeCalls += 1;
    return 'resumed';
  }

  @override
  Future<String> remove({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) async {
    removeCalls += 1;
    return 'removed';
  }

  @override
  Future<String> revokeSession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalRevocationJson,
  }) async {
    revokeCalls += 1;
    return 'revoked';
  }

  @override
  Future<String> status({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) async {
    statusCalls += 1;
    if (rejectStatus) {
      throw StateError('restricted control unavailable');
    }
    return 'running';
  }
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> readKeys = <String>[];

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
    readKeys.add(key);
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
    values.remove(key);
  }
}
