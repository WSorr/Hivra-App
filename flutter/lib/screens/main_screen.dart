import 'package:bech32/bech32.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';
import '../services/capsule_state_manager.dart';
import '../services/invitation_actions_service.dart';
import '../services/relationship_service.dart';
import '../services/settings_service.dart';
import 'starters_screen.dart';
import 'invitations_screen.dart';
import 'relationships_screen.dart';
import 'settings_screen.dart';
import 'wasm_plugins_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final HivraBindings _hivra = HivraBindings();
  late final CapsuleStateManager _stateManager;
  final CapsulePersistenceService _persistence = CapsulePersistenceService();
  late final InvitationActionsService _invitationActions;

  bool _bootstrapping = true;
  Stopwatch? _launchStopwatch;

  String _publicKeyText = '';
  int _starterCount = 0;
  int _relationshipCount = 0;
  int _pendingInvitations = 0;
  bool _isNeste = true;
  String _ledgerHashHex = '0';
  int _ledgerVersion = 0;
  bool _hasLedgerHistory = false;

  String get _shortPublicKey {
    if (_publicKeyText.isEmpty) return 'No key';
    if (_publicKeyText.length <= 18) return _publicKeyText;
    return '${_publicKeyText.substring(0, 10)}...${_publicKeyText.substring(_publicKeyText.length - 6)}';
  }

  String get _shortLedgerHash {
    if (_ledgerHashHex.isEmpty) return '0';
    if (_ledgerHashHex.length <= 14) return _ledgerHashHex;
    return '${_ledgerHashHex.substring(0, 8)}...${_ledgerHashHex.substring(_ledgerHashHex.length - 4)}';
  }

  final List<String> _titles = const [
    'Starters',
    'Invitations',
    'Relationships',
    'Plugins',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateManager = CapsuleStateManager(_hivra);
    _invitationActions = InvitationActionsService(_hivra);
    Future.microtask(_bootstrapActiveRuntime);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCapsuleData();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _snapshotLedger();
    }
  }

  Future<void> _snapshotLedger() async {
    await _persistence.persistLedgerSnapshot(_hivra);
  }

  Future<void> _receiveTransportOnLaunch() async {
    final startedAtMs = _launchStopwatch?.elapsedMilliseconds;

    try {
      final result = await _invitationActions.fetchInvitationsQuick();
      if (!result.isSuccess || result.ledgerJson == null || result.ledgerJson!.isEmpty) {
        return;
      }
      debugPrint(
        '[StartupTiming] launch_receive_done_ms='
        '${_launchStopwatch?.elapsedMilliseconds ?? -1} '
        'started_ms=${startedAtMs ?? -1}',
      );
    } catch (_) {
      // Launch-time receive is best-effort only.
      debugPrint(
        '[StartupTiming] launch_receive_failed_ms='
        '${_launchStopwatch?.elapsedMilliseconds ?? -1} '
        'started_ms=${startedAtMs ?? -1}',
      );
    }
  }

  void _scheduleLaunchReceive() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      debugPrint(
        '[StartupTiming] first_frame_ms='
        '${_launchStopwatch?.elapsedMilliseconds ?? -1}',
      );
      await _receiveTransportOnLaunch();
      if (!mounted) return;
      _loadCapsuleData();
      debugPrint(
        '[StartupTiming] post_receive_refresh_ms='
        '${_launchStopwatch?.elapsedMilliseconds ?? -1}',
      );
    });
  }

  void _loadCapsuleData() {
    _stateManager.refreshWithFullState();
    final state = _stateManager.state;
    final displayKey = _hivra.capsuleRootPublicKey() ?? state.publicKey;

    setState(() {
      _starterCount = state.starterCount;
      _relationshipCount = state.relationshipCount;
      _pendingInvitations = state.pendingInvitations;
      _isNeste = state.isNeste;
      _ledgerHashHex = state.ledgerHashHex;
      _ledgerVersion = state.version;
      _hasLedgerHistory = state.hasLedgerHistory;
      _publicKeyText = displayKey.isEmpty
          ? ''
          : _encodeCapsulePublicKey(displayKey);
    });
  }

  String _encodeCapsulePublicKey(Uint8List bytes) {
    final words = _convertBits(bytes, 8, 5, true);
    return bech32.encode(Bech32('h', words));
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxValue = (1 << to) - 1;

    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw ArgumentError('Invalid key byte for bech32 conversion');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxValue);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (to - bits)) & maxValue);
      }
    } else if (bits >= from ||
        ((acc << (to - bits)) & maxValue) != 0) {
      throw ArgumentError('Invalid bech32 padding');
    }

    return result;
  }

  Future<void> _handleLedgerChanged() async {
    if (!mounted) return;
    _loadCapsuleData();
  }

  Future<void> _bootstrapActiveRuntime() async {
    _launchStopwatch = Stopwatch()..start();
    final ok = await _persistence.bootstrapActiveCapsuleRuntime(_hivra);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _bootstrapping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to bootstrap active capsule')),
      );
      return;
    }

    debugPrint(
      '[StartupTiming] bootstrap_done_ms='
      '${_launchStopwatch?.elapsedMilliseconds ?? -1}',
    );
    _loadCapsuleData();
    setState(() {
      _bootstrapping = false;
    });
    _scheduleLaunchReceive();
  }

  Widget _buildCurrentScreen() {
    if (!_hasLedgerHistory && _selectedIndex != 4) {
      return _buildAwaitingHistoryState();
    }

    switch (_selectedIndex) {
      case 0:
        return StartersScreen(
          key: ValueKey('starters-$_ledgerVersion'),
          hivra: _hivra,
          onLedgerChanged: _handleLedgerChanged,
        );
      case 1:
        return InvitationsScreen(
          key: ValueKey('invitations-$_ledgerVersion'),
          hivra: _hivra,
          onLedgerChanged: _handleLedgerChanged,
        );
      case 2:
        return RelationshipsScreen(
          key: ValueKey('relationships-$_ledgerVersion'),
          service: RelationshipService(_hivra),
          onLedgerChanged: _handleLedgerChanged,
        );
      case 3:
        return const WasmPluginsScreen(embedded: true);
      case 4:
        return SettingsScreen(
          service: SettingsService(_hivra),
          onLedgerChanged: _handleLedgerChanged,
        );
      default:
        return StartersScreen(
          key: ValueKey('starters-$_ledgerVersion'),
          hivra: _hivra,
          onLedgerChanged: _handleLedgerChanged,
        );
    }
  }


  Widget _buildAwaitingHistoryState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            const Text(
              'Awaiting ledger history',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'This capsule is loaded, but its local ledger has no events yet. '
              'Import a ledger, restore a backup, or receive transport events to activate the capsule view.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _selectedIndex = 4);
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
                FilledButton.icon(
                  onPressed: _loadCapsuleData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh from ledger'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Settings stays available for import and recovery.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(98),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _isNeste
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _isNeste ? 'NESTE' : 'HOOD',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isNeste
                                    ? Colors.green.shade300
                                    : Colors.orange.shade300,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: _publicKeyText.isEmpty
                                  ? 'No capsule key'
                                  : _publicKeyText,
                              waitDuration: const Duration(milliseconds: 200),
                              showDuration: const Duration(seconds: 12),
                              preferBelow: false,
                              verticalOffset: 18,
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(
                                maxWidth: 520,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF11161D),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF2C3642),
                                ),
                              ),
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontFamily: 'monospace',
                                height: 1.35,
                              ),
                              child: Text(
                                _shortPublicKey,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            splashRadius: 16,
                            tooltip: 'Copy capsule key',
                            onPressed: _publicKeyText.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: _publicKeyText));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Capsule key copied')),
                                    );
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatItem(
                            icon: Icons.grid_3x3,
                            value: _starterCount.toString(),
                            label: 'Starters',
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 16),
                          _buildStatItem(
                            icon: Icons.people,
                            value: _relationshipCount.toString(),
                            label: 'Relationships',
                            color: Colors.green,
                          ),
                          const SizedBox(width: 16),
                          _buildStatItem(
                            icon: Icons.mail,
                            value: _pendingInvitations.toString(),
                            label: 'Pending',
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hasLedgerHistory
                            ? 'Ledger v$_ledgerVersion · hash $_shortLedgerHash'
                            : 'Ledger empty · awaiting history',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadCapsuleData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_3x3),
            label: 'Starters',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mail),
            label: 'Invitations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Relationships',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.extension),
            label: 'Plugins',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
