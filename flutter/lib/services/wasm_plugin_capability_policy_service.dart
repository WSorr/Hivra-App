class WasmPluginCapabilityPolicyService {
  static const Set<String> _allowedCapabilities = <String>{
    'consensus_guard.read',
    'content.draft.prepare',
    'content.feed.plan',
    'content.engagement.plan',
    'content.reply.prepare',
    'content.reply.delegate',
    'exchange.read.bingx.market',
    'exchange.trade.bingx.futures',
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
