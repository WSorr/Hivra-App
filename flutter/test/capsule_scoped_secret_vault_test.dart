import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_scoped_secret_vault.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

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
  }) async => values[key];

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

  test('deleting a capsule removes only its secret scopes', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');

    await vault.deleteCapsule(capsuleA);

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), 'key-b');
  });

  test('deleting a plugin removes its scopes from every capsule', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');
    await _save(vault, capsuleB, pluginA, 'account-b', 'key-b');
    await _save(vault, capsuleA, pluginB, 'account-c', 'key-c');

    await vault.deletePlugin(pluginA);

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleB, pluginA, 'account-b'), isNull);
    expect(await _load(vault, capsuleA, pluginB, 'account-c'), 'key-c');
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

  test('replaces an account secret without retaining the old scope', () async {
    await _save(vault, capsuleA, pluginA, 'account-a', 'key-a');

    await vault.replaceAccountSecret(
      capsuleHex: capsuleA,
      pluginId: pluginA,
      providerId: 'moltbook',
      previousAccountId: 'account-a',
      accountId: 'account-b',
      secretName: 'api_key',
      secretValue: 'key-b',
    );

    expect(await _load(vault, capsuleA, pluginA, 'account-a'), isNull);
    expect(await _load(vault, capsuleA, pluginA, 'account-b'), 'key-b');
  });
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
