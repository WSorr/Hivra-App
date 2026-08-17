import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_deterministic_replay_harness_service.dart';
import 'package:hivra_app/services/bingx_futures_shadow_stream_store.dart';

const _emptyEvidenceHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

void main() {
  group('BingxFuturesShadowStreamStore', () {
    late Directory temp;
    late SimpleKeyPair signingKey;
    late SimplePublicKey publicKey;
    late BingxFuturesShadowEvidenceProducer produce;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('hivra-shadow-stream-');
      signingKey = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));
      publicKey = await signingKey.extractPublicKey();
      produce =
          (sequence, previousHash) =>
              _evidence(sequence, previousHash, signingKey, publicKey);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('continues one authenticated immutable chain after restart', () async {
      final firstStore = BingxFuturesShadowStreamStore(directory: temp);
      final first = await firstStore.append(
        trustedRunnerKey: publicKey,
        produce: produce,
      );
      final restartedStore = BingxFuturesShadowStreamStore(directory: temp);
      final second = await restartedStore.append(
        trustedRunnerKey: publicKey,
        produce: produce,
      );

      expect(first.sequence, 1);
      expect(first.previousEvidenceHashHex, _emptyEvidenceHash);
      expect(second.sequence, 2);
      expect(second.previousEvidenceHashHex, first.evidenceHashHex);
      expect(await _evidenceFiles(temp), hasLength(2));
    });

    test('commits a flushed pending identity after restart', () async {
      await _prepareEmptyStream(temp);
      const owner = BingxFuturesDeterministicReplayHarnessService();
      final runnerKeyId = owner.runnerKeyId(publicKey);
      final pending = File('${temp.path}/stream_identity.v1.json.pending');
      await pending.writeAsString(
        '{"schema_version":1,"runner_key_id":"$runnerKeyId"}',
        flush: true,
      );

      final evidence = await BingxFuturesShadowStreamStore(
        directory: temp,
      ).append(trustedRunnerKey: publicKey, produce: produce);

      expect(evidence.sequence, 1);
      expect(await pending.exists(), isFalse);
      expect(
        await File('${temp.path}/stream_identity.v1.json').exists(),
        isTrue,
      );
    });

    test('replaces only a malformed uncommitted identity', () async {
      await _prepareEmptyStream(temp);
      final pending = File('${temp.path}/stream_identity.v1.json.pending');
      await pending.writeAsString('{partial', flush: true);

      final evidence = await BingxFuturesShadowStreamStore(
        directory: temp,
      ).append(trustedRunnerKey: publicKey, produce: produce);

      expect(evidence.sequence, 1);
      expect(await pending.exists(), isFalse);
      expect(
        await File('${temp.path}/stream_identity.v1.json').exists(),
        isTrue,
      );
    });

    test('preserves a pending identity bound to another runner', () async {
      await _prepareEmptyStream(temp);
      final otherSigningKey = await Ed25519().newKeyPairFromSeed(
        List<int>.filled(32, 8),
      );
      final otherPublicKey = await otherSigningKey.extractPublicKey();
      const owner = BingxFuturesDeterministicReplayHarnessService();
      final pending = File('${temp.path}/stream_identity.v1.json.pending');
      await pending.writeAsString(
        '{"schema_version":1,"runner_key_id":"${owner.runnerKeyId(otherPublicKey)}"}',
        flush: true,
      );
      var produced = false;

      await expectLater(
        BingxFuturesShadowStreamStore(directory: temp).append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );

      expect(produced, isFalse);
      expect(await pending.exists(), isTrue);
    });

    test('preserves malformed committed identity and fails closed', () async {
      await _prepareEmptyStream(temp);
      final identity = File('${temp.path}/stream_identity.v1.json');
      await identity.writeAsString('{}', flush: true);
      var produced = false;

      await expectLater(
        BingxFuturesShadowStreamStore(directory: temp).append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );

      expect(produced, isFalse);
      expect(await identity.readAsString(), '{}');
    });

    test('preserves ambiguous committed and pending identities', () async {
      await _prepareEmptyStream(temp);
      const owner = BingxFuturesDeterministicReplayHarnessService();
      final runnerKeyId = owner.runnerKeyId(publicKey);
      final encoded = '{"schema_version":1,"runner_key_id":"$runnerKeyId"}';
      final identity = File('${temp.path}/stream_identity.v1.json');
      final pending = File('${temp.path}/stream_identity.v1.json.pending');
      await identity.writeAsString(encoded, flush: true);
      await pending.writeAsString(encoded, flush: true);
      var produced = false;

      await expectLater(
        BingxFuturesShadowStreamStore(directory: temp).append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );

      expect(produced, isFalse);
      expect(await identity.readAsString(), encoded);
      expect(await pending.readAsString(), encoded);
    });

    test('does not bind an identity over existing unbound state', () async {
      await _prepareEmptyStream(temp);
      final retained = File('${temp.path}/evidence/unbound.json');
      await retained.writeAsString('existing', flush: true);
      var produced = false;

      await expectLater(
        BingxFuturesShadowStreamStore(directory: temp).append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );

      expect(produced, isFalse);
      expect(await retained.readAsString(), 'existing');
      expect(
        await File('${temp.path}/stream_identity.v1.json').exists(),
        isFalse,
      );
    });

    test(
      'serializes concurrent append attempts into distinct sequences',
      () async {
        final firstStore = BingxFuturesShadowStreamStore(directory: temp);
        final secondStore = BingxFuturesShadowStreamStore(directory: temp);
        final results = await Future.wait(<Future<BingxFuturesShadowEvidence>>[
          firstStore.append(trustedRunnerKey: publicKey, produce: produce),
          secondStore.append(trustedRunnerKey: publicKey, produce: produce),
        ]);

        expect(results.map((item) => item.sequence).toSet(), <int>{1, 2});
        expect(await _evidenceFiles(temp), hasLength(2));
      },
    );

    test('serializes independent processes into one chain', () async {
      final first = await Process.start('dart', <String>[
        'run',
        'test/support/bingx_shadow_stream_append_process.dart',
        temp.path,
      ]);
      final second = await Process.start('dart', <String>[
        'run',
        'test/support/bingx_shadow_stream_append_process.dart',
        temp.path,
      ]);
      final exits = await Future.wait(<Future<int>>[
        first.exitCode,
        second.exitCode,
      ]);

      expect(exits, <int>[0, 0]);
      expect(await _evidenceFiles(temp), hasLength(2));
      final restarted = BingxFuturesShadowStreamStore(directory: temp);
      final third = await restarted.append(
        trustedRunnerKey: publicKey,
        produce: produce,
      );
      expect(third.sequence, 3);
    });

    test('fails closed after the bounded lock budget', () async {
      final ready = File('${temp.path}.lock-ready');
      final holder = await Process.start('dart', <String>[
        'run',
        'test/support/bingx_shadow_stream_lock_holder.dart',
        temp.path,
        ready.path,
      ]);
      try {
        for (
          var attempt = 0;
          attempt < 100 && !await ready.exists();
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(await ready.exists(), isTrue);
        final store = BingxFuturesShadowStreamStore(directory: temp);
        await expectLater(
          store.append(trustedRunnerKey: publicKey, produce: produce),
          throwsA(isA<FileSystemException>()),
        );
        expect(await _evidenceFiles(temp), isEmpty);
      } finally {
        await holder.exitCode;
        if (await ready.exists()) await ready.delete();
      }
    });

    test('rejects key confusion before producing evidence', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      final otherSigningKey = await Ed25519().newKeyPairFromSeed(
        List<int>.filled(32, 8),
      );
      final otherPublicKey = await otherSigningKey.extractPublicKey();
      var produced = false;

      await expectLater(
        store.append(
          trustedRunnerKey: otherPublicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return _evidence(
              sequence,
              previousHash,
              otherSigningKey,
              otherPublicKey,
            );
          },
        ),
        throwsFormatException,
      );
      expect(produced, isFalse);
      expect(await _evidenceFiles(temp), hasLength(1));
    });

    test('fails closed on truncated retained evidence', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      final retained = (await _evidenceFiles(temp)).single;
      await retained.writeAsString('', flush: true);
      var produced = false;

      await expectLater(
        store.append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );
      expect(produced, isFalse);
    });

    test('fails closed on retained signature mutation', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      final retained = (await _evidenceFiles(temp)).single;
      final raw = await retained.readAsString();
      await retained.writeAsString(
        raw.replaceFirst('"signature_hex":"', '"signature_hex":"00'),
        flush: true,
      );

      await expectLater(
        store.append(trustedRunnerKey: publicKey, produce: produce),
        throwsFormatException,
      );
    });

    test('discards one interrupted pending write before continuing', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      final first = await store.append(
        trustedRunnerKey: publicKey,
        produce: produce,
      );
      final pendingDirectory = Directory('${temp.path}/pending');
      final interrupted = File(
        '${pendingDirectory.path}/000000000002-${'f' * 64}.json.pending',
      );
      await interrupted.writeAsString('{partial', flush: true);

      final second = await BingxFuturesShadowStreamStore(
        directory: temp,
      ).append(trustedRunnerKey: publicKey, produce: produce);

      expect(second.sequence, 2);
      expect(second.previousEvidenceHashHex, first.evidenceHashHex);
      expect(await pendingDirectory.list().toList(), isEmpty);
      expect(await _evidenceFiles(temp), hasLength(2));
    });

    test('fails closed without deleting unknown pending state', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      final unknown = File('${temp.path}/pending/not-a-prepared-write');
      await unknown.writeAsString('unknown', flush: true);
      var produced = false;

      await expectLater(
        store.append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) async {
            produced = true;
            return produce(sequence, previousHash);
          },
        ),
        throwsFormatException,
      );
      expect(produced, isFalse);
      expect(await unknown.readAsString(), 'unknown');
    });

    test('fails closed without deleting multiple pending writes', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      final pendingDirectory = Directory('${temp.path}/pending');
      final first = File(
        '${pendingDirectory.path}/000000000002-${'a' * 64}.json.pending',
      );
      final second = File(
        '${pendingDirectory.path}/000000000002-${'b' * 64}.json.pending',
      );
      await first.writeAsString('first', flush: true);
      await second.writeAsString('second', flush: true);

      await expectLater(
        store.append(trustedRunnerKey: publicKey, produce: produce),
        throwsFormatException,
      );
      expect(await first.readAsString(), 'first');
      expect(await second.readAsString(), 'second');
    });

    test(
      'never overwrites a committed target that appears before commit',
      () async {
        final store = BingxFuturesShadowStreamStore(directory: temp);
        late File conflict;

        await expectLater(
          store.append(
            trustedRunnerKey: publicKey,
            produce: (sequence, previousHash) async {
              final evidence = await produce(sequence, previousHash);
              conflict = File(
                '${temp.path}/evidence/'
                '${sequence.toString().padLeft(12, '0')}-'
                '${evidence.evidenceHashHex}.json',
              );
              await conflict.writeAsString('existing', flush: true);
              return evidence;
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await conflict.readAsString(), 'existing');
        expect(
          await Directory('${temp.path}/pending').list().toList(),
          isEmpty,
        );
      },
    );

    test('rejects producer sequence and predecessor conflicts', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);

      await expectLater(
        store.append(
          trustedRunnerKey: publicKey,
          produce:
              (sequence, previousHash) => produce(sequence + 1, previousHash),
        ),
        throwsFormatException,
      );
      expect(await _evidenceFiles(temp), isEmpty);
    });

    test('leaves no evidence when observation fails', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);

      await expectLater(
        store.append(
          trustedRunnerKey: publicKey,
          produce: (sequence, previousHash) => throw StateError('timeout'),
        ),
        throwsStateError,
      );
      expect(await _evidenceFiles(temp), isEmpty);
    });

    test('rejects unknown stream entries', () async {
      final store = BingxFuturesShadowStreamStore(directory: temp);
      await store.append(trustedRunnerKey: publicKey, produce: produce);
      await File('${temp.path}/unexpected').writeAsString('data');

      await expectLater(
        store.append(trustedRunnerKey: publicKey, produce: produce),
        throwsFormatException,
      );
    });

    test(
      'fails closed at bounded capacity without deleting evidence',
      () async {
        final store = BingxFuturesShadowStreamStore(directory: temp);
        var latest = await store.append(
          trustedRunnerKey: publicKey,
          produce: produce,
        );
        final evidenceDirectory = Directory('${temp.path}/evidence');
        for (
          var sequence = 2;
          sequence <= BingxFuturesShadowStreamStore.maxEntries;
          sequence++
        ) {
          latest = await produce(sequence, latest.evidenceHashHex);
          final file = File(
            '${evidenceDirectory.path}/'
            '${sequence.toString().padLeft(12, '0')}-'
            '${latest.evidenceHashHex}.json',
          );
          await file.writeAsBytes(latest.wireBytes, flush: true);
        }
        var produced = false;

        await expectLater(
          store.append(
            trustedRunnerKey: publicKey,
            produce: (sequence, previousHash) async {
              produced = true;
              return produce(sequence, previousHash);
            },
          ),
          throwsStateError,
        );
        expect(produced, isFalse);
        expect(
          await _evidenceFiles(temp),
          hasLength(BingxFuturesShadowStreamStore.maxEntries),
        );
      },
    );
  });
}

Future<void> _prepareEmptyStream(Directory directory) async {
  await Directory('${directory.path}/evidence').create();
  await Directory('${directory.path}/pending').create();
}

Future<BingxFuturesShadowEvidence> _evidence(
  int sequence,
  String previousEvidenceHashHex,
  SimpleKeyPair signingKey,
  SimplePublicKey publicKey,
) async {
  const owner = BingxFuturesDeterministicReplayHarnessService();
  final unsigned = BingxFuturesShadowEvidence(
    runnerBuildId: 'runner-build-test',
    pluginId: 'hivra.bingx-futures-trading',
    pluginVersion: '0.2.7-plugins',
    packageDigestHex: '1' * 64,
    hostAbi: 'dart-headless-v1',
    policyHashHex: '2' * 64,
    marketSnapshotHashHex: '3' * 64,
    featureHashHex: '4' * 64,
    decisionHashHex: '5' * 64,
    decision: 'long',
    observedAtEpochMs: 1770000000000 + sequence,
    validUntilEpochMs: 1770000060000 + sequence,
    sequence: sequence,
    previousEvidenceHashHex: previousEvidenceHashHex,
    runnerKeyId: owner.runnerKeyId(publicKey),
  );
  final signature = await Ed25519().sign(
    unsigned.signingPayload,
    keyPair: signingKey,
  );
  return unsigned.withSignature(_encodeHex(signature.bytes));
}

String _encodeHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

Future<List<File>> _evidenceFiles(Directory root) async {
  final evidenceDirectory = Directory('${root.path}/evidence');
  if (!await evidenceDirectory.exists()) return <File>[];
  return evidenceDirectory
      .list()
      .where((entry) => entry is File)
      .cast<File>()
      .toList();
}
