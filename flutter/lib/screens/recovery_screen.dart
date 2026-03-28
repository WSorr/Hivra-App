import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/capsule_backup_codec.dart';
import '../services/recovery_service.dart';

class RecoveryScreen extends StatefulWidget {
  final RecoveryService service;

  const RecoveryScreen({super.key, required this.service});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final TextEditingController _phraseController = TextEditingController();
  String? _errorMessage;
  String? _selectedBackupName;
  String? _selectedBackupLedgerJson;
  bool? _selectedBackupIsGenesis;
  bool _isValid = false;
  bool _isRecovering = false;
  bool _showAdvancedOptions = false;

  @override
  void initState() {
    super.initState();
    _phraseController.addListener(_validatePhrase);
  }

  void _validatePhrase() {
    final phrase = _phraseController.text.trim();
    if (phrase.isEmpty) {
      setState(() {
        _isValid = false;
        _errorMessage = null;
      });
      return;
    }

    final isValid = widget.service.validateMnemonic(phrase);
    setState(() {
      _isValid = isValid;
      _errorMessage = isValid ? null : 'Invalid seed phrase';
    });
  }

  Future<void> _recover() async {
    if (!_isValid) return;

    setState(() {
      _isRecovering = true;
      _errorMessage = null;
    });

    final result = await widget.service.recover(
      phrase: _phraseController.text.trim(),
      selectedBackupLedgerJson: _selectedBackupLedgerJson,
      selectedBackupIsGenesis: _selectedBackupIsGenesis,
    );

    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, '/main');
      return;
    }

    setState(() {
      _errorMessage = result.errorMessage ?? 'Recovery failed';
      _isRecovering = false;
    });
  }

  Future<void> _pickBackupFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;

      final raw = await File(file.path).readAsString();
      final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(raw);
      if (ledgerJson == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid backup file format';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedBackupLedgerJson = ledgerJson;
        _selectedBackupName = file.name;
        _selectedBackupIsGenesis =
            widget.service.extractGenesisHintFromBackupJson(raw);
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Backup file read failed: $e';
      });
    }
  }

  Future<void> _pasteBackupJson() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Clipboard is empty. Copy a backup JSON file and try again.';
        });
        return;
      }

      final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(raw);
      if (ledgerJson == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Clipboard does not contain backup JSON. Choose a backup file or copy the full backup JSON and try again.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedBackupLedgerJson = ledgerJson;
        _selectedBackupName = 'Pasted from clipboard';
        _selectedBackupIsGenesis =
            widget.service.extractGenesisHintFromBackupJson(raw);
        _errorMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup loaded from clipboard')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not read backup JSON from the clipboard: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover Capsule'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your seed phrase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your 12 or 24 word seed phrase to restore your capsule identity.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Capsule type will be inferred automatically from recovered state.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'A backup file can be added to restore your history after the seed phrase is validated.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'If local backup files exist (ledger.json or capsule-backup.v1.json), they will be imported automatically.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phraseController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter seed phrase...',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                suffixIcon: _isValid
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickBackupFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose Backup File'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a backup file to restore history after your seed phrase is validated.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAdvancedOptions = !_showAdvancedOptions;
                  });
                },
                icon: Icon(
                  _showAdvancedOptions ? Icons.expand_less : Icons.expand_more,
                ),
                label: const Text('Advanced recovery options'),
              ),
            ),
            if (_showAdvancedOptions) ...[
              const SizedBox(height: 8),
              const Text(
                'If file selection is unavailable, you can paste the full backup JSON from the clipboard.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pasteBackupJson,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste Backup JSON'),
              ),
            ],
            if (_selectedBackupName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Selected backup: $_selectedBackupName',
                style: const TextStyle(color: Colors.greenAccent),
              ),
            ],
            const SizedBox(height: 16),
            if (_isRecovering)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _isValid ? _recover : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Recover Capsule'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }
}
