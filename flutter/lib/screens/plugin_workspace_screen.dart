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
  final Future<List<Map<String, String>>> Function(
    List<Map<String, String>> secrets,
  )?
  saveSecrets;
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
    this.saveSecrets,
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
  bool _actionResultVisible = false;
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
        _view?['execution']?['running'] == true &&
        !_actionResultVisible &&
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

  bool get _remoteSelected =>
      _view?['host_connection']?['target'] == 'vps' ||
      _view?['host_connection']?['selected'] == true;

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
        !_remoteSelected &&
        const {'workspace.start'}.contains(hostAction)) {
      return;
    }
    final generation = ++_presentationGeneration;
    final preserveEdits = action == 'open' && _edited;
    if (hostAction == 'workspace.authorize' &&
        !_hasAccess(Map<String, dynamic>.from(_view!['access'] as Map))) {
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
      _actionResultVisible = action != 'open' && hostAction == null;
      if (action != 'open') _edited = true;
    });
    try {
      final settings = action == 'open' ? <String, dynamic>{} : _settings();
      final remoteStart = hostAction == 'workspace.start' && _remoteSelected;
      // The new server process invokes the package Start after installation.
      // Never send selected settings to the previous runner before replacement.
      var view =
          remoteStart
              ? _view!
              : await widget.runWorkspaceAction(action, settings);
      if (!mounted || generation != _presentationGeneration) return;
      if (hostAction == 'workspace.start') {
        final configure = widget.configureExecution;
        if (configure == null || view['schedule'] is! Map) {
          throw StateError('Scheduled execution is not available in this host');
        }
        final scope = Map<String, dynamic>.from(view['schedule'] as Map);
        if (remoteStart) scope['start_action'] = action;
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
      if (_supportsExecution &&
          view['execution']?['running'] == true &&
          !_actionResultVisible) {
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
    setState(() {
      _busy = true;
      _actionResultVisible = false;
    });
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
          setState(() {
            _error =
                'Saved VPS connection was not acknowledged. Check server availability; no execution Start was granted.';
            _actionResultVisible = true;
          });
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
        setState(() {
          _error =
              'VPS connection was not completed. Check installer availability, login and server identity. No execution Start was granted.';
          _actionResultVisible = true;
        });
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
    final remote = _view == null || _view?['execution']?['mode'] == 'vps';
    if (remote) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Return execution control to this app?'),
                  content: const Text(
                    'Retrieve this workspace after ending its VPS authority. If another device already replaced it, recover its ended handoff without changing the new runner. Previously accepted external effects remain. Local cycles require a new Start; the app must remain open.',
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
    const newSecret = '=new=';
    final names = <String, Map<String, String>>{
      for (final entry in declarations.entries)
        entry.key as String: {
          for (final field in entry.value as List)
            field['id'] as String: field['label'] as String,
        },
    };
    final values = <String, Map<String, String>>{
      for (final entry in declarations.entries)
        entry.key as String: {
          for (final field in entry.value as List) field['id'] as String: '',
        },
    };
    String? permissionIssue() {
      for (final entry in declarations.entries) {
        for (final field in entry.value as List) {
          final alias = entry.key as String;
          final id = field['id'] as String;
          final label = field['label'] as String;
          if (selected[alias]?[id] == null) {
            return 'Choose a saved secret or Add new secret for $label.';
          }
          if (selected[alias]?[id] != newSecret) continue;
          final name = names[alias]![id]!.trim();
          final value = values[alias]![id]!.trim();
          if (name.isEmpty) return 'Enter a secret name for $label.';
          if (name.length > 128) {
            return 'Use a secret name of at most 128 characters for $label.';
          }
          if (value.isEmpty) return 'Enter the secret value for $label.';
          if (value.length > 4096) {
            return 'The secret value for $label exceeds 4096 characters.';
          }
        }
      }
      if (!untilRevoked) {
        final duration = double.tryParse(hours);
        if (duration == null ||
            !duration.isFinite ||
            duration <= 0 ||
            duration > 1000000) {
          return 'Enter a duration above 0 and at most 1000000 hours. Use a decimal point for part of an hour.';
        }
      }
      return null;
    }

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
                              for (final field in entry.value as List) ...[
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
                                    if (widget.saveSecrets != null)
                                      const DropdownMenuItem(
                                        value: newSecret,
                                        child: Text('Add new secret…'),
                                      ),
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
                                if (selected[entry.key]![field['id']] ==
                                    newSecret) ...[
                                  TextFormField(
                                    key: ValueKey(
                                      'plugin-secret-name-${entry.key}-${field['id']}',
                                    ),
                                    initialValue:
                                        names[entry.key]![field['id']],
                                    decoration: const InputDecoration(
                                      labelText: 'Secret name',
                                    ),
                                    onChanged:
                                        (value) => update(() {
                                          names[entry.key]![field['id']
                                                  as String] =
                                              value;
                                        }),
                                  ),
                                  TextFormField(
                                    key: ValueKey(
                                      'plugin-secret-value-${entry.key}-${field['id']}',
                                    ),
                                    initialValue:
                                        values[entry.key]![field['id']],
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      labelText: '${field['label']} value',
                                      helperText:
                                          'Never enter your device password here.',
                                    ),
                                    onChanged:
                                        (value) => update(() {
                                          values[entry.key]![field['id']
                                                  as String] =
                                              value;
                                        }),
                                  ),
                                ],
                              ],
                            if (declarations.isNotEmpty && references.isEmpty)
                              Text(
                                widget.saveSecrets == null
                                    ? 'Connect secrets to this Capsule in Keychain first.'
                                    : 'Choose Add new secret to save a connection in secure storage.',
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
                            if (permissionIssue() case final issue?) ...[
                              const SizedBox(height: 12),
                              Text(
                                issue,
                                key: const ValueKey('plugin-permission-issue'),
                              ),
                            ],
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
                              permissionIssue() != null
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
    final additions = <Map<String, String>>[];
    final targets = <(String, String)>[];
    for (final entry in declarations.entries) {
      for (final field in entry.value as List) {
        if (selected[entry.key]![field['id']] != newSecret) continue;
        final alias = entry.key as String;
        final id = field['id'] as String;
        targets.add((alias, id));
        additions.add({
          'label': names[alias]![id]!.trim(),
          'value': values[alias]![id]!.trim(),
        });
      }
    }
    if (additions.isNotEmpty) {
      final saved = await widget.saveSecrets!(additions);
      if (!mounted) return false;
      if (saved.length != targets.length ||
          saved.any((r) => r['id']?.isNotEmpty != true)) {
        throw StateError('Secret connection was not saved');
      }
      for (var i = 0; i < targets.length; i++) {
        selected[targets[i].$1]![targets[i].$2] = saved[i]['id']!;
      }
    }
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
      enabled: !_busy && !_choosing,
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
      final rawAccess = field['source']?['access'];
      final access =
          rawAccess is Map ? Map<String, dynamic>.from(rawAccess) : null;
      if (access != null && !_hasAccess(access)) {
        final granted = await _authorize(
          access,
          scope: {
            'version': 2,
            'access': access,
            'description': 'Load ${field['label']} choices',
          },
        );
        if (!granted || !mounted) return;
      }
      if (!mounted) return;
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final execution = view?['execution'];
    final message =
        _busy
            ? 'Working... Complete any system permission prompt to continue.'
            : view?['message'] as String? ?? '';
    final messageLines = message.split('\n');
    final actions =
        (view?['actions'] as List? ?? const [])
            .cast<Map>()
            .where(
              (a) =>
                  _supportsExecution ||
                  !const {
                    'workspace.start',
                    'workspace.stop',
                  }.contains(a['host']),
            )
            .toList();
    final fields = (view?['fields'] as List? ?? const []).cast<Map>();
    final primaryFields = fields.where((f) => f['advanced'] != true).toList();
    final hasAdvanced =
        fields.any((f) => f['advanced'] == true) ||
        (_supportsExecution &&
            widget.connectVps != null &&
            widget.useOnline != null &&
            view?['host_connection']?['installed'] == true);
    final health = switch (view?['host_connection']?['health']) {
      'not_started' => 'Execution has not moved to this VPS',
      'setup_unconfirmed' => 'Setup not confirmed',
      'running' => 'Runner is running',
      'detached' => 'Execution authority ended',
      _ => 'Checking connection',
    };

    Widget panel(String title, List<Widget> children, {IconData? icon}) => Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: colors.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );

    Widget actionButton(Map action, bool primary) {
      final VoidCallback? onPressed =
          action['host'] == 'workspace.stop'
              ? () => _run(action['id'] as String)
              : _busy ||
                  _choosing ||
                  (_observationUnavailable &&
                      !_remoteSelected &&
                      action['host'] == 'workspace.start')
              ? null
              : () => _run(action['id'] as String);
      final key = ValueKey('plugin-action-${action['id']}');
      final label = Text(
        action['label'] as String,
        textAlign: TextAlign.center,
      );
      return primary
          ? FilledButton(
            key: key,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            child: label,
          )
          : OutlinedButton(
            key: key,
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: label,
          );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(view?['title']?.toString() ?? 'Plugin'),
        centerTitle: false,
        toolbarHeight: 72,
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.surface, colors.surfaceContainerLowest],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  if ((view == null || _observationUnavailable) && !_busy)
                    OutlinedButton(
                      onPressed: _choosing ? null : () => _run('open'),
                      child: Text(
                        view == null
                            ? 'Retry opening plugin'
                            : 'Retry connection',
                      ),
                    ),
                  if (view == null &&
                      _error != null &&
                      !_busy &&
                      _supportsExecution &&
                      widget.connectVps != null)
                    OutlinedButton(
                      onPressed: _choosing ? null : _connectVps,
                      child: const Text('Connect VPS'),
                    ),
                  if (view == null &&
                      _error != null &&
                      !_busy &&
                      _supportsExecution &&
                      widget.useOnline != null)
                    TextButton(
                      onPressed: _choosing ? null : _useOnline,
                      child: const Text('Recover local access'),
                    ),
                  if (view != null) ...[
                    panel('Current status', [
                      if (_edited) ...[
                        Text(
                          'Changes not applied. The observation below uses the previous settings.',
                          style: TextStyle(color: colors.primary),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_supportsExecution &&
                          view['host_connection'] is Map) ...[
                        Text(
                          switch (view['host_connection']['target']) {
                            'vps' =>
                              'VPS execution · ${view['host_connection']['host'] ?? health}',
                            'local' => 'On this device · keep the app open',
                            _ => 'Execution target unavailable',
                          },
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_observationUnavailable) ...[
                        Text(
                          'Last received data; current status is unavailable. Connection loss does not stop remote execution.',
                          style: TextStyle(color: colors.error),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (view['summary'] is String &&
                          (view['summary'] as String).isNotEmpty) ...[
                        SelectableText(
                          view['summary'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      SelectableText(
                        messageLines.first,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      if (messageLines.length > 1) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          messageLines.skip(1).join('\n'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                        ),
                      ],
                      if (actions.isNotEmpty) ...[
                        if (_remoteSelected &&
                            actions.any(
                              (a) => a['host'] == 'workspace.start',
                            )) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Start replaces the VPS runner with this package and the selected settings. Already accepted service actions remain in effect.',
                          ),
                        ],
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var i = 0; i < actions.length; i++)
                              actionButton(actions[i], i == 0),
                          ],
                        ),
                      ],
                    ], icon: Icons.insights_outlined),
                    if (primaryFields.isNotEmpty || hasAdvanced)
                      panel('Configuration', [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns =
                                constraints.maxWidth >= 840
                                    ? 3
                                    : constraints.maxWidth >= 560
                                    ? 2
                                    : 1;
                            final width =
                                (constraints.maxWidth - (columns - 1) * 16) /
                                columns;
                            return Wrap(
                              spacing: 16,
                              children: [
                                for (final field in primaryFields)
                                  SizedBox(width: width, child: _field(field)),
                              ],
                            );
                          },
                        ),
                        if (hasAdvanced)
                          ExpansionTile(
                            title: const Text('Advanced settings'),
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(top: 8),
                            children: [
                              for (final field in fields)
                                if (field['advanced'] == true) _field(field),
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
                      ], icon: Icons.tune_outlined),
                    if ((view['access'] is Map &&
                            widget.configureExecution != null) ||
                        (_supportsExecution &&
                            (widget.connectVps != null || execution is Map)))
                      panel('Access and execution', [
                        if (_supportsExecution &&
                            widget.connectVps != null) ...[
                          Text(
                            view['host_connection']?['target'] == 'vps'
                                ? 'VPS ${view['host_connection']?['host'] ?? ''} · $health'
                                : 'Local execution · keep this app open for scheduled cycles.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (view['host_connection']?['target'] != 'vps' &&
                              view['host_connection']?['host'] != null)
                            Text(
                              '${view['host_connection']['selected'] == true ? 'Selected' : 'Saved'} VPS ${view['host_connection']['host']} · $health. This session is on this device.',
                              style: theme.textTheme.bodySmall,
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed:
                                    _busy || _choosing ? null : _connectVps,
                                child: const Text('Connect VPS'),
                              ),
                              if (view['host_connection']?['installed'] == true)
                                TextButton(
                                  onPressed:
                                      _busy || _choosing
                                          ? null
                                          : () =>
                                              _connectVps(restoreAccess: true),
                                  child: const Text('Restore VPS access'),
                                ),
                              TextButton(
                                onPressed:
                                    _busy ||
                                            _choosing ||
                                            widget.useOnline == null
                                        ? null
                                        : _useOnline,
                                child: const Text('Use local execution'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_observationUnavailable &&
                            _supportsExecution &&
                            execution is Map) ...[
                          Text(
                            '${execution['revoked'] == true
                                ? 'Permissions revoked'
                                : execution['active'] == true
                                ? 'Permissions active'
                                : execution['active'] == false
                                ? 'Permissions inactive'
                                : 'Permission status unavailable'}. '
                            '${execution['running'] == true
                                ? 'Scheduled workflow running.'
                                : execution['running'] == false
                                ? 'Scheduled workflow not running.'
                                : 'Workflow status unavailable.'}'
                            '${execution['active'] != true
                                ? ''
                                : execution['expires_at_ms'] == null
                                ? ' Until you revoke access.'
                                : ' Until ${DateTime.fromMillisecondsSinceEpoch(execution['expires_at_ms'] as int).toLocal()}.'}'
                            '${execution['last_checked_at_ms'] == null ? '' : '\nLast completed cycle: ${DateTime.fromMillisecondsSinceEpoch(execution['last_checked_at_ms'] as int).toLocal()}'}'
                            '${execution['last_error'] == null ? '' : '\n${execution['last_error']}'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          if (execution['last_result'] is String &&
                              (execution['last_result'] as String)
                                  .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Last cycle result',
                              style: theme.textTheme.labelLarge,
                            ),
                            SelectableText(execution['last_result'] as String),
                          ],
                          const SizedBox(height: 12),
                        ],
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (view['access'] is Map &&
                                widget.configureExecution != null)
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
                                            if (mounted) {
                                              setState(() => _error = '$error');
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _choosing = false);
                                            }
                                          }
                                        },
                                child: const Text('Plugin permissions'),
                              ),
                            if (widget.configureExecution != null &&
                                execution is Map &&
                                execution['active'] == true)
                              OutlinedButton(
                                onPressed:
                                    _choosing
                                        ? null
                                        : () => _stopExecution(revoke: true),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.error,
                                ),
                                child: const Text('Revoke plugin permissions'),
                              ),
                          ],
                        ),
                      ], icon: Icons.shield_outlined),
                    if (!_edited &&
                        !_observationUnavailable &&
                        ((view['rows'] as List).isNotEmpty ||
                            (view['details'] as String).isNotEmpty))
                      Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: colors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: colors.outlineVariant.withValues(alpha: .45),
                          ),
                        ),
                        child: ExpansionTile(
                          key: const ValueKey('plugin-calculation-details'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          title: Text(
                            view['details_title'] as String? ??
                                'Calculation details',
                          ),
                          children: [
                            if ((view['rows'] as List).isNotEmpty)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: [
                                    for (final column
                                        in view['columns'] as List)
                                      DataColumn(label: Text(column as String)),
                                  ],
                                  rows: [
                                    for (final row in view['rows'] as List)
                                      DataRow(
                                        cells: [
                                          for (final cell in row as List)
                                            DataCell(
                                              SelectableText(cell as String),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            if ((view['details'] as String).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: SelectableText(
                                  view['details'] as String,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
