import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/ffi/capsule_address_runtime.dart';
import 'package:hivra_app/models/invitation.dart';
import 'package:hivra_app/models/relationship.dart';
import 'package:hivra_app/models/starter.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/utils/hivra_id_format.dart';

class _TestUserVisibleDataDirectoryService
    extends UserVisibleDataDirectoryService {
  final Directory _root;

  const _TestUserVisibleDataDirectoryService(this._root);

  @override
  Future<Directory> rootDirectory({bool create = false}) async {
    if (create && !await _root.exists()) {
      await _root.create(recursive: true);
    }
    return _root;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDocsDir;
  late CapsuleAddressService service;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp(
      'hivra_address_service_test_',
    );
    service = CapsuleAddressService(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
    );
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
  });

  test('imports, lists, resolves and removes trusted card', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 255 - i),
    );
    final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);
    final rootHex = _toHex(rootBytes);
    final nostrHex = _toHex(nostrBytes);

    final rawCard = jsonEncode({
      'version': 1,
      'rootKey': rootKey,
      'rootHex': rootHex,
      'transports': {
        'nostr': {'npub': nostrHex, 'hex': nostrHex},
      },
    });

    await service.importCardPayload(rawCard);

    expect(await service.contactCount(), 1);

    final listed = await service.listTrustedCards();
    expect(listed.length, 1);
    expect(listed.first.rootKey, rootKey);
    expect(listed.first.rootHex, rootHex);
    expect(listed.first.nostrHex, nostrHex);

    final resolved = await service.resolveNostrRecipient(rootKey);
    expect(resolved, isNotNull);
    expect(_toHex(resolved!), nostrHex);

    expect(await service.removeTrustedCard(rootKey), isTrue);
    expect(await service.removeTrustedCard(rootKey), isFalse);
    expect(await service.contactCount(), 0);
  });

  test('throws on non-object contact card json', () async {
    expect(
      () => service.importCardJson('["invalid"]'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'imports contact card pasted with non-breaking JSON whitespace',
    () async {
      final rootBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 1),
      );
      final nostrBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => 254 - i),
      );
      final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);
      final rootHex = _toHex(rootBytes);
      final nostrHex = _toHex(nostrBytes);
      final nbsp = String.fromCharCode(0x00A0);

      final rawCard = '''
{
$nbsp$nbsp"version": 1,
$nbsp$nbsp"rootKey": "$rootKey",
$nbsp$nbsp"rootHex": "$rootHex",
$nbsp$nbsp"transports": {
$nbsp$nbsp$nbsp$nbsp"nostr": {
$nbsp$nbsp$nbsp$nbsp$nbsp$nbsp"npub": "$nostrHex",
$nbsp$nbsp$nbsp$nbsp$nbsp$nbsp"hex": "$nostrHex"
$nbsp$nbsp$nbsp$nbsp}
$nbsp$nbsp}
}
''';

      await service.importCardJson(rawCard);

      expect(await service.contactCount(), 1);
      final resolved = await service.resolveNostrRecipient(rootKey);
      expect(resolved, isNotNull);
      expect(_toHex(resolved!), nostrHex);
    },
  );

  test(
    'round trips the canonical QR envelope through card validation',
    () async {
      final rootBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 2),
      );
      final nostrBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => 252 - i),
      );
      final card = CapsuleAddressCard(
        rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
        rootHex: _toHex(rootBytes),
        nostrNpub: _toHex(nostrBytes),
        nostrHex: _toHex(nostrBytes),
      );

      await service.importCardPayload(card.toQrPayload());

      final listed = await service.listTrustedCards();
      expect(listed, hasLength(1));
      expect(listed.single.rootKey, card.rootKey);
      expect(listed.single.nostrHex, card.nostrHex);
    },
  );

  test('builds signed v2 own card when root signer is available', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 9));
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 210 - i),
    );
    final signatureBytes = Uint8List.fromList(
      List<int>.generate(64, (i) => 90 + (i % 20)),
    );
    final signedService = CapsuleAddressService(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      runtime: _FakeCapsuleAddressRuntime(
        rootPubkey: rootBytes,
        nostrPubkey: nostrBytes,
        signResult: signatureBytes,
      ),
    );

    final card = await signedService.buildOwnCard();

    expect(card, isNotNull);
    expect(card!.version, 2);
    expect(card.signatureHex, _toHex(signatureBytes));
    expect(card.toJson()['proof'], isA<Map>());
  });

  test('builds legacy v1 own card when root signer is unavailable', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 10));
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 205 - i),
    );
    final unsignedService = CapsuleAddressService(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      runtime: _FakeCapsuleAddressRuntime(
        rootPubkey: rootBytes,
        nostrPubkey: nostrBytes,
      ),
    );

    final card = await unsignedService.buildOwnCard();

    expect(card, isNotNull);
    expect(card!.version, 1);
    expect(card.signatureHex, isNull);
    expect(card.toJson().containsKey('proof'), isFalse);
  });

  test('excludes own card only from invitation recipients', () async {
    final ownRoot = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 20),
    );
    final ownNostr = Uint8List.fromList(
      List<int>.generate(32, (index) => 200 - index),
    );
    final peerRoot = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 60),
    );
    final peerNostr = Uint8List.fromList(
      List<int>.generate(32, (index) => 160 - index),
    );
    final runtimeService = CapsuleAddressService(
      dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      runtime: _FakeCapsuleAddressRuntime(rootPubkey: ownRoot),
    );

    await runtimeService.importCardJson(
      CapsuleAddressCard(
        rootKey: HivraIdFormat.formatCapsuleKeyBytes(ownRoot),
        rootHex: _toHex(ownRoot),
        nostrNpub: _toHex(ownNostr),
        nostrHex: _toHex(ownNostr),
      ).toPrettyJson(),
    );
    await runtimeService.importCardJson(
      CapsuleAddressCard(
        rootKey: HivraIdFormat.formatCapsuleKeyBytes(peerRoot),
        rootHex: _toHex(peerRoot),
        nostrNpub: _toHex(peerNostr),
        nostrHex: _toHex(peerNostr),
      ).toPrettyJson(),
    );

    expect(await runtimeService.listTrustedCards(), hasLength(2));
    final recipients = await runtimeService.listInvitationRecipients();
    expect(recipients, hasLength(1));
    expect(recipients.single.rootHex, _toHex(peerRoot));
  });

  test(
    'imports signed v2 contact card after root signature verification',
    () async {
      final rootBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 11),
      );
      final nostrBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => 200 - i),
      );
      final signatureBytes = Uint8List.fromList(
        List<int>.generate(64, (i) => 120 + (i % 40)),
      );
      final unsignedCard = CapsuleAddressCard(
        version: 2,
        rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
        rootHex: _toHex(rootBytes),
        nostrNpub: _toHex(nostrBytes),
        nostrHex: _toHex(nostrBytes),
      );
      final signedCard = CapsuleAddressCard(
        version: 2,
        rootKey: unsignedCard.rootKey,
        rootHex: unsignedCard.rootHex,
        nostrNpub: unsignedCard.nostrNpub,
        nostrHex: unsignedCard.nostrHex,
        signatureHex: _toHex(signatureBytes),
      );
      final verifyingService = CapsuleAddressService(
        dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
        runtime: _FakeCapsuleAddressRuntime(
          verifiedDigestHex: _toHex(unsignedCard.signingDigest32()),
          verifiedPubkeyHex: _toHex(rootBytes),
          verifiedSignatureHex: _toHex(signatureBytes),
        ),
      );

      await verifyingService.importCardPayload(signedCard.toQrPayload());

      expect(await verifyingService.contactCount(), 1);
      final listed = await verifyingService.listTrustedCards();
      expect(listed.single.version, 2);
      expect(listed.single.signatureHex, _toHex(signatureBytes));
    },
  );

  test('rejects signed v2 contact card when verifier is unavailable', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 13));
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 190 - i),
    );
    final card = CapsuleAddressCard(
      version: 2,
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      rootHex: _toHex(rootBytes),
      nostrNpub: _toHex(nostrBytes),
      nostrHex: _toHex(nostrBytes),
      signatureHex: 'a' * 128,
    );

    await expectLater(
      service.importCardPayload(card.toQrPayload()),
      throwsA(isA<FormatException>()),
    );
    expect(await service.contactCount(), 0);
  });

  test('rejects contact card with mismatched root representations', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 3));
    final otherRootBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => i + 4),
    );
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 240 - i),
    );
    final rawCard = jsonEncode({
      'version': 1,
      'rootKey': HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      'rootHex': _toHex(otherRootBytes),
      'transports': {
        'nostr': {'npub': _toHex(nostrBytes), 'hex': _toHex(nostrBytes)},
      },
    });

    await expectLater(
      service.importCardPayload(rawCard),
      throwsA(isA<FormatException>()),
    );
    expect(await service.contactCount(), 0);
  });

  test('rejects contact card with mismatched Nostr representations', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 5));
    final nostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 230 - i),
    );
    final otherNostrBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => 220 - i),
    );
    final rawCard = jsonEncode({
      'version': 1,
      'rootKey': HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      'rootHex': _toHex(rootBytes),
      'transports': {
        'nostr': {'npub': _toHex(nostrBytes), 'hex': _toHex(otherNostrBytes)},
      },
    });

    await expectLater(
      service.importCardPayload(rawCard),
      throwsA(isA<FormatException>()),
    );
    expect(await service.contactCount(), 0);
  });

  test('rejects contact card that routes delivery to the root key', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 11));
    final rootHex = _toHex(rootBytes);
    final rawCard = jsonEncode({
      'version': 1,
      'rootKey': HivraIdFormat.formatCapsuleKeyBytes(rootBytes),
      'rootHex': rootHex,
      'transports': {
        'nostr': {'npub': rootHex, 'hex': rootHex},
      },
    });

    await expectLater(
      service.importCardPayload(rawCard),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('root as its delivery endpoint'),
        ),
      ),
    );
    expect(await service.contactCount(), 0);
  });

  test('rejects malformed or oversized QR envelopes', () async {
    expect(
      () => CapsuleAddressCard.decodeQrPayload('hivra:card:v1:not base64'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CapsuleAddressCard.decodeQrPayload(
        '${CapsuleAddressCard.qrPayloadPrefix}${'a' * 4096}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'upserts trusted card from invitation root and transport keys',
    () async {
      final rootBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 7),
      );
      final nostrBytes = Uint8List.fromList(
        List<int>.generate(32, (i) => 180 - i),
      );
      final rootKey = HivraIdFormat.formatCapsuleKeyBytes(rootBytes);

      final saved = await service.upsertTrustedCardFromKeys(
        rootPubkey: rootBytes,
        nostrPubkey: nostrBytes,
      );

      expect(saved, isTrue);
      expect(await service.contactCount(), 1);
      final listed = await service.listTrustedCards();
      expect(listed.single.rootKey, rootKey);
      expect(listed.single.rootHex, _toHex(rootBytes));
      expect(listed.single.nostrHex, _toHex(nostrBytes));

      final resolved = await service.resolveNostrRecipient(rootKey);
      expect(resolved, isNotNull);
      expect(_toHex(resolved!), _toHex(nostrBytes));
    },
  );

  test('does not upsert trusted card from malformed key lengths', () async {
    final saved = await service.upsertTrustedCardFromKeys(
      rootPubkey: Uint8List(31),
      nostrPubkey: Uint8List(32),
    );

    expect(saved, isFalse);
    expect(await service.contactCount(), 0);
  });

  test('does not upsert a root key as its own transport endpoint', () async {
    final rootBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 13));

    final saved = await service.upsertTrustedCardFromKeys(
      rootPubkey: rootBytes,
      nostrPubkey: Uint8List.fromList(rootBytes),
    );

    expect(saved, isFalse);
    expect(await service.contactCount(), 0);
  });

  test('gracefully handles malformed cards file root shape', () async {
    final cardsFile = File('${tempDocsDir.path}/capsule_contact_cards.json');
    await cardsFile.writeAsString('["bad-root-shape"]', flush: true);

    final listed = await service.listTrustedCards();

    expect(listed, isEmpty);
    expect(await service.contactCount(), 0);
  });
  test('routing prefers cards, then relationships, then invitations', () {
    final root = Uint8List.fromList(List.filled(32, 1));
    final cardEndpoint = Uint8List.fromList(List.filled(32, 2));
    final relationshipEndpoint = Uint8List.fromList(List.filled(32, 3));
    final invitationEndpoint = Uint8List.fromList(List.filled(32, 4));
    final relationship = Relationship(
      peerPubkey: base64Encode(relationshipEndpoint),
      peerRootPubkey: base64Encode(root),
      kind: StarterKind.juice,
      ownStarterId: '',
      peerStarterId: '',
      establishedAt: DateTime.utc(2026),
    );
    final invitation = Invitation(
      id: 'routing',
      fromPubkey: base64Encode(invitationEndpoint),
      fromRootPubkey: base64Encode(root),
      kind: StarterKind.juice,
      status: InvitationStatus.accepted,
      sentAt: DateTime.utc(2026),
    );
    final card = CapsuleAddressCard(
      rootKey: HivraIdFormat.formatCapsuleKeyBytes(root),
      rootHex: _toHex(root),
      nostrNpub: HivraIdFormat.formatNostrKeyBytes(cardEndpoint),
      nostrHex: _toHex(cardEndpoint),
    );
    final index = service.peerIdentityIndex(
      relationships: [relationship],
      invitations: [invitation],
      cards: [card],
    );
    expect(index.resolveTransportForSend(_toHex(root)), _toHex(cardEndpoint));
    for (final endpoint in [
      cardEndpoint,
      relationshipEndpoint,
      invitationEndpoint,
    ]) {
      expect(index.resolveConsensusForIncoming(_toHex(endpoint)), _toHex(root));
    }
    expect(
      service
          .peerIdentityIndex(
            relationships: [relationship],
            invitations: [invitation],
            cards: [],
          )
          .resolveTransportForSend(_toHex(root)),
      _toHex(relationshipEndpoint),
    );
    expect(
      service
          .peerIdentityIndex(
            relationships: [],
            invitations: [invitation],
            cards: [],
          )
          .resolveTransportForSend(_toHex(root)),
      _toHex(invitationEndpoint),
    );
  });

  test(
    'concurrent imports and cleanup through separate instances retain updates',
    () async {
      Future<bool> upsert(int i) => CapsuleAddressService(
        dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      ).upsertTrustedCardFromKeys(
        rootPubkey: Uint8List.fromList(List.filled(32, i + 1)),
        nostrPubkey: Uint8List.fromList(List.filled(32, i + 65)),
      );
      await Future.wait(List.generate(16, upsert));
      expect(await service.contactCount(), 16);
      await Future.wait<void>([
        for (var i = 0; i < 8; i++)
          service.removeCapsuleReferences(
            _toHex(Uint8List.fromList(List.filled(32, i + 1))),
          ),
        for (var i = 16; i < 24; i++) upsert(i).then((_) {}),
      ]);
      final reopened = CapsuleAddressService(
        dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
      );
      expect(
        (await reopened.listTrustedCards()).map((c) => c.rootHex).toSet(),
        {
          for (var i = 8; i < 24; i++)
            _toHex(Uint8List.fromList(List.filled(32, i + 1))),
        },
      );
    },
  );

  for (final invalid in [
    '{broken',
    '["retained-card-evidence"]',
    'null',
    'true',
    '42',
    '"retained-card-evidence"',
  ]) {
    test(
      'failed card mutation preserves bytes and permits retry ($invalid)',
      () async {
        final file = File('${tempDocsDir.path}/capsule_contact_cards.json');
        await file.writeAsString(invalid);
        final retained = await file.readAsBytes();
        final root = Uint8List.fromList(List.filled(32, 1));
        final endpoint = Uint8List.fromList(List.filled(32, 2));
        final rootKey = HivraIdFormat.formatCapsuleKeyBytes(root);
        final reopened = CapsuleAddressService(
          dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
        );
        final cardJson = jsonEncode(
          CapsuleAddressCard(
            rootKey: rootKey,
            rootHex: _toHex(root),
            nostrNpub: _toHex(endpoint),
            nostrHex: _toHex(endpoint),
          ).toJson(),
        );
        for (final mutate in <Future<dynamic> Function()>[
          () => service.importCardPayload(cardJson),
          () => service.upsertTrustedCardFromKeys(
            rootPubkey: root,
            nostrPubkey: endpoint,
          ),
          () => reopened.removeTrustedCard(rootKey),
          () => reopened.removeCapsuleReferences(_toHex(root)),
        ]) {
          await expectLater(mutate(), throwsFormatException);
          expect(await file.readAsBytes(), retained);
        }
        // An external repair is observed on the next operation. Failed work in
        // another instance must not poison the existing per-file mutation queue.
        await file.writeAsString('{}');
        await Future.wait([
          service.upsertTrustedCardFromKeys(
            rootPubkey: root,
            nostrPubkey: endpoint,
          ),
          reopened.upsertTrustedCardFromKeys(
            rootPubkey: Uint8List.fromList(List.filled(32, 3)),
            nostrPubkey: Uint8List.fromList(List.filled(32, 4)),
          ),
        ]);
        expect(await reopened.contactCount(), 2);
      },
    );
  }

  test(
    'local key synchronization preserves a signed card for matching keys',
    () async {
      final root = Uint8List.fromList(List.filled(32, 1));
      final endpoint = Uint8List.fromList(List.filled(32, 2));
      final signature = _toHex(Uint8List.fromList(List.filled(64, 3)));
      final card = CapsuleAddressCard(
        version: 2,
        rootKey: HivraIdFormat.formatCapsuleKeyBytes(root),
        rootHex: _toHex(root),
        nostrNpub: HivraIdFormat.formatNostrKeyBytes(endpoint),
        nostrHex: _toHex(endpoint),
        signatureHex: signature,
      );
      final signed = CapsuleAddressService(
        dirs: _TestUserVisibleDataDirectoryService(tempDocsDir),
        runtime: _FakeCapsuleAddressRuntime(
          verifiedDigestHex: _toHex(card.signingDigest32()),
          verifiedPubkeyHex: _toHex(root),
          verifiedSignatureHex: signature,
        ),
      );
      await signed.importCardJson(card.toPrettyJson());
      await service.upsertTrustedCardFromKeys(
        rootPubkey: root,
        nostrPubkey: endpoint,
      );
      expect((await service.listTrustedCards()).single.signatureHex, signature);
    },
  );
}

String _toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

class _FakeCapsuleAddressRuntime implements CapsuleAddressRuntime {
  final Uint8List? rootPubkey;
  final Uint8List? nostrPubkey;
  final Uint8List? signResult;
  final String? verifiedDigestHex;
  final String? verifiedPubkeyHex;
  final String? verifiedSignatureHex;

  const _FakeCapsuleAddressRuntime({
    this.rootPubkey,
    this.nostrPubkey,
    this.signResult,
    this.verifiedDigestHex,
    this.verifiedPubkeyHex,
    this.verifiedSignatureHex,
  });

  @override
  Uint8List? capsuleRootPublicKey() => rootPubkey;

  @override
  Uint8List? capsuleNostrPublicKey() => nostrPubkey;

  @override
  Uint8List? signRootDigest32(Uint8List message32) => signResult;

  @override
  bool verifyRootDigest32({
    required Uint8List message32,
    required Uint8List pubkey32,
    required Uint8List signature64,
  }) {
    return _toHex(message32) == verifiedDigestHex &&
        _toHex(pubkey32) == verifiedPubkeyHex &&
        _toHex(signature64) == verifiedSignatureHex;
  }
}
