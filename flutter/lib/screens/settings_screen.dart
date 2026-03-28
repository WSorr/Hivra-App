import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../utils/hivra_id_format.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService service;
  final Future<void> Function()? onLedgerChanged;

  const SettingsScreen({super.key, required this.service, this.onLedgerChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _notifyLedgerChanged() async {
    await widget.onLedgerChanged?.call();
  }

  bool _isNeste = true;
  bool _isRelay = false;
  int _contactCount = 0;

  @override
  void initState() {
    super.initState();
    _isNeste = widget.service.loadIsNeste();
    _loadContactCount();
  }

  Future<void> _loadContactCount() async {
    final count = await widget.service.contactCount();
    if (!mounted) return;
    setState(() => _contactCount = count);
  }

  Future<void> _showSeedPhrase() async {
    final seed = widget.service.loadSeed();
    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No seed found')),
      );
      return;
    }

    await Navigator.pushNamed(
      context,
      '/backup',
      arguments: {
        'seed': seed,
        'isNewWallet': false,
      },
    );
    await _notifyLedgerChanged();
  }

  Future<void> _showLocalTraceReport() async {
    final report = await widget.service.diagnoseCapsuleTraces();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local capsule trace'),
        content: SingleChildScrollView(
          child: SelectableText(report.toMultilineString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBootstrapDiagnostics() async {
    final report = await widget.service.diagnoseBootstrapReport();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bootstrap diagnostics'),
        content: SingleChildScrollView(
          child: SelectableText(report.toMultilineString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyContactCard() async {
    final card = await widget.service.buildOwnCard();
    if (card == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build capsule card')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: card.toPrettyJson()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Capsule card copied')),
    );
  }

  Future<void> _showOwnCardDialog() async {
    final json = await widget.service.exportOwnCardJson();
    if (json == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build capsule card')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My capsule card'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(json),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Capsule card copied')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _importPeerCard() async {
    final data = await Clipboard.getData('text/plain');
    final controller = TextEditingController(text: data?.text?.trim() ?? '');
    String? errorText;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import peer capsule card'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste the JSON capsule card shared by the other capsule.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 8,
                  maxLines: 16,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '{ "version": 1, ... }',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final clipboard = await Clipboard.getData('text/plain');
                controller.text = clipboard?.text?.trim() ?? '';
                setDialogState(() => errorText = null);
              },
              child: const Text('Paste clipboard'),
            ),
            FilledButton(
              onPressed: () async {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  setDialogState(() => errorText = 'Card JSON is empty');
                  return;
                }
                try {
                  await widget.service.importCardJson(raw);
                  await _loadContactCount();
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Peer capsule card imported')),
                  );
                } catch (e) {
                  setDialogState(() => errorText = '$e');
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTrustedPeerCards() async {
    final cards = await widget.service.listTrustedCards();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Trusted peer cards'),
          content: SizedBox(
            width: 620,
            child: cards.isEmpty
                ? const Text('No trusted peer cards imported yet.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: cards.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(HivraIdFormat.short(card.rootKey)),
                        subtitle: Text(
                          'Nostr ${HivraIdFormat.short(card.nostrNpub)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove',
                          onPressed: () async {
                            final removed =
                                await widget.service.removeTrustedCard(card.rootKey);
                            if (!removed) return;
                            cards.removeAt(index);
                            await _loadContactCount();
                            if (!dialogContext.mounted) return;
                            setDialogState(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 16),
          
          _buildSection(
            title: 'Security',
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Switch capsule'),
                subtitle: const Text('Choose a different capsule'),
                onTap: () {
                  Navigator.pushReplacementNamed(
                    context,
                    '/',
                    arguments: {'autoSelectSingle': false},
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Show seed phrase'),
                subtitle: const Text('View your backup phrase'),
                onTap: _showSeedPhrase,
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Ledger inspector'),
                subtitle: const Text('View owner, hash and recent ledger events'),
                onTap: () async {
                  await Navigator.pushNamed(context, '/ledger_inspector');
                  await _notifyLedgerChanged();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Local capsule trace'),
                subtitle: const Text(
                    'Inspect local files, seeds, runtime and legacy traces'),
                onTap: _showLocalTraceReport,
              ),
              ListTile(
                leading: const Icon(Icons.health_and_safety),
                title: const Text('Bootstrap diagnostics'),
                subtitle: const Text(
                    'Inspect startup bootstrap source, seed match and import readiness'),
                onTap: _showBootstrapDiagnostics,
              ),
            ],
          ),

          const Divider(),

          _buildSection(
            title: 'Network',
            children: [
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Network'),
                subtitle: Text(_isNeste ? 'Neste (main)' : 'Hood (test)'),
                trailing: Switch(
                  value: _isNeste,
                  onChanged: (value) {
                    setState(() {
                      _isNeste = value;
                    });
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.extension),
                title: const Text('WASM plugins'),
                subtitle: const Text(
                  'Inspect plugin host status and planned transport adapters',
                ),
                onTap: () async {
                  await Navigator.pushNamed(context, '/wasm_plugins');
                  await _notifyLedgerChanged();
                },
              ),
            ],
          ),
          if (Theme.of(context).platform == TargetPlatform.android) ...[
            _buildSection(
              title: 'Role',
              children: [
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: const Text('Relay mode'),
                  subtitle: Text(
                    _isRelay
                        ? 'Active (stores messages for trusted peers)'
                        : 'Inactive (leaf node only)'
                  ),
                  trailing: Switch(
                    value: _isRelay,
                    onChanged: (value) {
                      setState(() {
                        _isRelay = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const Divider(),
          ],

          _buildSection(
            title: 'Trusted Peers',
            children: [
              ListTile(
                leading: const Icon(Icons.badge),
                title: const Text('Copy my capsule card'),
                subtitle: const Text('Copy capsule address card as JSON'),
                onTap: _copyContactCard,
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Show my capsule card'),
                subtitle: const Text('View the JSON shared with remote peers'),
                onTap: _showOwnCardDialog,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Import peer capsule card'),
                subtitle: const Text('Paste JSON from clipboard or message'),
                onTap: _importPeerCard,
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Trusted peer cards'),
                subtitle: Text('$_contactCount saved'),
                onTap: _showTrustedPeerCards,
              ),
            ],
          ),

          const Divider(),

          _buildSection(
            title: 'About',
            children: [
              const ListTile(
                leading: Icon(Icons.info),
                title: Text('Version'),
                subtitle: Text('Hivra v1.0.0'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
