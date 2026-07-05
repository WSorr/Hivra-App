import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_capsule_inspection_service.dart';
import '../services/ai_developer_workspace_service.dart';
import '../services/ai_doctor_chat_service.dart';
import '../services/ai_doctor_prompt_service.dart';
import '../services/ai_plugin_audit_service.dart';
import '../services/app_runtime_service.dart';

class CapsuleDoctorScreen extends StatefulWidget {
  final AppRuntimeService runtime;

  const CapsuleDoctorScreen({
    super.key,
    required this.runtime,
  });

  @override
  State<CapsuleDoctorScreen> createState() => _CapsuleDoctorScreenState();
}

class _CapsuleDoctorScreenState extends State<CapsuleDoctorScreen> {
  late final AiCapsuleInspectionService _service;
  late final AiDoctorChatService _chatService;
  late final AiPluginAuditService _pluginAuditService;
  late final AiDeveloperWorkspaceService _developerWorkspaceService;
  Future<AiCapsuleInspectionReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.runtime.buildAiCapsuleInspectionService();
    _chatService = widget.runtime.buildAiDoctorChatService();
    _pluginAuditService = widget.runtime.buildAiPluginAuditService();
    _developerWorkspaceService =
        widget.runtime.buildAiDeveloperWorkspaceService();
    _reportFuture = _service.inspect();
  }

  void _refresh() {
    setState(() {
      _reportFuture = _service.inspect();
    });
  }

  Future<void> _copySnapshot(AiCapsuleInspectionReport report) async {
    await Clipboard.setData(
      ClipboardData(text: report.snapshot.toPrettyJson()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capsule Doctor snapshot copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsule Doctor'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh local diagnosis',
          ),
        ],
      ),
      body: FutureBuilder<AiCapsuleInspectionReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final report = snapshot.data;
          if (report == null) {
            return _ErrorState(
              error: 'No diagnosis report',
              onRetry: _refresh,
            );
          }
          return _ReportView(
            report: report,
            chatService: _chatService,
            pluginAuditService: _pluginAuditService,
            developerWorkspaceService: _developerWorkspaceService,
            onCopySnapshot: () => _copySnapshot(report),
          );
        },
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final AiCapsuleInspectionReport report;
  final AiDoctorChatService chatService;
  final AiPluginAuditService pluginAuditService;
  final AiDeveloperWorkspaceService developerWorkspaceService;
  final VoidCallback onCopySnapshot;

  const _ReportView({
    required this.report,
    required this.chatService,
    required this.pluginAuditService,
    required this.developerWorkspaceService,
    required this.onCopySnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: _statusColor(report.statusLabel),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        report.statusLabel,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCopySnapshot,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy snapshot'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Local deterministic diagnosis. No AI provider call, no upload, no secrets.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Snapshot ${report.snapshot.snapshotHashHex}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...report.findings.map(_FindingCard.new),
        const SizedBox(height: 12),
        _AiDoctorChatCard(
          snapshot: report.snapshot,
          chatService: chatService,
        ),
        const SizedBox(height: 12),
        _PluginAuditCard(service: pluginAuditService),
        const SizedBox(height: 12),
        _DeveloperWorkspaceCard(service: developerWorkspaceService),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Ledger',
          rows: _rows(report.snapshot.ledgerSummary),
        ),
        _SectionCard(
          title: 'Invitations',
          rows: _rows(report.snapshot.invitationSummary),
        ),
        _SectionCard(
          title: 'Relationships',
          rows: _rows(report.snapshot.relationshipSummary),
        ),
        _SectionCard(
          title: 'Transport Outbox',
          rows: _rows(report.snapshot.transportSummary),
        ),
        _SectionCard(
          title: 'Consensus',
          rows: _rows(report.snapshot.consensusSummary),
        ),
        _SectionCard(
          title: 'Bootstrap',
          rows: _rows(report.snapshot.bootstrapSummary),
        ),
        _SectionCard(
          title: 'Filesystem Trace',
          rows: _rows(report.snapshot.traceSummary),
        ),
        _SectionCard(
          title: 'Plugins',
          rows: _rows(report.snapshot.pluginSummary),
        ),
      ],
    );
  }

  static List<_Row> _rows(Map<String, dynamic> map) {
    final keys = map.keys.toList()..sort();
    return keys
        .map((key) => _Row(key, _displayValue(map[key])))
        .toList(growable: false);
  }

  static String _displayValue(Object? value) {
    if (value is List) {
      if (value.isEmpty) return 'none';
      if (value.length > 5) {
        return '${value.take(5).join(', ')} +${value.length - 5}';
      }
      return value.join(', ');
    }
    return value?.toString() ?? 'null';
  }

  static Color _statusColor(String status) {
    return switch (status) {
      'Critical' => Colors.red,
      'Needs attention' => Colors.orange,
      _ => Colors.green,
    };
  }
}

class _FindingCard extends StatelessWidget {
  final AiCapsuleInspectionFinding finding;

  const _FindingCard(this.finding);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_icon(finding.severity), color: _color(finding.severity)),
        title: Text(finding.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${finding.area}: ${finding.detail}'),
            const SizedBox(height: 6),
            Text('Action: ${finding.recommendedAction}'),
          ],
        ),
      ),
    );
  }

  IconData _icon(String severity) {
    return switch (severity) {
      'critical' => Icons.error,
      'warning' => Icons.warning,
      _ => Icons.info,
    };
  }

  Color _color(String severity) {
    return switch (severity) {
      'critical' => Colors.red,
      'warning' => Colors.orange,
      _ => Colors.blue,
    };
  }
}

class _AiDoctorChatCard extends StatefulWidget {
  final AiCapsuleInspectionSnapshot snapshot;
  final AiDoctorChatService chatService;

  const _AiDoctorChatCard({
    required this.snapshot,
    required this.chatService,
  });

  @override
  State<_AiDoctorChatCard> createState() => _AiDoctorChatCardState();
}

class _AiDoctorChatCardState extends State<_AiDoctorChatCard> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController =
      TextEditingController(text: AiDoctorChatService.defaultModel);
  final TextEditingController _queryController = TextEditingController(
    text: 'What should I check next in this capsule?',
  );
  final Set<AiDoctorContextSection> _sections =
      AiDoctorContextSection.values.toSet();

  AiDoctorOutboundPreview? _preview;
  String? _answer;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await _run(() async {
      await widget.chatService.saveOpenAiApiKey(_apiKeyController.text);
      _apiKeyController.clear();
      _showSnack('AI Doctor key saved in secure storage');
    });
  }

  Future<void> _clearKey() async {
    await _run(() async {
      await widget.chatService.clearOpenAiApiKey();
      _apiKeyController.clear();
      _showSnack('AI Doctor key cleared');
    });
  }

  void _previewContext() {
    try {
      final preview = widget.chatService.preview(
        snapshot: widget.snapshot,
        userQuery: _queryController.text,
        sections: _sections,
      );
      setState(() {
        _preview = preview;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _askDoctor() async {
    await _run(() async {
      final result = await widget.chatService.ask(
        snapshot: widget.snapshot,
        userQuery: _queryController.text,
        sections: _sections,
        model: _modelController.text,
      );
      setState(() {
        _preview = result.preview;
        _answer = result.providerResponse.text;
      });
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_alt),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Doctor Chat',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Optional provider call over selected redacted sections. Advisory only; no ledger mutation and no repository access.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'OpenAI API key',
                helperText:
                    'Stored only in secure storage. No plaintext fallback.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _saveKey,
                  icon: const Icon(Icons.key),
                  label: const Text('Save key'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearKey,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear key'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Question',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Outbound sections', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: AiDoctorContextSection.values
                  .map(
                    (section) => FilterChip(
                      label: Text(section.label),
                      selected: _sections.contains(section),
                      onSelected: _busy
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _sections.add(section);
                                } else {
                                  _sections.remove(section);
                                }
                              });
                            },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _previewContext,
                  icon: const Icon(Icons.visibility),
                  label: const Text('Preview outbound context'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _askDoctor,
                  icon: const Icon(Icons.send),
                  label: const Text('Ask AI Doctor'),
                ),
              ],
            ),
            if (_preview != null) ...[
              const SizedBox(height: 12),
              _PreviewPanel(preview: _preview!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ],
            if (_answer != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                _answer!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final AiDoctorOutboundPreview preview;

  const _PreviewPanel({required this.preview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outbound preview', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText('Snapshot ${preview.snapshotHashHex}'),
          Text('Sections: ${preview.sectionsLabel}'),
          Text('Payload: ${preview.payloadBytes} bytes'),
          Text('Query: ${preview.userQueryBytes} bytes'),
          Text('Secrets redacted: ${preview.secretsRedacted}'),
        ],
      ),
    );
  }
}

class _PluginAuditCard extends StatefulWidget {
  final AiPluginAuditService service;

  const _PluginAuditCard({required this.service});

  @override
  State<_PluginAuditCard> createState() => _PluginAuditCardState();
}

class _PluginAuditCardState extends State<_PluginAuditCard> {
  Future<AiPluginAuditReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = widget.service.auditInstalledPlugins();
  }

  void _refresh() {
    setState(() {
      _reportFuture = widget.service.auditInstalledPlugins();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<AiPluginAuditReport>(
          future: _reportFuture,
          builder: (context, snapshot) {
            final report = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.extension,
                      color: report == null
                          ? null
                          : _pluginAuditStatusColor(report.statusLabel),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Plugin Auditor',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh plugin audit',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Read-only audit of installed plugin packages, ABI, entry export, declared capabilities, and package digest.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  Text(
                    snapshot.error.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.redAccent,
                    ),
                  )
                else if (report == null)
                  const Text('No plugin audit report')
                else ...[
                  SelectableText('Audit ${report.reportHashHex}'),
                  const SizedBox(height: 6),
                  Text(
                    '${report.entries.length} plugin(s) · ${report.statusLabel}',
                  ),
                  const SizedBox(height: 8),
                  if (report.entries.isEmpty)
                    const Text('No installed plugins.')
                  else
                    ...report.entries.map(_PluginAuditEntryTile.new),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Color _pluginAuditStatusColor(String status) {
    return switch (status) {
      'Critical' => Colors.red,
      'Needs attention' => Colors.orange,
      _ => Colors.green,
    };
  }
}

class _PluginAuditEntryTile extends StatelessWidget {
  final AiPluginAuditEntry entry;

  const _PluginAuditEntryTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(entry.pluginLabel),
      subtitle: Text(
        '${entry.pluginVersion ?? 'no version'} · ${entry.packageKind} · '
        '${entry.findings.length} finding(s)',
      ),
      children: [
        ListTile(
          dense: true,
          title: const Text('Package digest'),
          subtitle: SelectableText(entry.packageDigestHex),
        ),
        ListTile(
          dense: true,
          title: const Text('Capabilities'),
          subtitle: Text(
            entry.capabilities.isEmpty ? 'none' : entry.capabilities.join(', '),
          ),
        ),
        if (entry.findings.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No findings'),
          )
        else
          ...entry.findings.map(
            (finding) => ListTile(
              dense: true,
              leading: Icon(
                finding.severity == 'critical'
                    ? Icons.error_outline
                    : Icons.warning_amber,
                color:
                    finding.severity == 'critical' ? Colors.red : Colors.orange,
              ),
              title: Text(finding.title),
              subtitle: Text(
                '${finding.detail}\nAction: ${finding.recommendedAction}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _DeveloperWorkspaceCard extends StatefulWidget {
  final AiDeveloperWorkspaceService service;

  const _DeveloperWorkspaceCard({required this.service});

  @override
  State<_DeveloperWorkspaceCard> createState() =>
      _DeveloperWorkspaceCardState();
}

class _DeveloperWorkspaceCardState extends State<_DeveloperWorkspaceCard> {
  final TextEditingController _pathsController = TextEditingController(
    text: '/Volumes/Dev/projects/hivra\n/Volumes/Dev/projects/hivra-plugins',
  );
  final TextEditingController _selectedFilesController =
      TextEditingController();
  AiDeveloperWorkspaceReport? _report;
  AiDeveloperWorkspaceSelectedContext? _selectedContext;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pathsController.dispose();
    _selectedFilesController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final paths = _pathsController.text
          .split(RegExp(r'[\n,]+'))
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty);
      final report = await widget.service.scanLocalRepositories(paths);
      if (!mounted) return;
      setState(() {
        _report = report;
        _selectedContext = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _buildSelectedContext() async {
    final report = _report;
    if (report == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selections = _selectedFilesController.text
          .split(RegExp(r'[\n,]+'))
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty);
      final context = await widget.service.buildSelectedFileContext(
        report: report,
        selectedRelativePaths: selections,
      );
      if (!mounted) return;
      setState(() {
        _selectedContext = context;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Developer Workspace Preview',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Explicit local repository allowlist. Read-only scan returns file paths, sizes, hashes, and denylist findings; no source contents are uploaded or sent to AI.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathsController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Allowed repository paths',
                helperText: 'One local path per line. Scan is manual.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.manage_search),
              label: const Text('Scan workspace preview'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ],
            if (_report != null) ...[
              const SizedBox(height: 12),
              SelectableText('Workspace ${_report!.reportHashHex}'),
              const SizedBox(height: 8),
              ..._report!.repositories.map(_DeveloperWorkspaceRepoTile.new),
              const SizedBox(height: 12),
              TextField(
                controller: _selectedFilesController,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Selected relative files for developer context',
                  helperText:
                      'Manual selection only. Example: docs/specification.md',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _buildSelectedContext,
                icon: const Icon(Icons.fact_check),
                label: const Text('Build selected context preview'),
              ),
            ],
            if (_selectedContext != null) ...[
              const SizedBox(height: 12),
              _DeveloperSelectedContextPanel(contextData: _selectedContext!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeveloperSelectedContextPanel extends StatelessWidget {
  final AiDeveloperWorkspaceSelectedContext contextData;

  const _DeveloperSelectedContextPanel({required this.contextData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected developer context', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText('Context ${contextData.contextHashHex}'),
          Text('${contextData.snippets.length} snippet(s)'),
          Text('${contextData.payloadBytes} bytes'),
          if (contextData.findings.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...contextData.findings.map(
              (finding) => Text('${finding.severity}: ${finding.title}'),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Preview JSON'),
            children: [
              SelectableText(contextData.toPrettyJson()),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeveloperWorkspaceRepoTile extends StatelessWidget {
  final AiDeveloperWorkspaceRepoSummary repo;

  const _DeveloperWorkspaceRepoTile(this.repo);

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(repo.rootPath),
      subtitle: Text(
        '${repo.scannedFileCount} files · '
        '${repo.skippedFileCount} skipped files · '
        '${repo.findings.length} finding(s)',
      ),
      children: [
        if (repo.findings.isNotEmpty)
          ...repo.findings.map(
            (finding) => ListTile(
              dense: true,
              leading: Icon(
                finding.severity == 'critical'
                    ? Icons.error_outline
                    : Icons.info_outline,
                color:
                    finding.severity == 'critical' ? Colors.red : Colors.orange,
              ),
              title: Text(finding.title),
              subtitle: Text(
                '${finding.detail}\nAction: ${finding.recommendedAction}',
              ),
            ),
          ),
        ...repo.files.take(12).map(
              (file) => ListTile(
                dense: true,
                title: Text(file.relativePath),
                subtitle: SelectableText(
                  '${file.sizeBytes} bytes · ${file.sha256Hex}',
                ),
              ),
            ),
        if (repo.files.length > 12)
          ListTile(
            dense: true,
            title: Text('+${repo.files.length - 12} more file(s)'),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _SectionCard({
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: rows
            .map(
              (row) => ListTile(
                dense: true,
                title: Text(row.label),
                subtitle: SelectableText(row.value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;

  const _Row(this.label, this.value);
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
