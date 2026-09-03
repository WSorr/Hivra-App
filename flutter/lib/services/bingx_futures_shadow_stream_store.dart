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
  static const String _pendingIdentityFileName =
      'stream_identity.v1.json.pending';
  static const String _checkpointFileName = 'stream_checkpoint.v1.json';
  static const String _pendingCheckpointFileName =
      'stream_checkpoint.v1.json.pending';
  static const String _lockFileName = 'stream.lock';
  static const String _lockTokenFileName = 'stream.lock.v2';
  static const String _evidenceDirectoryName = 'evidence';
  static const String _pendingDirectoryName = 'pending';
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
    final lockFile = File('${directory.path}/$_lockTokenFileName');
    await _rejectLink(lockFile.path);
    var lockAcquired = false;
    try {
      await _acquireLock(lockFile);
      lockAcquired = true;
      await _prepareStreamDirectories();
      await _ensureKnownRootEntries();
      await _bindIdentity(runnerKeyId);
      await _clearInterruptedCheckpointWrite();
      await _clearInterruptedPendingWrite();
      var checkpoint = await _loadCheckpoint(
        runnerKeyId,
        trustedRunnerKey: trustedRunnerKey,
      );
      var entries = await _loadEntries(
        runnerKeyId,
        trustedRunnerKey: trustedRunnerKey,
        checkpoint: checkpoint,
      );
      final previous = entries.isEmpty ? checkpoint : entries.last;
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
      if (entries.length >= maxEntries) {
        checkpoint = entries.last;
        await _commitCheckpoint(checkpoint);
        await _deleteCheckpointedEvidence(checkpoint);
      }
      await _commitEvidence(evidence);
      return evidence;
    } finally {
      if (lockAcquired) {
        await lockFile.delete();
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

  Future<void> _acquireLock(File lockFile) async {
    for (var attempt = 1; attempt <= _lockAttemptLimit; attempt++) {
      try {
        await lockFile.create(exclusive: true);
        return;
      } on FileSystemException {
        if (attempt == _lockAttemptLimit) rethrow;
      }
      if (attempt == _lockAttemptLimit) {
        throw const FileSystemException(
          'shadow stream lock budget exhausted',
        );
      }
      await Future<void>.delayed(_lockRetryDelay);
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

  Future<void> _prepareStreamDirectories() async {
    await _prepareChildDirectory(
      _evidenceDirectoryName,
      label: 'shadow evidence',
    );
    await _prepareChildDirectory(
      _pendingDirectoryName,
      label: 'shadow pending evidence',
    );
  }

  Future<void> _prepareChildDirectory(
    String name, {
    required String label,
  }) async {
    final child = Directory('${directory.path}/$name');
    final childType = await FileSystemEntity.type(
      child.path,
      followLinks: false,
    );
    if (childType == FileSystemEntityType.link) {
      throw FileSystemException('$label directory is a link');
    }
    if (childType == FileSystemEntityType.notFound) {
      await child.create();
    } else if (childType != FileSystemEntityType.directory) {
      throw FileSystemException('$label path is not a directory');
    }
  }

  Future<void> _ensureKnownRootEntries() async {
    const allowed = <String>{
      _identityFileName,
      _pendingIdentityFileName,
      _checkpointFileName,
      _pendingCheckpointFileName,
      _lockFileName,
      _lockTokenFileName,
      _evidenceDirectoryName,
      _pendingDirectoryName,
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
    final pending = File('${directory.path}/$_pendingIdentityFileName');
    await _rejectLink(identity.path);
    await _rejectLink(pending.path);
    final identityExists = await identity.exists();
    final pendingExists = await pending.exists();
    if (identityExists) {
      if (pendingExists) {
        throw const FormatException('ambiguous shadow stream identity state');
      }
      if (await _readIdentityRunnerKeyId(identity) != runnerKeyId) {
        throw const FormatException('shadow stream identity mismatch');
      }
      return;
    }

    await _requireEmptyUnboundStream();
    if (pendingExists) {
      String? pendingRunnerKeyId;
      try {
        pendingRunnerKeyId = await _readIdentityRunnerKeyId(pending);
      } on FormatException {
        await pending.delete();
      }
      if (pendingRunnerKeyId != null) {
        if (pendingRunnerKeyId != runnerKeyId) {
          throw const FormatException('shadow stream identity mismatch');
        }
        await pending.rename(identity.path);
        return;
      }
    }

    final encoded = jsonEncode(<String, Object>{
      'schema_version': 1,
      'runner_key_id': runnerKeyId,
    });
    await pending.create(exclusive: true);
    try {
      await pending.writeAsString(encoded, flush: true);
      if (await FileSystemEntity.type(identity.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'shadow stream identity target appeared during commit',
        );
      }
      await pending.rename(identity.path);
    } catch (_) {
      if (await FileSystemEntity.type(pending.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await pending.delete();
      }
      rethrow;
    }
  }

  Future<String> _readIdentityRunnerKeyId(File identity) async {
    if (await identity.length() > _maxIdentityBytes) {
      throw const FormatException('shadow stream identity is oversized');
    }
    final decoded = jsonDecode(await identity.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema_version'] != 1 ||
        decoded['runner_key_id'] is! String ||
        !_isSha256(decoded['runner_key_id'] as String)) {
      throw const FormatException('invalid shadow stream identity');
    }
    return decoded['runner_key_id'] as String;
  }

  Future<void> _requireEmptyUnboundStream() async {
    final evidence = Directory('${directory.path}/$_evidenceDirectoryName');
    final pending = Directory('${directory.path}/$_pendingDirectoryName');
    final checkpointType = await FileSystemEntity.type(
      '${directory.path}/$_checkpointFileName',
      followLinks: false,
    );
    final pendingCheckpointType = await FileSystemEntity.type(
      '${directory.path}/$_pendingCheckpointFileName',
      followLinks: false,
    );
    if (!(await evidence.list(followLinks: false).isEmpty) ||
        !(await pending.list(followLinks: false).isEmpty) ||
        checkpointType != FileSystemEntityType.notFound ||
        pendingCheckpointType != FileSystemEntityType.notFound) {
      throw const FormatException('unbound shadow stream contains state');
    }
  }

  Future<BingxFuturesShadowEvidence?> _loadCheckpoint(
    String runnerKeyId, {
    required SimplePublicKey trustedRunnerKey,
  }) async {
    final checkpoint = File('${directory.path}/$_checkpointFileName');
    final checkpointType = await FileSystemEntity.type(
      checkpoint.path,
      followLinks: false,
    );
    if (checkpointType == FileSystemEntityType.notFound) return null;
    if (checkpointType != FileSystemEntityType.file) {
      throw const FileSystemException('shadow checkpoint is not a file');
    }
    if (await checkpoint.length() > _maxEvidenceBytes) {
      throw const FormatException('shadow checkpoint is oversized');
    }
    final evidence = _evidenceOwner.parseShadowEvidence(
      await checkpoint.readAsBytes(),
      maxEncodedBytes: _maxEvidenceBytes,
    );
    if (evidence.sequence < maxEntries ||
        evidence.sequence % maxEntries != 0 ||
        evidence.runnerKeyId != runnerKeyId ||
        !await _evidenceOwner.authenticateShadowEvidence(
          evidence: evidence,
          trustedRunnerKey: trustedRunnerKey,
        )) {
      throw const FormatException('invalid shadow checkpoint');
    }
    return evidence;
  }

  Future<List<BingxFuturesShadowEvidence>> _loadEntries(
    String runnerKeyId, {
    required SimplePublicKey trustedRunnerKey,
    required BingxFuturesShadowEvidence? checkpoint,
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
      if (int.parse(match.group(1)!) != evidence.sequence ||
          match.group(2) != evidence.evidenceHashHex ||
          evidence.runnerKeyId != runnerKeyId ||
          !await _evidenceOwner.authenticateShadowEvidence(
            evidence: evidence,
            trustedRunnerKey: trustedRunnerKey,
          )) {
        throw const FormatException('shadow evidence chain conflict');
      }
      entries.add(evidence);
    }
    if (entries.isEmpty) return entries;

    for (var index = 1; index < entries.length; index++) {
      final previous = entries[index - 1];
      final current = entries[index];
      if (current.sequence != previous.sequence + 1 ||
          current.previousEvidenceHashHex != previous.evidenceHashHex) {
        throw const FormatException('shadow evidence chain conflict');
      }
    }

    final first = entries.first;
    if (checkpoint == null) {
      if (first.sequence != 1 ||
          first.previousEvidenceHashHex != _emptyEvidenceHash) {
        throw const FormatException('shadow evidence chain conflict');
      }
      return entries;
    }

    if (first.sequence <= checkpoint.sequence) {
      final last = entries.last;
      if (last.sequence != checkpoint.sequence ||
          last.evidenceHashHex != checkpoint.evidenceHashHex) {
        throw const FormatException('shadow checkpoint overlap conflict');
      }
      await _deleteCheckpointedEvidence(checkpoint);
      return <BingxFuturesShadowEvidence>[];
    }

    if (first.sequence != checkpoint.sequence + 1 ||
        first.previousEvidenceHashHex != checkpoint.evidenceHashHex) {
      throw const FormatException('shadow evidence chain conflict');
    }
    return entries;
  }

  Future<void> _clearInterruptedCheckpointWrite() async {
    final pending = File('${directory.path}/$_pendingCheckpointFileName');
    final pendingType = await FileSystemEntity.type(
      pending.path,
      followLinks: false,
    );
    if (pendingType == FileSystemEntityType.notFound) return;
    if (pendingType != FileSystemEntityType.file) {
      throw const FileSystemException(
        'shadow pending checkpoint is not a file',
      );
    }
    await pending.delete();
  }

  Future<void> _commitCheckpoint(BingxFuturesShadowEvidence checkpoint) async {
    final committed = File('${directory.path}/$_checkpointFileName');
    final pending = File('${directory.path}/$_pendingCheckpointFileName');
    await _rejectLink(committed.path);
    await _rejectLink(pending.path);
    if (await FileSystemEntity.type(committed.path, followLinks: false) !=
            FileSystemEntityType.notFound &&
        await FileSystemEntity.type(committed.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FileSystemException('shadow checkpoint is not a file');
    }
    await pending.create(exclusive: true);
    try {
      await pending.writeAsBytes(checkpoint.wireBytes, flush: true);
      await pending.rename(committed.path);
    } catch (_) {
      if (await FileSystemEntity.type(pending.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await pending.delete();
      }
      rethrow;
    }
  }

  Future<void> _deleteCheckpointedEvidence(
    BingxFuturesShadowEvidence checkpoint,
  ) async {
    final evidenceDirectory = Directory(
      '${directory.path}/$_evidenceDirectoryName',
    );
    await for (final entry in evidenceDirectory.list(followLinks: false)) {
      if (entry is! File) {
        throw const FormatException('invalid shadow evidence entry type');
      }
      await _rejectLink(entry.path);
      final match = RegExp(
        r'^([0-9]{12})-([0-9a-f]{64})\.json$',
      ).firstMatch(entry.uri.pathSegments.last);
      if (match == null || int.parse(match.group(1)!) > checkpoint.sequence) {
        throw const FormatException('shadow checkpoint cleanup conflict');
      }
      await entry.delete();
    }
  }

  Future<void> _clearInterruptedPendingWrite() async {
    final pendingDirectory = Directory(
      '${directory.path}/$_pendingDirectoryName',
    );
    File? interrupted;
    await for (final entry in pendingDirectory.list(followLinks: false)) {
      if (entry is! File ||
          interrupted != null ||
          !RegExp(
            r'^[0-9]{12}-[0-9a-f]{64}\.json\.pending$',
          ).hasMatch(entry.uri.pathSegments.last)) {
        throw const FormatException('invalid shadow pending evidence state');
      }
      await _rejectLink(entry.path);
      interrupted = entry;
    }
    if (interrupted != null) {
      await interrupted.delete();
    }
  }

  Future<void> _commitEvidence(BingxFuturesShadowEvidence evidence) async {
    final fileName =
        '${evidence.sequence.toString().padLeft(12, '0')}-'
        '${evidence.evidenceHashHex}.json';
    final committed = File(
      '${directory.path}/$_evidenceDirectoryName/$fileName',
    );
    final pending = File(
      '${directory.path}/$_pendingDirectoryName/$fileName.pending',
    );
    if (await FileSystemEntity.type(committed.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(pending.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FileSystemException('shadow evidence target already exists');
    }
    await pending.create(exclusive: true);
    try {
      await pending.writeAsBytes(evidence.wireBytes, flush: true);
      if (await FileSystemEntity.type(committed.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'shadow evidence target appeared during commit',
        );
      }
      await pending.rename(committed.path);
    } catch (_) {
      if (await FileSystemEntity.type(pending.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await pending.delete();
      }
      rethrow;
    }
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
