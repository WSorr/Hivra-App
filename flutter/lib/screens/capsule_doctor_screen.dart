import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_capsule_inspection_service.dart';
import '../services/ai_developer_engineer_service.dart';
import '../services/ai_developer_workspace_service.dart';
import '../services/ai_doctor_chat_service.dart';
import '../services/ai_doctor_prompt_service.dart';
import '../services/ai_plugin_audit_service.dart';
import '../services/ai_tooling_module_service.dart';
import '../services/app_runtime_service.dart';
import '../services/inference_provider_adapter.dart';
import '../services/ui_event_log_service.dart';
import '../widgets/ai_diagnostics/developer_workspace_widgets.dart';
import '../widgets/ai_diagnostics/plugin_audit_widgets.dart';
import '../widgets/ai_diagnostics/provider_widgets.dart';
import '../widgets/ai_diagnostics/report_widgets.dart';

String _doctorErrorMessage(Object error) {
  return error
      .toString()
      .replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), '')
      .trim();
}

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
  late final AiToolingModule _aiTooling;
  Future<AiCapsuleInspectionReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _aiTooling = AiToolingModuleService(runtime: widget.runtime).buildModule();
    _reportFuture = _aiTooling.capsuleInspection.inspect();
  }

  void _refresh() {
    setState(() {
      _reportFuture = _aiTooling.capsuleInspection.inspect();
    });
  }

  Future<void> _copySnapshot(AiCapsuleInspectionReport report) async {
    await Clipboard.setData(
      ClipboardData(text: report.snapshot.toPrettyJson()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capsule diagnostics snapshot copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsule Diagnostics'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh local diagnostics',
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
            return AiCapsuleErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final report = snapshot.data;
          if (report == null) {
            return AiCapsuleErrorState(
              error: 'No diagnosis report',
              onRetry: _refresh,
            );
          }
          return _ReportView(
            report: report,
            chatService: _aiTooling.capsuleAnalystChat,
            pluginAuditService: _aiTooling.pluginAudit,
            developerWorkspaceService: _aiTooling.developerWorkspace,
            developerEngineerService: _aiTooling.developerEngineer,
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
  final AiDeveloperEngineerService developerEngineerService;
  final VoidCallback onCopySnapshot;

  const _ReportView({
    required this.report,
    required this.chatService,
    required this.pluginAuditService,
    required this.developerWorkspaceService,
    required this.developerEngineerService,
    required this.onCopySnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AiCapsuleReportHeaderCard(
          statusLabel: report.statusLabel,
          snapshotHashHex: report.snapshot.snapshotHashHex,
          onCopySnapshot: onCopySnapshot,
        ),
        const SizedBox(height: 12),
        ...report.findings.map(
          (finding) => AiCapsuleFindingCard(finding: finding),
        ),
        const SizedBox(height: 12),
        _AiDoctorChatCard(
          snapshot: report.snapshot,
          chatService: chatService,
        ),
        const SizedBox(height: 12),
        _PluginAuditCard(service: pluginAuditService),
        const SizedBox(height: 12),
        _DeveloperModeBoundary(
          snapshot: report.snapshot,
          workspaceService: developerWorkspaceService,
          engineerService: developerEngineerService,
        ),
        const SizedBox(height: 12),
        AiCapsuleSectionCard(
          title: 'Ledger',
          rows: report.snapshot.ledgerSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Invitations',
          rows: report.snapshot.invitationSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Relationships',
          rows: report.snapshot.relationshipSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Transport Outbox',
          rows: report.snapshot.transportSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Consensus',
          rows: report.snapshot.consensusSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Bootstrap',
          rows: report.snapshot.bootstrapSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Filesystem Trace',
          rows: report.snapshot.traceSummary,
        ),
        AiCapsuleSectionCard(
          title: 'Plugins',
          rows: report.snapshot.pluginSummary,
        ),
      ],
    );
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
  static const UiEventLogService _uiLog = UiEventLogService();

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://127.0.0.1:11434',
  );
  final TextEditingController _modelController =
      TextEditingController(text: AiDoctorChatService.defaultModel);
  final TextEditingController _queryController = TextEditingController(
    text: 'What should I check next in this capsule?',
  );
  final Set<AiDoctorContextSection> _sections =
      AiDoctorContextSection.values.toSet();
  InferenceProviderKind _provider = InferenceProviderKind.openAi;

  AiDoctorOutboundPreview? _preview;
  String? _answer;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _saveProviderSettings() async {
    await _run(() async {
      if (_provider.requiresApiKey ||
          _apiKeyController.text.trim().isNotEmpty) {
        await widget.chatService.saveApiKey(_provider, _apiKeyController.text);
      }
      if (_provider == InferenceProviderKind.localOpenAiCompatible) {
        await widget.chatService
            .saveBaseUrl(_provider, _baseUrlController.text);
      }
      await _uiLog.log(
        'ai_capsule_analyst',
        'provider_settings_saved provider=${_provider.id}',
      );
      _apiKeyController.clear();
      _showSnack('${_provider.label} settings saved in secure storage');
    });
  }

  Future<void> _clearProviderSettings() async {
    await _run(() async {
      await widget.chatService.clearApiKey(_provider);
      await widget.chatService.clearBaseUrl(_provider);
      await _uiLog.log(
        'ai_capsule_analyst',
        'provider_settings_cleared provider=${_provider.id}',
      );
      _apiKeyController.clear();
      _showSnack('${_provider.label} settings cleared');
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
        _error = _doctorErrorMessage(error);
      });
    }
  }

  Future<void> _askAnalyst() async {
    await _run(() async {
      final model = _modelController.text.trim().isEmpty
          ? _provider.defaultModel
          : _modelController.text.trim();
      await _uiLog.log(
        'ai_capsule_analyst',
        'ask_start provider=${_provider.id} model=$model '
            'sections=${_sections.length}',
      );
      final result = await widget.chatService.ask(
        snapshot: widget.snapshot,
        userQuery: _queryController.text,
        sections: _sections,
        model: model,
        provider: _provider,
      );
      await _uiLog.log(
        'ai_capsule_analyst',
        'ask_ok provider=${result.providerResponse.provider.id} '
            'model=${result.providerResponse.model} '
            'payloadBytes=${result.preview.payloadBytes} '
            'answerChars=${result.providerResponse.text.length}',
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
      await _uiLog.log(
        'ai_capsule_analyst',
        'action_error ${_doctorErrorMessage(error)}',
      );
      setState(() {
        _error = _doctorErrorMessage(error);
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
                    'AI Capsule Analyst',
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
            DropdownButtonFormField<InferenceProviderKind>(
              initialValue: _provider,
              decoration: const InputDecoration(
                labelText: 'Inference provider',
                border: OutlineInputBorder(),
              ),
              items: InferenceProviderKind.values
                  .map(
                    (provider) => DropdownMenuItem<InferenceProviderKind>(
                      value: provider,
                      child: Text(provider.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _busy
                  ? null
                  : (provider) {
                      if (provider == null) return;
                      setState(() {
                        _provider = provider;
                        _modelController.text = provider.defaultModel;
                        if (provider ==
                            InferenceProviderKind.localOpenAiCompatible) {
                          _baseUrlController.text = 'http://127.0.0.1:11434';
                        }
                        _error = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            if (_provider == InferenceProviderKind.localOpenAiCompatible) ...[
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Local OpenAI-compatible base URL',
                  helperText:
                      'Example: http://127.0.0.1:11434. The app calls /v1/chat/completions.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _apiKeyController,
              obscureText: _provider.requiresApiKey,
              decoration: InputDecoration(
                labelText: _provider.requiresApiKey
                    ? '${_provider.label} API key'
                    : '${_provider.label} optional API key',
                helperText: 'Stored only in secure storage. '
                    'Provider keys are isolated.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _saveProviderSettings,
                  icon: const Icon(Icons.key),
                  label: const Text('Save provider settings'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearProviderSettings,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear provider settings'),
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
                  onPressed: _busy ? null : _askAnalyst,
                  icon: const Icon(Icons.send),
                  label: const Text('Ask AI Analyst'),
                ),
              ],
            ),
            if (_preview != null) ...[
              const SizedBox(height: 12),
              AiOutboundPreviewPanel(preview: _preview!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              AiStatusMessage(message: _error!),
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
                          : aiPluginAuditStatusColor(report.statusLabel),
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
                    ...report.entries.map(
                      (entry) => AiPluginAuditEntryTile(entry: entry),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeveloperModeBoundary extends StatefulWidget {
  final AiCapsuleInspectionSnapshot snapshot;
  final AiDeveloperWorkspaceService workspaceService;
  final AiDeveloperEngineerService engineerService;

  const _DeveloperModeBoundary({
    required this.snapshot,
    required this.workspaceService,
    required this.engineerService,
  });

  @override
  State<_DeveloperModeBoundary> createState() => _DeveloperModeBoundaryState();
}

class _DeveloperModeBoundaryState extends State<_DeveloperModeBoundary> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: _enabled
          ? Color.alphaBlend(
              Colors.orange.withValues(alpha: 0.12),
              theme.cardColor,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction,
                  color: _enabled ? Colors.orange : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Developer Mode',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (value) {
                    setState(() {
                      _enabled = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _enabled
                  ? 'Developer Mode is enabled for this screen session. Repository context remains manual, read-only, and preview-first.'
                  : 'Disabled by default. Enable only when you intentionally want local repository diagnostics.',
              style: theme.textTheme.bodyMedium,
            ),
            if (!_enabled) ...[
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Workspace tools are locked'),
                subtitle: Text(
                  'Capsule Diagnostics remains user-facing until Developer Mode is explicitly enabled.',
                ),
              ),
            ],
            if (_enabled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Developer evidence is untrusted input. AI output cannot patch, commit, push, release, mutate ledger, or change plugin registry.',
                ),
              ),
              const SizedBox(height: 12),
              _DeveloperWorkspaceCard(
                snapshot: widget.snapshot,
                workspaceService: widget.workspaceService,
                engineerService: widget.engineerService,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeveloperWorkspaceCard extends StatefulWidget {
  final AiCapsuleInspectionSnapshot snapshot;
  final AiDeveloperWorkspaceService workspaceService;
  final AiDeveloperEngineerService engineerService;

  const _DeveloperWorkspaceCard({
    required this.snapshot,
    required this.workspaceService,
    required this.engineerService,
  });

  @override
  State<_DeveloperWorkspaceCard> createState() =>
      _DeveloperWorkspaceCardState();
}

class _DeveloperWorkspaceCardState extends State<_DeveloperWorkspaceCard> {
  static const UiEventLogService _uiLog = UiEventLogService();

  final TextEditingController _pathsController = TextEditingController(
    text: '/Volumes/Dev/projects/hivra\n/Volumes/Dev/projects/hivra-plugins',
  );
  final TextEditingController _selectedFilesController =
      TextEditingController();
  final TextEditingController _engineerModelController =
      TextEditingController(text: AiDeveloperEngineerService.defaultModel);
  final TextEditingController _engineerQuestionController =
      TextEditingController(
    text: 'What is the safest next code path to inspect?',
  );
  AiDeveloperWorkspaceReport? _report;
  AiDeveloperWorkspaceSelectedContext? _selectedContext;
  AiDeveloperEngineerPreview? _engineerPreview;
  int? _selectedFileRequestCount;
  InferenceProviderKind _engineerProvider = InferenceProviderKind.openAi;
  String? _engineerAnswer;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pathsController.dispose();
    _selectedFilesController.dispose();
    _engineerModelController.dispose();
    _engineerQuestionController.dispose();
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
      final pathCount = paths.length;
      await _uiLog.log(
        'hivra_engineer',
        'workspace_scan_start paths=$pathCount',
      );
      final report = await widget.workspaceService.scanLocalRepositories(paths);
      await _uiLog.log(
        'hivra_engineer',
        'workspace_scan_ok repos=${report.repositories.length} '
            'hash=${report.reportHashHex}',
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _selectedContext = null;
        _engineerPreview = null;
        _selectedFileRequestCount = null;
        _engineerAnswer = null;
      });
    } catch (error) {
      if (!mounted) return;
      await _uiLog.log(
        'hivra_engineer',
        'workspace_scan_error ${_doctorErrorMessage(error)}',
      );
      setState(() {
        _error = _doctorErrorMessage(error);
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
    final selections = _selectedFilesController.text
        .split(RegExp(r'[\n,]+'))
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (selections.isEmpty) {
      const message = 'Select at least one file from scanned repositories';
      await _uiLog.log(
        'hivra_engineer',
        'selected_context_error empty_selection',
      );
      setState(() {
        _error = message;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selectionCount = selections.length;
      await _uiLog.log(
        'hivra_engineer',
        'selected_context_start files=$selectionCount',
      );
      final context = await widget.workspaceService.buildSelectedFileContext(
        report: report,
        selectedRelativePaths: selections,
      );
      await _uiLog.log(
        'hivra_engineer',
        'selected_context_ok requested=$selectionCount '
            'included=${context.snippets.length} '
            'payloadBytes=${context.payloadBytes} '
            'hash=${context.contextHashHex}',
      );
      if (!mounted) return;
      setState(() {
        _selectedContext = context;
        _engineerPreview = null;
        _selectedFileRequestCount = selectionCount;
        _engineerAnswer = null;
      });
    } catch (error) {
      if (!mounted) return;
      await _uiLog.log(
        'hivra_engineer',
        'selected_context_error ${_doctorErrorMessage(error)}',
      );
      setState(() {
        _error = _doctorErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _addSelectedFile(String relativePath) {
    _addSuggestedFiles(<String>[relativePath]);
  }

  void _addSuggestedFiles(Iterable<String> relativePaths) {
    final selected = _selectedFilesController.text
        .split(RegExp(r'[\n,]+'))
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet();
    selected.addAll(
      relativePaths.map((path) => path.trim()).where((path) => path.isNotEmpty),
    );
    final sorted = selected.toList()..sort();
    _selectedFilesController.text = sorted.join('\n');
    _selectedFilesController.selection = TextSelection.collapsed(
      offset: _selectedFilesController.text.length,
    );
    setState(() {
      _error = null;
    });
  }

  List<String> _availableRelativePaths() {
    final report = _report;
    if (report == null) return const <String>[];
    final paths = report.repositories
        .expand((repo) => repo.files)
        .map((file) => file.relativePath)
        .toSet()
        .toList()
      ..sort();
    return paths;
  }

  List<String> _matchingAvailableFiles(Iterable<String> preferredPaths) {
    final available = _availableRelativePaths().toSet();
    return preferredPaths
        .where(available.contains)
        .take(AiDeveloperWorkspaceService.maxSelectedFiles)
        .toList(growable: false);
  }

  List<String> _firstAvailableFiles([int count = 3]) {
    return _availableRelativePaths().take(count).toList(growable: false);
  }

  Future<void> _previewEngineerAsk() async {
    final selectedContext = _selectedContext;
    if (selectedContext == null) {
      setState(() {
        _error = 'Build selected developer context first';
      });
      return;
    }
    try {
      final preview = widget.engineerService.preview(
        snapshot: widget.snapshot,
        selectedContext: selectedContext,
        question: _engineerQuestionController.text,
      );
      await _uiLog.log(
        'hivra_engineer',
        'preview_ok snippets=${preview.snippetCount} '
            'payloadBytes=${preview.payloadBytes} '
            'contextHash=${preview.developerContextHashHex}',
      );
      setState(() {
        _engineerPreview = preview;
        _error = null;
      });
    } catch (error) {
      await _uiLog.log(
        'hivra_engineer',
        'preview_error ${_doctorErrorMessage(error)}',
      );
      setState(() {
        _error = _doctorErrorMessage(error);
      });
    }
  }

  Future<void> _askEngineer() async {
    final selectedContext = _selectedContext;
    if (selectedContext == null || _busy) {
      setState(() {
        _error = 'Build selected developer context first';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final model = _engineerModelController.text.trim().isEmpty
          ? _engineerProvider.defaultModel
          : _engineerModelController.text.trim();
      await _uiLog.log(
        'hivra_engineer',
        'ask_start provider=${_engineerProvider.id} model=$model '
            'snippets=${selectedContext.snippets.length}',
      );
      final result = await widget.engineerService.ask(
        snapshot: widget.snapshot,
        selectedContext: selectedContext,
        question: _engineerQuestionController.text,
        model: model,
        provider: _engineerProvider,
      );
      await _uiLog.log(
        'hivra_engineer',
        'ask_ok provider=${result.providerResponse.provider.id} '
            'model=${result.providerResponse.model} '
            'payloadBytes=${result.preview.payloadBytes} '
            'answerChars=${result.providerResponse.text.length}',
      );
      if (!mounted) return;
      setState(() {
        _engineerPreview = result.preview;
        _engineerAnswer = result.providerResponse.text;
      });
    } catch (error) {
      if (!mounted) return;
      await _uiLog.log(
        'hivra_engineer',
        'ask_error ${_doctorErrorMessage(error)}',
      );
      setState(() {
        _error = _doctorErrorMessage(error);
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
              AiStatusMessage(message: _error!),
            ],
            if (_report != null) ...[
              const SizedBox(height: 12),
              SelectableText('Workspace ${_report!.reportHashHex}'),
              const SizedBox(height: 8),
              AiDeveloperWorkspaceQuickAddPanel(
                availableFiles: _availableRelativePaths(),
                onAddFiles: _addSuggestedFiles,
                firstFiles: _firstAvailableFiles(),
                coreFiles: _matchingAvailableFiles(const <String>[
                  'README.md',
                  'docs/roadmap.md',
                  'docs/specification.md',
                  'docs/hivra-conceptual-model.md',
                ]),
                doctorFiles: _matchingAvailableFiles(const <String>[
                  'flutter/lib/screens/capsule_doctor_screen.dart',
                  'flutter/lib/services/inference_provider_adapter.dart',
                  'flutter/lib/services/ai_doctor_chat_service.dart',
                  'flutter/lib/services/ai_developer_engineer_service.dart',
                ]),
              ),
              const SizedBox(height: 8),
              ..._report!.repositories.map(
                (repo) => AiDeveloperWorkspaceRepoTile(
                  repo: repo,
                  onAddFile: _addSelectedFile,
                ),
              ),
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
              AiDeveloperSelectedContextPanel(
                contextData: _selectedContext!,
                requestedFileCount: _selectedFileRequestCount,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<InferenceProviderKind>(
                initialValue: _engineerProvider,
                decoration: const InputDecoration(
                  labelText: 'Hivra Engineer provider',
                  border: OutlineInputBorder(),
                ),
                items: InferenceProviderKind.values
                    .map(
                      (provider) => DropdownMenuItem<InferenceProviderKind>(
                        value: provider,
                        child: Text(provider.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (provider) {
                        if (provider == null) return;
                        setState(() {
                          _engineerProvider = provider;
                          _engineerModelController.text = provider.defaultModel;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _engineerModelController,
                decoration: const InputDecoration(
                  labelText: 'Hivra Engineer model',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _engineerQuestionController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Ask Hivra Engineer',
                  helperText:
                      'Advisory only. No file writes, git operations, or ledger/plugin mutations.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _previewEngineerAsk,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Preview engineer ask'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _askEngineer,
                    icon: const Icon(Icons.engineering),
                    label: const Text('Ask Hivra Engineer'),
                  ),
                ],
              ),
            ],
            if (_engineerPreview != null) ...[
              const SizedBox(height: 12),
              AiDeveloperEngineerPreviewPanel(preview: _engineerPreview!),
            ],
            if (_engineerAnswer != null) ...[
              const SizedBox(height: 12),
              SelectableText(_engineerAnswer!),
            ],
          ],
        ),
      ),
    );
  }
}
