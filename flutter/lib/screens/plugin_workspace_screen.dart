import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

typedef PluginWorkspaceAction =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> settings, {
      Map<String, String>? credentials,
      Map<String, dynamic>? approvedOrder,
    });

/// Displays bounded package-owned fields, actions and evidence. This shell
/// does not know which product or strategy produced them.
class PluginWorkspaceScreen extends StatefulWidget {
  final List<String> capabilities;
  final PluginWorkspaceAction runWorkspaceAction;
  final Future<List<String>> Function(String fieldId)? readFieldOptions;
  final Future<Map<String, dynamic>> Function({
    required bool enabled,
    required int? expiresAtMs,
    int? expectedRevision,
    bool revoke,
    Map<String, dynamic>? approvedScope,
    Map<String, dynamic> settings,
  })?
  configureExecution;
  final Future<void> Function({
    required String host,
    required int port,
    required String password,
    required Future<bool> Function(String) trustPeer,
  })?
  connectVps;
  final Future<void> Function()? useOnline;

  const PluginWorkspaceScreen({
    super.key,
    this.capabilities = const [],
    required this.runWorkspaceAction,
    this.readFieldOptions,
    this.configureExecution,
    this.connectVps,
    this.useOnline,
  });

  @override
  State<PluginWorkspaceScreen> createState() => _PluginWorkspaceScreenState();
}

class _PluginWorkspaceScreenState extends State<PluginWorkspaceScreen>
    with WidgetsBindingObserver {
  final Map<String, TextEditingController> _fields = {};
  Map<String, dynamic>? _view;
  String? _error;
  bool _busy = false;
  bool _edited = false;
  bool _observationUnavailable = false;
  bool _choosing = false;
  int _presentationGeneration = 0;
  Timer? _refresh;
  AppLifecycleState? _appState;

  bool get _supportsExecution =>
      widget.capabilities.contains('workspace.schedule');

  @override
  void initState() {
    super.initState();
    _appState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _run('open');
  }

  @override
  void dispose() {
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    if (state == AppLifecycleState.resumed) _refreshVisibleStatus();
  }

  void _refreshVisibleStatus() {
    if (mounted &&
        _appState == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true &&
        _supportsExecution &&
        _view?['execution'] != null &&
        !_busy &&
        !_choosing) {
      _run('open');
    }
  }

  Future<void> _run(String action) async {
    final descriptor = (_view?['actions'] as List? ?? const []).where(
      (a) => (a as Map)['id'] == action,
    );
    final hostAction = descriptor.isEmpty ? null : descriptor.single['host'];
    if (hostAction == 'workspace.stop' && widget.configureExecution != null) {
      await _stopExecution();
      return;
    }
    if (_busy || _choosing) return;
    if (_observationUnavailable &&
        const {'workspace.start', 'bingx.order.submit'}.contains(hostAction)) {
      return;
    }
    final generation = ++_presentationGeneration;
    final preserveEdits = action == 'open' && _edited;
    Map<String, String>? credentials;
    Map<String, dynamic>? approvedOrder;
    if (descriptor.isNotEmpty &&
        (descriptor.single as Map)['host'] == 'bingx.account.connect') {
      setState(() => _choosing = true);
      try {
        credentials = await _accountCredentials();
      } finally {
        if (mounted && generation == _presentationGeneration) {
          setState(() => _choosing = false);
        }
      }
      if (!mounted ||
          generation != _presentationGeneration ||
          credentials == null) {
        return;
      }
    }
    if (descriptor.isNotEmpty &&
        (descriptor.single as Map)['host'] == 'bingx.order.submit') {
      if (_edited || _view?['confirmation'] is! Map) return;
      final request = Map<String, dynamic>.from(_view!['confirmation'] as Map);
      final plan = request['plan'] as Map;
      final cancelling = request['kind'] == 'order.entry.cancel';
      final exiting = request['kind'] == 'position.exit.place';
      final entry = exiting ? plan['entry_plan'] as Map : plan;
      setState(() => _choosing = true);
      bool confirmed = false;
      try {
        confirmed =
            await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: Text(
                      exiting
                          ? 'Place this LIVE position exit?'
                          : cancelling
                          ? 'Cancel this exact LIVE entry?'
                          : 'Place one LIVE limit order?',
                    ),
                    content: SingleChildScrollView(
                      child: Text(
                        exiting
                            ? '${entry["symbol"]} / position ${plan["position_id"]}\n'
                                'Limit ${plan["price"]}, reducing quantity ${plan["quantity"]}\n\n'
                                'Exit only the journaled fill. The target stays fixed after submission. '
                                'A limit order is not a guaranteed fill or verified stop protection.'
                            : cancelling
                            ? '${_view!["summary"]}\n\n${plan["symbol"]} / order ${request["order_id"]}\n'
                                'Cancel only this journaled entry if it is still unfilled. '
                                'A racing fill remains a position; cancellation does not close it. '
                                'No replacement is sent by this action.'
                            : '${_view!["summary"]}\n\n${plan["symbol"]} / ${plan["side"]} / ${plan["timeframe"]}\n'
                                'Price ${plan["price"]}, quantity ${plan["quantity"]}\n'
                                'Margin ${plan["margin"]} USDT, leverage ${plan["leverage"]}x\n'
                                'Requested stop ${plan["stop_price"]}\n\n'
                                'One entry only. Attached stop is requested, not verified position protection. '
                                'No automatic profit exit or background trader. Fees, slippage and liquidation may exceed the estimate. '
                                'Closing the app does not cancel the exchange order.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const ValueKey('plugin-confirm-entry'),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          cancelling ? 'Cancel this entry' : 'Place LIVE order',
                        ),
                      ),
                    ],
                  ),
            ) ??
            false;
      } finally {
        if (mounted && generation == _presentationGeneration) {
          setState(() => _choosing = false);
        }
      }
      if (!mounted || generation != _presentationGeneration || !confirmed) {
        return;
      }
      approvedOrder = request;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (action != 'open') _edited = true;
    });
    try {
      final settings = <String, dynamic>{};
      // Opening reads committed state. Draft input, including an incomplete
      // number, must neither block status recovery nor be committed by it.
      for (final raw
          in (action == 'open'
              ? const []
              : _view?['fields'] as List? ?? const [])) {
        final field = raw as Map;
        final text = _fields[field['id']]!.text.trim();
        settings[field['id'] as String] = switch (field['type']) {
          'integer' => int.parse(text),
          'number' => double.parse(text),
          _ => text,
        };
      }
      var view = await widget.runWorkspaceAction(
        action,
        settings,
        credentials: credentials,
        approvedOrder: approvedOrder,
      );
      if (!mounted || generation != _presentationGeneration) return;
      if (hostAction == 'workspace.start') {
        final configure = widget.configureExecution;
        if (configure == null || view['schedule'] is! Map) {
          throw StateError('Scheduled execution is not available in this host');
        }
        final scope = Map<String, dynamic>.from(view['schedule'] as Map);
        final onVps = view['host_connection']?['target'] == 'vps';
        final expectedRevision = view['execution']?['revision'] as int?;
        var untilRevoked = false;
        var hours = '24';
        int? deadline =
            DateTime.now().millisecondsSinceEpoch +
            const Duration(hours: 24).inMilliseconds;
        void updateDeadline() {
          final duration = double.tryParse(hours);
          if (duration == null ||
              !duration.isFinite ||
              duration <= 0 ||
              duration >
                  (8640000000000000 - DateTime.now().millisecondsSinceEpoch) /
                      3600000) {
            deadline = null;
            return;
          }
          final milliseconds = (duration * 3600000).round();
          final value = DateTime.now().millisecondsSinceEpoch + milliseconds;
          deadline =
              milliseconds > 0 && value <= 8640000000000000 ? value : null;
        }

        setState(() {
          _choosing = true;
          _busy = false;
        });
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder:
                  (context) => StatefulBuilder(
                    builder:
                        (context, update) => AlertDialog(
                          scrollable: true,
                          title: Text(
                            onVps
                                ? 'Start VPS LIVE cycles?'
                                : 'Start local LIVE cycles?',
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Until fully revoked'),
                                value: untilRevoked,
                                onChanged:
                                    (value) =>
                                        update(() => untilRevoked = value),
                              ),
                              if (!untilRevoked)
                                TextFormField(
                                  initialValue: hours,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Permission duration (hours)',
                                    errorText:
                                        deadline == null
                                            ? 'Enter a positive representable duration'
                                            : null,
                                  ),
                                  onChanged:
                                      (value) => update(() {
                                        hours = value;
                                        updateDeadline();
                                      }),
                                ),
                              Text(
                                untilRevoked
                                    ? 'No automatic expiry. An unreachable VPS may continue until revocation reaches it.'
                                    : deadline == null
                                    ? 'A valid deadline is required.'
                                    : 'Authorization ends: ${DateTime.fromMillisecondsSinceEpoch(deadline!).toLocal()}',
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${scope["symbol"]} / account ${scope["account_id"]}\n'
                                'Up to ${scope["max_margin"]} USDT margin per entry; requested stop '
                                '${scope["max_stop_percent"]}% of entry margin.\n\n'
                                'Authorize cancellation of invalidated, unfilled managed entries and '
                                'repeated entries after confirmed closure. No daily loss limit: '
                                'successive losses can exhaust the account. '
                                '${onVps ? "The VPS will continue while Capsule is closed; exchange credentials are sent over pinned SSH into the server host store, not WASM." : "App must remain open and online."} '
                                'Authorize reducing limit exits selected by the package for managed fills. '
                                'Stop protection remains unverified. '
                                'Stop disables automatic entries and cancellations; reducing exits remain authorized until expiry or full revocation. It does not '
                                'cancel exchange orders or close positions.',
                              ),
                              const Text(
                                'Full revocation ends all new automatic trading effects, including reducing exits. Existing exchange orders and positions remain. Expiry also ends reducing exits.',
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              key: const ValueKey('plugin-confirm-start'),
                              onPressed:
                                  !untilRevoked &&
                                          (deadline == null ||
                                              deadline! <=
                                                  DateTime.now()
                                                      .millisecondsSinceEpoch)
                                      ? null
                                      : () => Navigator.of(context).pop(true),
                              child: Text(
                                onVps
                                    ? 'Start VPS cycles'
                                    : 'Start local cycles',
                              ),
                            ),
                          ],
                        ),
                  ),
            ) ??
            false;
        if (!mounted || generation != _presentationGeneration) return;
        setState(() {
          _choosing = false;
          _busy = true;
        });
        if (confirmed) {
          view = await configure(
            enabled: true,
            expiresAtMs: untilRevoked ? null : deadline,
            expectedRevision: expectedRevision,
            approvedScope: scope,
            settings: settings,
          );
        }
        if (!mounted || generation != _presentationGeneration) return;
      }
      final ids = <String>{};
      for (final raw in view['fields'] as List) {
        final field = raw as Map;
        final id = field['id'] as String;
        ids.add(id);
        final controller = _fields.putIfAbsent(
          id,
          () => TextEditingController(),
        );
        final previous = (_view?['fields'] as List? ?? const []).where(
          (raw) => (raw as Map)['id'] == id,
        );
        if (!preserveEdits ||
            previous.isEmpty ||
            previous.single['type'] != field['type']) {
          final text = field['value'].toString();
          if (controller.text != text) controller.text = text;
        }
      }
      for (final id in _fields.keys.where((id) => !ids.contains(id)).toList()) {
        _fields.remove(id)!.dispose();
      }
      setState(() {
        _view = view;
        _edited = preserveEdits;
        _observationUnavailable = false;
      });
      _refresh?.cancel();
      _refresh = null;
      if (_supportsExecution && view['execution'] != null) {
        final remote = view['host_connection']?['target'] == 'vps';
        _refresh = Timer.periodic(
          Duration(seconds: remote ? 60 : 15),
          (_) => _refreshVisibleStatus(),
        );
      }
    } catch (error) {
      if (!mounted || generation != _presentationGeneration) return;
      setState(() {
        _error = _describeError(error);
        if (action == 'open' || error is! FormatException) {
          _observationUnavailable = true;
        }
      });
    } finally {
      if (mounted && generation == _presentationGeneration) {
        setState(() {
          _busy = false;
          _choosing = false;
        });
      }
    }
  }

  Future<void> _stopExecution({bool revoke = false}) async {
    // Both revocation intents supersede stale reads and share one host path.
    final generation = ++_presentationGeneration;
    setState(() => _busy = true);
    try {
      final stopped = await widget.configureExecution!(
        enabled: false,
        expiresAtMs: null,
        revoke: revoke,
        settings: const {},
      );
      if (mounted && generation == _presentationGeneration) {
        setState(() {
          _view = stopped;
          _error = null;
          _observationUnavailable = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _presentationGeneration) {
        setState(() {
          _error = _describeError(error);
          _observationUnavailable = true;
        });
      }
    } finally {
      if (mounted && generation == _presentationGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  String _describeError(Object error) => switch (error) {
    SocketException() || TimeoutException() =>
      'Connection unavailable. Check your network and server availability, then retry. '
          'An unreachable executor may still be running.',
    FormatException() => 'Check the entered settings: ${error.message}',
    _ => error.toString(),
  };

  Future<void> _connectVps({
    bool reinstall = false,
    bool restoreAccess = false,
  }) async {
    if (_busy || _choosing || widget.connectVps == null) return;
    var host = _view?['host_connection']?['host']?.toString() ?? '';
    var port = _view?['host_connection']?['port']?.toString() ?? '22';
    var password = '';
    var connected = false;
    var returnedOnline = false;
    if (!reinstall &&
        !restoreAccess &&
        _view?['host_connection']?['installed'] == true) {
      setState(() => _busy = true);
      try {
        await widget.connectVps!(
          host: host,
          port: int.parse(port),
          password: '',
          trustPeer: (_) async => false,
        );
        connected = true;
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _error =
                    'Saved VPS connection was not acknowledged. Check server availability; no trading Start was granted.',
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (mounted && connected) await _run('open');
      return;
    }
    setState(() => _choosing = true);
    try {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder:
                (context) => StatefulBuilder(
                  builder:
                      (context, update) => AlertDialog(
                        scrollable: true,
                        insetPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        title: Text(
                          reinstall
                              ? 'Update VPS runtime'
                              : restoreAccess
                              ? 'Restore VPS access'
                              : 'Connect your VPS',
                        ),
                        content: SizedBox(
                          width: 420,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                reinstall
                                    ? 'End VPS trading authority and install the runtime bundled with this Capsule. Existing exchange orders and plugin state are retained. Website and VPN are not changed. Root password is never saved. Resume trading only after a separate Start confirmation.'
                                    : restoreAccess
                                    ? 'Use the root password for this same VPS to restore access. This reinstalls the bundled workspace runner after checking the server identity and Capsule binding. Existing exchange orders are not cancelled; unexpired trading permissions may resume. Website and VPN are not changed. Root password is never saved; no new trading permission is granted.'
                                    : 'Linux x86-64 with systemd. One managed installation; website and VPN are not changed. To restore an existing connection, enter the original VPS address. Root password is used only for installation, never saved. No new trading permission is granted; existing unexpired permissions may resume.',
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: host,
                                readOnly: reinstall || restoreAccess,
                                decoration: const InputDecoration(
                                  labelText: 'VPS IP or hostname',
                                ),
                                autocorrect: false,
                                onChanged: (s) => update(() => host = s.trim()),
                              ),
                              TextFormField(
                                initialValue: port,
                                readOnly: reinstall || restoreAccess,
                                decoration: const InputDecoration(
                                  labelText: 'SSH port',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (s) => update(() => port = s.trim()),
                              ),
                              TextField(
                                obscureText: true,
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Root password (installation only)',
                                ),
                                onChanged: (s) => update(() => password = s),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed:
                                host.isEmpty ||
                                        password.isEmpty ||
                                        int.tryParse(port) == null
                                    ? null
                                    : () => Navigator.pop(context, true),
                            child: Text(
                              reinstall
                                  ? 'Update securely'
                                  : restoreAccess
                                  ? 'Restore securely'
                                  : 'Connect securely',
                            ),
                          ),
                        ],
                      ),
                ),
          ) ??
          false;
      if (!accepted || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      if (reinstall) {
        final returnOnline = widget.useOnline;
        if (returnOnline == null) {
          throw StateError(
            'VPS authority must end before updating its runtime',
          );
        }
        await returnOnline();
        returnedOnline = true;
        if (!mounted) return;
      }
      await widget.connectVps!(
        host: host,
        port: int.parse(port),
        password: password,
        trustPeer: (fingerprint) async {
          if (!mounted) return false;
          return await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Confirm server identity'),
                      content: SelectableText(
                        '$host:$port\n$fingerprint\n\nCompare this fingerprint with your VPS provider or a trusted SSH connection. A different fingerprint will be refused on future connections.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Trust this server'),
                        ),
                      ],
                    ),
              ) ??
              false;
        },
      );
      connected = true;
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'VPS connection was not completed. Check installer availability, login and server identity. No trading Start was granted.',
        );
      }
    } finally {
      password = '';
      if (mounted) {
        setState(() {
          _busy = false;
          _choosing = false;
        });
      }
    }
    if (mounted && (connected || returnedOnline)) {
      final connectionError = _error;
      await _run('open');
      if (mounted && connectionError != null) {
        setState(() => _error = connectionError);
      }
    }
  }

  Future<void> _useOnline() async {
    if (_busy || _choosing || widget.useOnline == null) return;
    final remote = _view?['execution']?['mode'] == 'vps';
    if (remote) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Return trading control to this app?'),
                  content: const Text(
                    'End all VPS trading authority and retrieve its latest workspace and order journal. This does not cancel exchange orders or close positions. Local cycles require a new Start; the app must remain open.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Return to online'),
                    ),
                  ],
                ),
          ) ??
          false;
      if (!accepted || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.useOnline!();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'VPS return was not acknowledged. Control remains assigned there; there is no local fallback.',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _run('open');
  }

  Future<Map<String, String>?> _accountCredentials() async {
    var key = '';
    var secret = '';
    return showDialog<Map<String, String>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  scrollable: true,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  title: const Text('Connect BingX account'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          key: const ValueKey('plugin-account-api-key'),
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'API key',
                          ),
                          onChanged: (s) => update(() => key = s.trim()),
                        ),
                        TextField(
                          key: const ValueKey('plugin-account-secret-key'),
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Secret key',
                          ),
                          onChanged: (s) => update(() => secret = s.trim()),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Read-only account check. Keys are stored securely for this Capsule. Trading needs separate confirmation.',
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          key.isEmpty || secret.isEmpty
                              ? null
                              : () => Navigator.of(
                                context,
                              ).pop({'api_key': key, 'secret_key': secret}),
                      child: const Text('Connect and save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _field(Map raw) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: ValueKey('plugin-field-${raw['id']}'),
      controller: _fields[raw['id']],
      enabled:
          !_busy &&
          !_choosing &&
          _view?['execution']?['allow_new_entries'] != true,
      readOnly: raw['type'] == 'choice',
      onTap: raw['type'] == 'choice' ? () => _choose(raw) : null,
      onChanged: (_) => setState(() => _edited = true),
      keyboardType:
          raw['type'] == 'text'
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: raw['label'] as String,
        border: const OutlineInputBorder(),
        suffixIcon:
            raw['type'] == 'choice' ? const Icon(Icons.arrow_drop_down) : null,
      ),
    ),
  );

  Future<void> _choose(Map field) async {
    if (_busy || _choosing) return;
    final id = field['id'] as String;
    Future<List<String>> load() => Future.sync(() {
      final read = widget.readFieldOptions;
      if (read == null) throw StateError('Instrument selection is unavailable');
      return read(id);
    });
    Future<List<String>>? options;
    var query = '';
    setState(() => _choosing = true);
    try {
      final selected = await showDialog<String>(
        context: context,
        builder:
            (context) => StatefulBuilder(
              builder:
                  (context, update) => AlertDialog(
                    title: Text('Choose ${field['label']}'),
                    content: SizedBox(
                      width: 420,
                      height: 400,
                      child: Column(
                        children: [
                          TextField(
                            key: const ValueKey('plugin-choice-search'),
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Search instruments',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged:
                                (text) => update(
                                  () => query = text.trim().toUpperCase(),
                                ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: FutureBuilder<List<String>>(
                              future: options ??= load(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState !=
                                    ConnectionState.done) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return ListView(
                                    children: [
                                      Text(
                                        'Could not load instruments: ${snapshot.error}',
                                      ),
                                      TextButton(
                                        onPressed:
                                            () => update(() {
                                              options = null;
                                            }),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  );
                                }
                                final matches =
                                    (snapshot.data ?? const <String>[])
                                        .where(
                                          (s) =>
                                              s.toUpperCase().contains(query),
                                        )
                                        .toList();
                                if (matches.isEmpty) {
                                  return const Center(
                                    child: Text('No matching instruments'),
                                  );
                                }
                                return ListView.builder(
                                  itemCount: matches.length,
                                  itemBuilder:
                                      (context, index) => ListTile(
                                        title: Text(matches[index]),
                                        selected:
                                            matches[index] == _fields[id]!.text,
                                        onTap:
                                            () => Navigator.of(
                                              context,
                                            ).pop(matches[index]),
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
            ),
      );
      if (mounted && selected != null && selected != _fields[id]!.text) {
        setState(() {
          _fields[id]!.text = selected;
          _edited = true;
          _error = null;
        });
      }
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final health =
        _observationUnavailable || _error != null
            ? 'observation unavailable'
            : switch (view?['host_connection']?['health']) {
              'not_started' => 'connected; press Start to begin',
              'running' => 'runner is running',
              'detached' => 'trading authority ended',
              _ => 'checking runner',
            };
    return Scaffold(
      appBar: AppBar(title: Text(view?['title']?.toString() ?? 'Plugin')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if ((view != null || (_error != null && !_busy)) &&
                _supportsExecution &&
                widget.connectVps != null) ...[
              Text(
                view == null
                    ? 'Execution status unavailable. Connect your VPS to restore access.'
                    : _view?['host_connection']?['target'] == 'vps'
                    ? 'VPS ${_view?["host_connection"]?["host"] ?? ""}: $health'
                    : 'Local execution: keep this app open for scheduled cycles.',
              ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _busy || _choosing ? null : _connectVps,
                    child: const Text('Connect VPS'),
                  ),
                  if (view?['host_connection']?['installed'] == true)
                    TextButton(
                      onPressed:
                          _busy || _choosing
                              ? null
                              : () => _connectVps(restoreAccess: true),
                      child: const Text('Restore VPS access'),
                    ),
                  if (view != null)
                    TextButton(
                      onPressed:
                          _busy || _choosing || widget.useOnline == null
                              ? null
                              : _useOnline,
                      child: const Text('Use local execution'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if ((view == null || _observationUnavailable) && !_busy)
              OutlinedButton(
                onPressed: _choosing ? null : () => _run('open'),
                child: Text(
                  view == null ? 'Retry opening plugin' : 'Retry connection',
                ),
              ),
            if (view != null) ...[
              if (_observationUnavailable)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Last received data; current status is unavailable. '
                    'Connection loss does not stop remote execution.',
                  ),
                ),
              if (!_observationUnavailable &&
                  _supportsExecution &&
                  view['execution'] is Map)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${view["execution"]["allow_new_entries"] == true ? (view["execution"]["mode"] == "vps" ? "VPS entries enabled" : "Local entries enabled") : "New entries stopped or expired"}. '
                    '${view["execution"]["revoked"] == true
                        ? "Automation authorization fully revoked."
                        : view["execution"]["expires_at_ms"] == null
                        ? "Authorized until full revocation."
                        : "Until ${DateTime.fromMillisecondsSinceEpoch(view["execution"]["expires_at_ms"]).toLocal()}."} '
                    '${view["execution"]["last_checked_at_ms"] == null ? "No cycle observed in this process yet." : "Last successful cycle: ${DateTime.fromMillisecondsSinceEpoch(view["execution"]["last_checked_at_ms"]).toLocal()}"}'
                    '${view["execution"]["last_error"] == null ? "" : "\n${view["execution"]["last_error"]}"}',
                  ),
                ),
              if (_supportsExecution &&
                  widget.configureExecution != null &&
                  view['execution'] is Map &&
                  view['execution']['active'] == true)
                OutlinedButton(
                  onPressed:
                      _choosing ? null : () => _stopExecution(revoke: true),
                  child: const Text('Revoke all automation'),
                ),
              if (view['summary'] is String &&
                  (view['summary'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(view['summary'] as String),
                ),
              for (final raw in view['fields'] as List)
                if ((raw as Map)['advanced'] != true) _field(raw),
              if ((view['fields'] as List).any(
                    (raw) => (raw as Map)['advanced'] == true,
                  ) ||
                  (_supportsExecution &&
                      widget.connectVps != null &&
                      widget.useOnline != null &&
                      view['host_connection']?['installed'] == true))
                ExpansionTile(
                  title: const Text('Advanced settings'),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    for (final raw in view['fields'] as List)
                      if ((raw as Map)['advanced'] == true) _field(raw),
                    if (_supportsExecution &&
                        widget.connectVps != null &&
                        widget.useOnline != null &&
                        view['host_connection']?['installed'] == true)
                      TextButton(
                        onPressed:
                            _busy || _choosing
                                ? null
                                : () => _connectVps(reinstall: true),
                        child: const Text('Update VPS runtime'),
                      ),
                  ],
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final raw in view['actions'] as List)
                    if (_supportsExecution ||
                        !const {
                          'workspace.start',
                          'workspace.stop',
                        }.contains((raw as Map)['host']))
                      FilledButton(
                        key: ValueKey('plugin-action-${(raw as Map)['id']}'),
                        onPressed:
                            raw['host'] == 'workspace.stop'
                                ? () => _run(raw['id'] as String)
                                : _busy ||
                                    _choosing ||
                                    (_observationUnavailable &&
                                        const {
                                          'workspace.start',
                                          'bingx.order.submit',
                                        }.contains(raw['host'])) ||
                                    (_edited &&
                                        raw['host'] == 'bingx.order.submit')
                                ? null
                                : () => _run(raw['id'] as String),
                        child: Text(raw['label'] as String),
                      ),
                ],
              ),
              const SizedBox(height: 20),
              SelectableText(
                _busy
                    ? 'Working... Complete any system permission prompt to continue.'
                    : _edited
                    ? 'Settings or inputs changed. Run an action to refresh the results.'
                    : view['message'] as String,
              ),
              const SizedBox(height: 16),
              if (!_edited &&
                  !_observationUnavailable &&
                  ((view['rows'] as List).isNotEmpty ||
                      (view['details'] as String).isNotEmpty))
                ExpansionTile(
                  key: const ValueKey('plugin-calculation-details'),
                  title: Text(
                    view['details_title'] as String? ?? 'Calculation details',
                  ),
                  children: [
                    if ((view['rows'] as List).isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final column in view['columns'] as List)
                              DataColumn(label: Text(column as String)),
                          ],
                          rows: [
                            for (final row in view['rows'] as List)
                              DataRow(
                                cells: [
                                  for (final cell in row as List)
                                    DataCell(SelectableText(cell as String)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    if ((view['details'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          view['details'] as String,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
