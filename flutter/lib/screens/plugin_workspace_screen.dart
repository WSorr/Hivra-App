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
  final Future<Map<String, dynamic>> Function(
    String action,
    Map<String, dynamic> access,
    bool approved,
  )?
  loadLocalChoices;
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
    bool reinstall,
  })?
  connectVps;
  final Future<void> Function()? useOnline;

  const PluginWorkspaceScreen({
    super.key,
    this.capabilities = const [],
    required this.runWorkspaceAction,
    this.loadLocalChoices,
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
  static const _permissionDurationError =
      'Enter a duration above 0 and at most 1000000 hours. Use a decimal point for part of an hour.';
  final Map<String, TextEditingController> _fields = {};
  String _nextStartHours = '';
  Map<String, dynamic>? _view;
  String? _error;
  bool _busy = false;
  bool _refreshingStatus = false;
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
        !_choosing &&
        !_refreshingStatus) {
      _run('open', background: true);
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

  bool get _assignedToVps =>
      _view?['host_connection']?['target'] == 'vps' ||
      _view?['execution']?['mode'] == 'vps';

  String? get _startDestination {
    final connection = _view?['host_connection'];
    if (connection is! Map) return null;
    if (_remoteSelected) {
      return connection['host'] == null ? 'VPS' : 'VPS ${connection['host']}';
    }
    return connection['target'] == 'local' ? 'this device' : null;
  }

  String _displayTime(int milliseconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatShortDate(time)} '
        '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: true)}';
  }

  Future<void> _run(String action, {bool background = false}) async {
    final descriptor = (_view?['actions'] as List? ?? const []).where(
      (a) => (a as Map)['id'] == action,
    );
    final selectedAction = descriptor.singleOrNull;
    final hostAction = selectedAction?['host'];
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
    final previousView = _view;
    final previousError = _error;
    final generation =
        background ? _presentationGeneration : ++_presentationGeneration;
    bool canPresent() =>
        mounted &&
        generation == _presentationGeneration &&
        (!background ||
            (!_busy &&
                !_choosing &&
                identical(_view, previousView) &&
                _error == previousError));
    final submitSettings =
        action != 'open' && selectedAction?['settings'] != false;
    if (hostAction == 'workspace.authorize' &&
        !_hasAccess(Map<String, dynamic>.from(_view!['access'] as Map))) {
      setState(() => _choosing = true);
      try {
        final granted = await _authorize(
          Map<String, dynamic>.from(_view!['access'] as Map),
          settings: submitSettings ? _settings() : const {},
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
    if (background) {
      // A status read must not take input away from the owner.
      _refreshingStatus = true;
    } else {
      setState(() {
        _busy = true;
        _error = null;
        _actionResultVisible = action != 'open' && hostAction == null;
      });
    }
    try {
      final settings = submitSettings ? _settings() : <String, dynamic>{};
      final Map<String, dynamic> view;
      if (hostAction == 'workspace.start') {
        final configure = widget.configureExecution;
        final schedule = _view?['schedule'];
        if (configure == null || schedule is! Map) {
          throw StateError('Scheduled execution is not available in this host');
        }
        final scope = {
          ...schedule.cast<String, dynamic>(),
          'start_action': action,
        };
        final access = Map<String, dynamic>.from(scope['access'] as Map);
        final hours = _remoteSelected && _edited ? _nextStartHours.trim() : '';
        final duration = _permissionDurationMs(hours);
        if (hours.isNotEmpty && duration == null) {
          throw const FormatException(_permissionDurationError);
        }
        if (!_hasAccess(access)) {
          setState(() {
            _choosing = true;
            _busy = false;
          });
          final granted = await _authorize(
            access,
            scope: scope,
            settings: settings,
            initialDurationHours: hours,
          );
          if (!mounted || generation != _presentationGeneration) return;
          setState(() {
            _choosing = false;
            _busy = true;
          });
          if (!granted) return;
          view = _view!;
        } else {
          view = await configure(
            enabled: true,
            expiresAtMs:
                duration == null
                    ? _view!['execution']['expires_at_ms'] as int?
                    : DateTime.now().millisecondsSinceEpoch + duration,
            expectedRevision: _view!['execution']['revision'] as int?,
            approvedScope: {...scope, 'access': _view!['execution']['access']},
            settings: settings,
          );
        }
      } else {
        view = await widget.runWorkspaceAction(action, settings);
      }
      if (!canPresent()) return;
      final preserveEdits = !submitSettings && _edited;
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
        if (!preserveEdits) _nextStartHours = '';
        _observationUnavailable = _isSavedView(view);
        if (background) _error = null;
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
      if (!canPresent()) return;
      setState(() {
        _error = _describeError(error);
        if (action == 'open' ||
            (_remoteSelected && error is! FormatException)) {
          _observationUnavailable = true;
        }
      });
    } finally {
      if (background) {
        _refreshingStatus = false;
      } else if (canPresent()) {
        setState(() {
          _busy = false;
          _choosing = false;
        });
      }
    }
  }

  bool _isSavedView(Map view) {
    final connection = view['host_connection'];
    return const {
          'replaced',
          'unavailable',
          'package_updated',
        }.contains(connection?['health']) ||
        (connection?['target'] == 'vps' &&
            connection?['health'] == 'not_started');
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
          _observationUnavailable = _isSavedView(stopped);
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
    if (!reinstall &&
        !restoreAccess &&
        _view?['host_connection']?['saved'] == true) {
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
                                    ? 'Update the Hivra runtime bundled with this Capsule. The existing assignment, permissions and package data are retained; an active assignment may resume after the service restart. Website and VPN are not changed. Root password is never saved.'
                                    : restoreAccess
                                    ? 'Enter the correct VPS address, SSH port and root password. If execution is assigned to a VPS, a changed address must match its saved server fingerprint. A new assignment requires Start. Root password is never saved.'
                                    : 'Linux x86-64 with systemd. Connect prepares SSH access and installs a runtime only if none exists. It leaves the current assignment running. Start replaces the assignment with this package and your selected settings. Website and VPN are not changed. Root password is never saved.',
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: host,
                                readOnly: reinstall,
                                decoration: const InputDecoration(
                                  labelText: 'VPS IP or hostname',
                                ),
                                autocorrect: false,
                                onChanged: (s) => update(() => host = s.trim()),
                              ),
                              TextFormField(
                                initialValue: port,
                                readOnly: reinstall,
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
      await widget.connectVps!(
        host: host,
        port: int.parse(port),
        password: password,
        reinstall: reinstall,
        trustPeer: (fingerprint) async {
          if (!mounted) return false;
          return await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Confirm server identity'),
                      content: SelectableText(
                        '$host:$port\n$fingerprint\n\nCompare this fingerprint with your VPS provider or a trusted SSH connection before sending the root password. After successful root login, this becomes the saved server identity. If it changes again, ordinary access is blocked until you confirm the new identity during VPS recovery.',
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
    if (mounted && connected) {
      final connectionError = _error;
      await _run('open');
      if (mounted && connectionError != null) {
        setState(() => _error = connectionError);
      }
    }
  }

  Future<void> _useOnline() async {
    if (_busy || _choosing || widget.useOnline == null) return;
    final remote = _view == null || _assignedToVps;
    if (remote) {
      setState(() => _choosing = true);
      bool? accepted;
      try {
        accepted = await showDialog<bool>(
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
                    child: const Text('Return to this device'),
                  ),
                ],
              ),
        );
      } finally {
        if (mounted) setState(() => _choosing = false);
      }
      if (accepted != true || !mounted) return;
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

  int? _permissionDurationMs(String hours) {
    final duration = double.tryParse(hours);
    if (duration == null ||
        !duration.isFinite ||
        duration <= 0 ||
        duration > 1000000) {
      return null;
    }
    final milliseconds = (duration * 3600000).round();
    return milliseconds > 0 ? milliseconds : null;
  }

  Future<bool> _authorize(
    Map<String, dynamic> access, {
    Map<String, dynamic>? scope,
    Map<String, dynamic> settings = const {},
    bool forChoice = false,
    String initialDurationHours = '',
  }) async {
    final configure = widget.configureExecution;
    if (configure == null) throw StateError('Owner permissions unavailable');
    final generation = _presentationGeneration;
    final expectedRevision = _view?['execution']?['revision'] as int?;
    final declarations = access['credentials'] as Map? ?? const {};
    if (forChoice && declarations.isNotEmpty) {
      throw StateError('Local choices require public read access');
    }
    final references =
        declarations.isEmpty
            ? <Map<String, String>>[]
            : await widget.listSecrets?.call() ?? <Map<String, String>>[];
    if (!mounted) return false;
    final selected = <String, Map<String, String>>{};
    final previous = _view?['execution']?['credentials'] as Map? ?? const {};
    final fields = {
      for (final entry in declarations.entries)
        for (final field in entry.value as List)
          '${entry.key}:${field['id']}': (
            label: (field['label'] as String).trim().toLowerCase(),
            previous: previous[entry.key]?[field['id']],
          ),
    };
    final choices = <String, List<Map<String, String>>>{};
    for (final reference in references) {
      var slot = reference['secret_name'];
      if (slot == 'secret') {
        // Older owner-saved entries have no field in their vault scope.
        final bound = {
          for (final field in fields.entries)
            if (field.value.previous == reference['id']) field.key,
        };
        final label = reference['label']?.trim().toLowerCase();
        final named = {
          for (final field in fields.entries)
            if (field.value.label == label) field.key,
        };
        if (bound.isNotEmpty && named.isNotEmpty) {
          slot = bound.intersection(named).singleOrNull;
        } else {
          slot = (bound.isEmpty ? named : bound).singleOrNull;
        }
      }
      if (slot != null && fields.containsKey(slot)) {
        choices.putIfAbsent(slot, () => []).add(reference);
      }
    }
    final destinations = <String, Set<String>>{};
    for (final network in access['network'] as List) {
      if (network['credential'] case final String alias) {
        destinations
            .putIfAbsent(alias, () => {})
            .add(Uri.parse(network['origin'] as String).authority);
      }
    }
    for (final entry in declarations.entries) {
      selected[entry.key as String] = {};
      for (final field in entry.value as List) {
        final id = previous[entry.key]?[field['id']];
        if (choices['${entry.key}:${field['id']}']?.any((r) => r['id'] == id) ==
            true) {
          selected[entry.key]![field['id'] as String] = id as String;
        }
      }
    }
    var untilRevoked =
        initialDurationHours.isEmpty &&
        _view?['execution']?['expires_at_ms'] == null;
    var hours = initialDurationHours.isEmpty ? '24' : initialDurationHours;
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
      if (!forChoice && !untilRevoked && _permissionDurationMs(hours) == null) {
        return _permissionDurationError;
      }
      return null;
    }

    final startDestination =
        scope?['action'] == null ? null : _startDestination;
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
                            if (startDestination != null) ...[
                              Text(
                                'Start on $startDestination',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (scope?['start_action'] != null)
                                for (final field
                                    in (_view?['fields'] as List? ?? const [])
                                        .cast<Map>())
                                  if (field['advanced'] != true &&
                                      settings.containsKey(field['id']))
                                    Text(
                                      '${field['label']} ${settings[field['id']]}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              const SizedBox(height: 12),
                            ],
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
                                    for (final reference
                                        in choices['${entry.key}:${field['id']}'] ??
                                            const [])
                                      DropdownMenuItem(
                                        value: reference['id'],
                                        child: Text(
                                          [
                                            reference['label']!,
                                            ...?destinations[entry.key],
                                          ].join(' · '),
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
                            if (declarations.isNotEmpty && choices.isEmpty)
                              Text(
                                widget.saveSecrets == null
                                    ? 'Connect secrets to this Capsule in Keychain first.'
                                    : 'Choose Add new secret to save a connection in secure storage.',
                              ),
                            if (!forChoice)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Until revoked'),
                                value: untilRevoked,
                                onChanged:
                                    (value) =>
                                        update(() => untilRevoked = value),
                              ),
                            if (!forChoice && !untilRevoked)
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
                            Text(
                              forChoice
                                  ? 'Allow public reads while this choice is open.'
                                  : 'This permission covers the plugin workflow. The plugin handles service logic; the service owns its account state. Revocation blocks new requests and cannot undo accepted actions.',
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
    if (!accepted || !mounted || generation != _presentationGeneration) {
      return false;
    }
    if (forChoice) return true;
    final additions = <Map<String, String>>[];
    final targets = <(String, String)>[];
    for (final entry in declarations.entries) {
      for (final field in entry.value as List) {
        if (selected[entry.key]![field['id']] != newSecret) continue;
        final alias = entry.key as String;
        final id = field['id'] as String;
        targets.add((alias, id));
        additions.add({
          'secret_name': '$alias:$id',
          'label': names[alias]![id]!.trim(),
          'value': values[alias]![id]!.trim(),
        });
      }
    }
    if (additions.isNotEmpty) {
      final saved = await widget.saveSecrets!(additions);
      if (!mounted || generation != _presentationGeneration) return false;
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
                  _permissionDurationMs(hours)!,
      expectedRevision: expectedRevision,
      approvedScope:
          scope ??
          ({
            if (_view?['execution']?['running'] == true)
              ...?_view?['execution']?['scope'] as Map?,
            'version': 2,
            'access': access,
            'description':
                _view?['execution']?['scope']?['description'] ??
                'Owner-granted plugin access',
          }..remove('start_action')),
      credentialBindings: selected,
      settings: settings,
    );
    if (!mounted || generation != _presentationGeneration) return false;
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
    final source = field['source'] as Map;
    final action = source['action'];
    final access = (source['access'] as Map?)?.cast<String, dynamic>();
    final loadLocal =
        _view?['host_connection']?['target'] == 'vps'
            ? widget.loadLocalChoices
            : null;
    var approved = false;
    Future<Map<String, dynamic>> load() async {
      if (action is! String) throw StateError('Choice source is unavailable');
      return loadLocal == null
          ? widget.runWorkspaceAction(action, const {})
          : loadLocal(
            action,
            access ?? const {'version': 2, 'network': []},
            approved,
          );
    }

    Future<Map<String, dynamic>>? options;
    var query = '';
    setState(() => _choosing = true);
    try {
      if (access != null && !_hasAccess(access)) {
        final granted = await _authorize(
          access,
          scope: {
            'version': 2,
            'access': access,
            'description': 'Load ${field['label']} choices',
          },
          forChoice: loadLocal != null,
        );
        if (!granted || !mounted) return;
        approved = true;
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
                            child: FutureBuilder<Map<String, dynamic>>(
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
                                final hint =
                                    snapshot.data?['message'] as String?;
                                final matches =
                                    (snapshot.data?['options'] as List? ??
                                            const [])
                                        .cast<String>()
                                        .where(
                                          (s) =>
                                              s.toUpperCase().contains(query),
                                        )
                                        .toList();
                                final hasHint = hint != null && hint.isNotEmpty;
                                return ListView.builder(
                                  itemCount:
                                      (hasHint ? 1 : 0) +
                                      (matches.isEmpty ? 1 : matches.length),
                                  itemBuilder: (context, index) {
                                    if (hasHint && index == 0) {
                                      return Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(hint),
                                      );
                                    }
                                    if (matches.isEmpty) {
                                      return const ListTile(
                                        title: Text('No matching choices'),
                                      );
                                    }
                                    final option =
                                        matches[index - (hasHint ? 1 : 0)];
                                    return ListTile(
                                      title: Text(option),
                                      selected: option == _fields[id]!.text,
                                      onTap:
                                          () =>
                                              Navigator.of(context).pop(option),
                                    );
                                  },
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
    } catch (error) {
      if (mounted) setState(() => _error = _describeError(error));
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
    final statusTitle =
        _observationUnavailable
            ? 'Saved workspace'
            : _actionResultVisible
            ? 'Last action result'
            : _error != null
            ? 'Last known status'
            : 'Current status';
    final expiry = execution?['expires_at_ms'];
    final accessExpired =
        execution?['active'] == false &&
        execution?['revoked'] != true &&
        expiry is int &&
        expiry > 0 &&
        expiry <= DateTime.now().millisecondsSinceEpoch;
    final revokeControl =
        widget.configureExecution != null &&
                (_observationUnavailable || execution?['active'] == true)
            ? OutlinedButton(
              onPressed: _choosing ? null : () => _stopExecution(revoke: true),
              style: OutlinedButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Revoke plugin permissions'),
            )
            : null;
    final message = _busy ? 'Working…' : view?['message'] as String? ?? '';
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
    final startAccess = view?['schedule']?['access'];
    final showNextStartDuration =
        _remoteSelected &&
        _edited &&
        widget.configureExecution != null &&
        startAccess is Map &&
        actions.any((action) => action['host'] == 'workspace.start') &&
        _hasAccess(startAccess.cast<String, dynamic>());
    final showRevokeControl =
        !_observationUnavailable &&
        revokeControl != null &&
        !actions.any((a) => a['host'] == 'workspace.stop');
    final fields = (view?['fields'] as List? ?? const []).cast<Map>();
    final primaryFields = fields.where((f) => f['advanced'] != true).toList();
    final hasAdvanced =
        fields.any((f) => f['advanced'] == true) ||
        (_supportsExecution &&
            widget.connectVps != null &&
            view?['host_connection']?['saved'] == true);
    final connectionHealth = view?['host_connection']?['health'];
    final health = switch (connectionHealth) {
      'not_started' => 'No running assignment on this VPS',
      'setup_unconfirmed' => 'No assignment started from this Capsule',
      'running' => 'VPS process is running',
      'detached' => 'Execution authority ended',
      'replaced' => 'Previous assignment replaced',
      'unavailable' => 'Previous assignment unavailable',
      'package_updated' => 'Package updated',
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
                      (!_remoteSelected || action['host'] != 'workspace.start'))
              ? null
              : () => _run(action['id'] as String);
      final key = ValueKey('plugin-action-${action['id']}');
      final destination =
          action['host'] == 'workspace.start' ? _startDestination : null;
      final label = Text(
        destination == null
            ? action['label'] as String
            : '${action['label']} on $destination',
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
                  if (_observationUnavailable && revokeControl != null)
                    revokeControl,
                  if ((view == null ||
                          (_observationUnavailable &&
                              connectionHealth != 'package_updated')) &&
                      !_busy)
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
                    panel(statusTitle, [
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
                              _observationUnavailable
                                  ? 'Previous assignment: VPS ${view['host_connection']['host'] ?? ''}'
                                  : 'Execution location: VPS ${view['host_connection']['host'] ?? ''}',
                            'local' => 'Execution location: This device',
                            _ => 'Execution location unavailable',
                          },
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (view['host_connection']['target'] == 'local') ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Local execution requires this app to stay open.',
                          ),
                        ],
                        if (view['host_connection']['target'] == 'vps' ||
                            view['host_connection']['host'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            view['host_connection']['target'] == 'vps'
                                ? health
                                : '${_remoteSelected ? 'Next start' : 'Saved VPS'}: VPS ${view['host_connection']['host']}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (view['host_connection']['target'] != 'vps' &&
                              view['host_connection']['health'] ==
                                  'setup_unconfirmed')
                            Text(health, style: theme.textTheme.bodySmall),
                        ],
                        if (widget.connectVps != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('workspace-target-local'),
                                onPressed:
                                    _busy ||
                                            _choosing ||
                                            widget.useOnline == null
                                        ? null
                                        : _useOnline,
                                icon: Icon(
                                  _remoteSelected
                                      ? Icons.devices_outlined
                                      : Icons.check_circle_outline,
                                ),
                                label: Text(
                                  _assignedToVps
                                      ? 'Return from VPS'
                                      : 'Use this device',
                                ),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('workspace-target-vps'),
                                onPressed:
                                    _busy || _choosing ? null : _connectVps,
                                icon: Icon(
                                  _remoteSelected
                                      ? Icons.check_circle_outline
                                      : Icons.cloud_outlined,
                                ),
                                label: Text(
                                  view['host_connection']['saved'] == true
                                      ? 'Use VPS ${view['host_connection']['host']}'
                                      : 'Connect VPS',
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                      if (_observationUnavailable) ...[
                        Text(switch (connectionHealth) {
                          'not_started' =>
                            'Use Revoke plugin permissions to clear the saved assignment.',
                          'package_updated' =>
                            'Confirm Start to replace the previous VPS assignment with this version.',
                          'replaced' =>
                            'This assignment was replaced. Saved data below belongs to your previous assignment. Start creates a new assignment on this VPS.',
                          _ =>
                            'Current VPS status is unavailable. The assignment may have been replaced from another device. Saved data below is not the current VPS workflow. Connection loss does not stop remote execution.',
                        }, style: TextStyle(color: colors.error)),
                        const SizedBox(height: 12),
                        if (accessExpired)
                          Text(
                            'Saved permission expired at ${_displayTime(expiry)}.',
                          ),
                      ],
                      if (!_observationUnavailable &&
                          _supportsExecution &&
                          execution is Map) ...[
                        Text(
                          '${execution['revoked'] == true
                              ? 'Permissions revoked'
                              : accessExpired
                              ? 'Permissions expired'
                              : execution['active'] == true
                              ? 'Permissions active'
                              : execution['active'] == false
                              ? 'Permissions inactive'
                              : 'Permission status unavailable'}. '
                          '${execution['running'] == true
                              ? 'Automatic cycle enabled.'
                              : execution['running'] == false
                              ? 'Automatic cycle off.'
                              : 'Workflow status unavailable.'}'
                          '${accessExpired
                              ? ' Expired at ${_displayTime(expiry)}.'
                              : execution['active'] != true
                              ? ''
                              : execution['expires_at_ms'] == null
                              ? ' Until you revoke access.'
                              : ' Until ${_displayTime(execution['expires_at_ms'] as int)}.'}'
                          '${execution['last_checked_at_ms'] == null ? '' : '\nLast completed cycle: ${_displayTime(execution['last_checked_at_ms'] as int)}'}'
                          '${execution['last_error'] == null ? '' : '\n${execution['last_error']}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                accessExpired
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var i = 0; i < actions.length; i++)
                              actionButton(actions[i], i == 0),
                            if (_actionResultVisible &&
                                !_observationUnavailable &&
                                execution?['running'] == true &&
                                !actions.any((a) => a['id'] == 'open'))
                              OutlinedButton(
                                onPressed:
                                    _busy || _choosing
                                        ? null
                                        : () => _run('open'),
                                child: const Text('Refresh status'),
                              ),
                          ],
                        ),
                        if (_remoteSelected &&
                            actions.any(
                              (a) => a['host'] == 'workspace.start',
                            )) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Start replaces the VPS runner with this package and the selected settings. Already accepted service actions remain in effect.',
                          ),
                        ],
                      ],
                      if (!_observationUnavailable &&
                          _supportsExecution &&
                          execution is Map) ...[
                        if (execution['last_result'] is String &&
                            (execution['last_result'] as String)
                                .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last cycle result',
                            style: theme.textTheme.labelLarge,
                          ),
                          if ((execution['last_result'] as String).contains(
                            '\n',
                          ))
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                (execution['last_result'] as String)
                                    .split('\n')
                                    .first,
                              ),
                              children: [
                                SelectableText(
                                  execution['last_result'] as String,
                                ),
                              ],
                            )
                          else
                            SelectableText(execution['last_result'] as String),
                        ],
                      ],
                      const SizedBox(height: 16),
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
                                if (showNextStartDuration)
                                  SizedBox(
                                    width: width,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: TextFormField(
                                        key: const ValueKey(
                                          'plugin-next-start-duration',
                                        ),
                                        initialValue: _nextStartHours,
                                        enabled: !_busy && !_choosing,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Next Start duration (hours)',
                                          helperText:
                                              'Leave blank to keep the current expiry.',
                                          helperMaxLines: 2,
                                          errorMaxLines: 4,
                                          border: OutlineInputBorder(),
                                        ),
                                        validator: (value) {
                                          final hours = value?.trim() ?? '';
                                          return hours.isNotEmpty &&
                                                  _permissionDurationMs(
                                                        hours,
                                                      ) ==
                                                      null
                                              ? _permissionDurationError
                                              : null;
                                        },
                                        onChanged:
                                            (value) => _nextStartHours = value,
                                      ),
                                    ),
                                  ),
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
                                  view['host_connection']?['host'] != null)
                                TextButton(
                                  onPressed:
                                      _busy || _choosing
                                          ? null
                                          : () =>
                                              _connectVps(restoreAccess: true),
                                  child: const Text('Restore VPS access'),
                                ),
                              if (_supportsExecution &&
                                  widget.connectVps != null &&
                                  view['host_connection']?['host'] != null)
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
                        showRevokeControl)
                      panel('Access and execution', [
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
                            if (showRevokeControl) revokeControl,
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
