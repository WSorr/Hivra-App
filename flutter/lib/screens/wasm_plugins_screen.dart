import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
  List<WasmPluginRecord> _installed = const <WasmPluginRecord>[];
  bool _loading = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final installed = await _registry.loadPlugins();
    if (!mounted) return;
    setState(() {
      _installed = installed;
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
        const SizedBox(height: 16),
        _InstalledPluginsCard(
          loading: _loading,
          installing: _installing,
          installed: _installed,
          onInstallPressed: _installPlugin,
          onRemovePressed: _removePlugin,
        ),
        const SizedBox(height: 16),
        Text('Plugin Host', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _InfoCard(
          icon: Icons.extension,
          title: 'Runtime boundary reserved',
          subtitle:
              'WASM plugins are not mounted yet. This screen reserves the plugin boundary without letting transports bypass core rules.',
        ),
        const SizedBox(height: 16),
        Text('Transport Plugins', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _PluginCard(
          title: 'Nostr',
          subtitle: 'Built-in transport, native adapter',
          status: 'Built-in',
          accent: Colors.green,
          icon: Icons.hub,
        ),
        const SizedBox(height: 10),
        const _PluginCard(
          title: 'Matrix',
          subtitle: 'Planned WASM transport plugin',
          status: 'Planned',
          accent: Colors.orange,
          icon: Icons.grid_view,
        ),
        const SizedBox(height: 10),
        const _PluginCard(
          title: 'Bluetooth LE',
          subtitle: 'Planned WASM mesh transport plugin',
          status: 'Planned',
          accent: Colors.orange,
          icon: Icons.bluetooth,
        ),
        const SizedBox(height: 10),
        const _PluginCard(
          title: 'Local Network',
          subtitle: 'Planned WASM enclave transport plugin',
          status: 'Planned',
          accent: Colors.orange,
          icon: Icons.lan,
        ),
        const SizedBox(height: 16),
        Text('Boundary Rules', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _RuleCard(
          title: 'Bytes only',
          description:
              'Plugins transport bytes. They do not interpret ledger policy or create domain events on their own.',
        ),
        const SizedBox(height: 10),
        const _RuleCard(
          title: 'Strictly downward',
          description:
              'Core never depends on a plugin. Plugins depend downward on stable transport contracts only.',
        ),
        const SizedBox(height: 10),
        const _RuleCard(
          title: 'Determinism first',
          description:
              'Ledger and runtime stay authoritative. Plugin delivery must not rewrite resolved local truth.',
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

class _InstalledPluginsCard extends StatelessWidget {
  final bool loading;
  final bool installing;
  final List<WasmPluginRecord> installed;
  final Future<void> Function() onInstallPressed;
  final Future<void> Function(WasmPluginRecord record) onRemovePressed;

  const _InstalledPluginsCard({
    required this.loading,
    required this.installing,
    required this.installed,
    required this.onInstallPressed,
    required this.onRemovePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10151B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C3642)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Installed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
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
                    : const Icon(Icons.add),
                label: Text(installing ? 'Installing' : 'Install'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Local registry for plugin packages that will later be mounted by the wasm host.',
            style: TextStyle(
              color: Colors.grey.shade400,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (installed.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No plugin packages installed yet.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            )
          else
            ...installed.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InstalledPluginTile(
                  record: record,
                  onRemovePressed: () => onRemovePressed(record),
                ),
              ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.cyan.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.memory, color: Colors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.displayName.isEmpty
                      ? record.originalFileName
                      : record.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  record.originalFileName,
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatBytes(record.sizeBytes)} · ${record.installedAtIso}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemovePressed,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove plugin',
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
}

class _StatusBanner extends StatelessWidget {
  final ThemeData theme;

  const _StatusBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF304154)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF45361A),
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
            'WASM plugins will extend transport, not bypass architecture.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'This screen exposes the plugin boundary now, while runtime, ledger and deterministic rules stay in the existing core stack.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade300,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.cyan.shade300),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    height: 1.35,
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

class _PluginCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final Color accent;
  final IconData icon;

  const _PluginCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withAlpha(36),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final String title;
  final String description;

  const _RuleCard({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12161C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3440)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey.shade400,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
