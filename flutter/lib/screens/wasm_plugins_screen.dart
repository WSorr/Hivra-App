import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_runtime_service.dart';
import '../services/capsule_chat_delivery_service.dart';
import '../services/consensus_processor.dart';
import '../services/manual_consensus_check_service.dart';
import '../services/plugin_demo_contract_runner_service.dart';
import '../services/plugin_execution_guard_service.dart';
import '../services/plugin_host_api_service.dart';
import '../services/temperature_tomorrow_contract_service.dart';
import '../services/ui_event_log_service.dart';
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
  final PluginDemoContractRunnerService _demoRunner =
      AppRuntimeService().buildPluginDemoContractRunnerService();
  final PluginExecutionGuardService _guard =
      AppRuntimeService().buildPluginExecutionGuardService();
  final ManualConsensusCheckService _manualChecks =
      AppRuntimeService().buildManualConsensusCheckService();
  final PluginHostApiService _pluginHostApi =
      AppRuntimeService().buildPluginHostApiService();
  final CapsuleChatDeliveryService _chatDelivery =
      AppRuntimeService().buildCapsuleChatDeliveryService();
  final UiEventLogService _uiLog = const UiEventLogService();
  final TextEditingController _chatPeerController = TextEditingController();
  final TextEditingController _chatMessageController =
      TextEditingController(text: 'hello from capsule chat');
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
  bool _runningDemo = false;
  bool _runningChat = false;
  PluginDemoRunResult? _lastDemoResult;
  PluginHostApiResponse? _lastChatResponse;
  List<CapsuleChatInboxMessage> _chatInbox = const <CapsuleChatInboxMessage>[];
  int _chatDroppedByConsensus = 0;

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

  @override
  void dispose() {
    _chatPeerController.dispose();
    _chatMessageController.dispose();
    super.dispose();
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

  Future<void> _runTemperatureDemo() async {
    if (_runningDemo) return;
    setState(() {
      _runningDemo = true;
    });

    try {
      final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
      final targetDateUtc = _dateOnlyUtc(tomorrow);
      final result = _demoRunner.runTemperatureTomorrowDemo(
        contract: TemperatureTomorrowContractSpec(
          pluginId: 'hivra.contract.temperature-li.tomorrow.v1',
          locationCode: 'LI',
          targetDateUtc: targetDateUtc,
          thresholdDeciCelsius: 85,
          proposerRule: TemperatureOutcomeRule.above,
          drawOnEqual: true,
        ),
        observation: TemperatureOracleObservation(
          sourceId: 'oracle.mock.weather.v1',
          eventId: 'demo-${DateTime.now().millisecondsSinceEpoch}',
          locationCode: 'LI',
          targetDateUtc: targetDateUtc,
          recordedAtUtc: DateTime.now().toUtc().toIso8601String(),
          observedDeciCelsius: 90,
        ),
      );

      if (!mounted) return;
      setState(() {
        _lastDemoResult = result;
      });

      final messenger = ScaffoldMessenger.of(context);
      switch (result.state) {
        case PluginDemoRunState.noPairwisePaths:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No pairwise consensus paths yet. Create at least one relationship first.',
              ),
            ),
          );
          break;
        case PluginDemoRunState.blocked:
          final reason = result.blockingFacts.isEmpty
              ? 'Consensus guard blocked execution.'
              : result.blockingFacts.first.label;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Demo blocked for ${result.blockedPairCount} pair(s): $reason',
              ),
            ),
          );
          break;
        case PluginDemoRunState.partial:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Demo partial: executed ${result.readyPairCount}, blocked ${result.blockedPairCount}.',
              ),
            ),
          );
          break;
        case PluginDemoRunState.executed:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Demo settled for ${result.readyPairCount} pair(s).',
              ),
            ),
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningDemo = false;
        });
      }
    }
  }

  Future<void> _fillPeerFromConsensus() async {
    final checks = _manualChecks.loadChecks();
    if (checks.isEmpty) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No consensus peers yet. Create at least one relationship first.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final preferred = checks.firstWhere(
      (check) => check.isSignable,
      orElse: () => checks.first,
    );
    if (!mounted) return;
    setState(() {
      _chatPeerController.text = preferred.peerHex;
    });
  }

  Future<void> _runCapsuleChat() async {
    if (_runningChat) return;
    if (!mounted) return;

    final peerHex = _chatPeerController.text.trim().toLowerCase();
    final messageText = _chatMessageController.text;
    final createdAtUtc = DateTime.now().toUtc().toIso8601String();
    final clientMessageId = 'ui-${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      _runningChat = true;
    });

    try {
      await _uiLog.log(
        'chat.send.request',
        'peer=${peerHex.isEmpty ? "empty" : "${peerHex.substring(0, 8)}.."} textBytes=${messageText.length}',
      );
      final response = _pluginHostApi.execute(
        PluginHostApiRequest(
          schemaVersion: PluginHostApiService.schemaVersion,
          pluginId: PluginHostApiService.capsuleChatPluginId,
          method: PluginHostApiService.postCapsuleChatMethod,
          args: <String, dynamic>{
            'peer_hex': peerHex,
            'client_message_id': clientMessageId,
            'message_text': messageText,
            'created_at_utc': createdAtUtc,
          },
        ),
      );

      if (!mounted) return;
      setState(() {
        _lastChatResponse = response;
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      switch (response.status) {
        case PluginHostApiStatus.executed:
          final envelopeHash =
              response.result?['envelope_hash_hex']?.toString() ?? '';
          final shortHash = envelopeHash.length >= 12
              ? '${envelopeHash.substring(0, 12)}..'
              : envelopeHash;
          final canonicalEnvelopeJson =
              response.result?['canonical_envelope_json']?.toString() ?? '';
          final sendResult = await _chatDelivery.sendCanonicalEnvelope(
            peerHex: peerHex,
            canonicalEnvelopeJson: canonicalEnvelopeJson,
          );
          if (!sendResult.isSuccess) {
            await _uiLog.log(
              'chat.send.transport.error',
              'code=${sendResult.code} blocked=${sendResult.blockedByConsensus} deliveryPeer=${sendResult.deliveryPeerHex ?? "none"} message=${sendResult.errorMessage ?? "unknown"}',
            );
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  sendResult.errorMessage ??
                      'Chat transport failed (code ${sendResult.code})',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            break;
          }
          await _uiLog.log(
            'chat.send.success',
            'peer=${peerHex.substring(0, 8)}.. deliveryPeer=${sendResult.deliveryPeerHex ?? "none"} hash=${shortHash.isEmpty ? "none" : shortHash}',
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Chat message sent: $shortHash',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          await _refreshCapsuleChatInbox(silentWhenEmpty: true);
          break;
        case PluginHostApiStatus.blocked:
          final reason = response.blockingFacts.isEmpty
              ? 'Consensus guard blocked execution.'
              : response.blockingFacts.first.label;
          await _uiLog.log(
            'chat.send.blocked',
            reason,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(reason),
              duration: const Duration(seconds: 2),
            ),
          );
          break;
        case PluginHostApiStatus.rejected:
          await _uiLog.log(
            'chat.send.rejected',
            response.errorMessage ?? 'Chat request rejected',
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                response.errorMessage ?? 'Chat request rejected',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningChat = false;
        });
      }
    }
  }

  Future<void> _refreshCapsuleChatInbox({bool silentWhenEmpty = false}) async {
    if (!mounted) return;
    final result = await _chatDelivery.receiveAndFilter();
    await _uiLog.log(
      'chat.fetch.result',
      'code=${result.code} received=${result.messages.length} dropped=${result.droppedByConsensus}'
          '${result.errorMessage == null ? "" : " error=${result.errorMessage}"}',
    );
    if (!mounted) return;
    if (result.code < 0) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'Chat receive failed (code ${result.code})',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      final byId = <String, CapsuleChatInboxMessage>{
        for (final message in _chatInbox) message.id: message,
      };
      for (final message in result.messages) {
        byId[message.id] = message;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      _chatDroppedByConsensus = result.droppedByConsensus;
      _chatInbox = List<CapsuleChatInboxMessage>.unmodifiable(merged);
    });

    if (result.messages.isEmpty && silentWhenEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final droppedNote = result.droppedByConsensus > 0
        ? ' · dropped ${result.droppedByConsensus} by consensus'
        : '';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Chat inbox +${result.messages.length}$droppedNote'),
        duration: const Duration(seconds: 2),
      ),
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
          title: 'Contract Demo',
          subtitle:
              'Manual dry-run for the first test smart-contract (no wasm execution yet).',
        ),
        const SizedBox(height: 10),
        _ContractDemoPanel(
          running: _runningDemo,
          lastResult: _lastDemoResult,
          onRunPressed: _runTemperatureDemo,
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          title: 'Capsule Chat',
          subtitle:
              'Pre-host deterministic envelope call over plugin API boundary.',
        ),
        const SizedBox(height: 10),
        _CapsuleChatPanel(
          running: _runningChat,
          lastResponse: _lastChatResponse,
          inbox: _chatInbox,
          droppedByConsensus: _chatDroppedByConsensus,
          peerController: _chatPeerController,
          messageController: _chatMessageController,
          onUsePeerPressed: _fillPeerFromConsensus,
          onRefreshInboxPressed: _refreshCapsuleChatInbox,
          onRunPressed: _runCapsuleChat,
        ),
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
              if (record.pluginId != null && record.pluginId!.isNotEmpty)
                _InfoChip(
                  icon: Icons.badge_outlined,
                  label: record.pluginId!,
                ),
              if (record.contractKind != null &&
                  record.contractKind!.isNotEmpty)
                _InfoChip(
                  icon: Icons.gavel_outlined,
                  label: record.contractKind!,
                ),
              if (record.capabilities.isNotEmpty)
                _InfoChip(
                  icon: Icons.verified_user_outlined,
                  label: '${record.capabilities.length} capabilities',
                ),
              _InfoChip(
                icon: Icons.inventory_2_outlined,
                label: record.packageKind.toUpperCase(),
              ),
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

class _ContractDemoPanel extends StatelessWidget {
  final bool running;
  final PluginDemoRunResult? lastResult;
  final Future<void> Function() onRunPressed;

  const _ContractDemoPanel({
    required this.running,
    required this.lastResult,
    required this.onRunPressed,
  });

  @override
  Widget build(BuildContext context) {
    final result = lastResult;
    final firstExecuted = result?.firstExecutedPair;
    PluginDemoPairRunResult? firstBlocked;
    if (result != null) {
      for (final pair in result.pairResults) {
        if (!pair.isExecuted) {
          firstBlocked = pair;
          break;
        }
      }
    }
    final accent = switch (result?.state) {
      PluginDemoRunState.executed => const Color(0xFF75D98A),
      PluginDemoRunState.partial => const Color(0xFFFFC76A),
      PluginDemoRunState.blocked => const Color(0xFFFF8A7A),
      PluginDemoRunState.noPairwisePaths => const Color(0xFF75D2FF),
      null => const Color(0xFF7F92A8),
    };
    final title = switch (result?.state) {
      PluginDemoRunState.executed => 'Last run settled',
      PluginDemoRunState.partial => 'Last run mixed',
      PluginDemoRunState.blocked => 'Last run blocked by guard',
      PluginDemoRunState.noPairwisePaths => 'No pairwise paths yet',
      null => 'Not run yet',
    };
    final summary = switch (result?.state) {
      PluginDemoRunState.executed => firstExecuted == null
          ? 'Demo reported executed.'
          : 'Settled ${result!.readyPairCount} pair(s). Example: ${firstExecuted.settlement!.outcome.name}, hash ${firstExecuted.settlement!.settlementHashHex.substring(0, 12)}..',
      PluginDemoRunState.partial =>
        'Settled ${result!.readyPairCount} pair(s), blocked ${result.blockedPairCount} pair(s).',
      PluginDemoRunState.blocked => firstBlocked == null
          ? 'Consensus guard blocked execution.'
          : 'Blocking reason: ${firstBlocked.blockingFacts.isEmpty ? 'unknown' : firstBlocked.blockingFacts.first.label}',
      PluginDemoRunState.noPairwisePaths =>
        'Create at least one relationship so consensus checks can derive a pairwise path.',
      null =>
        'Runs a deterministic temperature dispute demo for tomorrow in Liechtenstein. Execution remains gated by consensus guard.',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIconPlate(
                icon: Icons.science_outlined,
                accent: accent,
                glow: accent.withAlpha(24),
              ),
              const SizedBox(width: 12),
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
                    if (result != null &&
                        result.state != PluginDemoRunState.noPairwisePaths) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.verified_outlined,
                            label: 'Ready: ${result.readyPairCount}',
                          ),
                          _InfoChip(
                            icon: Icons.block_outlined,
                            label: 'Blocked: ${result.blockedPairCount}',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (result != null && result.pairResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Pairwise results',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFCFD7E2),
              ),
            ),
            const SizedBox(height: 8),
            ...result.pairResults.map(
              (pair) => _DemoPairRunRow(pair: pair),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: running ? null : onRunPressed,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(running ? 'Running demo' : 'Run Demo Settlement'),
          ),
        ],
      ),
    );
  }
}

class _DemoPairRunRow extends StatelessWidget {
  final PluginDemoPairRunResult pair;

  const _DemoPairRunRow({required this.pair});

  @override
  Widget build(BuildContext context) {
    final accent =
        pair.isExecuted ? const Color(0xFF75D98A) : const Color(0xFFFF8A7A);
    final title = pair.peerLabel ?? pair.peerHex;
    final detail = pair.isExecuted
        ? 'Settled: ${pair.settlement!.outcome.name} · ${pair.settlement!.settlementHashHex.substring(0, 10)}..'
        : pair.blockingFacts.isEmpty
            ? 'Blocked'
            : 'Blocked: ${pair.blockingFacts.first.label}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(
            pair.isExecuted ? Icons.check_circle_outline : Icons.block_outlined,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title\n$detail',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFFC8D2DF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapsuleChatPanel extends StatelessWidget {
  final bool running;
  final PluginHostApiResponse? lastResponse;
  final List<CapsuleChatInboxMessage> inbox;
  final int droppedByConsensus;
  final TextEditingController peerController;
  final TextEditingController messageController;
  final Future<void> Function() onUsePeerPressed;
  final Future<void> Function() onRefreshInboxPressed;
  final Future<void> Function() onRunPressed;

  const _CapsuleChatPanel({
    required this.running,
    required this.lastResponse,
    required this.inbox,
    required this.droppedByConsensus,
    required this.peerController,
    required this.messageController,
    required this.onUsePeerPressed,
    required this.onRefreshInboxPressed,
    required this.onRunPressed,
  });

  @override
  Widget build(BuildContext context) {
    final response = lastResponse;
    final status = response?.status;
    final accent = switch (status) {
      PluginHostApiStatus.executed => const Color(0xFF75D98A),
      PluginHostApiStatus.blocked => const Color(0xFFFFC76A),
      PluginHostApiStatus.rejected => const Color(0xFFFF8A7A),
      null => const Color(0xFF7F92A8),
    };
    final title = switch (status) {
      PluginHostApiStatus.executed => 'Envelope prepared',
      PluginHostApiStatus.blocked => 'Blocked by guard',
      PluginHostApiStatus.rejected => 'Request rejected',
      null => 'Ready',
    };
    final details = switch (status) {
      PluginHostApiStatus.executed => () {
          final hash = response?.result?['envelope_hash_hex']?.toString() ?? '';
          return hash.isEmpty
              ? 'Deterministic envelope created.'
              : 'Envelope hash: ${hash.substring(0, hash.length < 16 ? hash.length : 16)}..';
        }(),
      PluginHostApiStatus.blocked => response!.blockingFacts.isEmpty
          ? 'Consensus guard blocked execution.'
          : response.blockingFacts.first.label,
      PluginHostApiStatus.rejected =>
        response?.errorMessage ?? 'Input rejected by host API.',
      null =>
        'Deterministic host envelope + transport send, guarded by pairwise consensus.',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121821),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIconPlate(
                icon: Icons.chat_bubble_outline_rounded,
                accent: accent,
                glow: accent.withAlpha(24),
              ),
              const SizedBox(width: 12),
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
                      details,
                      style: const TextStyle(
                        color: Color(0xFF9FAABA),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: peerController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Peer hex (64 lowercase chars)',
              hintText: 'bbbb...bbbb',
              filled: true,
              fillColor: const Color(0xFF0F141C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: messageController,
            minLines: 2,
            maxLines: 4,
            maxLength: 1024,
            decoration: InputDecoration(
              labelText: 'Message text',
              filled: true,
              fillColor: const Color(0xFF0F141C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: running ? null : onUsePeerPressed,
                icon: const Icon(Icons.group_outlined),
                label: const Text('Use Consensus Peer'),
              ),
              OutlinedButton.icon(
                onPressed: running ? null : onRefreshInboxPressed,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Fetch Inbox'),
              ),
              FilledButton.icon(
                onPressed: running ? null : onRunPressed,
                icon: running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(running ? 'Preparing' : 'Run Capsule Chat'),
              ),
            ],
          ),
          if (response != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.flag_outlined,
                  label: 'Status: ${response.status.name}',
                ),
                _InfoChip(
                  icon: Icons.tag_outlined,
                  label: 'Method: ${response.method}',
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.mail_outline,
                label: 'Inbox: ${inbox.length}',
              ),
              _InfoChip(
                icon: Icons.shield_outlined,
                label: 'Dropped: $droppedByConsensus',
              ),
            ],
          ),
          if (inbox.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Incoming',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFCFD7E2),
              ),
            ),
            const SizedBox(height: 8),
            ...inbox.reversed.take(8).map(
                  (message) => _ChatInboxRow(message: message),
                ),
          ],
        ],
      ),
    );
  }
}

class _ChatInboxRow extends StatelessWidget {
  final CapsuleChatInboxMessage message;

  const _ChatInboxRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final shortPeer = message.fromHex.length >= 12
        ? '${message.fromHex.substring(0, 6)}...${message.fromHex.substring(message.fromHex.length - 4)}'
        : message.fromHex;
    final shortHash = message.envelopeHashHex.length >= 12
        ? '${message.envelopeHashHex.substring(0, 12)}..'
        : message.envelopeHashHex;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A5E74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.messageText,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE0E6EE),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'from $shortPeer · ${message.createdAtUtc}${shortHash.isEmpty ? '' : ' · $shortHash'}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF95A5B7),
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

String _dateOnlyUtc(DateTime utcDateTime) {
  final year = utcDateTime.year.toString().padLeft(4, '0');
  final month = utcDateTime.month.toString().padLeft(2, '0');
  final day = utcDateTime.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
