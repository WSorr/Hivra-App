import 'dart:io';

import 'package:flutter/material.dart';

import '../models/plugin_contract_ids.dart';
import '../models/wasm_plugin_models.dart';
import '../services/app_runtime_service.dart';
import '../services/hivra_file_picker_service.dart';
import '../services/plugin_runtime_module_service.dart';
import '../services/wasm_plugin_runtime_service.dart';
import 'capsule_chat_plugin_screen.dart';
import 'moltbook_ambassador_screen.dart';
import 'trading_drone_screen.dart';

@visibleForTesting
String? installedPluginWorkspaceContractKind(WasmPluginRecord record) {
  if (record.packageKind.trim().toLowerCase() != 'zip' ||
      record.runtimeAbi?.trim() !=
          WasmPluginRuntimeService.requiredRuntimeAbi ||
      record.runtimeEntryExport?.trim() !=
          WasmPluginRuntimeService.requiredEntryExport ||
      (record.runtimeModulePath?.trim().isEmpty ?? true)) {
    return null;
  }

  final pluginId = record.pluginId?.trim();
  final contractKind = record.contractKind?.trim();
  return switch ((pluginId, contractKind)) {
    (capsuleChatPluginId, capsuleChatContractKind) => capsuleChatContractKind,
    (moltbookAmbassadorPluginId, moltbookAmbassadorContractKind) =>
      moltbookAmbassadorContractKind,
    (bingxFuturesTradingPluginId, bingxFuturesContractKind) =>
      bingxFuturesContractKind,
    _ => null,
  };
}

class WasmPluginsScreen extends StatefulWidget {
  final bool embedded;
  final AppRuntimeService? runtime;
  final VoidCallback? onChatUnreadChanged;

  const WasmPluginsScreen({
    super.key,
    this.embedded = false,
    this.runtime,
    this.onChatUnreadChanged,
  });

  @override
  State<WasmPluginsScreen> createState() => _WasmPluginsScreenState();
}

class _WasmPluginsScreenState extends State<WasmPluginsScreen> {
  late final PluginRuntimeModule _module;
  List<WasmPluginRecord> _installed = const <WasmPluginRecord>[];
  WasmPluginSourceCatalog? _sourceCatalogSnapshot;
  String? _sourceCatalogError;
  bool _loading = true;
  bool _loadingSourceCatalog = true;
  bool _installing = false;
  Set<String> _installingSourceEntryIds = <String>{};

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
    _module =
        PluginRuntimeModuleService(
          runtime: widget.runtime ?? AppRuntimeService(),
        ).build();
    _reload();
    _reloadSourceCatalog();
  }

  Future<void> _reload() async {
    final installed = await _module.registry.loadPlugins();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _loading = false;
    });
  }

  Future<void> _reloadSourceCatalog() async {
    setState(() {
      _loadingSourceCatalog = true;
      _sourceCatalogError = null;
    });
    await _module.uiLog.log('plugin.source.catalog.refresh', 'start');
    try {
      final catalog = await _module.sourceCatalog.fetchCatalogWithFallback();
      await _module.uiLog.log(
        'plugin.source.catalog.refresh',
        'success source=${catalog.sourceId} count=${catalog.entries.length}',
      );
      if (!mounted) return;
      setState(() {
        _sourceCatalogSnapshot = catalog;
      });
    } catch (error) {
      await _module.uiLog.log('plugin.source.catalog.refresh', 'error=$error');
      if (!mounted) return;
      setState(() {
        _sourceCatalogError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingSourceCatalog = false;
        });
      }
    }
  }

  Future<void> _installPlugin() async {
    final file = await HivraFilePickerService.openPluginPackage();
    if (file == null) return;
    await _module.uiLog.log(
      'plugin.install.pick',
      'path=${file.path} name=${file.name} mime=${file.mimeType ?? "-"}',
    );

    setState(() {
      _installing = true;
    });

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('hivra_plugin_import_');
      final safeName = _safePluginImportFileName(file.name, file.path);
      final source = File('${tempDir.path}/$safeName');
      await source.writeAsBytes(await file.readAsBytes(), flush: true);
      final record = await _module.registry.installPluginFromFile(source);
      await _module.uiLog.log(
        'plugin.install.success',
        'id=${record.id} plugin=${record.pluginId ?? "-"} '
            'version=${record.pluginVersion ?? "-"} kind=${record.packageKind} '
            'file=${record.originalFileName}',
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Installed ${record.displayName}')),
      );
    } on FormatException catch (error) {
      await _module.uiLog.log(
        'plugin.install.error',
        'format=${error.message}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      await _module.uiLog.log('plugin.install.error', 'exception=$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to install plugin package: $error')),
      );
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  String _safePluginImportFileName(String name, String fallbackPath) {
    final rawName = name.trim().isNotEmpty ? name.trim() : fallbackPath.trim();
    final normalized = rawName.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final fileName = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.endsWith('.zip') || safe.endsWith('.wasm')
        ? safe
        : 'plugin.zip';
  }

  Future<void> _removePlugin(WasmPluginRecord record) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
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

    await _module.removePlugin(record);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Removed ${record.displayName}')));
  }

  Future<void> _installFromSource(WasmPluginSourceCatalogEntry entry) async {
    if (_installingSourceEntryIds.contains(entry.id)) return;
    await _module.uiLog.log(
      'plugin.source.install.start',
      'id=${entry.id} plugin=${entry.pluginId} version=${entry.version}',
    );
    setState(() {
      _installingSourceEntryIds = <String>{
        ..._installingSourceEntryIds,
        entry.id,
      };
    });

    try {
      final record = await _module.sourceCatalog.installFromSourceEntry(entry);
      await _module.uiLog.log(
        'plugin.source.install.success',
        'id=${entry.id} plugin=${record.pluginId ?? "-"} '
            'version=${record.pluginVersion ?? "-"} kind=${record.packageKind}',
      );
      await _reload();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Installed ${record.displayName} from source'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on FormatException catch (error) {
      await _module.uiLog.log(
        'plugin.source.install.error',
        'id=${entry.id} format=${error.message}',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      await _module.uiLog.log(
        'plugin.source.install.error',
        'id=${entry.id} exception=$error',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to install ${entry.displayName}: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _installingSourceEntryIds =
              _installingSourceEntryIds
                  .where((value) => value != entry.id)
                  .toSet();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding =
            constraints.maxWidth < 600
                ? 12.0
                : constraints.maxWidth < 1000
                ? 20.0
                : 28.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            28,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PluginScreenOverview(
                      installedCount: _installed.length,
                      catalogCount: _sourceCatalogSnapshot?.entries.length ?? 0,
                      loading: _loading || _loadingSourceCatalog,
                    ),
                    const SizedBox(height: 16),
                    _InstalledSection(
                      loading: _loading,
                      installing: _installing,
                      installed: _installed,
                      onInstallPressed: _installPlugin,
                      onRemovePressed: _removePlugin,
                      onOpenWorkspacePressed: (record) {
                        switch (installedPluginWorkspaceContractKind(record)) {
                          case bingxFuturesContractKind:
                            return () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => TradingDroneScreen(
                                      runtime: widget.runtime,
                                    ),
                              ),
                            );
                          case capsuleChatContractKind:
                            return () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => CapsuleChatPluginScreen(
                                      module: _module,
                                      onUnreadChanged:
                                          widget.onChatUnreadChanged,
                                    ),
                              ),
                            );
                          case moltbookAmbassadorContractKind:
                            return () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => MoltbookAmbassadorScreen(
                                      module: _module.moltbook,
                                    ),
                              ),
                            );
                          default:
                            return null;
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _SourceCatalogSection(
                      loading: _loadingSourceCatalog,
                      sourceName: _sourceCatalogSnapshot?.sourceName,
                      sourceId: _sourceCatalogSnapshot?.sourceId,
                      sourceError: _sourceCatalogError,
                      entries:
                          _sourceCatalogSnapshot?.entries ??
                          const <WasmPluginSourceCatalogEntry>[],
                      installed: _installed,
                      installingEntryIds: _installingSourceEntryIds,
                      onRefreshPressed: _reloadSourceCatalog,
                      onInstallPressed: _installFromSource,
                    ),
                    const SizedBox(height: 16),
                    _AdvancedPluginTools(
                      children: [
                        const _SectionTitle(
                          title: 'Boundary Rules',
                          subtitle:
                              'The safety constraints applied to every plugin.',
                        ),
                        const SizedBox(height: 12),
                        _PluginGrid(
                          maxColumns: 3,
                          children:
                              _boundaryRules
                                  .map((rule) => _RuleTile(rule: rule))
                                  .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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

class _PluginScreenOverview extends StatelessWidget {
  final int installedCount;
  final int catalogCount;
  final bool loading;

  const _PluginScreenOverview({
    required this.installedCount,
    required this.catalogCount,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292F3A)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = Row(
            children: [
              const _PluginIconPlate(
                icon: Icons.extension_rounded,
                accent: Color(0xFFC5A8FF),
                glow: Color(0xFF32254D),
                size: 42,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Extend your capsule',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Install packages, open plugin workspaces and inspect runtime status.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverviewMetric(
                icon: Icons.inventory_2_outlined,
                label: loading ? 'Loading' : '$installedCount installed',
              ),
              _OverviewMetric(
                icon: Icons.cloud_download_outlined,
                label: loading ? 'Catalog' : '$catalogCount available',
              ),
              const _OverviewMetric(
                icon: Icons.shield_outlined,
                label: 'Sandboxed',
                accent: Color(0xFF72D98B),
              ),
            ],
          );

          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [description, const SizedBox(height: 14), metrics],
            );
          }
          return Row(
            children: [
              Expanded(child: description),
              const SizedBox(width: 24),
              metrics,
            ],
          );
        },
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;

  const _OverviewMetric({required this.icon, required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFFB8C0CD);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF10141B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPluginTools extends StatelessWidget {
  final List<Widget> children;

  const _AdvancedPluginTools({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF292F38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
          leading: const Icon(Icons.tune_rounded, color: Color(0xFF9FA8B6)),
          title: const Text(
            'Advanced tools',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Host diagnostics and plugin boundary details',
            style: TextStyle(color: Color(0xFF8E98A7)),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _InstalledSection extends StatelessWidget {
  final bool loading;
  final bool installing;
  final List<WasmPluginRecord> installed;
  final Future<void> Function() onInstallPressed;
  final Future<void> Function(WasmPluginRecord record) onRemovePressed;
  final VoidCallback? Function(WasmPluginRecord record) onOpenWorkspacePressed;

  const _InstalledSection({
    required this.loading,
    required this.installing,
    required this.installed,
    required this.onInstallPressed,
    required this.onRemovePressed,
    required this.onOpenWorkspacePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12161D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF292F38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Installed plugins',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Packages available to this device.',
                    style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
                  ),
                ],
              );
              final action = FilledButton.icon(
                onPressed: installing ? null : onInstallPressed,
                icon:
                    installing
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.add_rounded),
                label: Text(installing ? 'Installing' : 'Add package'),
              );

              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerLeft, child: action),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  action,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (installed.isEmpty)
            const _EmptyInstalledState()
          else
            _PluginGrid(
              maxColumns: 3,
              children:
                  installed
                      .map(
                        (record) => _InstalledPluginTile(
                          record: record,
                          onRemovePressed: () => onRemovePressed(record),
                          onOpenWorkspacePressed: onOpenWorkspacePressed(
                            record,
                          ),
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }
}

class _SourceCatalogSection extends StatelessWidget {
  final bool loading;
  final String? sourceName;
  final String? sourceId;
  final String? sourceError;
  final List<WasmPluginSourceCatalogEntry> entries;
  final List<WasmPluginRecord> installed;
  final Set<String> installingEntryIds;
  final Future<void> Function() onRefreshPressed;
  final Future<void> Function(WasmPluginSourceCatalogEntry entry)
  onInstallPressed;

  const _SourceCatalogSection({
    required this.loading,
    required this.sourceName,
    required this.sourceId,
    required this.sourceError,
    required this.entries,
    required this.installed,
    required this.installingEntryIds,
    required this.onRefreshPressed,
    required this.onInstallPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12161D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF292F38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discover plugins',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sourceName == null
                        ? 'Packages published by the configured source.'
                        : sourceName!,
                    style: const TextStyle(
                      color: Color(0xFF9CA7B5),
                      height: 1.35,
                    ),
                  ),
                ],
              );
              final action = IconButton(
                onPressed: loading ? null : onRefreshPressed,
                tooltip: 'Refresh catalog',
                icon:
                    loading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh_rounded),
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  action,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (sourceError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1D1F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6B3A3F)),
              ),
              child: Text(
                sourceError!,
                style: const TextStyle(color: Color(0xFFFFA4A4), height: 1.35),
              ),
            )
          else if (loading)
            const Center(child: CircularProgressIndicator())
          else if (entries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF11161D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262F3B)),
              ),
              child: const Text(
                'Source catalog is empty.',
                style: TextStyle(color: Color(0xFF93A0B1)),
              ),
            )
          else
            _PluginGrid(
              maxColumns: 3,
              children:
                  entries.map((entry) {
                    final busy = installingEntryIds.contains(entry.id);
                    final installedAlready = _isEntryInstalled(entry);
                    return _CatalogEntryTile(
                      entry: entry,
                      busy: busy,
                      installed: installedAlready,
                      onInstallPressed: () => onInstallPressed(entry),
                    );
                  }).toList(),
            ),
        ],
      ),
    );
  }

  bool _isEntryInstalled(WasmPluginSourceCatalogEntry entry) {
    final pluginId = entry.pluginId.trim().toLowerCase();
    final version = entry.version.trim().toLowerCase();
    final packageKind = entry.packageKind.trim().toLowerCase();
    return installed.any((record) {
      final recordPluginId = (record.pluginId ?? '').trim().toLowerCase();
      final recordVersion = (record.pluginVersion ?? '').trim().toLowerCase();
      final recordPackageKind = record.packageKind.trim().toLowerCase();
      return recordPluginId == pluginId &&
          recordVersion == version &&
          recordPackageKind == packageKind;
    });
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
          Icon(Icons.extension_off_rounded, color: Color(0xFF728196), size: 26),
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

class _CatalogEntryTile extends StatelessWidget {
  final WasmPluginSourceCatalogEntry entry;
  final bool busy;
  final bool installed;
  final VoidCallback onInstallPressed;

  const _CatalogEntryTile({
    required this.entry,
    required this.busy,
    required this.installed,
    required this.onInstallPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _InstalledPluginTile._accentForName(entry.displayName);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B323D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIconPlate(
                icon: Icons.extension_rounded,
                accent: accent,
                glow: accent.withAlpha(25),
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.pluginId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E98A7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _OverviewMetric(
                icon: Icons.sell_outlined,
                label: 'v${entry.version}',
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: busy || installed ? null : onInstallPressed,
                icon:
                    installed
                        ? const Icon(Icons.check_circle_rounded, size: 18)
                        : busy
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  installed
                      ? 'Installed'
                      : busy
                      ? 'Installing'
                      : 'Install',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstalledPluginTile extends StatelessWidget {
  final WasmPluginRecord record;
  final Future<void> Function() onRemovePressed;
  final VoidCallback? onOpenWorkspacePressed;

  const _InstalledPluginTile({
    required this.record,
    required this.onRemovePressed,
    required this.onOpenWorkspacePressed,
  });

  @override
  Widget build(BuildContext context) {
    final displayName =
        record.displayName.isEmpty
            ? record.originalFileName
            : record.displayName;
    final accent = _accentForName(displayName);
    final isZipPackage = record.packageKind.trim().toLowerCase() == 'zip';
    final runtimeAbi = record.runtimeAbi?.trim() ?? '';
    final runtimeEntryExport = record.runtimeEntryExport?.trim() ?? '';
    final abiMatches =
        runtimeAbi == WasmPluginRuntimeService.requiredRuntimeAbi;
    final entryMatches =
        runtimeEntryExport == WasmPluginRuntimeService.requiredEntryExport;
    final ready = !isZipPackage || (abiMatches && entryMatches);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B323D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PluginIconPlate(
                  icon: _iconForFileName(record.originalFileName),
                  accent: accent,
                  glow: accent.withAlpha(30),
                  size: 38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        record.pluginId?.trim().isNotEmpty == true
                            ? record.pluginId!
                            : record.originalFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E98A7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemovePressed,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: 'Remove plugin',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        label: ready ? 'Ready' : 'Needs attention',
                        accent:
                            ready
                                ? const Color(0xFF75D98A)
                                : const Color(0xFFFFA06B),
                      ),
                      if (record.pluginVersion?.trim().isNotEmpty == true)
                        _OverviewMetric(
                          icon: Icons.sell_outlined,
                          label: 'v${record.pluginVersion}',
                        ),
                    ],
                  ),
                ),
                if (onOpenWorkspacePressed != null) ...[
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: ready ? onOpenWorkspacePressed : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Open'),
                  ),
                ],
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: const Text(
                'Technical details',
                style: TextStyle(
                  color: Color(0xFFAAB3C0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.inventory_2_outlined,
                        label:
                            '${record.packageKind.toUpperCase()} · ${_formatBytes(record.sizeBytes)}',
                      ),
                      _InfoChip(
                        icon: Icons.schedule_rounded,
                        label: _formatInstalledAt(record.installedAtIso),
                      ),
                      if (record.contractKind?.trim().isNotEmpty == true)
                        _InfoChip(
                          icon: Icons.gavel_outlined,
                          label: record.contractKind!,
                        ),
                      if (isZipPackage)
                        _InfoChip(
                          icon:
                              abiMatches
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                          label:
                              runtimeAbi.isEmpty ? 'ABI missing' : runtimeAbi,
                          accent:
                              abiMatches
                                  ? const Color(0xFF75D98A)
                                  : const Color(0xFFFF8A7A),
                        ),
                      if (isZipPackage)
                        _InfoChip(
                          icon:
                              entryMatches
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                          label:
                              runtimeEntryExport.isEmpty
                                  ? 'Entry missing'
                                  : runtimeEntryExport,
                          accent:
                              entryMatches
                                  ? const Color(0xFF75D98A)
                                  : const Color(0xFFFF8A7A),
                        ),
                      if (record.capabilities.isNotEmpty)
                        _InfoChip(
                          icon: Icons.verified_user_outlined,
                          label: '${record.capabilities.length} capabilities',
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
    if (lower.contains('bingx') || lower.contains('trading')) {
      return const Color(0xFFFFC76A);
    }
    if (lower.contains('chat')) return const Color(0xFFC5A8FF);
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
    if (lower.contains('bingx') || lower.contains('trading')) {
      return Icons.candlestick_chart_rounded;
    }
    if (lower.contains('chat')) return Icons.forum_outlined;
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF96A2B2), height: 1.35),
        ),
      ],
    );
  }
}

class _PluginGrid extends StatelessWidget {
  final List<Widget> children;
  final int? maxColumns;

  const _PluginGrid({required this.children, this.maxColumns});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var columns =
            width >= 1120
                ? 4
                : width >= 780
                ? 3
                : width >= 540
                ? 2
                : 1;
        if (maxColumns != null && columns > maxColumns!) {
          columns = maxColumns!;
        }

        const gap = 12.0;
        final itemWidth =
            columns == 1 ? width : (width - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
        );
      },
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
          const SizedBox(height: 28),
          Text(
            rule.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            rule.description,
            style: const TextStyle(color: Color(0xFF9EABBA), height: 1.35),
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
    this.size = 24,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Icon(icon, color: accent, size: size * 0.52),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _StatusPill({required this.label, required this.accent});

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
        style: TextStyle(color: accent, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;

  const _InfoChip({required this.icon, required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final iconAndTextColor = accent ?? const Color(0xFFAEB9C7);
    final backgroundColor =
        accent == null ? const Color(0xFF10161D) : accent!.withAlpha(28);
    final borderColor =
        accent == null ? const Color(0xFF29313D) : accent!.withAlpha(120);
    final maxWidth = (MediaQuery.sizeOf(context).width - 80).clamp(
      160.0,
      520.0,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconAndTextColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: iconAndTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
