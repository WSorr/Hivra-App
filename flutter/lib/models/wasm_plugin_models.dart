class WasmPluginRecord {
  final String id;
  final String displayName;
  final String originalFileName;
  final String storedFileName;
  final int sizeBytes;
  final String installedAtIso;
  final String packageKind;
  final String? pluginId;
  final String? pluginVersion;
  final String? contractKind;
  final String? runtimeAbi;
  final String? runtimeEntryExport;
  final String? runtimeModulePath;
  final List<String> capabilities;

  const WasmPluginRecord({
    required this.id,
    required this.displayName,
    required this.originalFileName,
    required this.storedFileName,
    required this.sizeBytes,
    required this.installedAtIso,
    required this.packageKind,
    required this.pluginId,
    required this.pluginVersion,
    required this.contractKind,
    required this.runtimeAbi,
    required this.runtimeEntryExport,
    required this.runtimeModulePath,
    required this.capabilities,
  });

  factory WasmPluginRecord.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final capabilities = <String>{};
    if (rawCapabilities is List) {
      for (final value in rawCapabilities) {
        final normalized = value?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          capabilities.add(normalized);
        }
      }
    }
    return WasmPluginRecord(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown plugin',
      originalFileName: json['originalFileName'] as String? ?? 'unknown.wasm',
      storedFileName: json['storedFileName'] as String? ?? 'unknown.wasm',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      installedAtIso: json['installedAtIso'] as String? ?? '',
      packageKind: json['packageKind'] as String? ?? 'unknown',
      pluginId: json['pluginId'] as String?,
      pluginVersion: json['pluginVersion'] as String?,
      contractKind: json['contractKind'] as String?,
      runtimeAbi: json['runtimeAbi'] as String?,
      runtimeEntryExport: json['runtimeEntryExport'] as String?,
      runtimeModulePath: json['runtimeModulePath'] as String?,
      capabilities: (capabilities.toList()..sort()),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'originalFileName': originalFileName,
      'storedFileName': storedFileName,
      'sizeBytes': sizeBytes,
      'installedAtIso': installedAtIso,
      'packageKind': packageKind,
      'pluginId': pluginId,
      'pluginVersion': pluginVersion,
      'contractKind': contractKind,
      'runtimeAbi': runtimeAbi,
      'runtimeEntryExport': runtimeEntryExport,
      'runtimeModulePath': runtimeModulePath,
      'capabilities': capabilities,
    };
  }
}

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
