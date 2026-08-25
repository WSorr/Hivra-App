import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/plugin_contract_ids.dart';
import 'bingx_futures_deterministic_replay_harness_service.dart';
import 'capsule_file_store.dart';

class BingxFuturesRemoteRunnerBinding {
  static const String contractVersion =
      'hivra-trading-remote-runner-binding-v1';

  final String runnerKeyId;
  final String publicKeyHex;
  final String runnerBuildId;
  final String pluginVersion;
  final String packageDigestHex;
  final int anchorSequence;
  final String anchorEvidenceHashHex;
  final String anchorEvidenceJson;

  const BingxFuturesRemoteRunnerBinding({
    required this.runnerKeyId,
    required this.publicKeyHex,
    required this.runnerBuildId,
    required this.pluginVersion,
    required this.packageDigestHex,
    required this.anchorSequence,
    required this.anchorEvidenceHashHex,
    required this.anchorEvidenceJson,
  });

  String get canonicalJson => jsonEncode(<String, dynamic>{
    'contract_version': contractVersion,
    'runner_key_id': runnerKeyId,
    'public_key_hex': publicKeyHex,
    'runner_build_id': runnerBuildId,
    'plugin_version': pluginVersion,
    'package_digest_hex': packageDigestHex,
    'anchor_sequence': anchorSequence,
    'anchor_evidence_hash_hex': anchorEvidenceHashHex,
    'anchor_evidence_json': anchorEvidenceJson,
  });

  static BingxFuturesRemoteRunnerBinding? parse(String untrustedJson) {
    try {
      final decoded = jsonDecode(untrustedJson);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 9 ||
          decoded['contract_version'] != contractVersion) {
        return null;
      }
      final binding = BingxFuturesRemoteRunnerBinding(
        runnerKeyId: decoded['runner_key_id'] as String,
        publicKeyHex: decoded['public_key_hex'] as String,
        runnerBuildId: decoded['runner_build_id'] as String,
        pluginVersion: decoded['plugin_version'] as String,
        packageDigestHex: decoded['package_digest_hex'] as String,
        anchorSequence: decoded['anchor_sequence'] as int,
        anchorEvidenceHashHex: decoded['anchor_evidence_hash_hex'] as String,
        anchorEvidenceJson: decoded['anchor_evidence_json'] as String,
      );
      return binding.canonicalJson == untrustedJson ? binding : null;
    } on Object {
      return null;
    }
  }
}

class BingxFuturesRemoteRunnerIdentityService {
  static const String _bindingFileName = 'remote_runner_binding.v1.json';
  static const String _publicKeyFileName = 'runner-public-key.ed25519.hex';
  static const String _evidenceFileName = 'shadow-evidence.v1.json';
  static const int _maxEvidenceBytes = 8192;
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _capsuleHex = RegExp(r'^[0-9a-f]{64}$');

  final String? Function()? _readActiveCapsuleRootHex;
  final CapsuleFileStore _files;
  final BingxFuturesDeterministicReplayHarnessService _evidence;

  BingxFuturesRemoteRunnerIdentityService({
    String? Function()? readActiveCapsuleRootHex,
    CapsuleFileStore files = const CapsuleFileStore(),
    BingxFuturesDeterministicReplayHarnessService evidence =
        const BingxFuturesDeterministicReplayHarnessService(),
  }) : _readActiveCapsuleRootHex = readActiveCapsuleRootHex,
       _files = files,
       _evidence = evidence;

  String? normalizeRunnerKeyId(String untrustedText) {
    final value = untrustedText.trim();
    return _hex64.hasMatch(value) ? value : null;
  }

  String? runnerKeyIdFromPublicKeyFile(String untrustedText) {
    final publicKeyHex = normalizeRunnerKeyId(untrustedText);
    if (publicKeyHex == null) return null;
    return sha256.convert(_decodeHex(publicKeyHex)).toString();
  }

  Future<BingxFuturesRemoteRunnerBinding> verifyAnchorDirectory(
    String untrustedPath,
  ) async {
    final directory = Directory(untrustedPath.trim());
    if (!directory.isAbsolute ||
        await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const FormatException('Runner anchor must be one directory.');
    }
    final entries = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Runner anchor contains a non-file entry.');
      }
      entries.add(
        entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      );
    }
    entries.sort();
    final expected = <String>[_evidenceFileName, _publicKeyFileName]..sort();
    if (jsonEncode(entries) != jsonEncode(expected)) {
      throw const FormatException('Runner anchor has unexpected entries.');
    }

    final publicKeyHex = await _readCanonicalPublicKey(
      File('${directory.path}/$_publicKeyFileName'),
    );
    final evidenceBytes = await _readBounded(
      File('${directory.path}/$_evidenceFileName'),
      _maxEvidenceBytes,
    );
    return verifyAnchorPayload(
      publicKeyText: '$publicKeyHex\n',
      evidenceBytes: evidenceBytes,
    );
  }

  Future<BingxFuturesRemoteRunnerBinding> verifyAnchorPayload({
    required String publicKeyText,
    required List<int> evidenceBytes,
  }) async {
    final encodedPublicKey = utf8.encode(publicKeyText);
    if (encodedPublicKey.length != 65 || !publicKeyText.endsWith('\n')) {
      throw const FormatException('Runner public key is not canonical.');
    }
    final publicKeyHex = publicKeyText.substring(0, 64);
    if (!_hex64.hasMatch(publicKeyHex) ||
        evidenceBytes.isEmpty ||
        evidenceBytes.length > _maxEvidenceBytes) {
      throw const FormatException('Runner anchor payload is invalid.');
    }
    final publicKey = SimplePublicKey(
      _decodeHex(publicKeyHex),
      type: KeyPairType.ed25519,
    );
    final runnerKeyId = _evidence.runnerKeyId(publicKey);
    final evidence = _evidence.parseShadowEvidence(evidenceBytes);
    final verdict = await _evidence.verifyShadowEvidenceContinuity(
      untrustedWireBytes: evidenceBytes,
      trustedRunnerKey: publicKey,
      lastAcceptedSequence: evidence.sequence,
      lastAcceptedEvidenceHashHex: evidence.evidenceHashHex,
    );
    if (verdict != BingxFuturesShadowEvidenceVerdict.exactReplay ||
        evidence.runnerKeyId != runnerKeyId ||
        evidence.pluginId != 'hivra.bingx-futures-trading') {
      throw FormatException(
        'Runner anchor verification failed: ${verdict.name}.',
      );
    }
    return BingxFuturesRemoteRunnerBinding(
      runnerKeyId: runnerKeyId,
      publicKeyHex: publicKeyHex,
      runnerBuildId: evidence.runnerBuildId,
      pluginVersion: evidence.pluginVersion,
      packageDigestHex: evidence.packageDigestHex,
      anchorSequence: evidence.sequence,
      anchorEvidenceHashHex: evidence.evidenceHashHex,
      anchorEvidenceJson: utf8.decode(evidenceBytes, allowMalformed: false),
    );
  }

  Future<void> saveVerifiedBinding(
    BingxFuturesRemoteRunnerBinding binding, {
    required String expectedCapsuleRootHex,
  }) async {
    final capsuleHex = _activeCapsuleHex();
    if (capsuleHex != expectedCapsuleRootHex.trim().toLowerCase()) {
      throw StateError('Active Capsule changed during runner binding.');
    }
    if (!await _bindingAuthenticates(binding)) {
      throw const FormatException('Runner binding is not authenticated.');
    }
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex, create: true);
    await _files.writePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _bindingFileName,
      binding.canonicalJson,
    );
  }

  Future<BingxFuturesRemoteRunnerBinding?> loadVerifiedBinding() async {
    final capsuleHex = _activeCapsuleHexOrNull();
    if (capsuleHex == null) return null;
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex);
    final raw = await _files.readPluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _bindingFileName,
    );
    if (raw == null) return null;
    final binding = BingxFuturesRemoteRunnerBinding.parse(raw);
    if (binding == null || !await _bindingAuthenticates(binding)) {
      return null;
    }
    return binding;
  }

  Future<void> deleteVerifiedBinding({
    required String expectedRunnerKeyId,
  }) async {
    final capsuleHex = _activeCapsuleHex();
    final binding = await loadVerifiedBinding();
    if (binding == null) return;
    if (binding.runnerKeyId != expectedRunnerKeyId) {
      throw StateError(
        'Remote Runner binding does not match the removed Runner.',
      );
    }
    final capsuleDir = await _files.capsuleDirForHex(capsuleHex);
    await _files.deletePluginState(
      capsuleDir,
      bingxFuturesTradingPluginId,
      _bindingFileName,
    );
  }

  Future<bool> _bindingAuthenticates(
    BingxFuturesRemoteRunnerBinding binding,
  ) async {
    try {
      if (runnerKeyIdFromPublicKeyFile(binding.publicKeyHex) !=
          binding.runnerKeyId) {
        return false;
      }
      final publicKey = SimplePublicKey(
        _decodeHex(binding.publicKeyHex),
        type: KeyPairType.ed25519,
      );
      final evidenceBytes = utf8.encode(binding.anchorEvidenceJson);
      if (evidenceBytes.length > _maxEvidenceBytes) return false;
      final evidence = _evidence.parseShadowEvidence(evidenceBytes);
      final verdict = await _evidence.verifyShadowEvidenceContinuity(
        untrustedWireBytes: evidenceBytes,
        trustedRunnerKey: publicKey,
        lastAcceptedSequence: binding.anchorSequence,
        lastAcceptedEvidenceHashHex: binding.anchorEvidenceHashHex,
      );
      return verdict == BingxFuturesShadowEvidenceVerdict.exactReplay &&
          evidence.runnerKeyId == binding.runnerKeyId &&
          evidence.pluginId == 'hivra.bingx-futures-trading' &&
          evidence.runnerBuildId == binding.runnerBuildId &&
          evidence.pluginVersion == binding.pluginVersion &&
          evidence.packageDigestHex == binding.packageDigestHex &&
          evidence.sequence == binding.anchorSequence &&
          evidence.evidenceHashHex == binding.anchorEvidenceHashHex;
    } on Object {
      return false;
    }
  }

  String _activeCapsuleHex() {
    final value = _activeCapsuleHexOrNull();
    if (value == null) throw StateError('Active Capsule is unavailable.');
    return value;
  }

  String? _activeCapsuleHexOrNull() {
    final value = _readActiveCapsuleRootHex?.call()?.trim().toLowerCase();
    return value != null && _capsuleHex.hasMatch(value) ? value : null;
  }

  Future<String> _readCanonicalPublicKey(File file) async {
    final bytes = await _readBounded(file, 65);
    final encoded = utf8.decode(bytes, allowMalformed: false);
    if (encoded.length != 65 || !encoded.endsWith('\n')) {
      throw const FormatException('Runner public key is not canonical.');
    }
    final value = encoded.substring(0, 64);
    if (!_hex64.hasMatch(value)) {
      throw const FormatException('Runner public key is not canonical.');
    }
    return value;
  }

  Future<List<int>> _readBounded(File file, int maximumBytes) async {
    if (!file.isAbsolute ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FormatException('Runner anchor file is invalid.');
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(maximumBytes + 1);
      if (bytes.isEmpty || bytes.length > maximumBytes) {
        throw const FormatException('Runner anchor file is unbounded.');
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  List<int> _decodeHex(String value) => List<int>.generate(
    value.length ~/ 2,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}
