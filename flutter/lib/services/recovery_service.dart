import 'dart:convert';
import 'dart:typed_data';

import '../ffi/recovery_runtime.dart';
import 'capsule_ledger_summary_parser.dart';
import 'ledger_view_support.dart';

class RecoveryExecutionResult {
  final bool isSuccess;
  final String? errorMessage;

  const RecoveryExecutionResult._({
    required this.isSuccess,
    this.errorMessage,
  });

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
  ])  : _runtime = runtime ?? HivraRecoveryRuntime(),
        _support = support ?? const LedgerViewSupport(),
        _summaryParser = summaryParser ?? const CapsuleLedgerSummaryParser();

  bool validateMnemonic(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return false;
    return _runtime.validateMnemonic(trimmed);
  }

  bool? extractGenesisHintFromBackupJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final meta = map['meta'];
      if (meta is! Map) return null;
      final isGenesis = meta['is_genesis'];
      if (isGenesis is bool) return isGenesis;
    } catch (_) {
      // no-op
    }
    return null;
  }

  Future<RecoveryExecutionResult> recover({
    required String phrase,
    required String? selectedBackupLedgerJson,
    required bool? selectedBackupIsGenesis,
  }) async {
    try {
      final seed = _runtime.mnemonicToSeed(phrase.trim());
      bool isGenesisRecovered = selectedBackupIsGenesis ?? false;

      final createError = _runtime.createCapsuleError(
        seed,
        isGenesis: isGenesisRecovered,
      );
      if (createError != null) {
        return RecoveryExecutionResult.failure(createError);
      }

      if (selectedBackupLedgerJson != null) {
        final expectedOwner =
            _extractOwnerHexFromLedger(selectedBackupLedgerJson);
        final currentPubKey = _runtime.capsuleRuntimeOwnerPublicKey();
        final currentOwner =
            currentPubKey == null ? null : _bytesToHex(currentPubKey);
        if (expectedOwner != null &&
            currentOwner != null &&
            expectedOwner != currentOwner) {
          return const RecoveryExecutionResult.failure(
            'Selected backup does not match this seed phrase',
          );
        }
      }

      final importedLedger = selectedBackupLedgerJson != null
          ? _runtime.importLedger(selectedBackupLedgerJson)
          : await _runtime.importLedgerIfExists();

      if (selectedBackupLedgerJson != null && !importedLedger) {
        return const RecoveryExecutionResult.failure(
          'Failed to import selected backup ledger',
        );
      }

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

        if (selectedBackupLedgerJson != null) {
          if (!_runtime.importLedger(selectedBackupLedgerJson)) {
            return const RecoveryExecutionResult.failure(
              'Failed to import selected backup',
            );
          }
        } else {
          await _runtime.importLedgerIfExists();
        }
      }

      await _runtime.persistAfterCreate(
        seed: seed,
        isGenesis: isGenesisRecovered,
        isNeste: true,
      );

      return const RecoveryExecutionResult.success();
    } catch (e) {
      return RecoveryExecutionResult.failure('Recovery failed: $e');
    }
  }

  int _countOccupiedStarters(String? ledgerJson) {
    if (ledgerJson == null || ledgerJson.trim().isEmpty) return 0;
    final summary = _summaryParser.parse(ledgerJson, _bytesToHex);
    return summary.starterCount;
  }

  String? _extractOwnerHexFromLedger(String ledgerJson) {
    final root = _support.exportLedgerRoot(ledgerJson);
    if (root == null) return null;
    final ownerBytes = _summaryParser.parseBytesField(root['owner']);
    if (ownerBytes == null || ownerBytes.length != 32) return null;
    return _bytesToHex(Uint8List.fromList(ownerBytes));
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
