import 'dart:convert';

import '../ffi/hivra_bindings.dart';
import 'capsule_persistence_service.dart';

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

  RecoveryService([HivraBindings? hivra]) : _hivra = hivra ?? HivraBindings();

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
        final expectedOwner = _extractOwnerHexFromLedger(selectedBackupLedgerJson);
        final currentPubKey = _hivra.capsuleRuntimeOwnerPublicKey();
        final currentOwner = currentPubKey == null ? null : _bytesToHex(currentPubKey);
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
        final inferredFromLedger = _inferGenesisFromLedgerJson(_hivra.exportLedger());
        isGenesisRecovered = inferredFromLedger ?? (_countOccupiedStarters(_hivra) > 0);

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

  int _countOccupiedStarters(HivraBindings hivra) {
    final raw = hivra.exportLedger();
    if (raw == null || raw.trim().isEmpty) return 0;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 0;
      final ledger = Map<String, dynamic>.from(decoded);
      final eventsRaw = ledger['events'];
      final events = eventsRaw is List ? eventsRaw : const [];

      final byKind = <int, String>{};

      for (final eventRaw in events) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kindCode = _eventKindCode(event['kind']);
        final payload = _decodePayloadBytes(event['payload']);
        if (payload == null) continue;

        if (kindCode == 5) {
          if (payload.length < 66) continue;
          final starterIdHex = _bytesToHex(payload.sublist(0, 32));
          final slot = payload[64];
          if (slot >= 0 && slot < 5) {
            byKind[slot] = starterIdHex;
          }
        } else if (kindCode == 6) {
          if (payload.length < 32) continue;
          final burnedHex = _bytesToHex(payload.sublist(0, 32));
          final toRemove = <int>[];
          byKind.forEach((slot, idHex) {
            if (idHex == burnedHex) {
              toRemove.add(slot);
            }
          });
          for (final slot in toRemove) {
            byKind.remove(slot);
          }
        }
      }

      return byKind.length;
    } catch (_) {
      return 0;
    }
  }

  String? _extractOwnerHexFromLedger(String ledgerJson) {
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final ownerBytes = _decodePayloadBytes(map['owner']);
      if (ownerBytes == null || ownerBytes.length != 32) return null;
      return _bytesToHex(ownerBytes);
    } catch (_) {
      return null;
    }
  }

  bool? _inferGenesisFromLedgerJson(String? ledgerJson) {
    if (ledgerJson == null || ledgerJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final eventsRaw = map['events'];
      if (eventsRaw is! List) return null;

      for (final eventRaw in eventsRaw) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kindCode = _eventKindCode(event['kind']);
        if (kindCode != 0) continue;

        final payload = _decodePayloadBytes(event['payload']);
        if (payload == null || payload.length < 2) return null;
        final capsuleType = payload[1];
        if (capsuleType == 1) return true;
        if (capsuleType == 0) return false;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int _eventKindCode(dynamic rawKind) {
    if (rawKind is num) return rawKind.toInt();
    if (rawKind is! String) return -1;
    switch (rawKind) {
      case 'CapsuleCreated':
        return 0;
      case 'StarterCreated':
        return 5;
      case 'StarterBurned':
        return 6;
      default:
        return -1;
    }
  }

  List<int>? _decodePayloadBytes(dynamic raw) {
    if (raw is List) {
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed) && trimmed.length.isEven) {
        final out = <int>[];
        for (int i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }

      try {
        return base64Decode(trimmed);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  String _bytesToHex(List<int> bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}
