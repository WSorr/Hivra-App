import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/models/wasm_plugin_models.dart';
import 'package:hivra_app/services/ai_capsule_inspection_service.dart';
import 'package:hivra_app/services/ai_doctor_prompt_service.dart';
import 'package:hivra_app/services/consensus_runtime_service.dart';
import 'package:hivra_app/services/capsule_diagnostics_service.dart';
import 'package:hivra_app/services/capsule_persistence_models.dart';
import 'package:hivra_app/services/delivery_outbox_store.dart';
import 'package:hivra_app/services/ledger_view_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';

void main() {
  group('AiCapsuleInspectionService', () {
    test(
      'builds deterministic local snapshot without provider upload',
      () async {
        final service = _inspectionService(_fakeDiagnosticsService());

        final first = await service.inspect();
        final second = await service.inspect();

        expect(first.snapshot.snapshotHashHex, second.snapshot.snapshotHashHex);
        expect(first.snapshot.redaction['provider_upload'], isFalse);
        expect(first.snapshot.ledgerSummary['has_history'], isTrue);
        expect(first.snapshot.pluginSummary['installed_count'], equals(1));
        expect(first.snapshot.transportSummary['pending_count'], 1);
        expect(first.snapshot.transportSummary['quarantined_count'], 1);
        expect(
          first.findings.map((finding) => finding.area),
          contains('transport'),
        );
      },
    );

    test('warns when capsule has no ledger history', () async {
      final owner = List<int>.filled(32, 0xbb);
      final service = AiCapsuleInspectionService(
        ledgerView: LedgerViewService.withSources(
          exportLedger:
              () => jsonEncode(<String, dynamic>{
                'owner': owner,
                'events': <Map<String, dynamic>>[],
                'last_hash': '0',
              }),
          exportCapsuleState:
              () => jsonEncode(<String, dynamic>{
                'public_key': owner,
                'version': 0,
                'ledger_hash': '0',
                'slots': <Object?>[null, null, null, null, null],
              }),
          readRuntimeOwnerPublicKey: () => Uint8List.fromList(owner),
        ),
        consensus: ConsensusRuntimeService(
          exportLedger: () => null,
          readLocalTransportKey: () => null,
          readLocalRootKey: () => Uint8List.fromList(owner),
        ),
        diagnostics: _fakeDiagnosticsService(),
        outbox: _FakeOutboxStore(items: const <DeliveryOutboxItem>[]),
        plugins: const _FakePluginRegistryService(
          records: <WasmPluginRecord>[],
        ),
        readActiveCapsuleHex: () => 'bb' * 32,
      );

      final report = await service.inspect();

      expect(report.snapshot.ledgerSummary['has_history'], isFalse);
      expect(
        report.findings.any((finding) => finding.area == 'ledger'),
        isTrue,
      );
      expect(report.statusLabel, equals('Needs attention'));
    });

    for (final failingSection in ['bootstrap', 'trace']) {
      test(
        '$failingSection failure retains other observations without fabricated checks',
        () async {
          final baseline = await _fakeDiagnosticsService().inspect();
          final diagnostics = CapsuleDiagnosticsService(
            diagnoseBootstrap: () async {
              if (failingSection == 'bootstrap') {
                throw StateError(
                  'Keychain private-token /Users/private-person',
                );
              }
              return baseline.bootstrap!;
            },
            diagnoseTrace: () async {
              if (failingSection == 'trace') {
                throw StateError(
                  'SocketException private-token /Users/private-person',
                );
              }
              return baseline.trace!;
            },
          );
          final report = await _inspectionService(diagnostics).inspect();
          final failed =
              failingSection == 'bootstrap'
                  ? report.snapshot.bootstrapSummary
                  : report.snapshot.traceSummary;
          final retained =
              failingSection == 'bootstrap'
                  ? report.snapshot.traceSummary
                  : report.snapshot.bootstrapSummary;
          expect(failed['available'], false);
          expect(failed.containsKey('seed_available'), false);
          expect(failed.containsKey('issue_count'), false);
          expect(retained['available'], true);
          expect(retained['ledger_file_exists'], true);
          expect(report.statusLabel, 'Needs attention');
          final prompt = const AiDoctorPromptService().buildPrompt(
            snapshot: report.snapshot,
            userQuery: 'check',
          );
          expect(prompt.inputJson, isNot(contains('private-token')));
          expect(prompt.inputJson, isNot(contains('/Users/private-person')));
          final context = (prompt.payload as Map)['context'] as Map;
          expect(
            context['${failingSection == 'bootstrap' ? 'bootstrap' : 'trace'}_summary']['available'],
            false,
          );
          expect(
            context['${failingSection == 'bootstrap' ? 'bootstrap' : 'trace'}_summary']['error_codes'],
            [
              failingSection == 'bootstrap'
                  ? 'secure_storage_unavailable'
                  : 'network_unavailable',
            ],
          );
        },
      );
    }
    test(
      'missing diagnostic capability is unknown rather than missing files or seeds',
      () async {
        final report = await _inspectionService(null).inspect();
        expect(report.snapshot.bootstrapSummary['available'], false);
        expect(report.snapshot.traceSummary['available'], false);
        expect(report.snapshot.traceSummary.containsKey('issue_count'), false);
        expect(
          report.findings
              .where((f) => f.severity == 'warning')
              .map((f) => f.area),
          containsAll(['bootstrap', 'trace']),
        );
      },
    );
  });
}

AiCapsuleInspectionService _inspectionService(
  CapsuleDiagnosticsService? diagnostics,
) {
  final owner = List<int>.filled(32, 0xaa);
  return AiCapsuleInspectionService(
    ledgerView: LedgerViewService.withSources(
      exportLedger:
          () => jsonEncode(<String, dynamic>{
            'owner': owner,
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 'CapsuleCreated',
                'payload': <int>[1, 1],
                'timestamp': 1891000000000,
                'signer': owner,
              },
            ],
            'last_hash': 'abc123',
          }),
      exportCapsuleState:
          () => jsonEncode(<String, dynamic>{
            'public_key': owner,
            'version': 1,
            'ledger_hash': 'abc123',
            'slots': <Object?>[null, null, null, null, null],
          }),
      readRuntimeOwnerPublicKey: () => Uint8List.fromList(owner),
    ),
    consensus: ConsensusRuntimeService(
      exportLedger:
          () => jsonEncode(<String, dynamic>{
            'owner': owner,
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'kind': 'CapsuleCreated',
                'payload': <int>[1, 1],
                'timestamp': 1891000000000,
                'signer': owner,
              },
            ],
            'last_hash': 'abc123',
          }),
      readLocalTransportKey: () => null,
      readLocalRootKey: () => Uint8List.fromList(owner),
    ),
    diagnostics: diagnostics,
    outbox: _FakeOutboxStore(),
    plugins: const _FakePluginRegistryService(),
    readActiveCapsuleHex: () => 'aa' * 32,
  );
}

CapsuleDiagnosticsService _fakeDiagnosticsService() {
  return CapsuleDiagnosticsService(
    diagnoseBootstrap:
        () async => CapsuleBootstrapReport(
          activePubKeyHex: 'aa' * 32,
          runtimePubKeyHex: 'aa' * 32,
          rootPubKeyHex: 'aa' * 32,
          nostrPubKeyHex: 'bb' * 32,
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
        ),
    diagnoseTrace:
        () async => CapsuleTraceReport(
          activePubKeyHex: 'aa' * 32,
          runtimePubKeyHex: 'aa' * 32,
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
        ),
  );
}

class _FakeOutboxStore extends DeliveryOutboxStore {
  final List<DeliveryOutboxItem> items;

  _FakeOutboxStore({List<DeliveryOutboxItem>? items})
    : items =
          items ??
          <DeliveryOutboxItem>[
            DeliveryOutboxItem(
              id: 'retry-1',
              capsuleHex:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              transport: 'nostr',
              kind: 'InvitationSent',
              reason: 'send_invitation_retry',
              deliveryReference:
                  '1111111111111111111111111111111111111111111111111111111111111111',
              createdAt: DateTime.utc(2026, 7, 5),
              nextAttemptAt: DateTime.utc(2026, 7, 5),
              attempts: 2,
              status: DeliveryOutboxStatus.pending,
              lastError: 'timeout',
            ),
            DeliveryOutboxItem(
              id: 'legacy-quarantine-1',
              capsuleHex:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              transport: 'nostr',
              kind: 'InvitationSent',
              reason: 'send_invitation_retry',
              createdAt: DateTime.utc(2026, 7, 4),
              nextAttemptAt: DateTime.utc(2026, 7, 4),
              attempts: 7,
              status: DeliveryOutboxStatus.quarantined,
              lastError: 'missing immutable delivery reference',
            ),
          ];

  @override
  Future<List<DeliveryOutboxItem>> load(String capsuleHex) async => items;
}

class _FakePluginRegistryService extends WasmPluginRegistryService {
  final List<WasmPluginRecord> records;

  const _FakePluginRegistryService({
    this.records = const <WasmPluginRecord>[
      WasmPluginRecord(
        id: 'plugin-1',
        displayName: 'Capsule Chat',
        originalFileName: 'chat.zip',
        storedFileName: 'chat.zip',
        sizeBytes: 42,
        installedAtIso: '2026-07-05T00:00:00Z',
        packageKind: 'zip',
        pluginId: 'hivra.contract.capsule-chat.v1',
        pluginVersion: '0.1.0',
        contractKind: 'capsule_chat',
        runtimeAbi: 'hivra_wasm_abi_v1',
        runtimeEntryExport: 'hivra_plugin_invoke',
        runtimeModulePath: 'plugin/module.wasm',
        capabilities: <String>['trust.read'],
      ),
    ],
  });

  @override
  Future<List<WasmPluginRecord>> loadPlugins() async => records;
}
