import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/capsule_diagnostics_service.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';

void main() {
  test('combines bootstrap and trace diagnostics behind one boundary',
      () async {
    var bootstrapCalls = 0;
    var traceCalls = 0;
    final bootstrap = CapsuleBootstrapReport(
      activePubKeyHex: 'active',
      runtimePubKeyHex: 'runtime',
      rootPubKeyHex: 'root',
      nostrPubKeyHex: 'nostr',
      identityMode: 'root_owner',
      bootstrapSource: 'ledger',
      seedAvailable: true,
      seedMatchesActiveCapsule: true,
      rootMatchesActiveCapsule: true,
      nostrMatchesActiveCapsule: false,
      runtimeMatchesRoot: true,
      runtimeMatchesNostr: false,
      stateFileExists: true,
      ledgerFileExists: true,
      backupFileExists: true,
      workerBootstrapAvailable: true,
      ledgerImportable: true,
      issue: null,
    );
    final trace = CapsuleTraceReport(
      activePubKeyHex: 'active',
      runtimePubKeyHex: 'runtime',
      runtimeSeedExists: true,
      indexHasEntry: true,
      secureSeedExists: true,
      fallbackSeedExists: false,
      capsuleDirPath: '/tmp/capsule',
      capsuleDirExists: true,
      ledgerFileExists: true,
      stateFileExists: true,
      backupFileExists: true,
      legacyDocsPath: '/tmp/docs',
      legacyLedgerExists: false,
      legacyStateExists: false,
      legacyBackupExists: false,
    );

    final service = CapsuleDiagnosticsService(
      diagnoseBootstrap: () async {
        bootstrapCalls += 1;
        return bootstrap;
      },
      diagnoseTrace: () async {
        traceCalls += 1;
        return trace;
      },
    );

    final report = await service.inspect();

    expect(report.bootstrap, same(bootstrap));
    expect(report.trace, same(trace));
    expect(bootstrapCalls, 1);
    expect(traceCalls, 1);
  });
}
