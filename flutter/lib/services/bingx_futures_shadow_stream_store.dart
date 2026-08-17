import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'bingx_futures_deterministic_replay_harness_service.dart';

typedef BingxFuturesShadowEvidenceProducer =
    Future<BingxFuturesShadowEvidence> Function(
      int sequence,
      String previousEvidenceHashHex,
    );

class BingxFuturesShadowStreamStore {
  static const int maxEntries = 256;
  static const int _maxIdentityBytes = 1024;
  static const int _maxEvidenceBytes = 8192;
  static const int _lockAttemptLimit = 100;
  static const Duration _lockRetryDelay = Duration(milliseconds: 25);
  static const String _identityFileName = 'stream_identity.v1.json';
  static const String _lockFileName = 'stream.lock';
  static const String _evidenceDirectoryName = 'evidence';
  static const String _emptyEvidenceHash =
      '0000000000000000000000000000000000000000000000000000000000000000';
  static final Map<String, Future<void>> _mutationTails =
      <String, Future<void>>{};

  final Directory directory;
  final BingxFuturesDeterministicReplayHarnessService _evidenceOwner;

  const BingxFuturesShadowStreamStore({
    required this.directory,
    BingxFuturesDeterministicReplayHarnessService evidenceOwner =
        const BingxFuturesDeterministicReplayHarnessService(),
  }) : _evidenceOwner = evidenceOwner;

  Future<BingxFuturesShadowEvidence> append({
    required SimplePublicKey trustedRunnerKey,
    required BingxFuturesShadowEvidenceProducer produce,
  }) {
    final runnerKeyId = _evidenceOwner.runnerKeyId(trustedRunnerKey);
    if (!_isSha256(runnerKeyId)) {
      return Future<BingxFuturesShadowEvidence>.error(
        const FormatException('invalid shadow runner key id'),
      );
    }
    return _serialized(
      () => _appendLocked(
        runnerKeyId: runnerKeyId,
        trustedRunnerKey: trustedRunnerKey,
        produce: produce,
      ),
    );
  }

  Future<BingxFuturesShadowEvidence> _appendLocked({
    required String runnerKeyId,
    required SimplePublicKey trustedRunnerKey,
    required BingxFuturesShadowEvidenceProducer produce,
  }) async {
    await _prepareRootDirectory();
    final lockFile = File('${directory.path}/$_lockFileName');
    await _rejectLink(lockFile.path);
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      await _acquireLock(lock);
      await _prepareEvidenceDirectory();
      await _ensureKnownRootEntries();
      await _bindIdentity(runnerKeyId);
      final entries = await _loadEntries(
        runnerKeyId,
        trustedRunnerKey: trustedRunnerKey,
      );
      if (entries.length >= maxEntries) {
        throw StateError('shadow evidence stream reached bounded capacity');
      }
      final previous = entries.isEmpty ? null : entries.last;
      final nextSequence = (previous?.sequence ?? 0) + 1;
      final previousHash = previous?.evidenceHashHex ?? _emptyEvidenceHash;
      final evidence = await produce(nextSequence, previousHash);
      await _validateProducedEvidence(
        evidence,
        runnerKeyId: runnerKeyId,
        trustedRunnerKey: trustedRunnerKey,
        sequence: nextSequence,
        previousEvidenceHashHex: previousHash,
      );
      final evidenceFile = File(
        '${directory.path}/$_evidenceDirectoryName/'
        '${nextSequence.toString().padLeft(12, '0')}-'
        '${evidence.evidenceHashHex}.json',
      );
      await evidenceFile.create(exclusive: true);
      await evidenceFile.writeAsBytes(evidence.wireBytes, flush: true);
      return evidence;
    } finally {
      try {
        await lock.unlock();
      } finally {
        await lock.close();
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final key = directory.absolute.path;
    final completer = Completer<T>();
    final previous = _mutationTails[key] ?? Future<void>.value();
    final tail = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _mutationTails[key] = tail;
    tail.whenComplete(() {
      if (identical(_mutationTails[key], tail)) {
        _mutationTails.remove(key);
      }
    });
    return completer.future;
  }

  Future<void> _acquireLock(RandomAccessFile lock) async {
    for (var attempt = 1; attempt <= _lockAttemptLimit; attempt++) {
      try {
        await lock.lock(FileLock.exclusive);
        return;
      } on FileSystemException {
        if (attempt == _lockAttemptLimit) rethrow;
        await Future<void>.delayed(_lockRetryDelay);
      }
    }
  }

  Future<void> _prepareRootDirectory() async {
    final existingType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.link) {
      throw const FileSystemException('shadow stream directory is a link');
    }
    if (existingType != FileSystemEntityType.notFound &&
        existingType != FileSystemEntityType.directory) {
      throw const FileSystemException('shadow stream path is not a directory');
    }
    if (existingType == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
    }
  }

  Future<void> _prepareEvidenceDirectory() async {
    final evidenceDirectory = Directory(
      '${directory.path}/$_evidenceDirectoryName',
    );
    final evidenceType = await FileSystemEntity.type(
      evidenceDirectory.path,
      followLinks: false,
    );
    if (evidenceType == FileSystemEntityType.link) {
      throw const FileSystemException('shadow evidence directory is a link');
    }
    if (evidenceType == FileSystemEntityType.notFound) {
      await evidenceDirectory.create();
    } else if (evidenceType != FileSystemEntityType.directory) {
      throw const FileSystemException(
        'shadow evidence path is not a directory',
      );
    }
  }

  Future<void> _ensureKnownRootEntries() async {
    const allowed = <String>{
      _identityFileName,
      _lockFileName,
      _evidenceDirectoryName,
    };
    await for (final entry in directory.list(followLinks: false)) {
      if (!allowed.contains(
        entry.uri.pathSegments.lastWhere((value) => value.isNotEmpty),
      )) {
        throw const FormatException('unknown shadow stream entry');
      }
    }
  }

  Future<void> _bindIdentity(String runnerKeyId) async {
    final identity = File('${directory.path}/$_identityFileName');
    await _rejectLink(identity.path);
    if (!await identity.exists()) {
      await identity.create(exclusive: true);
      await identity.writeAsString(
        jsonEncode(<String, Object>{
          'schema_version': 1,
          'runner_key_id': runnerKeyId,
        }),
        flush: true,
      );
      return;
    }
    if (await identity.length() > _maxIdentityBytes) {
      throw const FormatException('shadow stream identity is oversized');
    }
    final decoded = jsonDecode(await identity.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema_version'] != 1 ||
        decoded['runner_key_id'] != runnerKeyId) {
      throw const FormatException('shadow stream identity mismatch');
    }
  }

  Future<List<BingxFuturesShadowEvidence>> _loadEntries(
    String runnerKeyId, {
    required SimplePublicKey trustedRunnerKey,
  }) async {
    final evidenceDirectory = Directory(
      '${directory.path}/$_evidenceDirectoryName',
    );
    final files = <File>[];
    await for (final entry in evidenceDirectory.list(followLinks: false)) {
      if (entry is! File) {
        throw const FormatException('invalid shadow evidence entry type');
      }
      await _rejectLink(entry.path);
      files.add(entry);
      if (files.length > maxEntries) {
        throw const FormatException('shadow evidence stream exceeds capacity');
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    final entries = <BingxFuturesShadowEvidence>[];
    var expectedSequence = 1;
    var expectedPreviousHash = _emptyEvidenceHash;
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final match = RegExp(
        r'^([0-9]{12})-([0-9a-f]{64})\.json$',
      ).firstMatch(name);
      if (match == null || await file.length() > _maxEvidenceBytes) {
        throw const FormatException('invalid shadow evidence file');
      }
      final evidence = _evidenceOwner.parseShadowEvidence(
        await file.readAsBytes(),
        maxEncodedBytes: _maxEvidenceBytes,
      );
      if (int.parse(match.group(1)!) != expectedSequence ||
          match.group(2) != evidence.evidenceHashHex ||
          evidence.sequence != expectedSequence ||
          evidence.previousEvidenceHashHex != expectedPreviousHash ||
          evidence.runnerKeyId != runnerKeyId ||
          !await _evidenceOwner.authenticateShadowEvidence(
            evidence: evidence,
            trustedRunnerKey: trustedRunnerKey,
          )) {
        throw const FormatException('shadow evidence chain conflict');
      }
      entries.add(evidence);
      expectedSequence++;
      expectedPreviousHash = evidence.evidenceHashHex;
    }
    return entries;
  }

  Future<void> _validateProducedEvidence(
    BingxFuturesShadowEvidence evidence, {
    required String runnerKeyId,
    required SimplePublicKey trustedRunnerKey,
    required int sequence,
    required String previousEvidenceHashHex,
  }) async {
    final reparsed = _evidenceOwner.parseShadowEvidence(
      evidence.wireBytes,
      maxEncodedBytes: _maxEvidenceBytes,
    );
    if (reparsed.sequence != sequence ||
        reparsed.previousEvidenceHashHex != previousEvidenceHashHex ||
        reparsed.runnerKeyId != runnerKeyId ||
        !await _evidenceOwner.authenticateShadowEvidence(
          evidence: reparsed,
          trustedRunnerKey: trustedRunnerKey,
        )) {
      throw const FormatException('produced shadow evidence breaks stream');
    }
  }

  Future<void> _rejectLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('shadow stream entry is a link');
    }
  }

  bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
