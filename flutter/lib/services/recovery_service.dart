import 'dart:typed_data';

import '../ffi/recovery_runtime.dart';
import 'capsule_ledger_summary_parser.dart';
import 'ledger_view_support.dart';

class RecoveryExecutionResult {
  final bool isSuccess;
  final String? errorMessage;

  const RecoveryExecutionResult._({required this.isSuccess, this.errorMessage});

  const RecoveryExecutionResult.success() : this._(isSuccess: true);

  const RecoveryExecutionResult.failure(String message)
    : this._(isSuccess: false, errorMessage: message);
}

class RecoveryService {
  final RecoveryRuntime _runtime;
  final LedgerViewSupport _support;
  final CapsuleLedgerSummaryParser _summaryParser;

  RecoveryService([
    RecoveryRuntime? runtime,
    LedgerViewSupport? support,
    CapsuleLedgerSummaryParser? summaryParser,
  ]) : _runtime = runtime ?? HivraRecoveryRuntime(),
       _support = support ?? const LedgerViewSupport(),
       _summaryParser = summaryParser ?? const CapsuleLedgerSummaryParser();

  bool validateMnemonic(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return false;
    return _runtime.validateMnemonic(trimmed);
  }

  Future<RecoveryExecutionResult> recover({
    required String phrase,
    required String? selectedBackupJson,
  }) async {
    try {
      final seed = _runtime.mnemonicToSeed(phrase.trim());
      if (selectedBackupJson != null) {
        final restored = await _runtime.importCompleteBackup(
          selectedBackupJson,
          seed,
        );
        return restored
            ? const RecoveryExecutionResult.success()
            : const RecoveryExecutionResult.failure(
              'Failed to restore Capsule backup',
            );
      }
      var isGenesisRecovered = false;

      final createError = _runtime.createCapsuleError(
        seed,
        isGenesis: isGenesisRecovered,
      );
      if (createError != null) {
        return RecoveryExecutionResult.failure(createError);
      }

      final importedLedger = await _runtime.importLedgerIfExists();

      if (importedLedger) {
        final exportedLedger = _runtime.exportLedger();
        final inferredFromLedger = _inferGenesisFromLedgerJson(exportedLedger);
        isGenesisRecovered =
            inferredFromLedger ?? (_countOccupiedStarters(exportedLedger) > 0);

        final recreateError = _runtime.createCapsuleError(
          seed,
          isGenesis: isGenesisRecovered,
        );
        if (recreateError != null) {
          return RecoveryExecutionResult.failure(recreateError);
        }

        await _runtime.importLedgerIfExists();
      }

      await _runtime.persistAfterCreate(
        seed: seed,
        isGenesis: isGenesisRecovered,
        isNeste: true,
      );

      return const RecoveryExecutionResult.success();
    } catch (e) {
      return const RecoveryExecutionResult.failure(
        'Recovery failed; the Capsule was not restored',
      );
    }
  }

  int _countOccupiedStarters(String? ledgerJson) {
    if (ledgerJson == null || ledgerJson.trim().isEmpty) return 0;
    final summary = _summaryParser.parse(ledgerJson, _bytesToHex);
    return summary.starterCount;
  }

  bool? _inferGenesisFromLedgerJson(String? ledgerJson) {
    final root = _support.exportLedgerRoot(ledgerJson);
    return _support.inferGenesisFromLedgerRoot(root);
  }

  String _bytesToHex(Uint8List bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}
