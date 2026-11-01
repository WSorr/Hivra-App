import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  int writes = 0;
  bool failWrite = false;
  Future<void> Function()? beforeRead;

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
    if (failWrite) throw StateError('Keychain unavailable');
    writes++;
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
    await beforeRead?.call();
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

void main() {
  const capsuleA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const capsuleB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const pluginA = 'hivra.contract.moltbook-ambassador.v1';
  const pluginB = 'hivra.contract.other.v1';

  late _FakeSecureStorage storage;
  late CapsuleScopedSecretVault vault;

  setUp(() {
    storage = _FakeSecureStorage();
    vault = CapsuleScopedSecretVault(secureStorage: storage);
  });

  test('isolates secrets by capsule plugin provider and account', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-a', 'key-b');
    await _save(vault, capsuleA, pluginB, 'account-a', 'key-c');

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), 'key-a');
    expect(await _load(vault, capsuleB, pluginA, 'account-a'), 'key-b');
    expect(await _load(vault, capsuleA, pluginB, 'account-a'), 'key-c');
    expect(storage.values.length, 1);
    expect(storage.values.values.single, isNot(contains('plaintext_file')));
  });

  test(
    'owner selects metadata references without exposing values or another Capsule',
    () async {
      await _save(vault, capsuleA, pluginA, 'account-a', 'secret-a');
      await _save(vault, capsuleB, pluginB, 'account-b', 'secret-b');
      final references = await vault.listReferences(capsuleA);
      expect(references.length, 1);
      expect(jsonEncode(references), isNot(contains('secret-a')));
      expect(
        await vault.resolveReferences(capsuleA, {
          'token': references.single['id']!,
        }),
        {'token': 'secret-a'},
      );
      await expectLater(
        vault.resolveReferences(capsuleB, {'token': references.single['id']!}),
        throwsStateError,
      );
      await vault.deleteCapsule(capsuleA);
      await expectLater(
        vault.resolveReferences(capsuleA, {'token': references.single['id']!}),
        throwsStateError,
      );
    },
  );

  test('deleting a capsule removes only its secret scopes', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');

    await vault.deleteCapsule(capsuleA);

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), 'key-b');
  });

  test('plugin removal is limited to capsules owned by this runtime', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');
    await _save(vault, capsuleA, pluginB, 'account-c', 'key-c');

    await vault.deletePlugin(pluginA, capsuleHexes: {capsuleA});

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), 'key-b');
    expect(await _load(vault, capsuleA, pluginB, 'account-c'), 'key-c');
  });

  test(
    'plugin removal without runtime capsules does not touch Keychain',
    () async {
      await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');
      final before = Map<String, String>.from(storage.values);
      await vault.deletePlugin(pluginA, capsuleHexes: {});
      expect(storage.values, before);
      expect(await _load(vault, capsuleB, pluginA, 'account-b'), 'key-b');
    },
  );

  test('plugin removal covers inactive capsules in the same runtime', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');
    await _save(vault, capsuleB, pluginB, 'account-c', 'key-c');
    await vault.deletePlugin(pluginA, capsuleHexes: {capsuleA, capsuleB});
    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), isNull);
    expect(await _load(vault, capsuleB, pluginB, 'account-c'), 'key-c');
  });

  test('fails closed on malformed persisted vault', () async {
    storage.values['hivra.capsule_scoped_secrets.v1'] = jsonEncode(
      <String, dynamic>{'schema_version': 99, 'entries': <dynamic>[]},
    );
    vault = CapsuleScopedSecretVault(secureStorage: storage);

    await expectLater(
      _load(vault, capsuleA, pluginA, 'account-a'),
      throwsA(isA<StateError>()),
    );
  });

  test('serializes concurrent updates without losing a scope', () async {
    await Future.wait(<Future<void>>[
      _save(vault, capsuleA, pluginA, 'account-a', 'key-a'),
      _save(vault, capsuleB, pluginA, 'account-b', 'key-b'),
    ]);

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), 'key-a');
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), 'key-b');
  });

  test(
    'owner adds labelled references atomically alongside legacy entries',
    () async {
      await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
      final before = storage.writes;
      final references = await vault.addReferences(
        capsuleHex: capsuleA,
        pluginId: pluginA,
        secrets: [
          {'label': 'Personal connection', 'value': 'new-token'},
          {'label': 'Signing key', 'value': 'new-key'},
        ],
      );
      expect(storage.writes - before, 1);
      expect(references.map((r) => r['id']).toSet().length, 2);
      expect(jsonEncode(references), isNot(contains('new-token')));
      vault = CapsuleScopedSecretVault(secureStorage: storage);
      expect(await vault.listReferences(capsuleA), containsAll(references));
      expect(await vault.listReferences(capsuleB), isEmpty);
      expect(
        await vault.resolveReferences(capsuleA, {
          'token': references[0]['id']!,
          'key': references[1]['id']!,
        }),
        {'token': 'new-token', 'key': 'new-key'},
      );
      expect(await _load(vault, capsuleA, pluginA, 'account-a'), 'key-a');
    },
  );

  test('failed native storage write returns no usable reference', () async {
    storage.failWrite = true;
    await expectLater(
      vault.addReferences(
        capsuleHex: capsuleA,
        pluginId: pluginA,
        secrets: [
          {'label': 'Connection', 'value': 'test-token'},
        ],
      ),
      throwsStateError,
    );
    storage.failWrite = false;
    expect(await vault.listReferences(capsuleA), isEmpty);
  });
  test(
    'a changed Capsule or package during native unlock prevents a write',
    () async {
      final entered = Completer<void>(), unlocked = Completer<void>();
      storage.beforeRead = () async {
        entered.complete();
        await unlocked.future;
      };
      var stillAuthorized = true;
      final saving = vault.addReferences(
        capsuleHex: capsuleA,
        pluginId: pluginA,
        secrets: [
          {'label': 'Connection', 'value': 'test-token'},
        ],
        authorize: () async {
          if (!stillAuthorized) throw StateError('Capsule or package changed');
        },
      );
      await entered.future;
      stillAuthorized = false;
      final rejected = expectLater(saving, throwsStateError);
      unlocked.complete();
      await rejected;
      expect(storage.writes, 0);
      storage.beforeRead = null;
      expect(await vault.listReferences(capsuleA), isEmpty);
    },
  );
}

Future<void> _save(
  CapsuleScopedSecretVault vault,
  String capsule,
  String plugin,
  String account,
  String value,
) {
  return vault.saveSecret(
    capsuleHex: capsule,
    pluginId: plugin,
    providerId: 'moltbook',
    accountId: account,
    secretName: 'api_key',
    secretValue: value,
  );
}

Future<String?> _load(
  CapsuleScopedSecretVault vault,
  String capsule,
  String plugin,
  String account,
) {
  return vault.loadSecret(
    capsuleHex: capsule,
    pluginId: plugin,
    providerId: 'moltbook',
    accountId: account,
    secretName: 'api_key',
  );
}
