import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/capsule_selector_service.dart';
import 'main_screen.dart';
import 'first_launch_screen.dart';

class CapsuleSelectorScreen extends StatefulWidget {
  final bool autoSelectSingle;

  const CapsuleSelectorScreen({super.key, this.autoSelectSingle = true});

  @override
  State<CapsuleSelectorScreen> createState() => _CapsuleSelectorScreenState();
}

class _CapsuleSelectorScreenState extends State<CapsuleSelectorScreen> {
  final CapsuleSelectorService _service = CapsuleSelectorService();
  List<CapsuleSelectorItem> _capsules = [];
  bool _isLoading = true;
  final TextEditingController _seedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCapsules);
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _loadCapsules() async {
    _capsules = await _service.loadCapsules();

    if (_capsules.isEmpty && _service.seedExists()) {
      // If we still don't have an index, stay empty and let user create/recover.
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (widget.autoSelectSingle && _capsules.length == 1 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectCapsule(_capsules.first);
      });
    }
  }

  Future<void> _selectCapsule(CapsuleSelectorItem capsule) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _service.activateCapsule(capsule.publicKeyHex);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to activate capsule: $e')),
      );
      return;
    }

    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  void _createNewCapsule() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FirstLaunchScreen()),
    );
  }

  Future<void> _importCapsule() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;

      final raw = await File(file.path).readAsString();
      final importedHex = await _service.importCapsuleFromBackupJson(raw);
      if (importedHex == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed: invalid backup')),
        );
        return;
      }
      await _loadCapsules();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  Future<void> _exportCapsule(CapsuleSelectorItem capsule) async {
    try {
      if (Platform.isMacOS || Platform.isAndroid) {
        final tempDir = Directory.systemTemp;
        final tempPath =
            '${tempDir.path}/capsule-backup-${capsule.publicKeyHex.substring(0, 8)}.json';
        final path = await _service.exportCapsuleBackupToPath(
          capsule.publicKeyHex,
          tempPath,
        );
        if (path == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed')),
          );
          return;
        }
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            text: 'Hivra capsule backup',
          ),
        );
        return;
      }

      final folder = await getDirectoryPath(confirmButtonText: 'Save Here');
      if (folder == null || folder.isEmpty) return;

      final targetPath =
          '$folder/capsule-backup-${capsule.publicKeyHex.substring(0, 8)}.json';

      final path = await _service.exportCapsuleBackupToPath(
        capsule.publicKeyHex,
        targetPath,
      );
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported: ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _deleteCapsule(CapsuleSelectorItem capsule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PANIC: Irreversible Delete'),
        content: const Text(
          'This will PERMANENTLY DELETE the capsule, seed, and local ledger/backup files.\n\n'
          'THIS ACTION IS IRREVERSIBLE.\n'
          'If you do not have the seed phrase and backup, recovery is impossible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteCapsule(capsule.publicKeyHex);
    if (!mounted) return;
    await _loadCapsules();
  }

  Future<void> _restoreSeedForCapsule(CapsuleSelectorItem capsule) async {
    _seedController.clear();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Restore Seed'),
          content: TextField(
            controller: _seedController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Enter seed phrase (12 or 24 words)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    final phrase = _seedController.text.trim();
    if (!_service.validateMnemonic(phrase)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid seed phrase')),
      );
      return;
    }

    final seed = _service.mnemonicToSeed(phrase);
    final matches = await _service.seedMatchesCapsule(
      seed,
      capsule.publicKeyHex,
    );
    if (!matches) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seed does not match capsule')),
      );
      return;
    }

    await _service.saveSeedForCapsule(capsule.publicKeyHex, seed);
    await _loadCapsules();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_capsules.isEmpty) {
      // No capsules, go to first launch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FirstLaunchScreen()),
        );
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Capsule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewCapsule,
            tooltip: 'Create new capsule',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importCapsule,
            tooltip: 'Import capsule',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _capsules.length,
        itemBuilder: (ctx, index) {
          final capsule = _capsules[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: capsule.network == 'NESTE'
                      ? Colors.green.shade900
                      : Colors.orange.shade900,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    capsule.starterCount.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: capsule.network == 'NESTE'
                          ? Colors.green.shade900
                          : Colors.orange.shade900,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      capsule.network,
                      style: TextStyle(
                        fontSize: 10,
                        color: capsule.network == 'NESTE'
                            ? Colors.green.shade300
                            : Colors.orange.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDisplayKey(capsule.displayKeyText),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                'Last active: ${_formatDate(capsule.lastActive)} · '
                'Starters ${capsule.starterCount} · '
                'Relationships ${capsule.relationshipCount} · '
                'Pending ${capsule.pendingInvitations} · '
                'v${capsule.ledgerVersion}\n'
                'hash ${capsule.ledgerHashHex}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async => _selectCapsule(capsule),
              onLongPress: () => _showCapsuleMenu(capsule),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCapsuleMenu(CapsuleSelectorItem capsule) async {
    final hasSeed = await _service.hasStoredSeed(capsule.publicKeyHex);
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key),
                title: Text(hasSeed ? 'Replace Seed' : 'Restore Seed'),
                onTap: () => Navigator.pop(ctx, 'restore'),
              ),
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('Export Backup'),
                onTap: () => Navigator.pop(ctx, 'export'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Capsule'),
                subtitle: const Text('Permanently remove all local data'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        );
      },
    );
    if (action == 'export') {
      await _exportCapsule(capsule);
    } else if (action == 'restore') {
      await _restoreSeedForCapsule(capsule);
    } else if (action == 'delete') {
      await _deleteCapsule(capsule);
    }
  }

  String _formatDisplayKey(String key) {
    if (key.isEmpty) return 'No key';
    if (key.length <= 18) return key;
    return '${key.substring(0, 10)}...${key.substring(key.length - 6)}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

}
