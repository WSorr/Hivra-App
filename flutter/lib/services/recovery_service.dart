import 'dart:convert';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_ledger_summary_parser.dart';
import 'capsule_persistence_service.dart';
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
  final HivraBindings _hivra;
  final LedgerViewSupport _support;
  final CapsuleLedgerSummaryParser _summaryParser;

  RecoveryService([
    HivraBindings? hivra,
    LedgerViewSupport? support,
    CapsuleLedgerSummaryParser? summaryParser,
  ])  : _hivra = hivra ?? HivraBindings(),
        _support = support ?? const LedgerViewSupport(),
        _summaryParser = summaryParser ?? const CapsuleLedgerSummaryParser();

  bool validateMnemonic(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return false;
    return _hivra.validateMnemonic(trimmed);
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
      final seed = _hivra.mnemonicToSeed(phrase.trim());
      bool isGenesisRecovered = selectedBackupIsGenesis ?? false;

      final createError = _hivra.createCapsuleError(
        seed,
        isGenesis: isGenesisRecovered,
        ownerMode: HivraBindings.rootOwnerMode,
      );
      if (createError != null) {
        return RecoveryExecutionResult.failure(createError);
      }

      if (selectedBackupLedgerJson != null) {
        final expectedOwner =
            _extractOwnerHexFromLedger(selectedBackupLedgerJson);
        final currentPubKey = _hivra.capsuleRuntimeOwnerPublicKey();
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

      final persistence = CapsulePersistenceService();
      final importedLedger = selectedBackupLedgerJson != null
          ? _hivra.importLedger(selectedBackupLedgerJson)
          : await persistence.importLedgerIfExists(_hivra);

      if (selectedBackupLedgerJson != null && !importedLedger) {
        return const RecoveryExecutionResult.failure(
          'Failed to import selected backup ledger',
        );
      }

      if (importedLedger) {
        final exportedLedger = _hivra.exportLedger();
        final inferredFromLedger = _inferGenesisFromLedgerJson(exportedLedger);
        isGenesisRecovered =
            inferredFromLedger ?? (_countOccupiedStarters(exportedLedger) > 0);

        final recreateError = _hivra.createCapsuleError(
          seed,
          isGenesis: isGenesisRecovered,
          ownerMode: HivraBindings.rootOwnerMode,
        );
        if (recreateError != null) {
          return RecoveryExecutionResult.failure(recreateError);
        }

        if (selectedBackupLedgerJson != null) {
          if (!_hivra.importLedger(selectedBackupLedgerJson)) {
            return const RecoveryExecutionResult.failure(
              'Failed to import selected backup',
            );
          }
        } else {
          await persistence.importLedgerIfExists(_hivra);
        }
      }

      await persistence.persistAfterCreate(
        hivra: _hivra,
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
