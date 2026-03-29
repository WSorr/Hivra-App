import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_runtime_service.dart';
import '../services/consensus_processor.dart';
import '../services/plugin_execution_guard_service.dart';
import '../services/wasm_plugin_registry_service.dart';

class WasmPluginsScreen extends StatefulWidget {
  final bool embedded;

  const WasmPluginsScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<WasmPluginsScreen> createState() => _WasmPluginsScreenState();
}

class _WasmPluginsScreenState extends State<WasmPluginsScreen> {
  final WasmPluginRegistryService _registry = const WasmPluginRegistryService();
  final PluginExecutionGuardService _guard =
      AppRuntimeService().buildPluginExecutionGuardService();
  List<WasmPluginRecord> _installed = const <WasmPluginRecord>[];
  PluginExecutionGuardSnapshot _guardSnapshot =
      const PluginExecutionGuardSnapshot(
    state: ConsensusGuardState.pending,
    readyPairCount: 0,
    blockedPairCount: 0,
    blockingFacts: <ConsensusBlockingFact>[],
  );
  bool _loading = true;
  bool _installing = false;

  static const List<_CatalogPlugin> _transportPlugins = <_CatalogPlugin>[
    _CatalogPlugin(
      title: 'Nostr',
      subtitle: 'Native transport already mounted',
      status: 'Built-in',
      accent: Color(0xFF5FD16F),
      icon: Icons.hub,
      glow: Color(0xFF1F3E27),
      note: 'Current active transport',
    ),
  ];

  static const List<_BoundaryRule> _boundaryRules = <_BoundaryRule>[
    _BoundaryRule(
      title: 'Bytes Only',
      description:
          'Plugins move bytes. They do not invent ledger meaning or bypass domain rules.',
      icon: Icons.data_object_rounded,
      accent: Color(0xFF6AD0FF),
    ),
    _BoundaryRule(
      title: 'Downward Only',
      description:
          'Core never depends on a plugin. Plugins hang from stable contracts below the app.',
      icon: Icons.south_rounded,
      accent: Color(0xFFFFC76A),
    ),
    _BoundaryRule(
      title: 'Determinism First',
      description:
          'Ledger and runtime stay authoritative. Replay and delivery must not rewrite local truth.',
      icon: Icons.gavel_rounded,
      accent: Color(0xFF82E39D),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final installed = await _registry.loadPlugins();
    final guardSnapshot = _guard.inspectHostReadiness();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _guardSnapshot = guardSnapshot;
      _loading = false;
    });
  }

  Future<void> _installPlugin() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'WASM plugin packages',
          extensions: <String>['wasm', 'zip'],
        ),
      ],
    );
    if (file == null) return;

    setState(() {
      _installing = true;
    });

    try {
      final source = File(file.path);
      final record = await _registry.installPluginFromFile(source);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Installed ${record.displayName}')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to install plugin package')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void> _removePlugin(WasmPluginRecord record) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove plugin'),
            content: Text('Remove ${record.displayName} from this device?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _registry.removePlugin(record.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${record.displayName}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBanner(theme: theme),
        const SizedBox(height: 20),
        _InstalledSection(
          loading: _loading,
          installing: _installing,
          installed: _installed,
          onInstallPressed: _installPlugin,
          onRemovePressed: _removePlugin,
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          title: 'Plugin Host',
          subtitle:
              'A reserved shell for future wasm adapters and transport extensions.',
        ),
        const SizedBox(height: 10),
        _HostPanel(snapshot: _guardSnapshot),
        const SizedBox(height: 20),
        _SectionTitle(
          title: 'Transport Plugins',
          subtitle:
              'Current transport surface, kept narrow until the wasm host is wired in.',
        ),
        const SizedBox(height: 12),
        _PluginGrid(
          children: _transportPlugins
              .map(
                (plugin) => _CatalogPluginTile(plugin: plugin),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          title: 'Boundary Rules',
          subtitle:
              'The plugin layer stays useful only if it remains narrow, deterministic, and boring.',
        ),
        const SizedBox(height: 12),
        _PluginGrid(
          children: _boundaryRules
              .map(
                (rule) => _RuleTile(rule: rule),
              )
              .toList(),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('WASM Plugins')),
      body: content,
    );
  }
}

class _InstalledSection extends StatelessWidget {
  final bool loading;
  final bool installing;
  final List<WasmPluginRecord> installed;
  final Future<void> Function() onInstallPressed;
  final Future<void> Function(WasmPluginRecord record) onRemovePressed;

  const _InstalledSection({
    required this.loading,
    required this.installing,
    required this.installed,
    required this.onInstallPressed,
    required this.onRemovePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF141922), Color(0xFF0F141B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3340)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Installed',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Packages stored locally and ready for a future wasm host.',
                      style: TextStyle(
                        color: Color(0xFF9CA7B5),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: installing ? null : onInstallPressed,
                icon: installing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_box_outlined),
                label: Text(installing ? 'Installing' : 'Install'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (installed.isEmpty)
            const _EmptyInstalledState()
          else
            _PluginGrid(
              children: installed
                  .map(
                    (record) => _InstalledPluginTile(
                      record: record,
                      onRemovePressed: () => onRemovePressed(record),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EmptyInstalledState extends StatelessWidget {
  const _EmptyInstalledState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11161D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF262F3B)),
      ),
      child: const Column(
        children: [
          Icon(Icons.extension_off_rounded, color: Color(0xFF728196), size: 34),
          SizedBox(height: 10),
          Text(
            'No plugin packages installed yet.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Install a .wasm or .zip package to stage it locally inside the plugin sandbox.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF93A0B1), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _InstalledPluginTile extends StatelessWidget {
  final WasmPluginRecord record;
  final Future<void> Function() onRemovePressed;

  const _InstalledPluginTile({
    required this.record,
    required this.onRemovePressed,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = record.displayName.isEmpty
        ? record.originalFileName
        : record.displayName;
    final accent = _accentForName(displayName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            accent.withAlpha(34),
            const Color(0xFF141A21),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIconPlate(
                icon: _iconForFileName(record.originalFileName),
                accent: accent,
                glow: accent.withAlpha(36),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.originalFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9AA7B8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemovePressed,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove plugin',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.memory_rounded,
                label: _formatBytes(record.sizeBytes),
              ),
              _InfoChip(
                icon: Icons.schedule_rounded,
                label: _formatInstalledAt(record.installedAtIso),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int sizeBytes) {
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  static String _formatInstalledAt(String iso) {
    if (iso.isEmpty) return 'Unknown install time';
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    final month = _monthName(parsed.month);
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$month ${parsed.day}, ${parsed.hour}:$minute';
  }

  static String _monthName(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  static Color _accentForName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('matrix')) return const Color(0xFFFFB347);
    if (lower.contains('bluetooth') || lower.contains('ble')) {
      return const Color(0xFF69C7FF);
    }
    if (lower.contains('local') || lower.contains('mesh')) {
      return const Color(0xFF82E39D);
    }
    if (lower.contains('nostr')) return const Color(0xFF67DA75);
    return const Color(0xFF7E9CFF);
  }

  static IconData _iconForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('matrix')) return Icons.grid_view_rounded;
    if (lower.contains('bluetooth') || lower.contains('ble')) {
      return Icons.bluetooth_rounded;
    }
    if (lower.contains('local') || lower.contains('lan')) {
      return Icons.router_rounded;
    }
    if (lower.contains('nostr')) return Icons.hub_rounded;
    if (lower.endsWith('.zip')) return Icons.archive_rounded;
    return Icons.extension_rounded;
  }
}

class _StatusBanner extends StatelessWidget {
  final ThemeData theme;

  const _StatusBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1D2430), Color(0xFF151A23)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF364559)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF253447), Color(0xFF17222F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome_mosaic_rounded,
              color: Color(0xFF8BC8FF),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF46371A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Host pending',
                    style: TextStyle(
                      color: Color(0xFFFFC76A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'WASM plugins have a home now, but not a backdoor.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'We can stage packages, inspect them, and shape the shell before execution exists. That keeps the plugin layer modular instead of magical.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFBEC8D4),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF96A2B2),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _HostPanel extends StatelessWidget {
  final PluginExecutionGuardSnapshot snapshot;

  const _HostPanel({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final accent = switch (snapshot.state) {
      ConsensusGuardState.ready => const Color(0xFF75D98A),
      ConsensusGuardState.partial => const Color(0xFFFFC76A),
      ConsensusGuardState.blocked => const Color(0xFFFF8A7A),
      ConsensusGuardState.pending => const Color(0xFF75D2FF),
    };
    final title = switch (snapshot.state) {
      ConsensusGuardState.ready => 'Consensus guard ready',
      ConsensusGuardState.partial => 'Consensus guard partially blocked',
      ConsensusGuardState.blocked => 'Consensus guard blocked',
      ConsensusGuardState.pending => 'Runtime boundary reserved',
    };
    final summary = switch (snapshot.state) {
      ConsensusGuardState.ready =>
        'Read-only precondition checks found ${snapshot.readyPairCount} signable pairwise path(s). Execution is still disabled, but the guard boundary is now alive.',
      ConsensusGuardState.partial =>
        'Some pairwise paths are signable and some are blocked. Ready: ${snapshot.readyPairCount}, blocked: ${snapshot.blockedPairCount}.',
      ConsensusGuardState.blocked =>
        'Pairwise consensus checks are now wired into the future host boundary, but current ledger truth is blocking execution for ${snapshot.blockedPairCount} pair(s).',
      ConsensusGuardState.pending =>
        'Plugins are not mounted yet. This screen exists to keep the boundary explicit while transport, ledger and policy remain inside the current core stack.',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PluginIconPlate(
            icon: Icons.shield_moon_rounded,
            accent: accent,
            glow: accent.withAlpha(20),
            size: 54,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  summary,
                  style: const TextStyle(
                    color: Color(0xFF9FAABA),
                    height: 1.4,
                  ),
                ),
                if (snapshot.blockingFacts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: snapshot.blockingFacts
                        .take(3)
                        .map(
                          (fact) => _InfoChip(
                            icon: Icons.lock_outline_rounded,
                            label: fact.label,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginGrid extends StatelessWidget {
  final List<Widget> children;

  const _PluginGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1080
            ? 4
            : width >= 760
                ? 3
                : width >= 520
                    ? 2
                    : 1;

        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: width < 520 ? 1.9 : 1.05,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _CatalogPluginTile extends StatelessWidget {
  final _CatalogPlugin plugin;

  const _CatalogPluginTile({required this.plugin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[plugin.glow, const Color(0xFF131920)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: plugin.accent.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIconPlate(
                icon: plugin.icon,
                accent: plugin.accent,
                glow: plugin.accent.withAlpha(28),
              ),
              const Spacer(),
              _StatusPill(
                label: plugin.status,
                accent: plugin.accent,
              ),
            ],
          ),
          const Spacer(),
          Text(
            plugin.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            plugin.subtitle,
            style: const TextStyle(
              color: Color(0xFFA5B0BE),
              height: 1.35,
            ),
          ),
          if (plugin.note != null) ...[
            const SizedBox(height: 12),
            Text(
              plugin.note!,
              style: TextStyle(
                color: plugin.accent.withAlpha(220),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final _BoundaryRule rule;

  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12171E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3440)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PluginIconPlate(
            icon: rule.icon,
            accent: rule.accent,
            glow: rule.accent.withAlpha(22),
          ),
          const Spacer(),
          Text(
            rule.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            rule.description,
            style: const TextStyle(
              color: Color(0xFF9EABBA),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginIconPlate extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final Color glow;
  final double size;

  const _PluginIconPlate({
    required this.icon,
    required this.accent,
    required this.glow,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[glow, glow.withAlpha(0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Icon(icon, color: accent, size: size * 0.5),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _StatusPill({
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF10161D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF29313D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFA1ADBC)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFAEB9C7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogPlugin {
  final String title;
  final String subtitle;
  final String status;
  final Color accent;
  final IconData icon;
  final Color glow;
  final String? note;

  const _CatalogPlugin({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.accent,
    required this.icon,
    required this.glow,
    this.note,
  });
}

class _BoundaryRule {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  const _BoundaryRule({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });
}
