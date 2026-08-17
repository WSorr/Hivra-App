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
