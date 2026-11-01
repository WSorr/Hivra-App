import 'dart:async';
import 'dart:io';
import '../services/plugin_capability_dispatcher.dart';

import 'package:flutter/material.dart';

typedef PluginWorkspaceAction =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> settings,
    );

/// Displays bounded package-owned fields, actions and evidence. This shell
/// does not know which product or strategy produced them.
class PluginWorkspaceScreen extends StatefulWidget {
  final List<String> capabilities;
  final PluginWorkspaceAction runWorkspaceAction;
  final Future<List<Map<String, String>>> Function()? listSecrets;
  final Future<Map<String, dynamic>> Function({
    required bool enabled,
    required int? expiresAtMs,
    int? expectedRevision,
    bool revoke,
    Map<String, dynamic>? approvedScope,
    Map<String, Map<String, String>>? credentialBindings,
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
    this.listSecrets,
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

  Map<String, dynamic> _settings() => {
    for (final raw in _view?['fields'] as List? ?? const [])
      raw['id'] as String: switch (raw['type']) {
        'integer' => int.parse(_fields[raw['id']]!.text.trim()),
        'number' => double.parse(_fields[raw['id']]!.text.trim()),
        _ => _fields[raw['id']]!.text.trim(),
      },
  };

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
        const {'workspace.start'}.contains(hostAction)) {
      return;
    }
    final generation = ++_presentationGeneration;
    final preserveEdits = action == 'open' && _edited;
    if (hostAction == 'workspace.authorize') {
      setState(() => _choosing = true);
      try {
        final granted = await _authorize(
          Map<String, dynamic>.from(_view!['access'] as Map),
          settings: _settings(),
        );
        if (!granted) return;
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
        return;
      } finally {
        if (mounted) setState(() => _choosing = false);
      }
      if (!mounted || generation != _presentationGeneration) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (action != 'open') _edited = true;
    });
    try {
      final settings = action == 'open' ? <String, dynamic>{} : _settings();
      var view = await widget.runWorkspaceAction(action, settings);
      if (!mounted || generation != _presentationGeneration) return;
      if (hostAction == 'workspace.start') {
        final configure = widget.configureExecution;
        if (configure == null || view['schedule'] is! Map) {
          throw StateError('Scheduled execution is not available in this host');
        }
        final scope = Map<String, dynamic>.from(view['schedule'] as Map);
        final access = Map<String, dynamic>.from(scope['access'] as Map);
        if (!_hasAccess(access)) {
          setState(() {
            _choosing = true;
            _busy = false;
          });
          final granted = await _authorize(
            access,
            scope: scope,
            settings: settings,
          );
          if (!mounted || generation != _presentationGeneration) return;
          setState(() {
            _choosing = false;
            _busy = true;
          });
          if (!granted) return;
          view = await widget.runWorkspaceAction('open', const {});
        } else {
          view = await configure(
            enabled: true,
            expiresAtMs: _view!['execution']['expires_at_ms'] as int?,
            expectedRevision: _view!['execution']['revision'] as int?,
            approvedScope: {...scope, 'access': _view!['execution']['access']},
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

  Future<void> _stopExecution({bool revoke = true}) async {
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
                    'Saved VPS connection was not acknowledged. Check server availability; no execution Start was granted.',
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
                                    ? 'End VPS execution authority and install the runtime bundled with this Capsule. Package state and already accepted external effects are retained. Website and VPN are not changed. Root password is never saved. Resume execution only after a separate Start confirmation.'
                                    : restoreAccess
                                    ? 'Use the root password for this same VPS to restore access. This reinstalls the bundled workspace runner after checking the server identity and Capsule binding. Accepted external effects are not undone; unexpired execution permissions may resume. Website and VPN are not changed. Root password is never saved; no new execution permission is granted.'
                                    : 'Linux x86-64 with systemd. One managed installation; website and VPN are not changed. To restore an existing connection, enter the original VPS address. Root password is used only for installation, never saved. No new execution permission is granted; existing unexpired permissions may resume.',
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
                  'VPS connection was not completed. Check installer availability, login and server identity. No execution Start was granted.',
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
                  title: const Text('Return execution control to this app?'),
                  content: const Text(
                    'End all VPS execution authority and retrieve its latest workspace checkpoint. This does not undo previously accepted external effects. Local cycles require a new Start; the app must remain open.',
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

  String _accessText(Map access) => [
    if (access['inference'] == true)
      'Allow inference using the owner-selected connection; package input is sent to that provider.',
    ...(access['network'] as List).map(
      (n) =>
          '${n['origin']}\n${(n['methods'] as List).join(', ')}${n['credential'] == null ? '' : ' / protected credentials'}',
    ),
  ].join('\n\n');

  bool _hasAccess(Map<String, dynamic> requested) {
    final execution = _view?['execution'];
    if (execution is! Map ||
        execution['active'] != true ||
        execution['enabled'] != true ||
        execution['access'] is! Map) {
      return false;
    }
    final granted = execution['access'] as Map;
    if (requested['inference'] == true && granted['inference'] != true) {
      return false;
    }
    for (final network in requested['network'] as List) {
      for (final method in network['methods'] as List) {
        if (!PluginCapabilityDispatcher.allows(granted, {
          'url': network['origin'],
          'method': method,
          'credential': network['credential'],
        })) {
          return false;
        }
      }
    }
    final selected = execution['credentials'] as Map? ?? const {};
    return (requested['credentials'] as Map? ?? const {}).entries.every(
      (e) =>
          (e.value as List).every((f) => selected[e.key]?[f['id']] is String),
    );
  }

  Future<bool> _authorize(
    Map<String, dynamic> access, {
    Map<String, dynamic>? scope,
    Map<String, dynamic> settings = const {},
  }) async {
    final configure = widget.configureExecution;
    if (configure == null) throw StateError('Owner permissions unavailable');
    final declarations = access['credentials'] as Map? ?? const {};
    final references =
        declarations.isEmpty
            ? <Map<String, String>>[]
            : await widget.listSecrets?.call() ?? <Map<String, String>>[];
    if (!mounted) return false;
    final selected = <String, Map<String, String>>{};
    final previous = _view?['execution']?['credentials'] as Map? ?? const {};
    for (final entry in declarations.entries) {
      selected[entry.key as String] = {};
      for (final field in entry.value as List) {
        final id = previous[entry.key]?[field['id']];
        if (references.any((r) => r['id'] == id)) {
          selected[entry.key]![field['id'] as String] = id as String;
        }
      }
    }
    var untilRevoked = _view?['execution']?['expires_at_ms'] == null;
    var hours = '24';
    final accepted =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => StatefulBuilder(
                builder:
                    (context, update) => AlertDialog(
                      scrollable: true,
                      title: const Text('Plugin permissions'),
                      content: SizedBox(
                        width: 460,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_accessText(access)),
                            for (final entry in declarations.entries)
                              for (final field in entry.value as List)
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'plugin-secret-${entry.key}-${field['id']}',
                                  ),
                                  initialValue:
                                      selected[entry.key]![field['id']],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: field['label'] as String,
                                  ),
                                  items: [
                                    for (final reference in references)
                                      DropdownMenuItem(
                                        value: reference['id'],
                                        child: Text(
                                          reference['label']!,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged:
                                      (value) => update(() {
                                        if (value != null) {
                                          selected[entry.key]![field['id']
                                                  as String] =
                                              value;
                                        }
                                      }),
                                ),
                            if (declarations.isNotEmpty && references.isEmpty)
                              const Text(
                                'Connect secrets to this Capsule in Keychain first.',
                              ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Until revoked'),
                              value: untilRevoked,
                              onChanged:
                                  (value) => update(() => untilRevoked = value),
                            ),
                            if (!untilRevoked)
                              TextFormField(
                                initialValue: hours,
                                decoration: const InputDecoration(
                                  labelText: 'Permission duration (hours)',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged:
                                    (value) => update(() => hours = value),
                              ),
                            const SizedBox(height: 12),
                            const Text(
                              'This permission covers the plugin workflow. The plugin handles service logic; the service owns its account state. Revocation blocks new requests and cannot undo accepted actions.',
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
                          key: const ValueKey('plugin-confirm-permissions'),
                          onPressed:
                              declarations.entries.any(
                                        (e) => (e.value as List).any(
                                          (f) =>
                                              selected[e.key]?[f['id']] == null,
                                        ),
                                      ) ||
                                      (!untilRevoked &&
                                          (double.tryParse(hours) == null ||
                                              !double.parse(hours).isFinite ||
                                              double.parse(hours) <= 0 ||
                                              double.parse(hours) > 1000000))
                                  ? null
                                  : () => Navigator.pop(context, true),
                          child: const Text('Allow'),
                        ),
                      ],
                    ),
              ),
        ) ??
        false;
    if (!accepted || !mounted) return false;
    final view = await configure(
      enabled: true,
      expiresAtMs:
          untilRevoked
              ? null
              : DateTime.now().millisecondsSinceEpoch +
                  (double.parse(hours) * 3600000).round(),
      expectedRevision: _view?['execution']?['revision'] as int?,
      approvedScope:
          scope ??
          {
            ...?_view?['execution']?['scope'] as Map?,
            'version': 2,
            'access': access,
            'description':
                _view?['execution']?['scope']?['description'] ??
                'Owner-granted plugin access',
          },
      credentialBindings: selected,
      settings: settings,
    );
    if (!mounted) return false;
    setState(() => _view = view);
    return true;
  }

  Widget _field(Map raw) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: ValueKey('plugin-field-${raw['id']}'),
      controller: _fields[raw['id']],
      enabled: !_busy && !_choosing && _view?['execution']?['running'] != true,
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
      final action = field['source']?['action'];
      if (action is! String) throw StateError('Choice source is unavailable');
      return widget
          .runWorkspaceAction(action, const {})
          .then((view) => List<String>.from(view['options'] as List));
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
                              labelText: 'Search',
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
                                        'Could not load choices: ${snapshot.error}',
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
                                    child: Text('No matching choices'),
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
              'detached' => 'execution authority ended',
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
                    '${view["execution"]["enabled"] == true ? (view["execution"]["mode"] == "vps" ? "VPS execution enabled" : "Local execution enabled") : "Execution stopped or expired"}. '
                    '${view["execution"]["revoked"] == true
                        ? "Automation authorization fully revoked."
                        : view["execution"]["expires_at_ms"] == null
                        ? "Authorized until full revocation."
                        : "Until ${DateTime.fromMillisecondsSinceEpoch(view["execution"]["expires_at_ms"]).toLocal()}."} '
                    '${view["execution"]["last_checked_at_ms"] == null ? "No cycle observed in this process yet." : "Last successful cycle: ${DateTime.fromMillisecondsSinceEpoch(view["execution"]["last_checked_at_ms"]).toLocal()}"}'
                    '${view["execution"]["last_error"] == null ? "" : "\n${view["execution"]["last_error"]}"}',
                  ),
                ),
              if (widget.configureExecution != null &&
                  view['execution'] is Map &&
                  view['execution']['active'] == true)
                OutlinedButton(
                  onPressed:
                      _choosing ? null : () => _stopExecution(revoke: true),
                  child: const Text('Revoke plugin permissions'),
                ),
              if (view['access'] is Map && widget.configureExecution != null)
                OutlinedButton(
                  onPressed:
                      _busy || _choosing
                          ? null
                          : () async {
                            setState(() => _choosing = true);
                            try {
                              await _authorize(
                                Map<String, dynamic>.from(
                                  view['access'] as Map,
                                ),
                              );
                            } catch (error) {
                              if (mounted) setState(() => _error = '$error');
                            } finally {
                              if (mounted) setState(() => _choosing = false);
                            }
                          },
                  child: const Text('Plugin permissions'),
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
                                        }.contains(raw['host']))
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
