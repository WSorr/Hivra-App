import 'package:flutter/material.dart';

import '../models/moltbook_ambassador_models.dart';
import '../models/moltbook_provider_models.dart';
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
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _bulletinIdController = TextEditingController(
    text: 'development-note',
  );
  final TextEditingController _releaseTagController = TextEditingController(
    text: 'development',
  );
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _titleHintController = TextEditingController(
    text: 'Hivra development update',
  );
  final TextEditingController _audienceController = TextEditingController(
    text: 'agent-developers',
  );
  final TextEditingController _factsController = TextEditingController();
  String _approvalMode = MoltbookAmbassadorConfiguration.approvalAssisted;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _connectionBusy = false;
  MoltbookConnectionBinding? _binding;
  MoltbookHomeObservation? _homeObservation;
  MoltbookDraftPreview? _draftPreview;
  List<MoltbookStoredDraft> _storedDrafts = const <MoltbookStoredDraft>[];
  bool _draftBusy = false;
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
    _apiKeyController.dispose();
    _bulletinIdController.dispose();
    _releaseTagController.dispose();
    _categoryController.dispose();
    _titleHintController.dispose();
    _audienceController.dispose();
    _factsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        widget.module.loadAmbassadorConfiguration(),
        widget.module.loadMoltbookBinding(),
        widget.module.loadMoltbookDrafts(),
      ]);
      final configuration = results[0] as MoltbookAmbassadorConfiguration;
      final binding = results[1] as MoltbookConnectionBinding?;
      final drafts = results[2] as List<MoltbookStoredDraft>;
      if (!mounted) return;
      _nameController.text = configuration.agentName;
      _descriptionController.text = configuration.agentDescription;
      _personaController.text = configuration.personaSummary;
      _topicsController.text = configuration.allowedTopics.join(', ');
      _categoryController.text = configuration.allowedTopics.first;
      setState(() {
        _approvalMode = configuration.approvalMode;
        _enabled = configuration.enabled;
        _binding = binding;
        _storedDrafts = drafts;
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

  Future<void> _connect() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showNotice('Enter a Moltbook API key', isError: true);
      return;
    }
    setState(() => _connectionBusy = true);
    try {
      final binding = await widget.module.connectMoltbook(apiKey);
      _apiKeyController.clear();
      if (!mounted) return;
      setState(() => _binding = binding);
      _showNotice('Connected to ${binding.accountName}');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Moltbook connection failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _refreshConnection() async {
    setState(() => _connectionBusy = true);
    try {
      final binding = await widget.module.refreshMoltbookBinding();
      if (!mounted) return;
      setState(() => _binding = binding);
      _showNotice('Moltbook account verified');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Moltbook refresh failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _connectionBusy = true);
    try {
      await widget.module.disconnectMoltbook();
      if (!mounted) return;
      setState(() {
        _binding = null;
        _homeObservation = null;
      });
      _showNotice('Moltbook account disconnected');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Moltbook disconnect failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _observeHome() async {
    setState(() => _connectionBusy = true);
    try {
      final observation = await widget.module.observeMoltbookHome();
      if (!mounted) return;
      setState(() => _homeObservation = observation);
      _showNotice('Moltbook home refreshed');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Moltbook home failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
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

  Future<void> _prepareDraft() async {
    final facts =
        _factsController.text
            .split('\n')
            .map((fact) => fact.trim())
            .where((fact) => fact.isNotEmpty)
            .toList();
    if (facts.isEmpty) {
      _showNotice('Add at least one public fact', isError: true);
      return;
    }
    setState(() {
      _draftBusy = true;
      _draftPreview = null;
    });
    try {
      final preview = await widget.module.prepareMoltbookDraft(
        bulletinId: _bulletinIdController.text,
        releaseTag: _releaseTagController.text,
        category: _categoryController.text,
        facts: facts,
        titleHint: _titleHintController.text,
        audience: _audienceController.text,
      );
      final drafts = await widget.module.loadMoltbookDrafts();
      if (!mounted) return;
      setState(() {
        _draftPreview = preview;
        _storedDrafts = drafts;
      });
      _showNotice('WASM draft prepared for review');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Could not prepare draft: $error', isError: true);
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Future<void> _deleteDraft(MoltbookStoredDraft draft) async {
    setState(() => _draftBusy = true);
    try {
      await widget.module.deleteMoltbookDraft(draft.preview.draftHashHex);
      final drafts = await widget.module.loadMoltbookDrafts();
      if (!mounted) return;
      setState(() {
        _storedDrafts = drafts;
        if (_draftPreview?.draftHashHex == draft.preview.draftHashHex) {
          _draftPreview = null;
        }
      });
      _showNotice('Local draft deleted');
    } catch (error) {
      if (!mounted) return;
      _showNotice('Could not delete draft: $error', isError: true);
    } finally {
      if (mounted) setState(() => _draftBusy = false);
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
                    'Draft-only workspace. Account observation is read-only; remote writes remain disabled.',
                    style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  _MoltbookConnectionCard(
                    binding: _binding,
                    apiKeyController: _apiKeyController,
                    busy: _connectionBusy,
                    homeObservation: _homeObservation,
                    onConnect: _connect,
                    onRefresh: _refreshConnection,
                    onObserveHome: _observeHome,
                    onDisconnect: _disconnect,
                  ),
                  const SizedBox(height: 20),
                  _MoltbookDraftCard(
                    bulletinIdController: _bulletinIdController,
                    releaseTagController: _releaseTagController,
                    categoryController: _categoryController,
                    titleHintController: _titleHintController,
                    audienceController: _audienceController,
                    factsController: _factsController,
                    busy: _draftBusy,
                    preview: _draftPreview,
                    onPrepare: _prepareDraft,
                  ),
                  if (_storedDrafts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _MoltbookDraftHistoryCard(
                      drafts: _storedDrafts,
                      busy: _draftBusy,
                      onDelete: _deleteDraft,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 18),
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

class _MoltbookDraftHistoryCard extends StatelessWidget {
  final List<MoltbookStoredDraft> drafts;
  final bool busy;
  final Future<void> Function(MoltbookStoredDraft draft) onDelete;

  const _MoltbookDraftHistoryCard({
    required this.drafts,
    required this.busy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local drafts · ${drafts.length}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Capsule-scoped review history. These drafts have not been published.',
              style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            const SizedBox(height: 10),
            ...drafts.map(
              (draft) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(draft.preview.title),
                subtitle: Text(
                  '${draft.status.replaceAll("_", " ")} · '
                  '${draft.createdAtUtc.toLocal()} · '
                  '${draft.preview.draftHashHex.substring(0, 12)}..',
                ),
                trailing: IconButton(
                  tooltip: 'Delete local draft',
                  onPressed: busy ? null : () => onDelete(draft),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoltbookDraftCard extends StatelessWidget {
  final TextEditingController bulletinIdController;
  final TextEditingController releaseTagController;
  final TextEditingController categoryController;
  final TextEditingController titleHintController;
  final TextEditingController audienceController;
  final TextEditingController factsController;
  final bool busy;
  final MoltbookDraftPreview? preview;
  final VoidCallback onPrepare;

  const _MoltbookDraftCard({
    required this.bulletinIdController,
    required this.releaseTagController,
    required this.categoryController,
    required this.titleHintController,
    required this.audienceController,
    required this.factsController,
    required this.busy,
    required this.preview,
    required this.onPrepare,
  });

  @override
  Widget build(BuildContext context) {
    final current = preview;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Public bulletin draft',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Only the facts entered here are sent to the installed WASM plugin. Preparing a draft does not publish anything.',
              style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: bulletinIdController,
                    decoration: const InputDecoration(labelText: 'Bulletin id'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: releaseTagController,
                    decoration: const InputDecoration(labelText: 'Release tag'),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Allowed topic',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleHintController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: audienceController,
              decoration: const InputDecoration(labelText: 'Audience'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: factsController,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Public facts',
                helperText: 'One explicit public fact per line.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : onPrepare,
              icon:
                  busy
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.auto_awesome_outlined),
              label: Text(busy ? 'Preparing draft' : 'Prepare WASM draft'),
            ),
            if (current != null) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      current.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(current.body),
              const SizedBox(height: 12),
              Text(
                '${current.audience} · ${current.category} · manual approval required',
                style: const TextStyle(color: Color(0xFF9CA7B5)),
              ),
              const SizedBox(height: 6),
              SelectableText(
                'Draft hash ${current.draftHashHex}',
                style: const TextStyle(color: Color(0xFF9CA7B5), fontSize: 12),
              ),
              if (current.safetyFlags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Safety flags: ${current.safetyFlags.join(", ")}',
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Remote publication is intentionally unavailable in this phase.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoltbookConnectionCard extends StatelessWidget {
  final MoltbookConnectionBinding? binding;
  final TextEditingController apiKeyController;
  final bool busy;
  final MoltbookHomeObservation? homeObservation;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;
  final VoidCallback onObserveHome;
  final VoidCallback onDisconnect;

  const _MoltbookConnectionCard({
    required this.binding,
    required this.apiKeyController,
    required this.busy,
    required this.homeObservation,
    required this.onConnect,
    required this.onRefresh,
    required this.onObserveHome,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final current = binding;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current == null ? 'Connect Moltbook' : current.accountName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              current == null
                  ? 'The key is verified before secure storage. Opening this screen never reads it.'
                  : 'Account ${current.accountId} · '
                      '${current.isClaimed ? "claimed" : "claim pending"} · '
                      '${current.isActive ? "active" : "inactive"}',
              style: const TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            if (current == null) ...[
              const SizedBox(height: 14),
              TextField(
                controller: apiKeyController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Moltbook API key',
                ),
                onSubmitted: busy ? null : (_) => onConnect(),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children:
                  current == null
                      ? <Widget>[
                        FilledButton.icon(
                          onPressed: busy ? null : onConnect,
                          icon:
                              busy
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.link_rounded),
                          label: const Text('Verify and connect'),
                        ),
                      ]
                      : <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : onRefresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : onObserveHome,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Observe home'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : onDisconnect,
                          icon: const Icon(Icons.link_off_rounded),
                          label: const Text('Disconnect'),
                        ),
                      ],
            ),
            if (homeObservation != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Karma ${homeObservation!.karma} · '
                '${homeObservation!.unreadNotificationCount} unread',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (homeObservation!.suggestedActions.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...homeObservation!.suggestedActions
                    .take(3)
                    .map(
                      (action) => Text(
                        '• $action',
                        style: const TextStyle(
                          color: Color(0xFF9CA7B5),
                          height: 1.35,
                        ),
                      ),
                    ),
              ],
            ],
          ],
        ),
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
