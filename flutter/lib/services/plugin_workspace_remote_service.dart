import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import '../models/wasm_plugin_models.dart';
import 'capsule_file_store.dart';
import 'capsule_scoped_secret_vault.dart';
import 'wasm_plugin_registry_service.dart';

/// Only authenticated transport and installation. Private workspace state and
/// provider effects remain opaque and enter the existing workspace executor.
class PluginWorkspaceRemoteService {
  static const connectionFile = 'workspace-remote.v1.json';
  static const _archive = 'hivra-workspace-runner-linux-x64.tar.gz';
  final CapsuleFileStore files;
  final CapsuleScopedSecretVault vault;
  final WasmPluginRegistryService registry;
  final Future<String> Function(Map<String, dynamic>, String, List<int>)?
  _requestTransport;

  PluginWorkspaceRemoteService({
    required this.files,
    required this.vault,
    required this.registry,
    Future<String> Function(Map<String, dynamic>, String, List<int>)?
    requestTransport,
  }) : _requestTransport = requestTransport;

  Future<String> _exchange(
    Map<String, dynamic> c,
    String command,
    List<int> input,
  ) {
    validateConnection(c, c['owner'] as String, c['plugin_id'] as String);
    return _requestTransport?.call(c, command, input) ??
        _withClient(c, (client) => _execute(client, command, input));
  }

  Future<Map<String, dynamic>?> connection(
    String owner,
    String pluginId,
  ) async {
    final directory = await files.capsuleDirForHex(owner);
    final raw = await files.readPluginState(
      directory,
      pluginId,
      connectionFile,
    );
    if (raw == null) return null;
    if (utf8.encode(raw).length > 4096) {
      throw StateError('Invalid VPS connection');
    }
    final value = jsonDecode(raw);
    validateConnection(value, owner, pluginId);
    return Map<String, dynamic>.from(value as Map);
  }

  static void validateConnection(dynamic c, String owner, String pluginId) {
    if (c is! Map ||
        c.length != 9 ||
        c['selected'] is! bool ||
        c['owner'] != owner ||
        c['plugin_id'] != pluginId ||
        c['host'] is! String ||
        !RegExp(r'^[a-zA-Z0-9.:-]{1,253}$').hasMatch(c['host']) ||
        c['port'] is! int ||
        c['port'] < 1 ||
        c['port'] > 65535 ||
        c['fingerprint'] is! String ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}=?$').hasMatch(c['fingerprint']) ||
        c['executor_id'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(c['executor_id']) ||
        (c['package_id'] != null &&
            (c['package_id'] is! String ||
                (c['package_id'] as String).isEmpty)) ||
        (c['package_digest'] != null &&
            (c['package_digest'] is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(c['package_digest'])))) {
      throw StateError('Invalid VPS connection; no remote action admitted');
    }
  }

  Future<void> _save(Map<String, dynamic> c) async {
    validateConnection(c, c['owner'] as String, c['plugin_id'] as String);
    final directory = await files.capsuleDirForHex(
      c['owner'] as String,
      create: true,
    );
    await files.writePluginState(
      directory,
      c['plugin_id'] as String,
      connectionFile,
      jsonEncode(c),
    );
  }

  Future<String?> _key(Map<String, dynamic> c) => vault.loadSecret(
    capsuleHex: c['owner'] as String,
    pluginId: c['plugin_id'] as String,
    providerId: 'workspace-vps',
    accountId: 'primary',
    secretName: 'ssh_key',
  );

  Future<void> connect({
    required String owner,
    required WasmPluginRecord record,
    required String host,
    required int port,
    required String password,
    required Future<bool> Function(String fingerprint) trustPeer,
    required bool Function() stillOwned,
  }) async {
    // Refuse an incomplete/stale distribution before asking the server to change.
    final archive =
        (await rootBundle.load(
          'assets/workspace_runner/$_archive',
        )).buffer.asUint8List();
    final sums = await rootBundle.loadString(
      'assets/workspace_runner/SHA256SUMS.txt',
    );
    verifyDistribution(archive, sums);
    final previous = await connection(owner, record.pluginId!);
    if (previous != null &&
        (previous['host'] != host || previous['port'] != port)) {
      throw StateError('Return to online mode before connecting another VPS');
    }
    final seed = await cryptography.Ed25519().newKeyPair();
    final data = await seed.extract();
    final generated = OpenSSHEd25519KeyPair(
      Uint8List.fromList(data.publicKey.bytes),
      Uint8List.fromList([...data.bytes, ...data.publicKey.bytes]),
      'hivra-workspace',
    );
    final pem = previous == null ? generated.toPem() : await _key(previous);
    if (pem == null) {
      throw StateError(
        'VPS key unavailable; reconnect from its original Capsule',
      );
    }
    final identity = SSHKeyPair.fromPem(pem).single;
    var peer = previous?['fingerprint'] as String?;
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 20),
    );
    final client = SSHClient(
      socket,
      username: 'root',
      onPasswordRequest: () => password,
      onVerifyHostKey: (_, fingerprint) async {
        final actual = utf8.decode(fingerprint);
        if (peer != null) return actual == peer;
        if (!await trustPeer(actual) || !stillOwned()) return false;
        peer = actual;
        return true;
      },
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 90));
      if (!stillOwned() || peer == null) {
        throw StateError('Connection cancelled or Capsule changed');
      }
      final c =
          previous != null
              ? {...previous, 'selected': true}
              : <String, dynamic>{
                'owner': owner,
                'plugin_id': record.pluginId,
                'host': host,
                'port': port,
                'fingerprint': peer,
                'executor_id':
                    sha256.convert(identity.toPublicKey().encode()).toString(),
                'package_id': null,
                'package_digest': null,
                'selected': true,
              };
      validateConnection(c, owner, record.pluginId!);
      // Persist key/pin before installation: a lost acknowledgement can be
      // recovered using the same identity, not by creating another runner.
      await vault.saveSecret(
        capsuleHex: owner,
        pluginId: record.pluginId!,
        providerId: 'workspace-vps',
        accountId: 'primary',
        secretName: 'ssh_key',
        secretValue: pem,
      );
      await _save(c);
      final existing = await _execute(
        client,
        'if [ -f /var/lib/hivra-workspace/runner.json ]; then cat /var/lib/hivra-workspace/runner.json; else printf "{}"; fi',
        const [],
      );
      final binding = _json(existing);
      if (binding.isNotEmpty &&
          (binding['owner'] != owner ||
              binding['plugin_id'] != record.pluginId ||
              binding['executor_id'] != c['executor_id'])) {
        throw StateError(
          'This VPS installation belongs to another Capsule or package',
        );
      }
      final input = await _setupInput(c, record);
      if (!stillOwned()) throw StateError('Capsule or package changed');
      final public =
          'ssh-ed25519 ${base64Encode(identity.toPublicKey().encode())} hivra-workspace-${c['executor_id']}';
      final script = installationScript(
        archive,
        sha256.convert(archive).toString(),
        public,
        input,
      );
      final result = _json(
        await _execute(
          client,
          'sh -s',
          utf8.encode(script),
          timeout: const Duration(minutes: 3),
        ),
      );
      _checkBinding(c, result, digest: input['package_digest'] as String);
      await _save({
        ...c,
        'package_id': result['package_id'],
        'package_digest': result['package_digest'],
      });
      if (!stillOwned()) {
        throw StateError(
          'Capsule changed; VPS installed without trading authority',
        );
      }
    } catch (_) {
      throw StateError(
        'VPS connection/installation failed. Check the address, root login and server fingerprint. No trading Start is implied; retry uses the same installation.',
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _setupInput(
    Map<String, dynamic> c,
    WasmPluginRecord record,
  ) async {
    final binding = await registry.resolveRuntimeBinding(record.pluginId!);
    if (binding.packageId != record.id ||
        binding.packageFilePath == null ||
        !binding.capabilities.contains('workspace.schedule')) {
      throw StateError('Installed workspace changed');
    }
    final bytes = await File(binding.packageFilePath!).readAsBytes();
    if (bytes.length > 4 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != binding.packageDigestHex) {
      throw StateError('Package bytes changed');
    }
    final raw = await vault.loadSecret(
      capsuleHex: c['owner'] as String,
      pluginId: record.pluginId!,
      providerId: 'bingx',
      accountId: 'primary',
      secretName: 'credentials',
    );
    return {
      'owner': c['owner'],
      'plugin_id': record.pluginId,
      'executor_id': c['executor_id'],
      'package_digest': binding.packageDigestHex,
      'package': base64Encode(bytes),
      'credentials': raw == null ? null : _json(raw),
    };
  }

  Future<Map<String, dynamic>> ensurePackage(
    String owner,
    WasmPluginRecord record,
  ) async {
    final c = await connection(owner, record.pluginId!);
    if (c == null) throw StateError('Connect your VPS first');
    final input = await _setupInput(c, record);
    final result = _json(
      await _exchange(c, 'setup', utf8.encode('${jsonEncode(input)}\n')),
    );
    _checkBinding(c, result, digest: input['package_digest'] as String);
    final updated = {
      ...c,
      'package_id': result['package_id'],
      'package_digest': result['package_digest'],
    };
    await _save(updated);
    return updated;
  }

  Future<void> selectOnline(String owner, String pluginId) async {
    final c = await connection(owner, pluginId);
    if (c != null) await _save({...c, 'selected': false});
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> c,
    String command, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    validateConnection(c, c['owner'] as String, c['plugin_id'] as String);
    if (c['package_id'] == null || c['package_digest'] == null) {
      throw StateError('VPS setup has not been acknowledged');
    }
    if (arguments.keys.any(
      (k) => {
        'owner',
        'plugin_id',
        'executor_id',
        'package_id',
        'package_digest',
        'command',
      }.contains(k),
    )) {
      throw StateError('Transport binding cannot be overridden');
    }
    final message = {
      'owner': c['owner'],
      'plugin_id': c['plugin_id'],
      'executor_id': c['executor_id'],
      'package_id': c['package_id'],
      'package_digest': c['package_digest'],
      'command': command,
      ...arguments,
    };
    final response = _json(
      await _exchange(c, 'request', utf8.encode('${jsonEncode(message)}\n')),
    );
    if (response['ok'] != true || response['result'] is! Map) {
      throw StateError(
        'VPS command was not acknowledged. Refresh before retrying; there is no local fallback.',
      );
    }
    final result = Map<String, dynamic>.from(response['result'] as Map);
    if (result['binding'] is! Map) throw StateError('Missing VPS binding');
    _checkBinding(
      c,
      Map<String, dynamic>.from(result['binding'] as Map),
      digest: c['package_digest'] as String,
    );
    if (result['binding']['package_id'] != c['package_id']) {
      throw StateError('VPS package changed');
    }
    return result;
  }

  Future<void> uninstall(Map<String, dynamic> c) async {
    final response = _json(
      await _exchange(
        c,
        'uninstall',
        utf8.encode(
          '${jsonEncode({'owner': c['owner'], 'plugin_id': c['plugin_id'], 'executor_id': c['executor_id'], 'package_id': c['package_id'], 'package_digest': c['package_digest'], 'command': 'forget'})}\n',
        ),
      ),
    );
    if (response['ok'] != true ||
        response['result'] is! Map ||
        response['result']['binding'] is! Map) {
      throw StateError('Remote uninstall was not acknowledged');
    }
    _checkBinding(
      c,
      Map<String, dynamic>.from(response['result']['binding'] as Map),
      digest: c['package_digest'] as String,
    );
    final directory = await files.capsuleDirForHex(c['owner'] as String);
    await files.deletePluginState(
      directory,
      c['plugin_id'] as String,
      connectionFile,
    );
    await vault.deleteAccount(
      capsuleHex: c['owner'] as String,
      pluginId: c['plugin_id'] as String,
      providerId: 'workspace-vps',
      accountId: 'primary',
    );
  }

  static void _checkBinding(
    Map<String, dynamic> c,
    Map<String, dynamic> b, {
    required String digest,
  }) {
    if (b.length != 5 ||
        b['owner'] != c['owner'] ||
        b['plugin_id'] != c['plugin_id'] ||
        b['executor_id'] != c['executor_id'] ||
        b['package_digest'] != digest ||
        b['package_id'] is! String) {
      throw StateError('VPS installation binding mismatch');
    }
  }

  Future<T> _withClient<T>(
    Map<String, dynamic> c,
    Future<T> Function(SSHClient client) action,
  ) async {
    final key = await _key(c);
    if (key == null) throw StateError('Unlock the Capsule VPS key');
    final socket = await SSHSocket.connect(
      c['host'] as String,
      c['port'] as int,
      timeout: const Duration(seconds: 20),
    );
    final client = SSHClient(
      socket,
      username: 'root',
      identities: SSHKeyPair.fromPem(key),
      onVerifyHostKey: (_, bytes) => utf8.decode(bytes) == c['fingerprint'],
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 30));
      return await action(client);
    } finally {
      client.close();
    }
  }

  static Future<String> _execute(
    SSHClient client,
    String command,
    List<int> input, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final session = await client.execute(command);
    final stdout = <int>[];
    var errorBytes = 0;
    final outputDone = Completer<void>();
    final errorsDone = Completer<void>();
    final out = session.stdout.listen(
      (bytes) {
        stdout.addAll(bytes);
        if (stdout.length > 8 * 1024 * 1024) session.close();
      },
      onDone: outputDone.complete,
      onError: outputDone.completeError,
    );
    final err = session.stderr.listen(
      (bytes) {
        errorBytes += bytes.length;
        if (errorBytes > 8192) session.close();
      },
      onDone: errorsDone.complete,
      onError: errorsDone.completeError,
    );
    try {
      // Do not place passwords, provider keys or checkpoints in argv or logs.
      session.stdin.add(Uint8List.fromList(input));
      await session.stdin.close();
      await Future.wait([
        session.done,
        outputDone.future,
        errorsDone.future,
      ]).timeout(timeout);
      if (session.exitCode != 0 ||
          stdout.length > 8 * 1024 * 1024 ||
          errorBytes > 8192) {
        throw StateError(
          'VPS operation failed; no remote success acknowledged',
        );
      }
      return utf8.decode(stdout);
    } finally {
      await out.cancel();
      await err.cancel();
      session.close();
    }
  }

  static Map<String, dynamic> _json(String raw) {
    if (utf8.encode(raw).length > 8 * 1024 * 1024) {
      throw const FormatException('VPS response too large');
    }
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('Invalid VPS response');
    return Map<String, dynamic>.from(value);
  }

  static void verifyDistribution(List<int> bytes, String sums) {
    final digest = sha256.convert(bytes).toString();
    if (bytes.isEmpty ||
        bytes.length > 16 * 1024 * 1024 ||
        sums.trim() != '$digest  $_archive') {
      throw StateError(
        'Canonical VPS runner assets are unavailable or corrupt',
      );
    }
    final tar = GZipDecoder().decodeBytes(bytes, verify: true);
    if (tar.length > 128 * 1024 * 1024) {
      throw StateError('Runner distribution exceeds bound');
    }
    final entries = TarDecoder().decodeBytes(tar, verify: true);
    const allowed = {
      './',
      './bin/',
      './BUILD-METADATA.txt',
      './bin/hivra-workspace-runner',
      './bin/libhivra_ffi.so',
      './hivra-workspace-runner.service',
    };
    if (entries.length != allowed.length ||
        entries.files
            .map((e) => e.name)
            .toSet()
            .difference(allowed)
            .isNotEmpty ||
        entries.files.any(
          (e) =>
              e.isSymbolicLink ||
              e.nameOfLinkedFile.isNotEmpty ||
              (e.isFile == e.name.endsWith('/')),
        )) {
      throw StateError('Unexpected runner archive members');
    }
    final metadata = entries.files.singleWhere(
      (e) => e.name == './BUILD-METADATA.txt',
    );
    if (metadata.size > 8192) throw StateError('Invalid runner provenance');
    final lines = utf8.decode(metadata.content as List<int>).trim().split('\n');
    final fields = <String, String>{};
    for (final line in lines) {
      final split = line.indexOf('=');
      if (split < 1 || fields.containsKey(line.substring(0, split))) {
        throw StateError('Invalid runner provenance');
      }
      fields[line.substring(0, split)] = line.substring(split + 1);
    }
    if (fields.length != 7 ||
        fields['platform'] != 'linux-x64' ||
        fields['workspace_protocol'] != '1' ||
        fields['source_dirty'] != '0' ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(fields['source_commit'] ?? '') ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(fields['source_tree'] ?? '') ||
        fields['rust'] == null ||
        fields['dart'] == null) {
      throw StateError(
        'Runner provenance does not match the supported protocol',
      );
    }
  }

  static String installationScript(
    List<int> archive,
    String digest,
    String publicKey,
    Map<String, dynamic> setup,
  ) {
    if (sha256.convert(archive).toString() != digest ||
        !RegExp(
          r'^ssh-ed25519 [A-Za-z0-9+/=]+ hivra-workspace-[0-9a-f]{64}$',
        ).hasMatch(publicKey)) {
      throw StateError('Invalid installation input');
    }
    final keyLine =
        'restrict,command="/opt/hivra-workspace/control ${setup['executor_id']}" $publicKey';
    return '''set -eu
umask 077
[ "\$(id -u)" = 0 ]
[ "\$(uname -s)" = Linux ] && [ "\$(uname -m)" = x86_64 ]
command -v systemctl >/dev/null
command -v runuser >/dev/null
base=/opt/hivra-workspace
data=/var/lib/hivra-workspace
for path in "\$base" "\$data"; do [ ! -L "\$path" ]; done
mkdir -p "\$base"
chmod 755 "\$base"
id hivra-workspace >/dev/null 2>&1 || useradd --system --home-dir "\$data" --shell /usr/sbin/nologin hivra-workspace
install -d -m 700 -o hivra-workspace -g hivra-workspace "\$data"
exec 9>"\$base/install.lock"
flock -n 9
[ ! -L "\$base/staging" ] && [ ! -L "\$base/current" ] && [ ! -L "\$base/previous" ]
rm -rf "\$base/staging"
mkdir -m 700 "\$base/staging"
switched=0
rollback() {
  result=\$?
  if [ "\$result" != 0 ] && [ "\$switched" = 1 ] && [ -d /opt/hivra-workspace/previous ]; then
    systemctl stop hivra-workspace-runner.service 2>/dev/null || true
    rm -rf /opt/hivra-workspace/current
    mv /opt/hivra-workspace/previous /opt/hivra-workspace/current
    install -m 644 /opt/hivra-workspace/current/hivra-workspace-runner.service /etc/systemd/system/hivra-workspace-runner.service
    systemctl daemon-reload
    systemctl start hivra-workspace-runner.service || true
  fi
  rm -rf /opt/hivra-workspace/staging
  exit "\$result"
}
trap rollback EXIT
base64 -d >"\$base/staging/runner.tar.gz" <<'HIVRA_ARCHIVE'
${base64Encode(archive)}
HIVRA_ARCHIVE
printf '%s  %s\\n' '$digest' "\$base/staging/runner.tar.gz" | sha256sum -c - >/dev/null
tar -xzf "\$base/staging/runner.tar.gz" -C "\$base/staging" --no-same-owner
rm "\$base/staging/runner.tar.gz"
chmod 755 "\$base" "\$base/staging" "\$base/staging/bin" "\$base/staging/bin/hivra-workspace-runner"
systemctl stop hivra-workspace-runner.service 2>/dev/null || true
rm -rf "\$base/previous"
if [ -d "\$base/current" ]; then mv "\$base/current" "\$base/previous"; fi
mv "\$base/staging" "\$base/current"
switched=1
install -m 644 "\$base/current/hivra-workspace-runner.service" /etc/systemd/system/hivra-workspace-runner.service
cat >"\$base/control" <<'HIVRA_CONTROL'
#!/bin/sh
set -eu
umask 077
[ "\$#" = 1 ]
case "\$1" in *[!0-9a-f]*|'') exit 64 ;; esac
[ "\${#1}" = 64 ]
if [ "\${SSH_ORIGINAL_COMMAND:-}" = uninstall ] && [ ! -f /var/lib/hivra-workspace/runner.json ]; then
  receipt=/opt/hivra-workspace/uninstall.json
  if [ -f /opt/hivra-workspace/uninstall.next ]; then
    grep -Fq '"executor_id":"'"\$1"'"' /opt/hivra-workspace/uninstall.next
    systemctl stop hivra-workspace-runner.service
    systemctl disable hivra-workspace-runner.service >/dev/null 2>&1
    [ ! -L /var/lib/hivra-workspace ]
    rm -rf /var/lib/hivra-workspace
    mv /opt/hivra-workspace/uninstall.next "\$receipt"
  fi
  grep -Fq '"executor_id":"'"\$1"'"' "\$receipt"
  cat "\$receipt"
  exit 0
fi
grep -Fq '"executor_id":"'"\$1"'"' /var/lib/hivra-workspace/runner.json
case "\${SSH_ORIGINAL_COMMAND:-}" in
  request) exec runuser -u hivra-workspace -- env HIVRA_WORKSPACE_EXECUTOR_ID="\$1" /opt/hivra-workspace/current/bin/hivra-workspace-runner request /var/lib/hivra-workspace ;;
  setup)
    systemctl stop hivra-workspace-runner.service
    trap 'systemctl start hivra-workspace-runner.service' EXIT
    runuser -u hivra-workspace -- env HIVRA_WORKSPACE_EXECUTOR_ID="\$1" /opt/hivra-workspace/current/bin/hivra-workspace-runner setup /var/lib/hivra-workspace
    ;;
  uninstall)
    [ ! -L /opt/hivra-workspace/uninstall.next ]
    runuser -u hivra-workspace -- env HIVRA_WORKSPACE_EXECUTOR_ID="\$1" HIVRA_WORKSPACE_COMMAND=forget /opt/hivra-workspace/current/bin/hivra-workspace-runner request /var/lib/hivra-workspace > /opt/hivra-workspace/uninstall.next
    systemctl stop hivra-workspace-runner.service
    systemctl disable hivra-workspace-runner.service >/dev/null 2>&1
    [ ! -L /var/lib/hivra-workspace ]
    rm -rf /var/lib/hivra-workspace
    mv /opt/hivra-workspace/uninstall.next /opt/hivra-workspace/uninstall.json
    cat /opt/hivra-workspace/uninstall.json
    ;;
  *) exit 64 ;;
esac
HIVRA_CONTROL
chmod 700 "\$base/control"
[ ! -L /root/.ssh ]
install -d -m 700 /root/.ssh
[ ! -L /root/.ssh/authorized_keys ]
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
[ ! -L /root/.ssh/authorized_keys.hivra.next ]
awk '\$0 !~ / hivra-workspace-[0-9a-f]+\$/ { print }' /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.hivra.next
printf '%s\\n' '$keyLine' >> /root/.ssh/authorized_keys.hivra.next
chmod 600 /root/.ssh/authorized_keys.hivra.next
mv /root/.ssh/authorized_keys.hivra.next /root/.ssh/authorized_keys
rm -f "\$base/uninstall.json" "\$base/uninstall.next"
printf '%s' '${base64Encode(utf8.encode('${jsonEncode(setup)}\n'))}' | base64 -d | runuser -u hivra-workspace -- "\$base/current/bin/hivra-workspace-runner" setup "\$data"
systemctl daemon-reload
systemctl enable hivra-workspace-runner.service >/dev/null 2>&1
systemctl start hivra-workspace-runner.service
''';
  }
}
