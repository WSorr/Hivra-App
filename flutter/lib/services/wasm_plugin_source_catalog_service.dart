import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'user_visible_data_directory_service.dart';
import 'wasm_plugin_registry_service.dart';

class WasmPluginSourceCatalogEntry {
  final String id;
  final String pluginId;
  final String displayName;
  final String version;
  final String downloadUrl;
  final String packageKind;
  final String? sha256Hex;

  const WasmPluginSourceCatalogEntry({
    required this.id,
    required this.pluginId,
    required this.displayName,
    required this.version,
    required this.downloadUrl,
    required this.packageKind,
    required this.sha256Hex,
  });
}

class WasmPluginSourceCatalog {
  final String sourceId;
  final String sourceName;
  final String fetchedAtIso;
  final List<WasmPluginSourceCatalogEntry> entries;

  const WasmPluginSourceCatalog({
    required this.sourceId,
    required this.sourceName,
    required this.fetchedAtIso,
    required this.entries,
  });
}

class WasmPluginSourceCatalogService {
  static const String defaultCatalogUrl =
      'https://cdn.jsdelivr.net/gh/WSorr/hivra-plugins@main/catalog/plugin_catalog.json';
  static const String githubRawCatalogUrl =
      'https://raw.githubusercontent.com/WSorr/hivra-plugins/main/catalog/plugin_catalog.json';
  static const Set<String> defaultTrustedRemoteCatalogSha256Hexes = {
    '07275bd8fb567ef5f9072f47fb132605264090efcc1014340b79785b4c411a43',
  };
  static const Set<String> defaultTrustedRemoteCatalogPublicKeyHexes = {};
  static const Duration _networkTimeout = Duration(seconds: 8);

  final WasmPluginRegistryService _registry;
  final UserVisibleDataDirectoryService _dataDirs;
  final HttpClient Function() _httpClientFactory;
  final Set<String> _trustedRemoteCatalogSha256Hexes;
  final Set<String> _trustedRemoteCatalogPublicKeyHexes;

  const WasmPluginSourceCatalogService({
    WasmPluginRegistryService registry = const WasmPluginRegistryService(),
    UserVisibleDataDirectoryService dataDirs =
        const UserVisibleDataDirectoryService(),
    HttpClient Function()? httpClientFactory,
    Set<String> trustedRemoteCatalogSha256Hexes =
        defaultTrustedRemoteCatalogSha256Hexes,
    Set<String> trustedRemoteCatalogPublicKeyHexes =
        defaultTrustedRemoteCatalogPublicKeyHexes,
  })  : _registry = registry,
        _dataDirs = dataDirs,
        _httpClientFactory = httpClientFactory ?? _defaultHttpClientFactory,
        _trustedRemoteCatalogSha256Hexes = trustedRemoteCatalogSha256Hexes,
        _trustedRemoteCatalogPublicKeyHexes =
            trustedRemoteCatalogPublicKeyHexes;

  static HttpClient _defaultHttpClientFactory() => HttpClient();

  Future<WasmPluginSourceCatalog> fetchCatalog({
    String catalogUrl = defaultCatalogUrl,
  }) async {
    final uri = Uri.tryParse(catalogUrl);
    if (uri == null) {
      throw const FormatException('Plugin source catalog URL is invalid');
    }
    if (!uri.hasScheme || uri.scheme == 'file') {
      final filePath = uri.hasScheme ? uri.toFilePath() : catalogUrl;
      final file = File(filePath);
      if (!await file.exists()) {
        throw FormatException(
            'Plugin source catalog file not found: $filePath');
      }
      final body = await file.readAsString();
      return _parseCatalogJson(body);
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException(
          'Unsupported plugin source catalog URL scheme');
    }

    final client = _httpClientFactory();
    client.autoUncompress = false;
    client.connectionTimeout = _networkTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_networkTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(_networkTimeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(_networkTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to fetch plugin catalog (HTTP ${response.statusCode})',
          uri: uri,
        );
      }

      await _verifyRemoteCatalogTrust(body);
      return _parseCatalogJson(body);
    } finally {
      client.close(force: true);
    }
  }

  Future<WasmPluginSourceCatalog> fetchCatalogWithFallback({
    String primaryCatalogUrl = defaultCatalogUrl,
    String secondaryCatalogUrl = githubRawCatalogUrl,
    String? localCatalogPathOverride,
  }) async {
    final localCatalogPath =
        localCatalogPathOverride ?? await _defaultLocalCatalogPath();
    if (await File(localCatalogPath).exists()) {
      try {
        return await fetchCatalog(catalogUrl: localCatalogPath);
      } catch (_) {
        // A malformed local catalog must not permanently block the published
        // source. If remote sources are unavailable too, the final local
        // fallback below will surface the local error.
      }
    }
    try {
      return await fetchCatalog(catalogUrl: primaryCatalogUrl);
    } catch (_) {
      try {
        return await fetchCatalog(catalogUrl: secondaryCatalogUrl);
      } catch (_) {
        return fetchCatalog(catalogUrl: localCatalogPath);
      }
    }
  }

  Future<WasmPluginRecord> installFromSourceEntry(
    WasmPluginSourceCatalogEntry entry,
  ) async {
    final uri = Uri.tryParse(entry.downloadUrl);
    if (uri == null) {
      throw const FormatException(
          'Plugin source entry download URL is invalid');
    }
    if (!uri.hasScheme || uri.scheme == 'file') {
      final filePath = uri.hasScheme ? uri.toFilePath() : entry.downloadUrl;
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        throw FormatException('Plugin source package not found: $filePath');
      }
      await _verifyChecksumIfPresent(
        sourceEntryId: entry.id,
        expectedSha256Hex: entry.sha256Hex,
        file: sourceFile,
      );
      final record = await _registry.installPluginFromFile(sourceFile);
      await _validateInstalledRecordAgainstCatalogEntry(
        entry: entry,
        record: record,
      );
      return record;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException(
          'Unsupported plugin source package URL scheme');
    }

    final extension = entry.packageKind == 'wasm' ? '.wasm' : '.zip';
    final tempDir = await Directory.systemTemp.createTemp('hivra_plugin_src_');
    final tempFile =
        File('${tempDir.path}/${entry.id}_v${entry.version}$extension');

    final client = _httpClientFactory();
    client.autoUncompress = false;
    client.connectionTimeout = _networkTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_networkTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(_networkTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download plugin package (HTTP ${response.statusCode})',
          uri: uri,
        );
      }
      final sink = tempFile.openWrite();
      await response.pipe(sink).timeout(_networkTimeout);
      await sink.flush();
      await sink.close();

      await _verifyChecksumIfPresent(
        sourceEntryId: entry.id,
        expectedSha256Hex: entry.sha256Hex,
        file: tempFile,
      );
      final record = await _registry.installPluginFromFile(tempFile);
      await _validateInstalledRecordAgainstCatalogEntry(
        entry: entry,
        record: record,
      );
      return record;
    } finally {
      client.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  WasmPluginSourceCatalog _parseCatalogJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Plugin source catalog must be a JSON map');
    }
    final json = Map<String, dynamic>.from(decoded);
    if (json['schema'] != 'hivra.plugin.catalog') {
      throw const FormatException('Unsupported plugin source catalog schema');
    }
    final catalogVersion = json['version'];
    if (catalogVersion != 1 && catalogVersion != 2) {
      throw const FormatException('Unsupported plugin source catalog version');
    }

    final sourceId = (json['source_id']?.toString().trim() ?? '');
    final sourceName = (json['source_name']?.toString().trim() ?? '');
    if (sourceId.isEmpty || sourceName.isEmpty) {
      throw const FormatException(
        'Plugin source catalog is missing source metadata',
      );
    }

    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException(
          'Plugin source catalog entries must be a list');
    }

    final entries = <WasmPluginSourceCatalogEntry>[];
    final seenEntryIds = <String>{};
    final seenPluginVersionKinds = <String>{};
    for (final item in rawEntries) {
      if (item is! Map) continue;
      final entry = Map<String, dynamic>.from(item);
      final id = (entry['id']?.toString().trim() ?? '');
      final pluginId = (entry['plugin_id']?.toString().trim() ?? '');
      final displayName = (entry['display_name']?.toString().trim() ?? '');
      final version = (entry['version']?.toString().trim() ?? '');
      final downloadUrl = (entry['download_url']?.toString().trim() ?? '');
      final packageKind =
          (entry['package_kind']?.toString().trim().toLowerCase() ?? '');
      final sha256 = entry['sha256_hex']?.toString().trim();

      if (id.isEmpty ||
          pluginId.isEmpty ||
          displayName.isEmpty ||
          version.isEmpty ||
          downloadUrl.isEmpty) {
        continue;
      }
      if (!_isValidPluginId(pluginId)) {
        continue;
      }
      if (!_isValidReleaseVersion(version)) {
        continue;
      }
      if (seenEntryIds.contains(id)) {
        continue;
      }
      if (packageKind != 'zip' && packageKind != 'wasm') {
        continue;
      }
      if (!_isSupportedDownloadUrl(downloadUrl)) {
        continue;
      }
      final pluginVersionKindKey =
          '${pluginId.toLowerCase()}::${version.toLowerCase()}::$packageKind';
      if (seenPluginVersionKinds.contains(pluginVersionKindKey)) {
        continue;
      }

      final normalizedSha = _normalizeSha256Hex(sha256, entryId: id);
      if (catalogVersion == 2 && normalizedSha == null) {
        throw FormatException(
          'Missing sha256_hex in source catalog entry: $id',
        );
      }
      seenEntryIds.add(id);
      seenPluginVersionKinds.add(pluginVersionKindKey);
      entries.add(
        WasmPluginSourceCatalogEntry(
          id: id,
          pluginId: pluginId,
          displayName: displayName,
          version: version,
          downloadUrl: downloadUrl,
          packageKind: packageKind,
          sha256Hex: normalizedSha,
        ),
      );
    }

    return WasmPluginSourceCatalog(
      sourceId: sourceId,
      sourceName: sourceName,
      fetchedAtIso: DateTime.now().toUtc().toIso8601String(),
      entries: entries,
    );
  }

  bool _isSupportedDownloadUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!uri.hasScheme) return true;
    return uri.scheme == 'file' ||
        uri.scheme == 'http' ||
        uri.scheme == 'https';
  }

  Future<void> _verifyRemoteCatalogTrust(String body) async {
    if (await _verifyRemoteCatalogSignature(body)) {
      return;
    }
    _verifyRemoteCatalogDigest(body);
  }

  Future<bool> _verifyRemoteCatalogSignature(String body) async {
    final trustedKeys = _trustedRemoteCatalogPublicKeyHexes
        .map((value) => value.trim().toLowerCase())
        .where((value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value))
        .toSet();
    if (trustedKeys.isEmpty) {
      return false;
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Plugin source catalog must be a JSON map');
    }
    final catalog = Map<String, dynamic>.from(decoded);
    final rawSignatures = catalog['signatures'];
    if (rawSignatures is! List || rawSignatures.isEmpty) {
      throw const FormatException(
        'Remote plugin source catalog is not signed',
      );
    }

    final unsignedCatalog = Map<String, dynamic>.from(catalog)
      ..remove('signatures');
    final payload = utf8.encode(_canonicalJson(unsignedCatalog));
    final verifier = Ed25519();

    for (final item in rawSignatures) {
      if (item is! Map) continue;
      final signature = Map<String, dynamic>.from(item);
      final algorithm =
          (signature['algorithm']?.toString().trim().toLowerCase() ?? '');
      if (algorithm != 'ed25519') continue;
      final keyId =
          (signature['key_id']?.toString().trim().toLowerCase() ?? '');
      final signatureHex =
          (signature['signature_hex']?.toString().trim().toLowerCase() ?? '');
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(keyId) ||
          !RegExp(r'^[0-9a-f]{128}$').hasMatch(signatureHex)) {
        continue;
      }

      for (final publicKeyHex in trustedKeys) {
        final publicKeyBytes = _decodeHex(publicKeyHex);
        final publicKeyId =
            sha256.convert(publicKeyBytes).toString().toLowerCase();
        if (keyId != publicKeyId) continue;
        final valid = await verifier.verify(
          payload,
          signature: Signature(
            _decodeHex(signatureHex),
            publicKey: SimplePublicKey(
              publicKeyBytes,
              type: KeyPairType.ed25519,
            ),
          ),
        );
        if (valid) return true;
      }
    }

    throw const FormatException(
      'Remote plugin source catalog signature is not trusted',
    );
  }

  void _verifyRemoteCatalogDigest(String body) {
    final trusted = _trustedRemoteCatalogSha256Hexes
        .map((value) => value.trim().toLowerCase())
        .where((value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value))
        .toSet();
    if (trusted.isEmpty) {
      throw const FormatException(
        'Remote plugin source catalog has no trusted digest pin',
      );
    }
    final actual = sha256.convert(utf8.encode(body)).toString();
    if (!trusted.contains(actual)) {
      throw FormatException(
        'Remote plugin source catalog digest is not trusted: $actual',
      );
    }
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      final entries = keys.map((key) {
        return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
      }).join(',');
      return '{$entries}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  List<int> _decodeHex(String hex) {
    final normalized = hex.trim().toLowerCase();
    if (normalized.length.isOdd ||
        !RegExp(r'^[0-9a-f]*$').hasMatch(normalized)) {
      throw const FormatException('Invalid hex value');
    }
    return List<int>.generate(
      normalized.length ~/ 2,
      (index) => int.parse(
        normalized.substring(index * 2, index * 2 + 2),
        radix: 16,
      ),
      growable: false,
    );
  }

  bool _isValidPluginId(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^hivra\.contract\.[a-z0-9.\-]+\.v[0-9]+$')
        .hasMatch(normalized);
  }

  bool _isValidReleaseVersion(String value) {
    final normalized = value.trim();
    return RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.\-]+)?$')
        .hasMatch(normalized);
  }

  Future<String> _defaultLocalCatalogPath() async {
    final pluginsDir = await _dataDirs.pluginsDirectory(create: true);
    return '${pluginsDir.path}/plugin_catalog.json';
  }

  Future<void> _verifyChecksumIfPresent({
    required String sourceEntryId,
    required String? expectedSha256Hex,
    required File file,
  }) async {
    final expected = expectedSha256Hex?.trim().toLowerCase();
    if (expected == null || expected.isEmpty) {
      return;
    }
    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (actual != expected) {
      final sizeBytes = await file.length();
      throw FormatException(
        'Plugin source package checksum mismatch for entry: $sourceEntryId '
        '(expected=$expected actual=$actual size=$sizeBytes)',
      );
    }
  }

  String? _normalizeSha256Hex(String? raw, {required String entryId}) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final normalized = value.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw FormatException(
        'Invalid sha256_hex in source catalog entry: $entryId',
      );
    }
    return normalized;
  }

  Future<void> _validateInstalledRecordAgainstCatalogEntry({
    required WasmPluginSourceCatalogEntry entry,
    required WasmPluginRecord record,
  }) async {
    final expectedPluginId = entry.pluginId.trim().toLowerCase();
    final expectedVersion = entry.version.trim().toLowerCase();
    final expectedPackageKind = entry.packageKind.trim().toLowerCase();
    final installedPluginId = (record.pluginId ?? '').trim().toLowerCase();
    final installedVersion = (record.pluginVersion ?? '').trim().toLowerCase();
    final installedPackageKind = record.packageKind.trim().toLowerCase();

    final pluginIdMatch =
        installedPluginId.isNotEmpty && installedPluginId == expectedPluginId;
    final versionMatch =
        installedVersion.isEmpty || installedVersion == expectedVersion;
    final packageKindMatch = installedPackageKind == expectedPackageKind;

    if (pluginIdMatch && versionMatch && packageKindMatch) {
      return;
    }

    await _registry.removePlugin(record.id);
    throw FormatException(
      'Installed package metadata mismatch for source entry: ${entry.id}',
    );
  }
}
