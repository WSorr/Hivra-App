import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import '../models/external_effect_models.dart';
import '../models/plugin_contract_ids.dart';
import 'bingx_futures_remote_runner_identity_service.dart';
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';

typedef ConfirmRemoteHostKey =
    Future<bool> Function(String algorithm, String fingerprint);

class BingxFuturesRemoteRunnerProfile {
  static const String contractVersion = 'hivra-remote-runner-profile-v1';

  final String profileId;
  final String capsuleHex;
  final String accountBindingHashHex;
  final String host;
  final int port;
  final String sshUsername;
  final String hostKeyAlgorithm;
  final String hostKeyFingerprint;
  final String runnerKeyId;
  final String runnerBuildId;
  final DateTime createdAtUtc;

  const BingxFuturesRemoteRunnerProfile({
    required this.profileId,
    required this.capsuleHex,
    required this.accountBindingHashHex,
    required this.host,
    required this.port,
    required this.sshUsername,
    required this.hostKeyAlgorithm,
    required this.hostKeyFingerprint,
    required this.runnerKeyId,
    required this.runnerBuildId,
    required this.createdAtUtc,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contract_version': contractVersion,
    'profile_id': profileId,
    'capsule_hex': capsuleHex,
    'account_binding_hash_hex': accountBindingHashHex,
    'host': host,
    'port': port,
    'ssh_username': sshUsername,
    'host_key_algorithm': hostKeyAlgorithm,
    'host_key_fingerprint': hostKeyFingerprint,
    'runner_key_id': runnerKeyId,
    'runner_build_id': runnerBuildId,
    'created_at_utc': createdAtUtc.toIso8601String(),
  };

  static BingxFuturesRemoteRunnerProfile? parse(Object? value) {
    try {
      if (value is! Map<String, dynamic> ||
          value.length != 12 ||
          value['contract_version'] != contractVersion) {
        return null;
      }
      final profile = BingxFuturesRemoteRunnerProfile(
        profileId: value['profile_id'] as String,
        capsuleHex: value['capsule_hex'] as String,
        accountBindingHashHex: value['account_binding_hash_hex'] as String,
        host: value['host'] as String,
        port: value['port'] as int,
        sshUsername: value['ssh_username'] as String,
        hostKeyAlgorithm: value['host_key_algorithm'] as String,
        hostKeyFingerprint: value['host_key_fingerprint'] as String,
        runnerKeyId: value['runner_key_id'] as String,
        runnerBuildId: value['runner_build_id'] as String,
        createdAtUtc: DateTime.parse(value['created_at_utc'] as String).toUtc(),
      );
      profile.validate();
      if (jsonEncode(profile.toJson()) != jsonEncode(value)) return null;
      return profile;
    } on Object {
      return null;
    }
  }

  void validate() {
    final hex64 = RegExp(r'^[0-9a-f]{64}$');
    if (!hex64.hasMatch(profileId) ||
        !hex64.hasMatch(capsuleHex) ||
        !hex64.hasMatch(accountBindingHashHex) ||
        !hex64.hasMatch(runnerKeyId) ||
        host.isEmpty ||
        host.length > 253 ||
        host.contains(RegExp(r'[\s/\\]')) ||
        port < 1 ||
        port > 65535 ||
        sshUsername != 'hivra-runner' ||
        !RegExp(r'^[a-z0-9][a-z0-9@._+-]{0,63}$').hasMatch(hostKeyAlgorithm) ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(hostKeyFingerprint) ||
        runnerBuildId.isEmpty ||
        runnerBuildId.length > 128 ||
        !createdAtUtc.isUtc) {
      throw const FormatException('Remote Runner profile is invalid.');
    }
  }
}

class BingxFuturesEmbeddedRunnerBundle {
  final Uint8List archiveBytes;
  final String archiveSha256;
  final Uint8List controlBytes;
  final String sourceCommit;

  const BingxFuturesEmbeddedRunnerBundle({
    required this.archiveBytes,
    required this.archiveSha256,
    required this.controlBytes,
    required this.sourceCommit,
  });
}

class BingxFuturesEmbeddedRunnerBundleLoader {
  static const String _manifestAsset =
      'assets/runner/runner-bundle-release.json';
  static const int _maximumArchiveBytes = 32 * 1024 * 1024;

  final AssetBundle _assets;

  BingxFuturesEmbeddedRunnerBundleLoader({AssetBundle? assets})
    : _assets = assets ?? rootBundle;

  Future<BingxFuturesEmbeddedRunnerBundle> load() async {
    final manifestText = await _assets.loadString(_manifestAsset);
    final decoded = jsonDecode(manifestText);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 9 ||
        decoded['schema_version'] != 'hivra-embedded-runner-release-v1' ||
        decoded['target'] != 'linux/x64' ||
        decoded['archive_asset'] !=
            'assets/runner/runner-bundle-linux-x64.tar.gz') {
      throw const FormatException('Embedded Runner manifest is invalid.');
    }
    final expectedHash = decoded['archive_sha256']?.toString() ?? '';
    final expectedSize = decoded['archive_size'];
    final controlAsset = decoded['control_asset']?.toString() ?? '';
    final controlHash = decoded['control_sha256']?.toString() ?? '';
    final controlSize = decoded['control_size'];
    final sourceCommit = decoded['source_commit']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash) ||
        expectedSize is! int ||
        expectedSize < 1 ||
        expectedSize > _maximumArchiveBytes ||
        controlAsset != 'assets/runner/runner-control' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(controlHash) ||
        controlSize is! int ||
        controlSize < 1 ||
        controlSize > 32 * 1024 ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceCommit)) {
      throw const FormatException('Embedded Runner manifest is invalid.');
    }
    final data = await _assets.load(decoded['archive_asset'] as String);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != expectedSize ||
        sha256.convert(bytes).toString() != expectedHash) {
      throw const FormatException('Embedded Runner bundle checksum mismatch.');
    }
    final controlData = await _assets.load(controlAsset);
    final controlBytes = controlData.buffer.asUint8List(
      controlData.offsetInBytes,
      controlData.lengthInBytes,
    );
    if (controlBytes.length != controlSize ||
        sha256.convert(controlBytes).toString() != controlHash) {
      throw const FormatException(
        'Embedded Runner controller checksum mismatch.',
      );
    }
    return BingxFuturesEmbeddedRunnerBundle(
      archiveBytes: Uint8List.fromList(bytes),
      archiveSha256: expectedHash,
      controlBytes: Uint8List.fromList(controlBytes),
      sourceCommit: sourceCommit,
    );
  }
}

class BingxFuturesRemoteRunnerProfileStore {
  static const String _stateFile = 'remote_runner_profiles.v1.json';
  static const String _activeSessionFile =
      'remote_runner_active_session.v1.json';
  static const int _maximumProfiles = 1;
  static const int _maximumSessionBytes = 768 * 1024;

  final CapsuleFileStore _files;
  final String? Function() _activeCapsuleRootHex;

  const BingxFuturesRemoteRunnerProfileStore({
    required String? Function() activeCapsuleRootHex,
    CapsuleFileStore files = const CapsuleFileStore(),
  }) : _activeCapsuleRootHex = activeCapsuleRootHex,
       _files = files;

  Future<List<BingxFuturesRemoteRunnerProfile>> load() async {
    final capsuleHex = _capsuleHex();
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex);
    final raw = await _files.readPluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _stateFile,
    );
    if (raw == null) return const <BingxFuturesRemoteRunnerProfile>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema_version'] != 'hivra-remote-runner-profile-store-v1' ||
        decoded['profiles'] is! List) {
      throw const FormatException('Remote Runner profile store is invalid.');
    }
    final values = decoded['profiles'] as List;
    if (values.length > _maximumProfiles) {
      throw const FormatException('Remote Runner profile store is invalid.');
    }
    final profiles = <BingxFuturesRemoteRunnerProfile>[];
    final ids = <String>{};
    for (final value in values) {
      final profile = BingxFuturesRemoteRunnerProfile.parse(value);
      if (profile == null ||
          profile.capsuleHex != capsuleHex ||
          !ids.add(profile.profileId)) {
        throw const FormatException('Remote Runner profile store is invalid.');
      }
      profiles.add(profile);
    }
    profiles.sort((left, right) => left.profileId.compareTo(right.profileId));
    return profiles;
  }

  Future<void> save(BingxFuturesRemoteRunnerProfile profile) async {
    profile.validate();
    final capsuleHex = _capsuleHex();
    if (profile.capsuleHex != capsuleHex) {
      throw StateError('Active Capsule changed during Runner provisioning.');
    }
    final profiles = await load();
    if (profiles.isNotEmpty && profiles.single.profileId != profile.profileId) {
      throw StateError(
        'This Capsule already owns a Remote Runner. Remove it before configuring another VPS or BingX account.',
      );
    }
    final byId = <String, BingxFuturesRemoteRunnerProfile>{
      profile.profileId: profile,
    };
    if (byId.length > _maximumProfiles) {
      throw StateError('Remote Runner profile limit reached.');
    }
    final ordered =
        byId.values.toList()
          ..sort((left, right) => left.profileId.compareTo(right.profileId));
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex, create: true);
    await _files.writePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _stateFile,
      jsonEncode(<String, dynamic>{
        'schema_version': 'hivra-remote-runner-profile-store-v1',
        'profiles': ordered.map((value) => value.toJson()).toList(),
      }),
    );
  }

  Future<void> delete(String profileId) async {
    final normalized = profileId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('Remote Runner profile id is invalid.');
    }
    final capsuleHex = _capsuleHex();
    final profiles = await load();
    final retained = profiles.where((item) => item.profileId != normalized);
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex, create: true);
    await _files.writePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _stateFile,
      jsonEncode(<String, dynamic>{
        'schema_version': 'hivra-remote-runner-profile-store-v1',
        'profiles': retained.map((value) => value.toJson()).toList(),
      }),
    );
  }

  Future<void> saveActiveSession({
    required String profileId,
    required String canonicalSessionJson,
  }) async {
    final normalized = profileId.trim().toLowerCase();
    final bytes = utf8.encode(canonicalSessionJson);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ||
        bytes.isEmpty ||
        bytes.length > _maximumSessionBytes) {
      throw const FormatException('Remote Runner session is invalid.');
    }
    final profiles = await load();
    if (profiles.length != 1 || profiles.single.profileId != normalized) {
      throw StateError('Remote Runner session has no matching profile.');
    }
    final capsuleDir = await _files.capsuleDirForHex(
      _capsuleHex(),
      create: true,
    );
    await _files.writePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _activeSessionFile,
      jsonEncode(<String, dynamic>{
        'schema_version': 'hivra-remote-runner-active-session-v1',
        'profile_id': normalized,
        'canonical_session_json': canonicalSessionJson,
      }),
    );
  }

  Future<String?> loadActiveSession(String profileId) async {
    final normalized = profileId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('Remote Runner profile id is invalid.');
    }
    final capsuleDir = await _files.capsuleDirForHex(_capsuleHex());
    final raw = await _files.readPluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _activeSessionFile,
    );
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 3 ||
        decoded['schema_version'] != 'hivra-remote-runner-active-session-v1' ||
        decoded['profile_id'] != normalized ||
        decoded['canonical_session_json'] is! String) {
      throw const FormatException('Remote Runner session store is invalid.');
    }
    final session = decoded['canonical_session_json'] as String;
    final bytes = utf8.encode(session);
    if (bytes.isEmpty || bytes.length > _maximumSessionBytes) {
      throw const FormatException('Remote Runner session store is invalid.');
    }
    return session;
  }

  Future<void> deleteActiveSession() async {
    final capsuleDir = await _files.capsuleDirForHex(_capsuleHex());
    await _files.deletePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _activeSessionFile,
    );
  }

  String _capsuleHex() {
    final value = _activeCapsuleRootHex()?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('Active Capsule is unavailable.');
    }
    return value;
  }
}

class BingxFuturesRemoteRunnerBootstrapResult {
  final String hostKeyAlgorithm;
  final String hostKeyFingerprint;
  final String runnerPublicKeyText;
  final Uint8List runnerEvidenceBytes;

  const BingxFuturesRemoteRunnerBootstrapResult({
    required this.hostKeyAlgorithm,
    required this.hostKeyFingerprint,
    required this.runnerPublicKeyText,
    required this.runnerEvidenceBytes,
  });
}

abstract interface class BingxFuturesRemoteRunnerHostPort {
  Future<BingxFuturesRemoteRunnerBootstrapResult> bootstrap({
    required String host,
    required int port,
    required String rootUsername,
    required String rootPassword,
    required String profileId,
    required String sshPublicKeyLine,
    required BingxFuturesEmbeddedRunnerBundle bundle,
    required ConfirmRemoteHostKey confirmHostKey,
  });

  Future<String> status({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  });

  Future<String> deploySession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalSessionJson,
    required String apiKey,
    required String apiSecret,
  });

  Future<String> completedSessionEffects({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String sessionOperationId,
  });

  Future<String> pause({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  });

  Future<String> remove({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  });

  Future<String> revokeSession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalRevocationJson,
  });
}

class DartSshBingxFuturesRemoteRunnerHostPort
    implements BingxFuturesRemoteRunnerHostPort {
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _interactiveAuthTimeout = Duration(minutes: 2);
  static const Duration _commandTimeout = Duration(minutes: 3);
  static const int _bootstrapAuthAttempts = 3;
  static const SSHAlgorithms _algorithms = SSHAlgorithms(
    cipher: <SSHCipherType>[SSHCipherType.chacha20poly1305],
  );

  const DartSshBingxFuturesRemoteRunnerHostPort();

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
    String? acceptedAlgorithm;
    String? acceptedFingerprint;
    SSHClient? client;
    try {
      for (var attempt = 1; attempt <= _bootstrapAuthAttempts; attempt += 1) {
        final socket = await SSHSocket.connect(
          host,
          port,
          timeout: _connectTimeout,
        );
        final candidate = SSHClient(
          socket,
          username: rootUsername,
          algorithms: _algorithms,
          onPasswordRequest: () => rootPassword,
          // dartssh2 verifies the host key during the handshake, so the
          // bounded interactive window covers fingerprint review and auth.
          handshakeTimeout: _interactiveAuthTimeout,
          authTimeout: _interactiveAuthTimeout,
          onVerifyHostKey: (algorithm, fingerprintBytes) async {
            final fingerprint = utf8.decode(
              fingerprintBytes,
              allowMalformed: false,
            );
            final knownAlgorithm = acceptedAlgorithm;
            final knownFingerprint = acceptedFingerprint;
            if (knownAlgorithm != null || knownFingerprint != null) {
              return algorithm == knownAlgorithm &&
                  fingerprint == knownFingerprint;
            }
            final accepted = await confirmHostKey(algorithm, fingerprint);
            if (accepted) {
              acceptedAlgorithm = algorithm;
              acceptedFingerprint = fingerprint;
            }
            return accepted;
          },
        );
        try {
          await candidate.authenticated.timeout(_interactiveAuthTimeout);
          client = candidate;
          break;
        } on SSHAuthAbortError {
          await candidate.close();
          await candidate.done.catchError((_) {});
          if (attempt == _bootstrapAuthAttempts) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        } catch (_) {
          await candidate.close();
          await candidate.done.catchError((_) {});
          rethrow;
        }
      }
      final authenticatedClient = client;
      if (authenticatedClient == null) {
        throw StateError('VPS authentication did not complete.');
      }
      if (acceptedAlgorithm == null || acceptedFingerprint == null) {
        throw StateError('VPS host key was not accepted.');
      }
      final random = Random.secure();
      final transferId =
          List<String>.generate(
            12,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
      final archivePath = '/tmp/hivra-runner-$profileId-$transferId.tar.gz';
      final bootstrapPath =
          '/tmp/hivra-runner-bootstrap-$profileId-$transferId.sh';
      final sftp = await authenticatedClient.sftp();
      final remote = await sftp.open(
        archivePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remote.write(Stream<Uint8List>.value(bundle.archiveBytes)).done;
      } finally {
        await remote.close();
      }
      final bootstrapBytes = utf8.encode(
        _bootstrapScript(
          profileId: profileId,
          sshPublicKeyLine: sshPublicKeyLine,
          controlBytes: bundle.controlBytes,
        ),
      );
      final remoteBootstrap = await sftp.open(
        bootstrapPath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        await remoteBootstrap
            .write(Stream<Uint8List>.value(Uint8List.fromList(bootstrapBytes)))
            .done;
      } finally {
        await remoteBootstrap.close();
      }
      await sftp.close();
      authenticatedClient.close();
      await authenticatedClient.done.catchError((_) {});
      client = null;

      final executionSocket = await SSHSocket.connect(
        host,
        port,
        timeout: _connectTimeout,
      );
      final executionClient = SSHClient(
        executionSocket,
        username: rootUsername,
        algorithms: _algorithms,
        onPasswordRequest: () => rootPassword,
        handshakeTimeout: _interactiveAuthTimeout,
        authTimeout: _interactiveAuthTimeout,
        onVerifyHostKey: (algorithm, fingerprintBytes) {
          final fingerprint = utf8.decode(
            fingerprintBytes,
            allowMalformed: false,
          );
          return algorithm == acceptedAlgorithm &&
              fingerprint == acceptedFingerprint;
        },
      );
      client = executionClient;
      await executionClient.authenticated.timeout(_interactiveAuthTimeout);
      final result = await _executeWithInput(
        executionClient,
        "bash '$bootstrapPath' '$archivePath' '${bundle.archiveSha256}' '$bootstrapPath'",
        const <int>[],
      ).timeout(_commandTimeout);
      (String, Uint8List) parsed;
      try {
        parsed = _parseBootstrapOutput(result.stdout);
      } on FormatException catch (error) {
        final stderr = _boundedText(result.stderr);
        final stdout = _boundedText(result.stdout);
        final detail =
            stderr.isNotEmpty
                ? stderr
                : stdout.isNotEmpty
                ? stdout
                : '${error.message} (exit code ${result.exitCode})';
        throw StateError('VPS bootstrap failed: $detail');
      }
      if (result.exitCode != 0 && result.exitCode != -1) {
        final stderr = _boundedText(result.stderr);
        final stdout = _boundedText(result.stdout);
        final detail =
            stderr.isNotEmpty
                ? stderr
                : stdout.isNotEmpty
                ? stdout
                : 'exit code ${result.exitCode}';
        throw StateError('VPS bootstrap failed: $detail');
      }
      return BingxFuturesRemoteRunnerBootstrapResult(
        hostKeyAlgorithm: acceptedAlgorithm!,
        hostKeyFingerprint: acceptedFingerprint!,
        runnerPublicKeyText: parsed.$1,
        runnerEvidenceBytes: parsed.$2,
      );
    } finally {
      await client?.close();
      await client?.done.catchError((_) {});
    }
  }

  @override
  Future<String> status({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) {
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'status',
      input: const <int>[],
    );
  }

  @override
  Future<String> deploySession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalSessionJson,
    required String apiKey,
    required String apiSecret,
  }) {
    final sessionBytes = utf8.encode(canonicalSessionJson);
    if (sessionBytes.isEmpty || sessionBytes.length > 768 * 1024) {
      throw const FormatException('Remote session payload is invalid.');
    }
    final normalizedKey = apiKey.trim();
    final normalizedSecret = apiSecret.trim();
    if (!RegExp(r'^[!-~]{1,512}$').hasMatch(normalizedKey) ||
        !RegExp(r'^[!-~]{1,512}$').hasMatch(normalizedSecret)) {
      throw const FormatException('BingX credentials are invalid.');
    }
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'apply-enable:${profile.runnerKeyId}',
      input: utf8.encode(
        '${base64Encode(sessionBytes)}\n$normalizedKey\n$normalizedSecret\n',
      ),
      requiredSuccessMarker: 'HIVRA_REMOTE_RUNNER_APPLY_OK=1',
    );
  }

  @override
  Future<String> completedSessionEffects({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String sessionOperationId,
  }) {
    final normalizedSession = sessionOperationId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedSession)) {
      throw const FormatException('Remote session operation id is invalid.');
    }
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'completed-effects:${profile.runnerKeyId}:$normalizedSession',
      input: const <int>[],
      maximumOutputBytes: 64 * 1024,
    );
  }

  @override
  Future<String> pause({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) {
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'pause',
      input: const <int>[],
    );
  }

  @override
  Future<String> remove({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
  }) {
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'remove:${profile.runnerKeyId}',
      input: const <int>[],
    );
  }

  @override
  Future<String> revokeSession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String canonicalRevocationJson,
  }) {
    final bytes = utf8.encode(canonicalRevocationJson);
    if (bytes.isEmpty || bytes.length > 256 * 1024) {
      throw const FormatException('Remote session revocation is invalid.');
    }
    return _runRestricted(
      profile: profile,
      privateKeyPem: privateKeyPem,
      operation: 'revoke:${profile.runnerKeyId}',
      input: utf8.encode('${base64Encode(bytes)}\n'),
    );
  }

  Future<String> _runRestricted({
    required BingxFuturesRemoteRunnerProfile profile,
    required String privateKeyPem,
    required String operation,
    required List<int> input,
    String? requiredSuccessMarker,
    int? maximumOutputBytes,
  }) async {
    final identities = SSHKeyPair.fromPem(privateKeyPem);
    if (identities.length != 1) {
      throw const FormatException('Runner SSH identity is invalid.');
    }
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: _connectTimeout,
    );
    final client = SSHClient(
      socket,
      username: profile.sshUsername,
      algorithms: _algorithms,
      identities: identities,
      handshakeTimeout: _connectTimeout,
      authTimeout: _connectTimeout,
      onVerifyHostKey: (algorithm, fingerprintBytes) {
        final fingerprint = utf8.decode(
          fingerprintBytes,
          allowMalformed: false,
        );
        return algorithm == profile.hostKeyAlgorithm &&
            fingerprint == profile.hostKeyFingerprint;
      },
    );
    try {
      await client.authenticated.timeout(_connectTimeout);
      final result = await _executeWithInput(
        client,
        operation,
        input,
      ).timeout(_commandTimeout);
      final stdout =
          maximumOutputBytes == null
              ? _boundedText(result.stdout)
              : result.stdout.length > maximumOutputBytes
              ? throw StateError(
                'Remote Runner output exceeded its bounded size.',
              )
              : utf8.decode(result.stdout, allowMalformed: false).trim();
      final markerPresent =
          requiredSuccessMarker == null ||
          const LineSplitter()
              .convert(utf8.decode(result.stdout, allowMalformed: true))
              .contains(requiredSuccessMarker);
      if ((result.exitCode != 0 && result.exitCode != -1) || !markerPresent) {
        final stderr = _boundedText(result.stderr);
        final detail =
            stderr.isNotEmpty
                ? stderr
                : stdout.isNotEmpty
                ? stdout
                : 'exit code ${result.exitCode}';
        throw StateError('Remote Runner operation failed: $detail');
      }
      if (result.exitCode == -1 && requiredSuccessMarker == null) {
        throw StateError(
          'Remote Runner operation ended without a verified result.',
        );
      }
      return stdout;
    } finally {
      client.close();
      await client.done.catchError((_) {});
    }
  }

  Future<({int exitCode, Uint8List stdout, Uint8List stderr})>
  _executeWithInput(SSHClient client, String command, List<int> input) async {
    final session = await client.execute(command);
    final stdoutFuture = session.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final stderrFuture = session.stderr.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (input.isNotEmpty) {
      await session.stdin.addStream(
        Stream<Uint8List>.value(Uint8List.fromList(input)),
      );
    }
    await session.stdin.close();
    await session.done;
    return (
      exitCode: session.exitCode ?? -1,
      stdout: Uint8List.fromList(await stdoutFuture),
      stderr: Uint8List.fromList(await stderrFuture),
    );
  }

  (String, Uint8List) _parseBootstrapOutput(Uint8List bytes) {
    final lines = const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: false),
    );
    String? publicKeyBase64;
    String? evidenceBase64;
    var ready = false;
    for (final line in lines) {
      if (line.startsWith('HIVRA_RUNNER_PUBLIC_KEY_B64=')) {
        publicKeyBase64 = line.substring('HIVRA_RUNNER_PUBLIC_KEY_B64='.length);
      } else if (line.startsWith('HIVRA_RUNNER_EVIDENCE_B64=')) {
        evidenceBase64 = line.substring('HIVRA_RUNNER_EVIDENCE_B64='.length);
      } else if (line == 'HIVRA_RUNNER_READY=1') {
        ready = true;
      }
    }
    if (!ready || publicKeyBase64 == null || evidenceBase64 == null) {
      throw const FormatException(
        'VPS bootstrap returned incomplete evidence.',
      );
    }
    final publicKey = utf8.decode(base64Decode(publicKeyBase64));
    final evidence = base64Decode(evidenceBase64);
    if (publicKey.length != 65 || evidence.length > 8192) {
      throw const FormatException('VPS bootstrap returned invalid evidence.');
    }
    return (publicKey, Uint8List.fromList(evidence));
  }

  String _boundedText(Uint8List bytes) {
    final bounded = bytes.length <= 2048 ? bytes : bytes.sublist(0, 2048);
    return utf8.decode(bounded, allowMalformed: true).trim();
  }

  String _bootstrapScript({
    required String profileId,
    required String sshPublicKeyLine,
    required Uint8List controlBytes,
  }) {
    final publicKeyBase64 = base64Encode(utf8.encode(sshPublicKeyLine));
    final controlBase64 = base64Encode(controlBytes);
    final originalCommand = r'\"$SSH_ORIGINAL_COMMAND\"';
    return '''#!/usr/bin/env bash
set -euo pipefail
archive="\$1"
expected_sha="\$2"
bootstrap_script="\$3"
profile_id="$profileId"
[ "\$(id -u)" = 0 ] || { echo "root required" >&2; exit 1; }
work=""
cleanup() { [ -z "\$work" ] || rm -rf "\$work"; rm -f "\$archive" "\$bootstrap_script"; }
trap cleanup EXIT INT TERM
for command in sha256sum tar systemctl systemd-creds python3 useradd usermod openssl getent base64 visudo; do
  command -v "\$command" >/dev/null 2>&1 || { echo "missing dependency: \$command" >&2; exit 1; }
done
[ -f "\$archive" ] && [ ! -L "\$archive" ] || { echo "runner archive missing" >&2; exit 1; }
[ "\$(sha256sum "\$archive" | awk '{print \$1}')" = "\$expected_sha" ] || { echo "runner archive checksum mismatch" >&2; exit 1; }
work="\$(mktemp -d /tmp/hivra-runner-bootstrap.XXXXXX)"
anchor="\$work/anchor"
tar -xzf "\$archive" -C "\$work"
bundle="\$work/linux-x64"
[ -x "\$bundle/hivra-trading-runner-lifecycle" ] || { echo "runner lifecycle missing" >&2; exit 1; }
expected_public_key="\$(printf '%s' '$publicKeyBase64' | base64 -d)"
if [ -x /opt/hivra/trading-public-shadow/hivra-trading-runner-lifecycle ]; then
  /opt/hivra/trading-public-shadow/hivra-trading-runner-lifecycle --verify /opt/hivra/trading-public-shadow >/dev/null
  [ -f /var/lib/hivra-runner-control/.ssh/key.pub ] || { echo "existing Runner has no control identity" >&2; exit 1; }
  [ "\$(cat /var/lib/hivra-runner-control/.ssh/key.pub)" = "\$expected_public_key" ] || { echo "VPS already belongs to another Remote Runner" >&2; exit 1; }
  runner_key_id="\$(python3 - <<'PY'
import json
import re
from pathlib import Path
value = json.loads(Path('/var/lib/hivra-trading-public-shadow/stream/stream_identity.v1.json').read_text())
if set(value) != {'schema_version', 'runner_key_id'} or value.get('schema_version') != 1:
    raise SystemExit('installed Runner key is invalid')
runner_key_id = value.get('runner_key_id')
if not isinstance(runner_key_id, str) or re.fullmatch(r'[0-9a-f]{64}', runner_key_id) is None:
    raise SystemExit('installed Runner key is invalid')
print(runner_key_id)
PY
)"
  if ! cmp -s "\$bundle/ARTIFACT-MANIFEST.v2" /opt/hivra/trading-public-shadow/ARTIFACT-MANIFEST.v2; then
    "\$bundle/hivra-trading-runner-lifecycle" --upgrade-disabled "\$bundle" --expected-runner-key-id "\$runner_key_id"
  fi
  /opt/hivra/trading-public-shadow/hivra-trading-runner-lifecycle --verify /opt/hivra/trading-public-shadow >/dev/null
  /opt/hivra/trading-public-shadow/hivra-trading-runner-lifecycle --export-anchor /opt/hivra/trading-public-shadow --expected-runner-key-id "\$runner_key_id" --anchor-output "\$anchor"
else
  "\$bundle/hivra-trading-runner-lifecycle" --provision-disabled "\$bundle" --anchor-output "\$anchor"
fi
install -d -m 0755 /usr/local/libexec
printf '%s' '$controlBase64' | base64 -d > /usr/local/libexec/hivra-trading-runner-control
chown root:root /usr/local/libexec/hivra-trading-runner-control
chmod 0755 /usr/local/libexec/hivra-trading-runner-control
runner_login_hash="\$(openssl rand -hex 32 | openssl passwd -6 -stdin)"
if ! id hivra-runner >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/hivra-runner-control --shell /bin/sh --password "\$runner_login_hash" hivra-runner
elif getent shadow hivra-runner | cut -d: -f2 | grep -q '^!'; then
  usermod --password "\$runner_login_hash" hivra-runner
fi
unset runner_login_hash
install -d -o hivra-runner -g hivra-runner -m 0700 /var/lib/hivra-runner-control/.ssh
printf '%s' '$publicKeyBase64' | base64 -d > /var/lib/hivra-runner-control/.ssh/key.pub
public_key="\$(cat /var/lib/hivra-runner-control/.ssh/key.pub)"
printf '%s %s\n' 'restrict,command="/usr/bin/sudo -n /usr/local/libexec/hivra-trading-runner-control $originalCommand"' "\$public_key" > /var/lib/hivra-runner-control/.ssh/authorized_keys
chown hivra-runner:hivra-runner /var/lib/hivra-runner-control/.ssh/key.pub /var/lib/hivra-runner-control/.ssh/authorized_keys
chmod 0600 /var/lib/hivra-runner-control/.ssh/key.pub /var/lib/hivra-runner-control/.ssh/authorized_keys
printf 'hivra-runner ALL=(root) NOPASSWD: /usr/local/libexec/hivra-trading-runner-control *\n' > /etc/sudoers.d/hivra-runner-control
chmod 0440 /etc/sudoers.d/hivra-runner-control
visudo -cf /etc/sudoers.d/hivra-runner-control >/dev/null
printf 'HIVRA_RUNNER_PUBLIC_KEY_B64=%s\n' "\$(base64 < "\$anchor/runner-public-key.ed25519.hex" | tr -d '\n')"
printf 'HIVRA_RUNNER_EVIDENCE_B64=%s\n' "\$(base64 < "\$anchor/shadow-evidence.v1.json" | tr -d '\n')"
printf 'HIVRA_RUNNER_PROFILE_ID=%s\n' "\$profile_id"
printf 'HIVRA_RUNNER_READY=1\n'
''';
  }
}

class BingxFuturesRemoteRunnerProvisioningService {
  static const String _vaultProvider = 'remote-runner-ssh';
  static const String _vaultSecret = 'private-key-pem';

  final String? Function() _activeCapsuleRootHex;
  final BingxFuturesRemoteRunnerIdentityService _identity;
  final BingxFuturesRemoteRunnerProfileStore _profiles;
  final CapsuleScopedSecretVault _secrets;
  final BingxFuturesEmbeddedRunnerBundleLoader _bundleLoader;
  final BingxFuturesRemoteRunnerHostPort _host;

  BingxFuturesRemoteRunnerProvisioningService({
    required String? Function() activeCapsuleRootHex,
    required BingxFuturesRemoteRunnerIdentityService identity,
    BingxFuturesRemoteRunnerProfileStore? profiles,
    CapsuleScopedSecretVault? secrets,
    BingxFuturesEmbeddedRunnerBundleLoader? bundleLoader,
    BingxFuturesRemoteRunnerHostPort host =
        const DartSshBingxFuturesRemoteRunnerHostPort(),
  }) : _activeCapsuleRootHex = activeCapsuleRootHex,
       _identity = identity,
       _profiles =
           profiles ??
           BingxFuturesRemoteRunnerProfileStore(
             activeCapsuleRootHex: activeCapsuleRootHex,
           ),
       _secrets = secrets ?? CapsuleScopedSecretVault(),
       _bundleLoader = bundleLoader ?? BingxFuturesEmbeddedRunnerBundleLoader(),
       _host = host;

  Future<BingxFuturesRemoteRunnerProfile> bootstrap({
    required String host,
    required int port,
    required String rootUsername,
    required String rootPassword,
    required String accountBindingHashHex,
    required ConfirmRemoteHostKey confirmHostKey,
  }) async {
    final capsuleHex = _capsuleHex();
    final normalizedHost = host.trim().toLowerCase();
    final normalizedRoot = rootUsername.trim();
    final normalizedAccount = accountBindingHashHex.trim().toLowerCase();
    if (normalizedHost.isEmpty ||
        normalizedHost.length > 253 ||
        normalizedHost.contains(RegExp(r'[\s/\\]')) ||
        port < 1 ||
        port > 65535 ||
        normalizedRoot != 'root' ||
        rootPassword.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedAccount)) {
      throw const FormatException('VPS connection details are invalid.');
    }
    final profileId =
        sha256
            .convert(
              utf8.encode(
                'hivra.remote-runner-profile.v1\n$capsuleHex\n'
                '$normalizedAccount\n$normalizedHost\n$port',
              ),
            )
            .toString();
    final existingProfiles = await _profiles.load();
    BingxFuturesRemoteRunnerProfile? existingProfile;
    if (existingProfiles.isNotEmpty) {
      final existing = existingProfiles.single;
      if (existing.profileId != profileId) {
        throw StateError(
          'This Capsule already owns a Remote Runner. Remove it before configuring another VPS or BingX account.',
        );
      }
      existingProfile = existing;
    }
    final generated = await _loadOrCreateSshIdentity(
      capsuleHex: capsuleHex,
      profileId: profileId,
    );
    final bundle = await _bundleLoader.load();
    final result = await _host.bootstrap(
      host: normalizedHost,
      port: port,
      rootUsername: normalizedRoot,
      rootPassword: rootPassword,
      profileId: profileId,
      sshPublicKeyLine: generated.$2,
      bundle: bundle,
      confirmHostKey: confirmHostKey,
    );
    final binding = await _identity.verifyAnchorPayload(
      publicKeyText: result.runnerPublicKeyText,
      evidenceBytes: result.runnerEvidenceBytes,
    );
    final profile = BingxFuturesRemoteRunnerProfile(
      profileId: profileId,
      capsuleHex: capsuleHex,
      accountBindingHashHex: normalizedAccount,
      host: normalizedHost,
      port: port,
      sshUsername: 'hivra-runner',
      hostKeyAlgorithm: result.hostKeyAlgorithm,
      hostKeyFingerprint: result.hostKeyFingerprint,
      runnerKeyId: binding.runnerKeyId,
      runnerBuildId: binding.runnerBuildId,
      createdAtUtc: existingProfile?.createdAtUtc ?? DateTime.now().toUtc(),
    )..validate();
    await _host.status(profile: profile, privateKeyPem: generated.$1);
    await _identity.saveVerifiedBinding(
      binding,
      expectedCapsuleRootHex: capsuleHex,
    );
    await _profiles.save(profile);
    return profile;
  }

  Future<List<BingxFuturesRemoteRunnerProfile>> loadProfiles() =>
      _profiles.load();

  Future<String> status(BingxFuturesRemoteRunnerProfile profile) async {
    return _host.status(
      profile: profile,
      privateKeyPem: await _privateKey(profile),
    );
  }

  Future<void> deploySession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String accountBindingHashHex,
    required String canonicalSessionJson,
    required String apiKey,
    required String apiSecret,
  }) async {
    final capsuleHex = _capsuleHex();
    final accountHash = accountBindingHashHex.trim().toLowerCase();
    if (profile.capsuleHex != capsuleHex ||
        profile.accountBindingHashHex != accountHash) {
      throw StateError('Remote Runner profile belongs to another authority.');
    }
    await _host.deploySession(
      profile: profile,
      privateKeyPem: await _privateKey(profile),
      canonicalSessionJson: canonicalSessionJson,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
    await _profiles.saveActiveSession(
      profileId: profile.profileId,
      canonicalSessionJson: canonicalSessionJson,
    );
  }

  Future<List<ExternalEffectOperation>> completedSessionEffects({
    required BingxFuturesRemoteRunnerProfile profile,
    required String sessionOperationId,
  }) async {
    final capsuleHex = _capsuleHex();
    final normalizedSession = sessionOperationId.trim().toLowerCase();
    if (profile.capsuleHex != capsuleHex ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedSession)) {
      throw StateError('Remote Runner session belongs to another authority.');
    }
    final retainedSession = await _profiles.loadActiveSession(
      profile.profileId,
    );
    if (retainedSession == null) {
      throw StateError('This Runner has no locally retained active session.');
    }
    final retainedWire = jsonDecode(retainedSession);
    if (retainedWire is! Map<String, dynamic> ||
        retainedWire['operation_id'] != normalizedSession ||
        retainedWire['runner_key_id'] != profile.runnerKeyId) {
      throw StateError('The retained Remote Runner session does not match.');
    }
    final raw = await _host.completedSessionEffects(
      profile: profile,
      privateKeyPem: await _privateKey(profile),
      sessionOperationId: normalizedSession,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.length > 256) {
      throw const FormatException('Remote Runner effect evidence is invalid.');
    }
    final operations = <ExternalEffectOperation>[];
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException(
          'Remote Runner effect evidence is invalid.',
        );
      }
      operations.add(
        ExternalEffectOperation.fromJson(Map<String, dynamic>.from(value)),
      );
    }
    if (jsonEncode(operations.map((value) => value.toJson()).toList()) != raw) {
      throw const FormatException(
        'Remote Runner effect evidence is not canonical.',
      );
    }
    return List<ExternalEffectOperation>.unmodifiable(operations);
  }

  Future<String> pause(BingxFuturesRemoteRunnerProfile profile) async {
    if (profile.capsuleHex != _capsuleHex()) {
      throw StateError('Remote Runner profile belongs to another Capsule.');
    }
    return _host.pause(
      profile: profile,
      privateKeyPem: await _privateKey(profile),
    );
  }

  Future<String> remove(BingxFuturesRemoteRunnerProfile profile) async {
    if (profile.capsuleHex != _capsuleHex()) {
      throw StateError('Remote Runner profile belongs to another Capsule.');
    }
    final privateKey = await _privateKey(profile);
    final result = await _host.remove(
      profile: profile,
      privateKeyPem: privateKey,
    );
    await _identity.deleteVerifiedBinding(
      expectedRunnerKeyId: profile.runnerKeyId,
    );
    await _profiles.deleteActiveSession();
    await _profiles.delete(profile.profileId);
    await _secrets.deleteAccount(
      capsuleHex: profile.capsuleHex,
      pluginId: bingxFuturesTradingPluginId,
      providerId: _vaultProvider,
      accountId: profile.profileId,
    );
    return result;
  }

  Future<String?> loadActiveSession(
    BingxFuturesRemoteRunnerProfile profile,
  ) async {
    if (profile.capsuleHex != _capsuleHex()) {
      throw StateError('Remote Runner profile belongs to another Capsule.');
    }
    return _profiles.loadActiveSession(profile.profileId);
  }

  Future<String> revokeSession({
    required BingxFuturesRemoteRunnerProfile profile,
    required String canonicalRevocationJson,
  }) async {
    if (profile.capsuleHex != _capsuleHex()) {
      throw StateError('Remote Runner profile belongs to another Capsule.');
    }
    final result = await _host.revokeSession(
      profile: profile,
      privateKeyPem: await _privateKey(profile),
      canonicalRevocationJson: canonicalRevocationJson,
    );
    await _profiles.deleteActiveSession();
    return result;
  }

  Future<String> _privateKey(BingxFuturesRemoteRunnerProfile profile) async {
    final value = await _secrets.loadSecret(
      capsuleHex: profile.capsuleHex,
      pluginId: bingxFuturesTradingPluginId,
      providerId: _vaultProvider,
      accountId: profile.profileId,
      secretName: _vaultSecret,
    );
    if (value == null || value.isEmpty) {
      throw StateError('Remote Runner SSH identity is unavailable.');
    }
    return value;
  }

  Future<(String, String)> _generateSshIdentity(String profileId) async {
    final keyPair = await Ed25519().newKeyPair();
    final privateSeed = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    if (privateSeed.length != 32 || publicKey.bytes.length != 32) {
      throw StateError('SSH identity generation failed.');
    }
    final sshPair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(publicKey.bytes),
      Uint8List.fromList(<int>[...privateSeed, ...publicKey.bytes]),
      'hivra-$profileId',
    );
    final publicLine =
        'ssh-ed25519 ${base64Encode(sshPair.toPublicKey().encode())} '
        'hivra-$profileId';
    return (sshPair.toPem(), publicLine);
  }

  Future<(String, String)> _loadOrCreateSshIdentity({
    required String capsuleHex,
    required String profileId,
  }) async {
    final retained = await _secrets.loadSecret(
      capsuleHex: capsuleHex,
      pluginId: bingxFuturesTradingPluginId,
      providerId: _vaultProvider,
      accountId: profileId,
      secretName: _vaultSecret,
    );
    if (retained != null && retained.isNotEmpty) {
      final identities = SSHKeyPair.fromPem(retained);
      if (identities.length != 1) {
        throw const FormatException('Retained Runner SSH identity is invalid.');
      }
      final publicLine =
          'ssh-ed25519 ${base64Encode(identities.single.toPublicKey().encode())} '
          'hivra-$profileId';
      return (retained, publicLine);
    }
    final generated = await _generateSshIdentity(profileId);
    await _secrets.saveSecret(
      capsuleHex: capsuleHex,
      pluginId: bingxFuturesTradingPluginId,
      providerId: _vaultProvider,
      accountId: profileId,
      secretName: _vaultSecret,
      secretValue: generated.$1,
    );
    return generated;
  }

  String _capsuleHex() {
    final value = _activeCapsuleRootHex()?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('Active Capsule is unavailable.');
    }
    return value;
  }
}
