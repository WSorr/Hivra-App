import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ai_doctor_prompt_service.dart';
import '../../services/ai_capsule_inspection_service.dart';
import '../../services/ai_doctor_chat_service.dart';
import '../../services/inference_provider_adapter.dart';
import '../../services/ui_event_log_service.dart';

class AiOutboundPreviewPanel extends StatelessWidget {
  final AiDoctorOutboundPreview preview;

  const AiOutboundPreviewPanel({super.key, required this.preview});

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

class AiStatusMessage extends StatelessWidget {
  final String message;

  const AiStatusMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = _isProviderWarning(message);
    final color = isWarning ? Colors.amberAccent : Colors.redAccent;
    final icon = isWarning ? Icons.info_outline : Icons.error_outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isProviderWarning(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('quota') ||
        normalized.contains('rate limit') ||
        normalized.contains('api key was rejected') ||
        normalized.contains('openai api') ||
        normalized.contains('ai provider') ||
        normalized.contains('billing') ||
        normalized.contains('provider request failed') ||
        normalized.contains('secure ai credential storage') ||
        normalized.contains('secure ai endpoint storage') ||
        normalized.contains('gemini api');
  }
}

String _doctorErrorMessage(Object error) {
  return error
      .toString()
      .replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), '')
      .trim();
}

class AiDoctorChatCard extends StatefulWidget {
  final AiCapsuleInspectionSnapshot snapshot;
  final AiDoctorChatService chatService;
  final UiEventLogService uiLog;

  const AiDoctorChatCard({
    super.key,
    required this.snapshot,
    required this.chatService,
    this.uiLog = const UiEventLogService(),
  });

  @override
  State<AiDoctorChatCard> createState() => _AiDoctorChatCardState();
}

class _AiDoctorChatCardState extends State<AiDoctorChatCard> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _queryController = TextEditingController(
    text: 'What should I check next in this capsule?',
  );
  InferenceProviderKind _provider = InferenceProviderKind.openAi;

  AiDoctorOutboundPreview? _preview;
  String? _answer;
  String? _error;
  String? _apiKeyStatusError;
  bool _apiKeyConfigured = false;
  bool _apiKeyStatusKnown = false;
  bool _checkingApiKey = true;
  int _statusRevision = 0;
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
    final revision = ++_statusRevision;
    setState(() {
      _checkingApiKey = true;
      _apiKeyStatusKnown = false;
      _apiKeyStatusError = null;
    });
    try {
      final providerId = await widget.chatService.loadPreferredProviderId();
      final provider =
          InferenceProviderKind.values
              .where((candidate) => candidate.id == providerId)
              .firstOrNull ??
          _provider;
      if (!mounted || revision != _statusRevision) return;
      setState(() {
        _provider = provider;
        _modelController.text = provider.defaultModel;
        _baseUrlController.clear();
      });
      await _refreshApiKeyStatus(provider);
    } catch (_) {
      if (!mounted || revision != _statusRevision) return;
      setState(() {
        _checkingApiKey = false;
        _apiKeyStatusError =
            'Provider selection is unavailable. Check system access and retry.';
      });
    }
  }

  Future<void> _refreshApiKeyStatus(InferenceProviderKind provider) async {
    final revision = ++_statusRevision;
    if (mounted && _provider == provider) {
      setState(() {
        _checkingApiKey = true;
        _apiKeyStatusKnown = false;
        _apiKeyStatusError = null;
      });
    }
    try {
      final model = await widget.chatService.loadPreferredModel(provider.id);
      final configured =
          provider.requiresApiKey
              ? await widget.chatService.hasProviderApiKey(provider.id)
              : false;
      if (!mounted || _provider != provider || revision != _statusRevision) {
        return;
      }
      setState(() {
        _modelController.text = model;
        _apiKeyConfigured = configured;
        _apiKeyStatusKnown = true;
        _apiKeyStatusError = null;
        _checkingApiKey = false;
      });
    } catch (_) {
      if (!mounted || _provider != provider || revision != _statusRevision) {
        return;
      }
      setState(() {
        _apiKeyConfigured = false;
        _apiKeyStatusKnown = false;
        _apiKeyStatusError =
            'Secure storage status is unavailable. Check system access and retry.';
        _checkingApiKey = false;
      });
    }
  }

  Future<void> _saveProviderSettings() async {
    await _run(() async {
      if (_provider == InferenceProviderKind.cloudflareWorkersAi &&
          _baseUrlController.text.trim().isEmpty &&
          !_apiKeyConfigured) {
        throw ArgumentError(
          'Enter the Cloudflare Account ID before saving a new token',
        );
      }
      if (_provider.requiresBaseUrl &&
          _baseUrlController.text.trim().isNotEmpty) {
        final baseUrl =
            _provider == InferenceProviderKind.cloudflareWorkersAi
                ? OpenAiChatCompletionsInferenceProviderAdapter.cloudflareBaseUrlForAccount(
                  _baseUrlController.text,
                )
                : _baseUrlController.text;
        await widget.chatService.saveProviderBaseUrl(_provider.id, baseUrl);
      }
      if (_apiKeyController.text.trim().isNotEmpty) {
        await widget.chatService.saveProviderApiKey(
          _provider.id,
          _apiKeyController.text,
        );
      } else if (_provider.requiresApiKey && !_apiKeyConfigured) {
        throw ArgumentError('${_provider.label} API token is not saved');
      }
      await widget.chatService.savePreferredProviderId(
        _provider.id,
        model: _modelController.text,
      );
      await widget.uiLog.log(
        'ai_capsule_analyst',
        'provider_settings_saved provider=${_provider.id}',
      );
      if (!mounted) return;
      if (_provider.requiresApiKey) {
        setState(() {
          _apiKeyConfigured = true;
          _apiKeyStatusKnown = true;
          _apiKeyStatusError = null;
        });
      }
      _apiKeyController.clear();
      _showSnack('${_provider.label} settings saved in secure storage');
    });
  }

  Future<void> _clearProviderSettings() async {
    await _run(() async {
      await widget.chatService.clearProviderApiKey(_provider.id);
      await widget.chatService.clearProviderBaseUrl(_provider.id);
      await widget.uiLog.log(
        'ai_capsule_analyst',
        'provider_settings_cleared provider=${_provider.id}',
      );
      if (!mounted) return;
      if (_provider.requiresApiKey) {
        setState(() {
          _apiKeyConfigured = false;
          _apiKeyStatusKnown = true;
          _apiKeyStatusError = null;
        });
      }
      _apiKeyController.clear();
      _showSnack('${_provider.label} settings cleared');
    });
  }

  void _previewContext() {
    try {
      final preview = widget.chatService.preview(
        snapshot: widget.snapshot,
        userQuery: _queryController.text,
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
      final model = _modelController.text.trim();
      await widget.uiLog.log(
        'ai_capsule_analyst',
        'ask_start provider=${_provider.id} model=$model '
            'context=technical_modules',
      );
      final result = await widget.chatService.ask(
        snapshot: widget.snapshot,
        userQuery: _queryController.text,
        model: model,
        providerId: _provider.id,
      );
      await widget.uiLog.log(
        'ai_capsule_analyst',
        'ask_ok provider=${result.providerId} '
            'model=${result.model} '
            'payloadBytes=${result.preview.payloadBytes} '
            'answerChars=${result.text.length}',
      );
      if (!mounted) return;
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
      await widget.uiLog.log(
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
              'Ask about all module diagnostics. Secrets, personal content and addresses are excluded from the technical snapshot. Advisory only; no changes to Capsule.',
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
                          _baseUrlController.clear();
                          _apiKeyController.clear();
                          _error = null;
                          _apiKeyConfigured = false;
                          _apiKeyStatusKnown = false;
                          _apiKeyStatusError = null;
                        });
                        unawaited(_refreshApiKeyStatus(provider));
                        unawaited(
                          widget.chatService
                              .savePreferredProviderId(provider.id)
                              .catchError((Object error) {
                                return widget.uiLog.log(
                                  'ai_capsule_analyst',
                                  'provider_preference_save_error '
                                      '${_doctorErrorMessage(error)}',
                                );
                              }),
                        );
                      },
            ),
            const SizedBox(height: 12),
            if (_provider.requiresBaseUrl) ...[
              TextField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText:
                      _provider == InferenceProviderKind.cloudflareWorkersAi
                          ? 'Cloudflare Account ID'
                          : 'Local OpenAI-compatible base URL',
                  helperText:
                      _provider == InferenceProviderKind.cloudflareWorkersAi
                          ? '32-character Account ID from Workers AI → Use REST API. Leave blank to keep the saved account.'
                          : 'Example: http://127.0.0.1:11434. Leave blank to keep the saved endpoint; requests use /v1/chat/completions.',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_provider == InferenceProviderKind.cloudflareWorkersAi)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Workers Free includes 10,000 Neurons/day, resetting at 00:00 UTC. Some models require payment. Use a Workers AI API token; account billing applies.',
                  ),
                ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _apiKeyController,
              obscureText: _provider.requiresApiKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText:
                    _provider == InferenceProviderKind.cloudflareWorkersAi
                        ? '${_provider.label} API token'
                        : _provider.requiresApiKey
                        ? '${_provider.label} API key'
                        : '${_provider.label} optional API key',
                helperText:
                    'Saved keys remain hidden and are loaded directly from '
                    'secure storage when you ask. Enter a value only to save '
                    'or replace the current provider key.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_provider.requiresApiKey) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _apiKeyStatusError != null
                        ? Icons.error_outline
                        : _apiKeyConfigured
                        ? Icons.verified_outlined
                        : Icons.info_outline,
                    size: 18,
                    color:
                        _apiKeyStatusError != null
                            ? theme.colorScheme.error
                            : _apiKeyConfigured
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _checkingApiKey
                          ? 'Checking secure storage…'
                          : _apiKeyStatusError != null
                          ? 'Key status unavailable: $_apiKeyStatusError'
                          : _apiKeyStatusKnown && _apiKeyConfigured
                          ? '${_provider.label} API key is saved in secure storage.'
                          : '${_provider.label} API key is not saved.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (_apiKeyStatusError != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _loadPreferredProvider,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry secure storage check'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _modelController,
              enabled: !_busy && !_checkingApiKey,
              decoration: const InputDecoration(
                labelText: 'Model',
                helperText:
                    'Saved choice is shared by Analyst and authorized AI features.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      _busy || _checkingApiKey ? null : _saveProviderSettings,
                  icon: const Icon(Icons.key),
                  label: const Text('Save / replace provider settings'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || _checkingApiKey ? null : _clearProviderSettings,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear provider settings'),
                ),
              ],
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
                  onPressed: _busy || _checkingApiKey ? null : _askAnalyst,
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
