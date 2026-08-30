import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_capsule_inspection_service.dart';
import '../services/ai_doctor_chat_service.dart';
import '../services/ai_doctor_prompt_service.dart';
import '../services/ai_plugin_audit_service.dart';
import '../services/ai_tooling_module_service.dart';
import '../services/app_runtime_service.dart';
import '../services/inference_provider_adapter.dart';
import '../services/ui_event_log_service.dart';
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

  const CapsuleDoctorScreen({super.key, required this.runtime});

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
        title: const Text('Capsule Analyst'),
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
  final VoidCallback onCopySnapshot;

  const _ReportView({
    required this.report,
    required this.chatService,
    required this.pluginAuditService,
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
        _AiDoctorChatCard(snapshot: report.snapshot, chatService: chatService),
        const SizedBox(height: 12),
        _PluginAuditCard(service: pluginAuditService),
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

  const _AiDoctorChatCard({required this.snapshot, required this.chatService});

  @override
  State<_AiDoctorChatCard> createState() => _AiDoctorChatCardState();
}

class _AiDoctorChatCardState extends State<_AiDoctorChatCard> {
  static const UiEventLogService _uiLog = UiEventLogService();

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://127.0.0.1:11434',
  );
  final TextEditingController _modelController = TextEditingController(
    text: AiDoctorChatService.defaultModel,
  );
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
  void initState() {
    super.initState();
    unawaited(_loadPreferredProvider());
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferredProvider() async {
    try {
      final providerId = await widget.chatService.loadPreferredProviderId();
      if (!mounted || providerId == null) return;
      final provider =
          InferenceProviderKind.values
              .where((candidate) => candidate.id == providerId)
              .firstOrNull;
      if (provider == null) return;
      setState(() {
        _provider = provider;
        _modelController.text = provider.defaultModel;
        if (provider == InferenceProviderKind.localOpenAiCompatible) {
          _baseUrlController.text = 'http://127.0.0.1:11434';
        }
      });
    } catch (error) {
      await _uiLog.log(
        'ai_capsule_analyst',
        'provider_preference_load_error ${_doctorErrorMessage(error)}',
      );
    }
  }

  Future<void> _saveProviderSettings() async {
    await _run(() async {
      if (_provider.requiresApiKey ||
          _apiKeyController.text.trim().isNotEmpty) {
        await widget.chatService.saveProviderApiKey(
          _provider.id,
          _apiKeyController.text,
        );
      }
      if (_provider == InferenceProviderKind.localOpenAiCompatible) {
        await widget.chatService.saveProviderBaseUrl(
          _provider.id,
          _baseUrlController.text,
        );
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
      await widget.chatService.clearProviderApiKey(_provider.id);
      await widget.chatService.clearProviderBaseUrl(_provider.id);
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
      final model =
          _modelController.text.trim().isEmpty
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
        providerId: _provider.id,
      );
      await _uiLog.log(
        'ai_capsule_analyst',
        'ask_ok provider=${result.providerId} '
            'model=${result.model} '
            'payloadBytes=${result.preview.payloadBytes} '
            'answerChars=${result.text.length}',
      );
      setState(() {
        _preview = result.preview;
        _answer = result.text;
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
              key: ValueKey<String>('capsule_analyst_provider_${_provider.id}'),
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
              onChanged:
                  _busy
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
                        unawaited(
                          widget.chatService
                              .savePreferredProviderId(provider.id)
                              .catchError((Object error) {
                                return _uiLog.log(
                                  'ai_capsule_analyst',
                                  'provider_preference_save_error '
                                      '${_doctorErrorMessage(error)}',
                                );
                              }),
                        );
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
                labelText:
                    _provider.requiresApiKey
                        ? '${_provider.label} API key'
                        : '${_provider.label} optional API key',
                helperText:
                    'Saved keys remain hidden and are loaded directly from '
                    'secure storage when you ask. Enter a value only to save '
                    'or replace the current provider key.',
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
                  label: const Text('Save / replace provider settings'),
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
                      onSelected:
                          _busy
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
              SelectableText(_answer!, style: theme.textTheme.bodyMedium),
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
                      color:
                          report == null
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
