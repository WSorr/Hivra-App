import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  final Uint8List seed;
  final bool isNewWallet;
  final bool isGenesis;

  const BackupScreen({
    super.key,
    required this.seed,
    this.isNewWallet = true,
    this.isGenesis = false,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final BackupService _backup = BackupService();
  String? _mnemonic;
  String? _backupPath;
  bool _isSavingBackup = false;

  @override
  void initState() {
    super.initState();
    _generateMnemonic();
  }

  void _generateMnemonic() {
    try {
      final phrase = _backup.mnemonicFromSeed(widget.seed, wordCount: 24);
      setState(() {
        _mnemonic = phrase;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _copyToClipboard() {
    if (_mnemonic != null) {
      Clipboard.setData(ClipboardData(text: _mnemonic!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard!')),
      );
    }
  }

  Future<void> _exportBackup() async {
    if (_isSavingBackup) return;

    if (Platform.isMacOS || Platform.isAndroid) {
      await _shareBackup();
      return;
    }

    try {
      final folder = await getDirectoryPath(confirmButtonText: 'Save Here');
      if (folder == null || folder.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup save canceled')),
        );
        return;
      }

      final fileName =
          'capsule-backup-${DateTime.now().toIso8601String()}.json';
      final targetPath = '$folder/$fileName';

      if (mounted) {
        setState(() {
          _isSavingBackup = true;
        });
      }

      final path = await _backup.exportBackupEnvelopeToPath(targetPath);
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export capsule backup')),
        );
        return;
      }
      setState(() {
        _backupPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capsule backup saved: ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBackup = false;
        });
      }
    }
  }

  Future<void> _continue() async {
    if (widget.isNewWallet) {
      await _backup.persistAfterCreate(
        seed: widget.seed,
        isGenesis: widget.isGenesis,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _shareBackup() async {
    try {
      final tempFile = File(
        '${Directory.systemTemp.path}/capsule-backup-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      final path = await _backup.exportBackupEnvelopeToPath(tempFile.path);
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to prepare capsule backup')),
        );
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Hivra capsule backup',
        ),
      );
      if (!mounted) return;
      setState(() {
        _backupPath = path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup share failed: $e')),
      );
    }
  }

  Future<void> _revealBackup() async {
    final path = _backupPath;
    if (path == null || path.isEmpty) return;

    try {
      final result = await Process.run('open', ['-R', path]);
      if (!mounted) return;
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reveal backup: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mnemonic == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final words = _mnemonic!.split(' ');
    final backupActionLabel = Platform.isAndroid ? 'Share Backup' : 'Save Backup';
    final backupActionIcon = Platform.isAndroid ? Icons.share : Icons.save;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNewWallet ? 'Backup Your Capsule' : 'Seed Phrase'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Your Seed Phrase',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'This phrase is the ONLY way to restore your capsule.\n'
              'Store it securely. Never share it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? 'On Android, backup export currently uses the system share sheet.'
                  : 'Save a backup file in addition to storing the seed phrase securely.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${index + 1}. ${words[index]}'),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            if (_backupPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Backup file: $_backupPath',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSavingBackup ? null : _exportBackup,
                    icon: _isSavingBackup
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(backupActionIcon),
                    label: Text(_isSavingBackup ? 'Saving...' : backupActionLabel),
                  ),
                ),
                if (!Platform.isAndroid) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareBackup,
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _continue,
                    icon: const Icon(Icons.done),
                    label: Text(widget.isNewWallet ? 'Continue' : 'Done'),
                  ),
                ),
              ],
            ),
            if (_backupPath != null && Platform.isMacOS) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _revealBackup,
                icon: const Icon(Icons.folder_open),
                label: const Text('Reveal Saved Backup'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
