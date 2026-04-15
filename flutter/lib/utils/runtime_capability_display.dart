class RuntimeCapabilityDisplaySummary {
  final List<String> visibleCapabilities;
  final int hiddenCount;

  const RuntimeCapabilityDisplaySummary({
    required this.visibleCapabilities,
    required this.hiddenCount,
  });
}

RuntimeCapabilityDisplaySummary summarizeRuntimeCapabilitiesForDisplay(
  List<String> capabilities, {
  int visibleLimit = 3,
}) {
  final safeLimit = visibleLimit < 0 ? 0 : visibleLimit;
  final visibleCapabilities = capabilities.take(safeLimit).toList();
  final hiddenCount = capabilities.length - visibleCapabilities.length;
  return RuntimeCapabilityDisplaySummary(
    visibleCapabilities: visibleCapabilities,
    hiddenCount: hiddenCount < 0 ? 0 : hiddenCount,
  );
}
