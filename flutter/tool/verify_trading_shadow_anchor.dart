import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';

const _publicKeyFileName = 'runner-public-key.ed25519.hex';
const _evidenceFileName = 'shadow-evidence.v1.json';
const _maxEvidenceBytes = 8192;

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final anchorDirectory = Directory(_required(options, 'anchor-dir'));
    final expectedRunnerKeyId = _required(options, 'expected-runner-key-id');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedRunnerKeyId)) {
      throw const FormatException(
        'expected runner key id must be 64 lowercase hex characters',
      );
    }
    await _requireExactAnchorDirectory(anchorDirectory);
    final publicKeyHex = await _readPublicKeyHex(
      File('${anchorDirectory.path}/$_publicKeyFileName'),
    );
    final publicKey = SimplePublicKey(
      _decodeHex(publicKeyHex),
      type: KeyPairType.ed25519,
    );
    final owner = const BingxFuturesDeterministicReplayHarnessService();
    if (owner.runnerKeyId(publicKey) != expectedRunnerKeyId) {
      throw const FormatException('anchor public key does not match runner id');
    }
    final anchorBytes = await _readBoundedEvidence(
      File('${anchorDirectory.path}/$_evidenceFileName'),
    );
    final anchor = owner.parseShadowEvidence(
      anchorBytes,
      maxEncodedBytes: _maxEvidenceBytes,
    );
    final anchorVerdict = await owner.verifyShadowEvidenceContinuity(
      untrustedWireBytes: anchorBytes,
      trustedRunnerKey: publicKey,
      lastAcceptedSequence: anchor.sequence,
      lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
    );
    if (anchorVerdict != BingxFuturesShadowEvidenceVerdict.exactReplay) {
      throw FormatException(
        'anchor verification failed: ${anchorVerdict.name}',
      );
    }

    final candidatePath = options['candidate-evidence'];
    if (candidatePath != null) {
      final candidateBytes = await _readBoundedEvidence(File(candidatePath));
      final candidateVerdict = await owner.verifyShadowEvidenceContinuity(
        untrustedWireBytes: candidateBytes,
        trustedRunnerKey: publicKey,
        lastAcceptedSequence: anchor.sequence,
        lastAcceptedEvidenceHashHex: anchor.evidenceHashHex,
      );
      if (candidateVerdict != BingxFuturesShadowEvidenceVerdict.accepted &&
          candidateVerdict != BingxFuturesShadowEvidenceVerdict.exactReplay) {
        throw FormatException(
          'candidate continuity failed: ${candidateVerdict.name}',
        );
      }
      stdout.writeln('candidate_verdict=${candidateVerdict.name}');
    }
    stdout.writeln(
      'PASS trading-shadow-anchor: runner_key_id=$expectedRunnerKeyId '
      'sequence=${anchor.sequence} evidence_hash=${anchor.evidenceHashHex}',
    );
  } on Object catch (error) {
    stderr.writeln('trading shadow anchor verification failed: $error');
    exitCode = 1;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  const allowed = <String>{
    'anchor-dir',
    'expected-runner-key-id',
    'candidate-evidence',
  };
  final parsed = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--') ||
        index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('invalid argument: $argument');
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || parsed.containsKey(key)) {
      throw FormatException('unsupported or duplicate argument: $argument');
    }
    parsed[key] = arguments[++index];
  }
  return parsed;
}

Future<void> _requireExactAnchorDirectory(Directory directory) async {
  if (!directory.isAbsolute ||
      await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const FormatException(
      'anchor directory must be one absolute directory',
    );
  }
  final names = <String>[];
  await for (final entry in directory.list(followLinks: false)) {
    final type = await FileSystemEntity.type(entry.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const FormatException('anchor contains a non-file entry');
    }
    names.add(entry.uri.pathSegments.lastWhere((value) => value.isNotEmpty));
  }
  names.sort();
  if (jsonEncode(names) !=
      jsonEncode(<String>[_publicKeyFileName, _evidenceFileName]..sort())) {
    throw const FormatException('anchor directory has unexpected entries');
  }
}

Future<String> _readPublicKeyHex(File file) async {
  if (!file.isAbsolute ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException('anchor public key has invalid size');
  }
  final encoded = utf8.decode(
    await _readAtMost(file, 66),
    allowMalformed: false,
  );
  final value = encoded.endsWith('\n') ? encoded.substring(0, 64) : '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value) || encoded != '$value\n') {
    throw const FormatException('anchor public key is not canonical');
  }
  return value;
}

Future<List<int>> _readBoundedEvidence(File file) async {
  if (!file.isAbsolute ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException('anchor evidence is not one bounded file');
  }
  final bytes = await _readAtMost(file, _maxEvidenceBytes + 1);
  if (bytes.isEmpty || bytes.length > _maxEvidenceBytes) {
    throw const FormatException('anchor evidence is not one bounded file');
  }
  return bytes;
}

Future<List<int>> _readAtMost(File file, int limit) async {
  final handle = await file.open();
  try {
    return await handle.read(limit);
  } finally {
    await handle.close();
  }
}

String _required(Map<String, String> options, String key) {
  final value = options[key]?.trim() ?? '';
  if (value.isEmpty) throw FormatException('missing --$key');
  return value;
}

List<int> _decodeHex(String value) => List<int>.generate(
  value.length ~/ 2,
  (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  growable: false,
);
