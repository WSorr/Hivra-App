import 'package:bech32/bech32.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/app_runtime_service.dart';
import '../services/capsule_state_manager.dart';
import '../services/invitation_intent_handler.dart';
import '../models/invitation.dart';
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
  final AppRuntimeService _runtime = AppRuntimeService();
  late final CapsuleStateManager _stateManager;
  late final InvitationIntentHandler _invitationIntents;

  bool _bootstrapping = true;
  Stopwatch? _launchStopwatch;
  bool _transportQuickSyncInFlight = false;
  DateTime? _lastTransportQuickSyncAt;
  StreamSubscription<dynamic>? _connectivitySubscription;
  DateTime? _lastNetworkTriggeredSyncAt;

  String _publicKeyText = '';
  int _starterCount = 0;
  int _relationshipCount = 0;
  int _pendingInvitations = 0;
  bool _isNeste = true;
  String _ledgerHashHex = '0';
  int _ledgerVersion = 0;
  bool _hasLedgerHistory = false;
  String _activeCapsuleHex = '';

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
    _stateManager = _runtime.stateManager;
    _invitationIntents = _runtime.invitationIntents;
    _listenConnectivityChanges();
    Future.microtask(_bootstrapActiveRuntime);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _listenConnectivityChanges() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((dynamic result) {
      final hasTransport = _hasUsableTransport(result);
      if (!hasTransport) return;
      if (!mounted || _bootstrapping) return;
      unawaited(_syncInvitationsOnNetworkChange());
    });
  }

  bool _hasUsableTransport(dynamic result) {
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is Iterable) {
      for (final entry in result) {
        if (entry is ConnectivityResult && entry != ConnectivityResult.none) {
          return true;
        }
      }
      return false;
    }
    return true;
  }

  Future<void> _syncInvitationsOnNetworkChange() async {
    if (_activeCapsuleHex.isEmpty) return;
    final now = DateTime.now();
    final last = _lastNetworkTriggeredSyncAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastNetworkTriggeredSyncAt = now;

    final operationCapsuleHex = _activeCapsuleHex;
    debugPrint(
      '[StartupTiming] network_change_sync_start capsule=$operationCapsuleHex',
    );

    final result = await _runQuickTransportSync(
      reason: 'network_change',
      capsuleHex: operationCapsuleHex,
    );
    if (!mounted) return;
    if (result.code >= 0) {
      _loadCapsuleData();
    }
    unawaited(
      _runDelayedQuickTransportSync(
        reason: 'network_change_follow_up',
        delay: const Duration(seconds: 5),
        capsuleHex: operationCapsuleHex,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncInvitationsOnResume());
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
    await _runtime.persistLedgerSnapshot();
  }

  Future<void> _receiveTransportOnLaunch() async {
    final operationCapsuleHex = _activeCapsuleHex;
    final startedAtMs = _launchStopwatch?.elapsedMilliseconds;

    try {
      // Launch-time receive must stay lightweight so UI projection from ledger
      // remains responsive; full sync is still available via manual refresh.
      final result = await _runQuickTransportSync(
        reason: 'launch',
        capsuleHex: operationCapsuleHex,
      );
      if (result.code < 0) {
        debugPrint(
          '[StartupTiming] launch_receive_failed_code=${result.code}',
        );
      }
      debugPrint(
        '[StartupTiming] launch_receive_done_ms='
        '${_launchStopwatch?.elapsedMilliseconds ?? -1} '
        'started_ms=${startedAtMs ?? -1}',
      );
      unawaited(
        _runDelayedQuickTransportSync(
          reason: 'launch_follow_up',
          delay: const Duration(seconds: 7),
          capsuleHex: operationCapsuleHex,
        ),
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

  Future<void> _syncInvitationsOnResume() async {
    final operationCapsuleHex = _activeCapsuleHex;
    try {
      final result = await _runQuickTransportSync(
        reason: 'resume',
        capsuleHex: operationCapsuleHex,
      );
      if (!mounted) return;
      if (result.code >= 0) {
        _loadCapsuleData();
      }
      unawaited(
        _runDelayedQuickTransportSync(
          reason: 'resume_follow_up',
          delay: const Duration(seconds: 7),
          capsuleHex: operationCapsuleHex,
        ),
      );
    } catch (_) {
      // Resume sync is best-effort only.
    }
  }

  Future<void> _runDelayedQuickTransportSync({
    required String reason,
    required Duration delay,
    String? capsuleHex,
  }) async {
    await Future<void>.delayed(delay);
    if (!mounted) return;
    if (_isStaleCapsuleSyncRequest(capsuleHex)) {
      debugPrint(
        '[StartupTiming] quick_sync_delayed_stale_skip reason=$reason '
        'opCapsule=$capsuleHex activeCapsule=$_activeCapsuleHex',
      );
      return;
    }

    final result = await _runQuickTransportSync(
      reason: reason,
      capsuleHex: capsuleHex,
    );
    if (!mounted) return;
    if (result.code >= 0) {
      _loadCapsuleData();
    }
  }

  bool _shouldSkipQuickTransportSync({required bool force}) {
    if (force) return false;
    if (_transportQuickSyncInFlight) return true;
    final last = _lastTransportQuickSyncAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < const Duration(seconds: 4);
  }

  bool _isStaleCapsuleSyncRequest(String? capsuleHex) {
    final opCapsule = capsuleHex?.trim();
    if (opCapsule == null || opCapsule.isEmpty) {
      return false;
    }
    if (_activeCapsuleHex.isEmpty) {
      return false;
    }
    return opCapsule != _activeCapsuleHex;
  }

  Future<InvitationIntentResult> _runQuickTransportSync({
    required String reason,
    bool force = false,
    String? capsuleHex,
  }) async {
    if (_isStaleCapsuleSyncRequest(capsuleHex)) {
      debugPrint(
        '[StartupTiming] quick_sync_stale_skip reason=$reason '
        'opCapsule=$capsuleHex activeCapsule=$_activeCapsuleHex',
      );
      return const InvitationIntentResult(
        code: 0,
        message: 'Skipped stale capsule quick sync',
      );
    }

    if (_shouldSkipQuickTransportSync(force: force)) {
      debugPrint('[StartupTiming] quick_sync_skipped_reason=$reason');
      return const InvitationIntentResult(
        code: 0,
        message: 'Skipped duplicate quick sync',
      );
    }

    _transportQuickSyncInFlight = true;
    try {
      final quick = await _invitationIntents.fetchInvitationsQuick(
        capsuleHex: capsuleHex,
      );
      if (quick.code == -1003) {
        debugPrint(
          '[StartupTiming] quick_sync_timeout_fallback_full reason=$reason',
        );
        return await _invitationIntents.fetchInvitations(
          capsuleHex: capsuleHex,
        );
      }
      return quick;
    } finally {
      _transportQuickSyncInFlight = false;
      _lastTransportQuickSyncAt = DateTime.now();
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
    final displayKey = _runtime.capsuleRootPublicKey() ?? state.publicKey;
    final activeCapsuleHex = _bytesToHex(state.publicKey);
    var pendingInvitations = state.pendingInvitations;

    // Keep header pending counter aligned with Invitations projection while
    // user is on Invitations screen (same source of truth as visible list).
    if (_selectedIndex == 1) {
      pendingInvitations = _invitationIntents
          .loadInvitations(capsuleHex: activeCapsuleHex)
          .where((invitation) => invitation.status == InvitationStatus.pending)
          .length;
    }

    setState(() {
      _starterCount = state.starterCount;
      _relationshipCount = state.relationshipCount;
      _pendingInvitations = pendingInvitations;
      _isNeste = state.isNeste;
      _ledgerHashHex = state.ledgerHashHex;
      _ledgerVersion = state.version;
      _hasLedgerHistory = state.hasLedgerHistory;
      _activeCapsuleHex = activeCapsuleHex;
      _publicKeyText =
          displayKey.isEmpty ? '' : _encodeCapsulePublicKey(displayKey);
    });
  }

  String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
    } else if (bits >= from || ((acc << (to - bits)) & maxValue) != 0) {
      throw ArgumentError('Invalid bech32 padding');
    }

    return result;
  }

  Future<void> _handleLedgerChanged() async {
    if (!mounted) return;
    _loadCapsuleData();
  }

  Future<void> _syncRelationshipsTransport() async {
    final operationCapsuleHex = _activeCapsuleHex;
    final result = await _runQuickTransportSync(
      reason: 'relationships_screen_refresh',
      force: true,
      capsuleHex: operationCapsuleHex,
    );
    if (!mounted) return;
    if (result.code >= 0) {
      _loadCapsuleData();
    }
  }

  Future<void> _refreshFromTopBar() async {
    if (_selectedIndex == 1) {
      final result = await _invitationIntents.fetchInvitations(
        capsuleHex: _activeCapsuleHex,
      );
      if (!mounted) return;
      _loadCapsuleData();
      if (result.code < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
      return;
    }
    _loadCapsuleData();
  }

  Future<void> _bootstrapActiveRuntime() async {
    _launchStopwatch = Stopwatch()..start();
    final ok = await _runtime.bootstrapActiveCapsuleRuntime();
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
          key: ValueKey('starters-$_activeCapsuleHex-$_ledgerVersion'),
          runtime: _runtime,
          activeCapsuleHex: _activeCapsuleHex,
          onLedgerChanged: _handleLedgerChanged,
        );
      case 1:
        return InvitationsScreen(
          key: ValueKey('invitations-$_activeCapsuleHex'),
          runtime: _runtime,
          activeCapsuleHex: _activeCapsuleHex,
          ledgerVersion: _ledgerVersion,
          onLedgerChanged: _handleLedgerChanged,
        );
      case 2:
        return RelationshipsScreen(
          key: ValueKey('relationships-$_activeCapsuleHex'),
          service: _runtime.buildRelationshipService(),
          onLedgerChanged: _handleLedgerChanged,
          onSyncTransport: _syncRelationshipsTransport,
        );
      case 3:
        return WasmPluginsScreen(
          key: ValueKey('plugins-$_activeCapsuleHex-$_ledgerVersion'),
          embedded: true,
        );
      case 4:
        return SettingsScreen(
          service: _runtime.buildSettingsService(),
          onLedgerChanged: _handleLedgerChanged,
        );
      default:
        return StartersScreen(
          key: ValueKey('starters-$_activeCapsuleHex-$_ledgerVersion'),
          runtime: _runtime,
          activeCapsuleHex: _activeCapsuleHex,
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
        automaticallyImplyLeading: false,
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
                  onPressed: _refreshFromTopBar,
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
