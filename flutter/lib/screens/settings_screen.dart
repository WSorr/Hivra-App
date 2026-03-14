import 'package:flutter/material.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';
import '../services/capsule_state_manager.dart';

class SettingsScreen extends StatefulWidget {
  final HivraBindings hivra;

  const SettingsScreen({super.key, required this.hivra});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isNeste = true;
  bool _isRelay = false;
  final CapsulePersistenceService _persistence = CapsulePersistenceService();

  @override
  void initState() {
    super.initState();
    final state = CapsuleStateManager(widget.hivra).state;
    _isNeste = state.isNeste;
  }

  void _showSeedPhrase() async {
    final seed = widget.hivra.loadSeed();
    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No seed found')),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/backup',
      arguments: {
        'seed': seed,
        'isNewWallet': false,
      },
    );
  }

  Future<void> _showLocalTraceReport() async {
    final report = await _persistence.diagnoseCapsuleTraces(widget.hivra);
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
                onTap: () => Navigator.pushNamed(context, '/ledger_inspector'),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Local capsule trace'),
                subtitle: const Text(
                    'Inspect local files, seeds, runtime and legacy traces'),
                onTap: _showLocalTraceReport,
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
                onTap: () => Navigator.pushNamed(context, '/wasm_plugins'),
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
                leading: const Icon(Icons.people),
                title: const Text('Add trusted peer'),
                subtitle: const Text('Manually add a peer to trust'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('View trusted peers'),
                subtitle: const Text('0 peers'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coming soon')),
                  );
                },
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
