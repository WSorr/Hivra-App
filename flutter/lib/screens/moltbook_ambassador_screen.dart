import 'package:flutter/material.dart';

import '../models/moltbook_ambassador_models.dart';
import '../services/plugin_runtime_module_service.dart';

class MoltbookAmbassadorScreen extends StatefulWidget {
  final PluginRuntimeModule module;

  const MoltbookAmbassadorScreen({super.key, required this.module});

  @override
  State<MoltbookAmbassadorScreen> createState() =>
      _MoltbookAmbassadorScreenState();
}

class _MoltbookAmbassadorScreenState extends State<MoltbookAmbassadorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _personaController = TextEditingController();
  final TextEditingController _topicsController = TextEditingController();
  String _approvalMode = MoltbookAmbassadorConfiguration.approvalAssisted;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personaController.dispose();
    _topicsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final configuration = await widget.module.loadAmbassadorConfiguration();
      if (!mounted) return;
      _nameController.text = configuration.agentName;
      _descriptionController.text = configuration.agentDescription;
      _personaController.text = configuration.personaSummary;
      _topicsController.text = configuration.allowedTopics.join(', ');
      setState(() {
        _approvalMode = configuration.approvalMode;
        _enabled = configuration.enabled;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final configuration = MoltbookAmbassadorConfiguration(
      agentName: _nameController.text.trim(),
      agentDescription: _descriptionController.text.trim(),
      personaSummary: _personaController.text.trim(),
      allowedTopics:
          _topicsController.text
              .split(',')
              .map((topic) => topic.trim())
              .where((topic) => topic.isNotEmpty)
              .toList(),
      approvalMode: _approvalMode,
      enabled: _enabled,
    );
    try {
      configuration.validate();
    } on FormatException catch (error) {
      if (!mounted) return;
      _showNotice(error.message, isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.module.saveAmbassadorConfiguration(configuration);
      if (!mounted) return;
      _showNotice('Ambassador profile saved locally');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Could not save ambassador profile: $error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showNotice(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moltbook Ambassador')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? _ConfigurationLoadError(message: _loadError!, onRetry: _load)
              : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Local profile and policy',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Draft-only workspace. Remote effects and credentials are not enabled.',
                    style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Agent name',
                      helperText: 'Names the Moltbook agent, not the Capsule.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Agent description',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _personaController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Persona summary',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _topicsController,
                    decoration: const InputDecoration(
                      labelText: 'Allowed topics',
                      helperText:
                          'Comma-separated ids, for example hivra-development.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _approvalMode,
                    decoration: const InputDecoration(
                      labelText: 'Approval mode',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: MoltbookAmbassadorConfiguration.approvalDraft,
                        child: Text('Draft only'),
                      ),
                      DropdownMenuItem(
                        value: MoltbookAmbassadorConfiguration.approvalAssisted,
                        child: Text('Assisted approval'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _approvalMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    subtitle: const Text('Immediate local stop control'),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon:
                          _saving
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving' : 'Save profile'),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _ConfigurationLoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ConfigurationLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Ambassador configuration did not load',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
