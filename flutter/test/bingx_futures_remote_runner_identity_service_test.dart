import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/bingx_futures_remote_runner_identity_service.dart';

void main() {
  const service = BingxFuturesRemoteRunnerIdentityService();
  const publicKeyHex =
      '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
  const runnerKeyId =
      '56475aa75463474c0285df5dbf2bcab73da651358839e9b77481b2eab107708c';

  test('normalizes one lowercase runner key id', () {
    expect(service.normalizeRunnerKeyId('  $runnerKeyId\n'), runnerKeyId);
  });

  test('derives the canonical runner id from its public key file', () {
    expect(
      service.runnerKeyIdFromPublicKeyFile('$publicKeyHex\n'),
      runnerKeyId,
    );
  });

  test('rejects malformed and ambiguous runner identity input', () {
    expect(service.normalizeRunnerKeyId(runnerKeyId.toUpperCase()), isNull);
    expect(service.normalizeRunnerKeyId('${runnerKeyId}0'), isNull);
    expect(
      service.normalizeRunnerKeyId('g${runnerKeyId.substring(1)}'),
      isNull,
    );
    expect(
      service.runnerKeyIdFromPublicKeyFile('$publicKeyHex\n$publicKeyHex'),
      isNull,
    );
  });
}
