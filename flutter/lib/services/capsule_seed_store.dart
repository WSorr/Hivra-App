import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'atomic_file_write_service.dart';
import 'hivra_secure_storage_options.dart';
import 'user_visible_data_directory_service.dart';

class CapsuleSeedStore {
  static const String _seedKeyPrefix = 'hivra.seed.';
  static const String _seedFallbackFileName = 'capsule_seeds.json';

  final FlutterSecureStorage _secureStorage;
  final UserVisibleDataDirectoryService _dirs;
  final AtomicFileWriteService _atomicWrites;
  static final Map<String, Uint8List> _processSeedCache = <String, Uint8List>{};
  static final Map<String, Future<void>> _legacyMigrations =
      <String, Future<void>>{};
  static final Set<String> _legacyMigrationChecked = <String>{};

  CapsuleSeedStore({
    FlutterSecureStorage? secureStorage,
    UserVisibleDataDirectoryService? dirs,
    AtomicFileWriteService atomicWrites = const AtomicFileWriteService(),
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              mOptions: hivraMacOsSecureStorageOptions,
            ),
        _dirs = dirs ?? const UserVisibleDataDirectoryService(),
        _atomicWrites = atomicWrites;

  Future<void> storeSeed(String pubKeyHex, Uint8List seed) async {
    await _migrateLegacyFallbackFile();
    final encoded = base64.encode(seed);
    final key = '$_seedKeyPrefix$pubKeyHex';
    try {
      final existing = await _secureStorage.read(key: key);
      if (existing == encoded) {
        _processSeedCache[await _cacheKey(pubKeyHex)] =
            Uint8List.fromList(seed);
        await deleteFallback(pubKeyHex);
        return;
      }
      await _secureStorage.write(key: key, value: encoded);
      final persisted = await _secureStorage.read(key: key);
      if (persisted != encoded) {
        throw StateError('Secure seed read-back mismatch');
      }
    } catch (error) {
      throw StateError('Secure seed storage is unavailable: $error');
    }
    _processSeedCache[await _cacheKey(pubKeyHex)] = Uint8List.fromList(seed);
    await deleteFallback(pubKeyHex);
  }

  Future<String?> readSecureEncoded(String pubKeyHex) async {
    final key = '$_seedKeyPrefix$pubKeyHex';
    try {
      return _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> loadSeed(String pubKeyHex) async {
    final cacheKey = await _cacheKey(pubKeyHex);
    final cached = _processSeedCache[cacheKey];
    if (cached != null) return Uint8List.fromList(cached);

    await _migrateLegacyFallbackFile();
    final secureSeed = _decodeSeedString(await readSecureEncoded(pubKeyHex));
    if (secureSeed != null) {
      _processSeedCache[cacheKey] = Uint8List.fromList(secureSeed);
      return secureSeed;
    }
    return null;
  }

  Future<bool> hasStoredSeed(String pubKeyHex) async {
    final cacheKey = await _cacheKey(pubKeyHex);
    if (_processSeedCache.containsKey(cacheKey)) return true;

    await _migrateLegacyFallbackFile();
    var encoded = await readSecureEncoded(pubKeyHex);
    final seed = _decodeSeedString(encoded);
    if (seed == null) return false;
    _processSeedCache[cacheKey] = Uint8List.fromList(seed);
    return true;
  }

  Future<bool> hasFallback(String pubKeyHex) async {
    return _decodeSeedString(await _readSeedFallback(pubKeyHex)) != null;
  }

  Future<void> deleteSeed(String pubKeyHex) async {
    _processSeedCache.remove(await _cacheKey(pubKeyHex));
    try {
      await _secureStorage.delete(key: '$_seedKeyPrefix$pubKeyHex');
    } catch (_) {
      // Ignore secure storage cleanup errors.
    }
    await deleteFallback(pubKeyHex);
  }

  Future<void> deleteFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final map = _parseJsonMap(raw);
      if (map == null) return;
      map.remove(pubKeyHex);
      if (map.isEmpty) {
        await file.delete();
        return;
      }
      await _atomicWrites.writeString(file, jsonEncode(map));
    } catch (_) {
      // Ignore fallback cleanup errors.
    }
  }

  Future<void> _migrateLegacyFallbackFile() async {
    final file = await _seedFallbackFile();
    final path = file.path;
    if (_legacyMigrationChecked.contains(path)) return;
    final inFlight = _legacyMigrations[path];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final migration = _runLegacyFallbackMigration(file);
    _legacyMigrations[path] = migration;
    try {
      await migration;
      _legacyMigrationChecked.add(path);
    } finally {
      _legacyMigrations.remove(path);
    }
  }

  Future<void> _runLegacyFallbackMigration(File file) async {
    if (!await file.exists()) return;

    final raw = await file.readAsString();
    final map = _parseJsonMap(raw);
    if (map == null) {
      await file.delete();
      return;
    }

    final entries = <String, String>{};
    for (final entry in map.entries) {
      final pubKeyHex = entry.key.trim().toLowerCase();
      final encoded = entry.value?.toString() ?? '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pubKeyHex) ||
          _decodeSeedString(encoded) == null) {
        continue;
      }
      entries[pubKeyHex] = encoded;
    }

    try {
      for (final entry in entries.entries) {
        final key = '$_seedKeyPrefix${entry.key}';
        await _secureStorage.write(key: key, value: entry.value);
        final persisted = await _secureStorage.read(key: key);
        if (persisted != entry.value) {
          throw StateError('Secure seed migration read-back mismatch');
        }
      }
    } catch (error) {
      throw StateError('Secure seed migration failed: $error');
    }
    await file.delete();
  }

  Future<Uint8List?> loadValidatedSeed(
    String pubKeyHex, {
    required Future<bool> Function(Uint8List seed) isValidSeed,
    required Future<void> Function(Uint8List seed) persistValidatedSeed,
  }) async {
    final cacheKey = await _cacheKey(pubKeyHex);
    final cached = _processSeedCache[cacheKey];
    if (cached != null) {
      final copy = Uint8List.fromList(cached);
      if (await isValidSeed(copy)) return copy;
      _processSeedCache.remove(cacheKey);
    }

    await _migrateLegacyFallbackFile();
    final secureSeed = _decodeSeedString(await readSecureEncoded(pubKeyHex));
    if (secureSeed != null && await isValidSeed(secureSeed)) {
      _processSeedCache[cacheKey] = Uint8List.fromList(secureSeed);
      await deleteFallback(pubKeyHex);
      return secureSeed;
    }

    return null;
  }

  Future<File> _seedFallbackFile() async {
    final capsulesRoot = await _dirs.capsulesDirectory(create: true);
    return File('${capsulesRoot.path}/$_seedFallbackFileName');
  }

  Future<String> _cacheKey(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    return '${file.path}|${pubKeyHex.toLowerCase()}';
  }

  Future<String?> _readSeedFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return null;
    try {
      final map = _parseJsonMap(await file.readAsString());
      return map?[pubKeyHex]?.toString();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJsonMap(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeSeedString(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64.decode(encoded);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }
}
