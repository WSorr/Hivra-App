import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/external_effect_models.dart';
import '../models/moltbook_ambassador_models.dart';
import '../models/moltbook_provider_models.dart';
import '../services/moltbook_publication_service.dart';
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
  final TextEditingController _submoltController = TextEditingController(
    text: MoltbookPublicationService.defaultSubmolt,
  );
  String _approvalMode = MoltbookAmbassadorConfiguration.approvalAssisted;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _connectionBusy = false;
  MoltbookConnectionBinding? _binding;
  MoltbookHomeObservation? _homeObservation;
  MoltbookFeedObservation? _feedObservation;
  MoltbookDraftPreview? _draftPreview;
  List<MoltbookStoredDraft> _storedDrafts = const <MoltbookStoredDraft>[];
  List<ExternalEffectOperation> _publications =
      const <ExternalEffectOperation>[];
  bool _draftBusy = false;
  bool _publicationBusy = false;
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
    _submoltController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        widget.module.loadAmbassadorConfiguration(),
        widget.module.loadMoltbookBinding(),
        widget.module.loadMoltbookDrafts(),
        widget.module.loadMoltbookPublications(),
      ]);
      final configuration = results[0] as MoltbookAmbassadorConfiguration;
      final binding = results[1] as MoltbookConnectionBinding?;
      final drafts = results[2] as List<MoltbookStoredDraft>;
      final publications = results[3] as List<ExternalEffectOperation>;
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
        _publications = publications;
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

  Future<void> _observeFeed() async {
    setState(() => _connectionBusy = true);
    try {
      final observation = await widget.module.observeMoltbookFeed();
      if (!mounted) return;
      setState(() => _feedObservation = observation);
      _showNotice('Moltbook feed observed');
    } catch (error) {
      if (mounted) {
        _showNotice('Could not observe Moltbook feed: $error', isError: true);
      }
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

  Future<void> _reviewPublication(MoltbookStoredDraft draft) async {
    setState(() => _publicationBusy = true);
    try {
      final operation = await widget.module.prepareMoltbookPublication(
        draft: draft.preview,
        submoltName: _submoltController.text,
      );
      if (!mounted) return;
      final payload = MoltbookPublicationService.decodePayload(operation);
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('Approve permanent publication?'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Account: ${payload['account_name']}\n'
                        'Destination: m/${payload['submolt_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        payload['title'].toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(payload['content'].toString()),
                      const SizedBox(height: 16),
                      const Text(
                        'This creates a public external effect. Moltbook may retain or redistribute the post. Approval cannot be inferred or automated.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep as draft'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Approve exact post'),
                ),
              ],
            ),
      );
      if (!mounted) return;
      if (approved != true) {
        _showNotice('Publication remains local and unapproved');
      } else {
        await widget.module.approveMoltbookPublication(operation);
        _showNotice('Publication approved and queued locally');
      }
      final publications = await widget.module.loadMoltbookPublications();
      if (mounted) setState(() => _publications = publications);
    } catch (error) {
      if (mounted) {
        _showNotice('Could not prepare publication: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _publicationBusy = false);
    }
  }

  Future<void> _processPublication(ExternalEffectOperation operation) async {
    setState(() => _publicationBusy = true);
    try {
      final result = await widget.module.processMoltbookPublication(
        operation.operationId,
      );
      final publications = await widget.module.loadMoltbookPublications();
      if (!mounted) return;
      setState(() => _publications = publications);
      _showNotice(
        result.state == ExternalEffectState.succeeded
            ? 'Moltbook receipt verified'
            : 'Publication state: ${result.state.wireName} '
                '(${result.lastErrorCode ?? "no receipt"})',
        isError: result.state != ExternalEffectState.succeeded,
      );
    } catch (error) {
      if (mounted) {
        _showNotice('Publication processing failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _publicationBusy = false);
    }
  }

  Future<void> _openPublishedPost(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showNotice('Could not open the published post', isError: true);
      }
    } catch (error) {
      if (mounted) {
        _showNotice('Could not open the published post: $error', isError: true);
      }
    }
  }

  Future<void> _resolvePublicationVerification(
    ExternalEffectOperation operation,
  ) async {
    final action = operation.requiredAction;
    if (action == null) return;
    final answerController = TextEditingController();
    try {
      final answer = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('Complete Moltbook verification'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Moltbook created the approved post but keeps it hidden until this anti-spam challenge is solved.',
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        action.prompt,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Expires: ${action.expiresAtUtc}'),
                      const SizedBox(height: 14),
                      TextField(
                        controller: answerController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Numeric answer',
                          helperText:
                              'Enter only the result. It will be normalized to 2 decimal places.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed:
                      () => Navigator.pop(context, answerController.text),
                  child: const Text('Verify and confirm visibility'),
                ),
              ],
            ),
      );
      if (!mounted || answer == null) return;
      setState(() => _publicationBusy = true);
      final result = await widget.module.resolveMoltbookPublicationVerification(
        operationId: operation.operationId,
        answer: answer,
      );
      final publications = await widget.module.loadMoltbookPublications();
      if (!mounted) return;
      setState(() => _publications = publications);
      _showNotice(
        result.state == ExternalEffectState.succeeded
            ? 'Moltbook post verified and visible'
            : 'Verification state: ${result.state.wireName} '
                '(${result.lastErrorCode ?? "not confirmed"})',
        isError: result.state != ExternalEffectState.succeeded,
      );
    } catch (error) {
      if (mounted) {
        _showNotice('Moltbook verification failed: $error', isError: true);
      }
    } finally {
      answerController.dispose();
      if (mounted) setState(() => _publicationBusy = false);
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

  ExternalEffectOperation? _latestOperationWhere(
    bool Function(ExternalEffectOperation operation) predicate,
  ) {
    for (final operation in _publications.reversed) {
      if (predicate(operation)) return operation;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final verificationOperation = _latestOperationWhere(
      (operation) => operation.requiredAction != null,
    );
    final queuedOperation = _latestOperationWhere(
      (operation) => operation.state == ExternalEffectState.queued,
    );
    final latestDraft = _storedDrafts.isEmpty ? null : _storedDrafts.first;
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
                    'Drafts stay local until an exact post is reviewed, approved, queued, and explicitly published.',
                    style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  _MoltbookWorkflowCard(
                    connected: _binding != null,
                    hasDraft: latestDraft != null,
                    queuedOperation: queuedOperation,
                    verificationOperation: verificationOperation,
                    busy: _draftBusy || _publicationBusy,
                    onReview:
                        latestDraft == null
                            ? null
                            : () => _reviewPublication(latestDraft),
                    onPublish:
                        queuedOperation == null
                            ? null
                            : () => _processPublication(queuedOperation),
                    onVerify:
                        verificationOperation == null
                            ? null
                            : () => _resolvePublicationVerification(
                              verificationOperation,
                            ),
                  ),
                  const SizedBox(height: 20),
                  _MoltbookConnectionCard(
                    binding: _binding,
                    apiKeyController: _apiKeyController,
                    busy: _connectionBusy,
                    homeObservation: _homeObservation,
                    feedObservation: _feedObservation,
                    onConnect: _connect,
                    onRefresh: _refreshConnection,
                    onObserveHome: _observeHome,
                    onObserveFeed: _observeFeed,
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
                      busy: _draftBusy || _publicationBusy,
                      submoltController: _submoltController,
                      onDelete: _deleteDraft,
                      onReviewPublication: _reviewPublication,
                    ),
                  ],
                  if (_publications.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _MoltbookPublicationCard(
                      operations: _publications,
                      busy: _publicationBusy,
                      onProcess: _processPublication,
                      onResolveVerification: _resolvePublicationVerification,
                      onOpenPost: _openPublishedPost,
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

class _MoltbookWorkflowCard extends StatelessWidget {
  final bool connected;
  final bool hasDraft;
  final ExternalEffectOperation? queuedOperation;
  final ExternalEffectOperation? verificationOperation;
  final bool busy;
  final VoidCallback? onReview;
  final VoidCallback? onPublish;
  final VoidCallback? onVerify;

  const _MoltbookWorkflowCard({
    required this.connected,
    required this.hasDraft,
    required this.queuedOperation,
    required this.verificationOperation,
    required this.busy,
    required this.onReview,
    required this.onPublish,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasVerification = verificationOperation != null;
    final hasQueued = queuedOperation != null;
    final String title;
    final String description;
    final String? actionLabel;
    final IconData actionIcon;
    final VoidCallback? action;

    if (!connected) {
      title = 'Next: connect your Moltbook account';
      description = 'Add the API key in the connection section below.';
      actionLabel = null;
      actionIcon = Icons.key_outlined;
      action = null;
    } else if (hasVerification) {
      title = 'Next: verify the hidden post';
      description =
          'Moltbook created the post. Complete its anti-spam challenge before it expires.';
      actionLabel = 'Verify post now';
      actionIcon = Icons.verified_user_outlined;
      action = onVerify;
    } else if (hasQueued) {
      title = 'Next: publish the approved post';
      description =
          'The exact text is approved and queued locally. Nothing has been sent yet.';
      actionLabel = 'Publish approved post';
      actionIcon = Icons.public;
      action = onPublish;
    } else if (hasDraft) {
      title = 'Next: review the exact post';
      description =
          'The draft is local. Review the final public text before approving it.';
      actionLabel = 'Review latest draft';
      actionIcon = Icons.rate_review_outlined;
      action = onReview;
    } else {
      title = 'Next: create a local draft';
      description =
          'Enter one or more public facts below. Draft creation does not publish anything.';
      actionLabel = null;
      actionIcon = Icons.edit_note_outlined;
      action = null;
    }

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  actionIcon,
                  color: colorScheme.onPrimaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WorkflowStep(number: '1', label: 'Draft'),
                _WorkflowStep(number: '2', label: 'Review'),
                _WorkflowStep(number: '3', label: 'Approve'),
                _WorkflowStep(number: '4', label: 'Publish & verify'),
              ],
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : action,
                  icon:
                      busy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(actionIcon),
                  label: Text(busy ? 'Working…' : actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  final String number;
  final String label;

  const _WorkflowStep({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          '$number  $label',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MoltbookDraftHistoryCard extends StatelessWidget {
  final List<MoltbookStoredDraft> drafts;
  final bool busy;
  final TextEditingController submoltController;
  final Future<void> Function(MoltbookStoredDraft draft) onDelete;
  final Future<void> Function(MoltbookStoredDraft draft) onReviewPublication;

  const _MoltbookDraftHistoryCard({
    required this.drafts,
    required this.busy,
    required this.submoltController,
    required this.onDelete,
    required this.onReviewPublication,
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
            TextField(
              controller: submoltController,
              decoration: const InputDecoration(
                labelText: 'Publication destination',
                prefixText: 'm/',
              ),
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
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : () => onReviewPublication(draft),
                      icon: const Icon(Icons.rate_review_outlined),
                      label: const Text('Review'),
                    ),
                    IconButton(
                      tooltip: 'Delete local draft',
                      onPressed: busy ? null : () => onDelete(draft),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoltbookPublicationCard extends StatelessWidget {
  final List<ExternalEffectOperation> operations;
  final bool busy;
  final Future<void> Function(ExternalEffectOperation operation) onProcess;
  final Future<void> Function(ExternalEffectOperation operation)
  onResolveVerification;
  final Future<void> Function(Uri uri) onOpenPost;

  const _MoltbookPublicationCard({
    required this.operations,
    required this.busy,
    required this.onProcess,
    required this.onResolveVerification,
    required this.onOpenPost,
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
              'Publication status · ${operations.length}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'A post is complete only after Moltbook confirms that the exact approved text is publicly visible.',
              style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            const SizedBox(height: 10),
            ...operations.reversed.map((operation) {
              final postUri = MoltbookPublicationService.publishedPostUri(
                operation,
              );
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(operation.state.wireName.replaceAll('_', ' ')),
                subtitle: Text(
                  '${operation.operationId}\n'
                  'attempts ${operation.attemptCount} · '
                  '${operation.lastErrorCode ?? "no error"}',
                ),
                isThreeLine: true,
                trailing:
                    postUri != null
                        ? FilledButton.tonalIcon(
                          onPressed: busy ? null : () => onOpenPost(postUri),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open post'),
                        )
                        : operation.state == ExternalEffectState.queued ||
                            operation.state == ExternalEffectState.unresolved
                        ? FilledButton.icon(
                          onPressed:
                              busy
                                  ? null
                                  : operation.requiredAction != null
                                  ? () => onResolveVerification(operation)
                                  : () => onProcess(operation),
                          icon: Icon(
                            operation.requiredAction != null
                                ? Icons.verified_user_outlined
                                : Icons.public,
                            size: 18,
                          ),
                          label: Text(
                            operation.state == ExternalEffectState.queued
                                ? 'Publish'
                                : operation.requiredAction != null
                                ? 'Verify'
                                : 'Reconcile',
                          ),
                        )
                        : Icon(
                          operation.state == ExternalEffectState.succeeded
                              ? Icons.verified_outlined
                              : Icons.info_outline,
                        ),
              );
            }),
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
                'Use the local draft history below to review an exact publication.',
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
  final MoltbookFeedObservation? feedObservation;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;
  final VoidCallback onObserveHome;
  final VoidCallback onObserveFeed;
  final VoidCallback onDisconnect;

  const _MoltbookConnectionCard({
    required this.binding,
    required this.apiKeyController,
    required this.busy,
    required this.homeObservation,
    required this.feedObservation,
    required this.onConnect,
    required this.onRefresh,
    required this.onObserveHome,
    required this.onObserveFeed,
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
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : onObserveFeed,
                          icon: const Icon(Icons.dynamic_feed_outlined),
                          label: const Text('Observe feed'),
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
            if (feedObservation != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Latest public feed · ${feedObservation!.posts.length} posts',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...feedObservation!.posts
                  .take(5)
                  .map(
                    (post) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        post.isVerified && !post.isSpam
                            ? Icons.verified_outlined
                            : Icons.warning_amber_rounded,
                      ),
                      title: Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${post.authorName} · m/${post.submoltName} · '
                        '${post.commentCount} comments',
                      ),
                    ),
                  ),
              const Text(
                'Remote content is untrusted and remains in memory only.',
                style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
              ),
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
