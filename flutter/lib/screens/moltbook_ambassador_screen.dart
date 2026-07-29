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
  final TextEditingController _reviewedBodyController = TextEditingController();
  final TextEditingController _audienceController = TextEditingController(
    text: 'agent-developers',
  );
  final TextEditingController _publicSourceNotesController =
      TextEditingController();
  final TextEditingController _factsController = TextEditingController();
  final TextEditingController _replyBodyController = TextEditingController();
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
  MoltbookConversationObservation? _conversationObservation;
  String? _conversationSelectionKind;
  MoltbookHeartbeatPlan? _heartbeatPlan;
  MoltbookEngagementPlan? _engagementPlan;
  MoltbookReplyProposal? _replyProposal;
  MoltbookReplyDraftPreview? _replyDraftPreview;
  MoltbookFeedCheckpoint? _feedCheckpoint;
  MoltbookDraftPreview? _draftPreview;
  MoltbookPublicBulletinProposal? _publicBulletinProposal;
  List<MoltbookStoredDraft> _storedDrafts = const <MoltbookStoredDraft>[];
  List<ExternalEffectOperation> _publications =
      const <ExternalEffectOperation>[];
  bool _draftBusy = false;
  bool _publicFactsBusy = false;
  bool _publicationBusy = false;
  bool _replyBusy = false;
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
    _reviewedBodyController.dispose();
    _audienceController.dispose();
    _publicSourceNotesController.dispose();
    _factsController.dispose();
    _replyBodyController.dispose();
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
        widget.module.loadMoltbookFeedCheckpoint(),
      ]);
      final configuration = results[0] as MoltbookAmbassadorConfiguration;
      final binding = results[1] as MoltbookConnectionBinding?;
      final drafts = results[2] as List<MoltbookStoredDraft>;
      final publications = results[3] as List<ExternalEffectOperation>;
      final feedCheckpoint = results[4] as MoltbookFeedCheckpoint;
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
        _feedCheckpoint = feedCheckpoint;
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
        _feedObservation = null;
        _conversationObservation = null;
        _conversationSelectionKind = null;
        _heartbeatPlan = null;
        _engagementPlan = null;
        _replyProposal = null;
        _replyDraftPreview = null;
        _replyBodyController.clear();
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

  Future<void> _planHeartbeat() async {
    setState(() => _connectionBusy = true);
    try {
      final plan = await widget.module.planMoltbookHeartbeat();
      final checkpoint = await widget.module.loadMoltbookFeedCheckpoint();
      if (!mounted) return;
      setState(() {
        _heartbeatPlan = plan;
        _feedCheckpoint = checkpoint;
      });
      _showNotice('WASM heartbeat plan prepared');
    } catch (error) {
      if (mounted) {
        _showNotice('Could not plan Moltbook heartbeat: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _observeConversation(String postId, String selectionKind) async {
    setState(() {
      _connectionBusy = true;
      _conversationObservation = null;
      _conversationSelectionKind = null;
      _engagementPlan = null;
      _replyProposal = null;
      _replyDraftPreview = null;
      _replyBodyController.clear();
    });
    try {
      final observation = await widget.module.observeMoltbookConversation(
        postId,
      );
      if (!mounted) return;
      setState(() {
        _conversationObservation = observation;
        _conversationSelectionKind = selectionKind;
      });
      _showNotice(
        'Loaded ${observation.comments.length} recent comments for review',
      );
    } catch (error) {
      if (mounted) {
        _showNotice(
          'Could not observe Moltbook conversation: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _planEngagement() async {
    final conversation = _conversationObservation;
    final selectionKind = _conversationSelectionKind;
    if (conversation == null || selectionKind == null) {
      _showNotice('Review one Moltbook conversation first', isError: true);
      return;
    }
    setState(() {
      _connectionBusy = true;
      _engagementPlan = null;
      _replyProposal = null;
      _replyDraftPreview = null;
      _replyBodyController.clear();
    });
    try {
      final plan = await widget.module.planMoltbookEngagement(
        conversation: conversation,
        selectionKind: selectionKind,
      );
      if (!mounted) return;
      setState(() => _engagementPlan = plan);
      _showNotice('WASM engagement proposal prepared');
    } catch (error) {
      if (mounted) {
        _showNotice(
          'Could not plan Moltbook engagement: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _connectionBusy = false);
    }
  }

  Future<void> _proposeReply() async {
    final conversation = _conversationObservation;
    final plan = _engagementPlan;
    if (conversation == null || plan == null) {
      _showNotice('Prepare an engagement plan first', isError: true);
      return;
    }
    if (!const <String>{
      'reply_draft',
      'comment_draft',
    }.contains(plan.actionClass)) {
      _showNotice('This engagement plan does not allow a reply', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Send public conversation to AI?'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Gemini receives only the bounded public post, recent public comments, the engagement plan, and the local ambassador persona. Remote text is treated as untrusted. No ledger, contacts, credentials, or Capsule history are sent.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      conversation.post.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${conversation.comments.length} bounded comment(s) · '
                      'target ${plan.targetCommentId ?? "post root"}',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Generate reply proposal'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _replyBusy = true;
      _replyProposal = null;
      _replyDraftPreview = null;
    });
    try {
      final proposal = await widget.module.proposeMoltbookReply(
        conversation: conversation,
        engagementPlan: plan,
      );
      if (!mounted) return;
      setState(() {
        _replyProposal = proposal;
        _replyBodyController.text = proposal.body;
      });
      _showNotice(
        'AI reply proposed. Review and edit it before WASM preparation.',
      );
    } catch (error) {
      if (mounted) {
        _showNotice('Could not propose reply: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _replyBusy = false);
    }
  }

  Future<void> _prepareReply() async {
    final plan = _engagementPlan;
    if (plan == null) {
      _showNotice('Prepare an engagement plan first', isError: true);
      return;
    }
    setState(() {
      _replyBusy = true;
      _replyDraftPreview = null;
    });
    try {
      final preview = await widget.module.prepareMoltbookReply(
        engagementPlan: plan,
        reviewedBody: _replyBodyController.text,
      );
      if (!mounted) return;
      setState(() => _replyDraftPreview = preview);
      _showNotice('WASM reply draft prepared for exact review');
    } catch (error) {
      if (mounted) {
        _showNotice('Could not prepare reply: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _replyBusy = false);
    }
  }

  Future<void> _reviewReplyPublication() async {
    final draft = _replyDraftPreview;
    if (draft == null) {
      _showNotice('Prepare the WASM reply draft first', isError: true);
      return;
    }
    setState(() => _publicationBusy = true);
    try {
      final operation = await widget.module.prepareMoltbookReplyPublication(
        draft: draft,
      );
      if (!mounted) return;
      final payload = MoltbookPublicationService.decodePayload(operation);
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Approve permanent public reply?'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Account: ${payload['account_name']}\n'
                        'Post: ${payload['post_id']}\n'
                        'Reply target: ${payload['parent_comment_id'] ?? "post root"}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      SelectableText(payload['content'].toString()),
                      const SizedBox(height: 16),
                      const Text(
                        'This exact text creates a public external effect. Moltbook may retain or redistribute it. Approval cannot be inferred or automated.',
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
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Keep local'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Approve exact reply'),
                ),
              ],
            ),
      );
      if (!mounted) return;
      if (approved == true) {
        await widget.module.approveMoltbookPublication(operation);
        _showNotice('Reply approved and queued locally');
      } else {
        _showNotice('Reply remains local and unapproved');
      }
      final publications = await widget.module.loadMoltbookPublications();
      if (mounted) setState(() => _publications = publications);
    } catch (error) {
      if (mounted) {
        _showNotice(
          'Could not prepare reply publication: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _publicationBusy = false);
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
        reviewedBody: _reviewedBodyController.text,
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

  Future<void> _proposePublicBulletin() async {
    final sourceNotes = _publicSourceNotesController.text.trim();
    if (sourceNotes.isEmpty) {
      _showNotice('Add public source notes first', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Send these public notes to AI?'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Only the text below, the selected public topic, and the local ambassador persona will be sent. No ledger, contacts, repository files, credentials, or Capsule history are included.',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(sourceNotes),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Generate proposal'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _publicFactsBusy = true;
      _publicBulletinProposal = null;
    });
    try {
      final proposal = await widget.module.proposeMoltbookPublicBulletin(
        sourceNotes,
        category: _categoryController.text,
      );
      if (!mounted) return;
      setState(() {
        _publicBulletinProposal = proposal;
        _titleHintController.text = proposal.title;
        _reviewedBodyController.text = proposal.body;
        _factsController.text = proposal.facts.join('\n');
        _draftPreview = null;
      });
      _showNotice(
        'AI proposed a public post backed by ${proposal.facts.length} fact(s). Review and edit every field before preparing the WASM draft.',
      );
    } catch (error) {
      if (!mounted) return;
      _showNotice('Could not propose public bulletin: $error', isError: true);
    } finally {
      if (mounted) setState(() => _publicFactsBusy = false);
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
                    conversationObservation: _conversationObservation,
                    engagementPlan: _engagementPlan,
                    replyBodyController: _replyBodyController,
                    replyProposal: _replyProposal,
                    replyDraftPreview: _replyDraftPreview,
                    heartbeatPlan: _heartbeatPlan,
                    feedCheckpoint: _feedCheckpoint,
                    replyBusy: _replyBusy || _publicationBusy,
                    onConnect: _connect,
                    onRefresh: _refreshConnection,
                    onObserveHome: _observeHome,
                    onObserveFeed: _observeFeed,
                    onObserveConversation: _observeConversation,
                    onPlanEngagement: _planEngagement,
                    onProposeReply: _proposeReply,
                    onPrepareReply: _prepareReply,
                    onReviewReplyPublication: _reviewReplyPublication,
                    onReplyChanged:
                        () => setState(() => _replyDraftPreview = null),
                    onPlanHeartbeat: _planHeartbeat,
                    onDisconnect: _disconnect,
                  ),
                  const SizedBox(height: 20),
                  _MoltbookDraftCard(
                    bulletinIdController: _bulletinIdController,
                    releaseTagController: _releaseTagController,
                    categoryController: _categoryController,
                    titleHintController: _titleHintController,
                    reviewedBodyController: _reviewedBodyController,
                    audienceController: _audienceController,
                    publicSourceNotesController: _publicSourceNotesController,
                    factsController: _factsController,
                    busy: _draftBusy || _publicFactsBusy,
                    publicFactsBusy: _publicFactsBusy,
                    publicBulletinProposal: _publicBulletinProposal,
                    preview: _draftPreview,
                    onProposePublicBulletin: _proposePublicBulletin,
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
              'A post or reply is complete only after Moltbook confirms that the exact approved text is publicly visible.',
              style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
            ),
            const SizedBox(height: 10),
            ...operations.reversed.map((operation) {
              final payload = MoltbookPublicationService.decodePayload(
                operation,
              );
              final isReply = payload.containsKey('post_id');
              final postUri = MoltbookPublicationService.publishedPostUri(
                operation,
              );
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${isReply ? "Reply" : "Post"} · '
                  '${operation.state.wireName.replaceAll('_', ' ')}',
                ),
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
                          label: Text(isReply ? 'Open thread' : 'Open post'),
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
  final TextEditingController reviewedBodyController;
  final TextEditingController audienceController;
  final TextEditingController publicSourceNotesController;
  final TextEditingController factsController;
  final bool busy;
  final bool publicFactsBusy;
  final MoltbookPublicBulletinProposal? publicBulletinProposal;
  final MoltbookDraftPreview? preview;
  final VoidCallback onProposePublicBulletin;
  final VoidCallback onPrepare;

  const _MoltbookDraftCard({
    required this.bulletinIdController,
    required this.releaseTagController,
    required this.categoryController,
    required this.titleHintController,
    required this.reviewedBodyController,
    required this.audienceController,
    required this.publicSourceNotesController,
    required this.factsController,
    required this.busy,
    required this.publicFactsBusy,
    required this.publicBulletinProposal,
    required this.preview,
    required this.onProposePublicBulletin,
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
              'The reviewed title, body, and supporting facts are sent to the installed WASM plugin. Preparing a draft does not publish anything.',
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
              decoration: const InputDecoration(
                labelText: 'Reviewed post title',
                helperText:
                    'Specific and factual. Avoid generic repeated titles.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reviewedBodyController,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Reviewed post body',
                helperText:
                    'Natural public prose. Edit before WASM validation; no automatic publication.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: audienceController,
              decoration: const InputDecoration(labelText: 'Audience'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF17252B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF365C66)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF72D5C4)),
                      SizedBox(width: 8),
                      Text(
                        'AI communication proposal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Paste only information you are willing to send to the selected AI provider. The proposal stays local and cannot publish.',
                    style: TextStyle(color: Color(0xFFA9C7C4), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: publicSourceNotesController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Public source notes',
                      helperText:
                          'Explicit public input only. No secrets or private Capsule data.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onProposePublicBulletin,
                    icon:
                        publicFactsBusy
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.fact_check_outlined),
                    label: Text(
                      publicFactsBusy
                          ? 'Generating proposal'
                          : 'Propose reviewed post',
                    ),
                  ),
                  if (publicBulletinProposal != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${publicBulletinProposal!.providerLabel} · ${publicBulletinProposal!.model} · human review required',
                      style: const TextStyle(
                        color: Color(0xFF72D5C4),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: factsController,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Public facts',
                helperText:
                    'One supporting fact per line. These are provenance for the reviewed prose.',
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
  final MoltbookConversationObservation? conversationObservation;
  final MoltbookEngagementPlan? engagementPlan;
  final TextEditingController replyBodyController;
  final MoltbookReplyProposal? replyProposal;
  final MoltbookReplyDraftPreview? replyDraftPreview;
  final MoltbookHeartbeatPlan? heartbeatPlan;
  final MoltbookFeedCheckpoint? feedCheckpoint;
  final bool replyBusy;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;
  final VoidCallback onObserveHome;
  final VoidCallback onObserveFeed;
  final void Function(String postId, String selectionKind)
  onObserveConversation;
  final VoidCallback onPlanEngagement;
  final VoidCallback onProposeReply;
  final VoidCallback onPrepareReply;
  final VoidCallback onReviewReplyPublication;
  final VoidCallback onReplyChanged;
  final VoidCallback onPlanHeartbeat;
  final VoidCallback onDisconnect;

  const _MoltbookConnectionCard({
    required this.binding,
    required this.apiKeyController,
    required this.busy,
    required this.homeObservation,
    required this.feedObservation,
    required this.conversationObservation,
    required this.engagementPlan,
    required this.replyBodyController,
    required this.replyProposal,
    required this.replyDraftPreview,
    required this.heartbeatPlan,
    required this.feedCheckpoint,
    required this.replyBusy,
    required this.onConnect,
    required this.onRefresh,
    required this.onObserveHome,
    required this.onObserveFeed,
    required this.onObserveConversation,
    required this.onPlanEngagement,
    required this.onProposeReply,
    required this.onPrepareReply,
    required this.onReviewReplyPublication,
    required this.onReplyChanged,
    required this.onPlanHeartbeat,
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
                        FilledButton.icon(
                          onPressed: busy ? null : onPlanHeartbeat,
                          icon: const Icon(Icons.favorite_outline_rounded),
                          label: const Text('Plan heartbeat'),
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
              if (homeObservation!.activityOnOwnPosts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...homeObservation!.activityOnOwnPosts
                    .take(5)
                    .map(
                      (activity) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(
                          activity.postTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${activity.newNotificationCount} new · '
                          'm/${activity.submoltName}',
                        ),
                        trailing: TextButton(
                          onPressed:
                              busy
                                  ? null
                                  : () => onObserveConversation(
                                    activity.postId,
                                    'own_activity',
                                  ),
                          child: const Text('Review'),
                        ),
                      ),
                    ),
              ],
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
            if (conversationObservation != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                conversationObservation!.post.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${conversationObservation!.post.authorName} · '
                'm/${conversationObservation!.post.submoltName} · '
                '${conversationObservation!.comments.length} recent comments',
                style: const TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
              ),
              if (conversationObservation!.post.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  conversationObservation!.post.content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              ...conversationObservation!.comments.map(
                (comment) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                  title: Text(comment.authorName),
                  subtitle: Text(
                    comment.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (conversationObservation!.hasMoreComments)
                const Text(
                  'More comments exist remotely; this bounded review loads only the newest 20.',
                  style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
                ),
              const SizedBox(height: 4),
              const Text(
                'Read-only observation · remote text is untrusted and is not persisted.',
                style: TextStyle(color: Colors.orange, height: 1.35),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onPlanEngagement,
                icon: const Icon(Icons.rule_rounded),
                label: const Text('Plan engagement'),
              ),
              if (engagementPlan != null) ...[
                const SizedBox(height: 10),
                Text(
                  engagementPlan!.actionClass.replaceAll('_', ' '),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  engagementPlan!.reason,
                  style: const TextStyle(
                    color: Color(0xFF9CA7B5),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Proposal only · no AI text · no external effect',
                  style: TextStyle(color: Colors.orange, height: 1.35),
                ),
                if (const <String>{
                  'reply_draft',
                  'comment_draft',
                }.contains(engagementPlan!.actionClass)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16221D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF315A48)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assisted reply',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'AI proposes. You edit. WASM binds the exact text to this conversation. Publication still requires explicit approval.',
                          style: TextStyle(
                            color: Color(0xFF9CA7B5),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: replyBusy ? null : onProposeReply,
                          icon:
                              replyBusy
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Ask Gemini for reply'),
                        ),
                        if (replyProposal != null) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: replyBodyController,
                            minLines: 4,
                            maxLines: 10,
                            maxLength: 2000,
                            onChanged: (_) => onReplyChanged(),
                            decoration: const InputDecoration(
                              labelText: 'Exact public reply',
                              helperText:
                                  'Review every word. This field is still local.',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Grounded by ${replyProposal!.providerLabel} '
                            '(${replyProposal!.model})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          ...replyProposal!.groundingPoints.map(
                            (point) => Text(
                              '• $point',
                              style: const TextStyle(
                                color: Color(0xFF9CA7B5),
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: replyBusy ? null : onPrepareReply,
                            icon: const Icon(Icons.shield_outlined),
                            label: const Text('Prepare WASM reply'),
                          ),
                        ],
                        if (replyDraftPreview != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Bound draft ${replyDraftPreview!.draftHashHex.substring(0, 12)}…',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Target ${replyDraftPreview!.targetCommentId ?? "post root"} · exact reviewed text preserved',
                            style: const TextStyle(
                              color: Color(0xFF9CA7B5),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed:
                                replyBusy ? null : onReviewReplyPublication,
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('Review & queue reply'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
                      trailing: TextButton(
                        onPressed:
                            busy
                                ? null
                                : () => onObserveConversation(
                                  post.postId,
                                  'feed_candidate',
                                ),
                        child: const Text('Review'),
                      ),
                    ),
                  ),
              const Text(
                'Remote content is untrusted and remains in memory only.',
                style: TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
              ),
            ],
            if (heartbeatPlan != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Heartbeat · ${heartbeatPlan!.priority.replaceAll("_", " ")}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                heartbeatPlan!.reason,
                style: const TextStyle(color: Color(0xFF9CA7B5), height: 1.35),
              ),
              const SizedBox(height: 6),
              Text(
                '${heartbeatPlan!.candidatePostIds.length} candidates · '
                'review required · no external effect',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (feedCheckpoint?.lastObservedAtUtc != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${feedCheckpoint!.processedPostIds.length} remote post ids '
                  'remembered · checkpoint '
                  '${feedCheckpoint!.lastObservedAtUtc}',
                  style: const TextStyle(
                    color: Color(0xFF9CA7B5),
                    height: 1.35,
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
