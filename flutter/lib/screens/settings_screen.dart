import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/settings_service.dart';
import '../utils/hivra_id_format.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService service;
  final Future<void> Function()? onLedgerChanged;

  const SettingsScreen(
      {super.key, required this.service, this.onLedgerChanged});

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
  String _appVersionLabel = 'Loading version...';

  @override
  void initState() {
    super.initState();
    _isNeste = widget.service.loadIsNeste();
    _loadContactCount();
    _loadAppVersionLabel();
  }

  Future<void> _loadContactCount() async {
    final count = await widget.service.contactCount();
    if (!mounted) return;
    setState(() => _contactCount = count);
  }

  Future<void> _loadAppVersionLabel() async {
    final label = await widget.service.appVersionLabel();
    if (!mounted) return;
    setState(() => _appVersionLabel = label);
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

  Future<void> _showOwnCardDialog() async {
    final card = await widget.service.buildOwnCard();
    if (card == null) {
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
        title: const Text('Share capsule card'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The other person scans this code in Hivra to add your capsule address.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: card.toQrPayload(),
                  size: 248,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                HivraIdFormat.short(card.rootKey),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'This card contains public routing information only.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: card.toPrettyJson()),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Capsule card JSON copied')),
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
                  'Scan the other capsule QR code or paste its shared card.',
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
              child: const Text('Paste'),
            ),
            TextButton.icon(
              onPressed: () async {
                final scanned = await Navigator.of(dialogContext).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const _CapsuleCardScannerScreen(),
                  ),
                );
                if (scanned == null || !dialogContext.mounted) return;
                controller.text = scanned;
                setDialogState(() => errorText = null);
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
            ),
            FilledButton(
              onPressed: () async {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  setDialogState(() => errorText = 'Card JSON is empty');
                  return;
                }
                try {
                  await widget.service.importCardPayload(raw);
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
                    separatorBuilder: (_, _) => const Divider(height: 16),
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
                            final removed = await widget.service
                                .removeTrustedCard(card.rootKey);
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
                subtitle:
                    const Text('View owner, hash and recent ledger events'),
                onTap: () async {
                  await Navigator.pushNamed(context, '/ledger_inspector');
                  await _notifyLedgerChanged();
                },
              ),
              ListTile(
                leading: const Icon(Icons.troubleshoot_outlined),
                title: const Text('Capsule Analyst'),
                subtitle: const Text(
                  'Bootstrap, files, ledger, consensus and transport checks',
                ),
                onTap: () async {
                  await Navigator.pushNamed(context, '/capsule_doctor');
                  await _notifyLedgerChanged();
                },
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
                leading: const Icon(Icons.cable),
                title: const Text('Transports'),
                subtitle: const Text(
                  'Inspect host transport adapters and delivery boundary',
                ),
                onTap: () async {
                  await Navigator.pushNamed(context, '/transports');
                  await _notifyLedgerChanged();
                },
              ),
              ListTile(
                leading: const Icon(Icons.extension),
                title: const Text('WASM plugins'),
                subtitle: const Text(
                  'Install and inspect sandboxed drone packages',
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
                  subtitle: Text(_isRelay
                      ? 'Active (stores messages for trusted peers)'
                      : 'Inactive (leaf node only)'),
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
                title: const Text('Share my capsule card'),
                subtitle: const Text('Show QR code or copy address card JSON'),
                onTap: _showOwnCardDialog,
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Add a capsule'),
                subtitle: const Text('Scan a QR code or paste a shared card'),
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
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Version'),
                subtitle: Text(_appVersionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
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

class _CapsuleCardScannerScreen extends StatefulWidget {
  const _CapsuleCardScannerScreen();

  @override
  State<_CapsuleCardScannerScreen> createState() =>
      _CapsuleCardScannerScreenState();
}

class _CapsuleCardScannerScreenState extends State<_CapsuleCardScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan capsule card')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Point the camera at a Hivra capsule card QR code.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
