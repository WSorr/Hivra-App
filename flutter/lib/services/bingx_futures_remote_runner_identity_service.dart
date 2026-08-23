import 'package:crypto/crypto.dart';

class BingxFuturesRemoteRunnerIdentityService {
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  const BingxFuturesRemoteRunnerIdentityService();

  String? normalizeRunnerKeyId(String untrustedText) {
    final value = untrustedText.trim();
    return _hex64.hasMatch(value) ? value : null;
  }

  String? runnerKeyIdFromPublicKeyFile(String untrustedText) {
    final publicKeyHex = normalizeRunnerKeyId(untrustedText);
    if (publicKeyHex == null) return null;
    return sha256.convert(_decodeHex(publicKeyHex)).toString();
  }

  List<int> _decodeHex(String value) => List<int>.generate(
    value.length ~/ 2,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}
