class WasmPluginCapabilityPolicyService {
  static const Set<String> _allowedCapabilities = <String>{
    'consensus_guard.read',
    'oracle.read.mock_weather',
    'oracle.read.temperature.li',
  };

  const WasmPluginCapabilityPolicyService();

  List<String> normalizeAndValidate(List<String> capabilities) {
    final normalized = <String>{};
    for (final raw in capabilities) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (!_allowedCapabilities.contains(value)) {
        throw FormatException('Unsupported plugin capability: $value');
      }
      normalized.add(value);
    }
    final ordered = normalized.toList()..sort();
    return ordered;
  }

  List<String> allowedCapabilities() {
    final ordered = _allowedCapabilities.toList()..sort();
    return ordered;
  }
}
