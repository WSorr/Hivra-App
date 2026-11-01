import 'dart:convert';
import 'dart:io';
import 'package:hivra_app/ffi/hivra_bindings.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/plugin_capability_dispatcher.dart';
import 'package:hivra_app/services/plugin_host_api_service.dart';
import 'package:hivra_app/services/plugin_workspace_runtime.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';
import 'package:hivra_app/services/wasm_plugin_registry_service.dart';
import 'package:hivra_app/services/wasm_plugin_runtime_service.dart';

// Real installed WASM and common host; every service and AI response is synthetic.
// No live credential, HTTP connection, inference or publication is used.
Future<void> main(List<String> args) async {
  final package = File(args[0]).absolute;
  Directory.current = Directory(args[1]).absolute;
  final home = await Directory.systemTemp.createTemp('hivra_moltbook_common_');
  final dirs = UserVisibleDataDirectoryService(homeOverride: home.path);
  final files = CapsuleFileStore(dirs: dirs);
  final registry = WasmPluginRegistryService(dataDirs: dirs);
  final record = await registry.installPluginFromFile(package);
  final wasm = WasmPluginRuntimeService(
    invokeJson: HivraBindings.invokeInstalledWasmJson,
  );
  final owner = 'a' * 64;
  final posts = <Map<String, dynamic>>[];
  final comments = <Map<String, dynamic>>[];
  var writes = 0, histories = 0, ai = 0, largestResponse = 0;
  var activity = false, removeDuringAi = false;
  final profilePadding = 'public service metadata ' * 9500;
  PluginWorkspaceRuntime runtime() => PluginWorkspaceRuntime(
    registry: registry,
    pluginHostApi: PluginHostApiService(
      handlers: [],
      resolveRuntimeBinding: registry.resolveRuntimeBinding,
      resolveRuntimeInvoke:
          (request, binding) => wasm.invoke(request: request, binding: binding),
    ),
    fileStore: files,
    readActiveCapsuleRootHex: () => owner,
    scheduleTimers: false,
    resolveCredentialReferences: (selectedOwner, refs) async {
      if (selectedOwner != owner || refs['token'] != 'fixture-reference') {
        throw StateError('Wrong owner connection');
      }
      return {'token': 'fixture-token'};
    },
    infer: (request, authorize) async {
      if (removeDuringAi) await registry.removePlugin(record.id);
      await authorize();
      ai++;
      if (request['id'] == 'solve') {
        return {'outcome': 'response', 'text': '15.00'};
      }
      final input = request['input'] as Map;
      if (input['account'] != 'owner') {
        throw StateError('AI did not receive fresh service facts');
      }
      return {
        'outcome': 'response',
        'provider_label': 'Analyst fixture',
        'model': 'owner-selected-model',
        'text': jsonEncode(
          activity
              ? {
                'kind': 'reply',
                'parent_id': 'question',
                'content': 'A concrete answer to the service conversation.',
              }
              : {
                'kind': 'news',
                'title': 'Public Capsule capability',
                'content':
                    'An original factual description of the public change.',
              },
        ),
      };
    },
    capabilities: PluginCapabilityDispatcher(
      send: (method, uri, headers, body) async {
        if (uri.host != 'api.github.com' && uri.host != 'www.moltbook.com') {
          throw StateError('Unexpected destination');
        }
        if (headers['Authorization'] != null &&
            headers['Authorization'] != 'Bearer fixture-token') {
          throw StateError('Wrong protected token');
        }
        dynamic data;
        final path = uri.path;
        if (path.endsWith('/agents/me')) {
          data = {
            'success': true,
            'agent': {'id': 'me', 'name': 'owner'},
          };
        } else if (path.endsWith('/agents/profile')) {
          histories++;
          data = {
            'success': true,
            'agent': {'id': 'me', 'name': 'owner'},
            'recentPosts': posts,
            'recentComments':
                comments
                    .where((c) => (c['author'] as Map)['id'] == 'me')
                    .toList(),
            'extra_service_metadata': profilePadding,
          };
        } else if (path.endsWith('/home')) {
          data = {
            'success': true,
            'activity_on_your_posts':
                activity
                    ? [
                      {'post_id': 'thread'},
                    ]
                    : [],
          };
        } else if (uri.host == 'api.github.com') {
          data = [
            {
              'sha': 'b' * 40,
              'commit': {
                'message': 'A new public product capability',
                'author': {'date': '2026-11-01T09:00:00Z'},
              },
            },
          ];
        } else if (path.endsWith('/comments') && method == 'GET') {
          data = {
            'success': true,
            'post_id': 'thread',
            'comments': [
              {
                'id': 'question',
                'author': {'id': 'other', 'name': 'reader'},
                'content': 'How does this work?',
                'replies': comments,
              },
            ],
            'has_more': false,
          };
        } else if ((path.endsWith('/posts') || path.endsWith('/comments')) &&
            method == 'POST') {
          writes++;
          final content = Map<String, dynamic>.from(jsonDecode(body!) as Map);
          content.addAll({
            'id': 'created-$writes',
            'author': {'id': 'me', 'name': 'owner'},
            'verification_status': 'pending',
            'verification': {
              'verification_code': 'fixture-code',
              'challenge_text': '20 minus 5',
            },
          });
          (path.endsWith('/comments') ? comments : posts).add(content);

          data = {
            'success': true,
            path.endsWith('/comments') ? 'comment' : 'post': content,
          };
        } else if (path.endsWith('/verify')) {
          final verification = jsonDecode(body!) as Map;
          if (verification['answer'] != '15.00') {
            throw StateError('Wrong verification response');
          }
          final row = activity ? comments.last : posts.last;
          row['verification_status'] = 'verified';
          data = {'success': true, 'content_id': row['id']};
        } else if (path.contains('/posts/') && method == 'GET') {
          data = {
            'success': true,
            'post': posts.singleWhere((p) => p['id'] == path.split('/').last),
          };
        } else {
          throw StateError('Unexpected fixture request $method $path');
        }
        final encoded = jsonEncode(data);
        final size = utf8.encode(encoded).length;
        if (size > largestResponse) largestResponse = size;
        return {'status': 200, 'body': encoded};
      },
    ),
  );
  Future<Map<String, dynamic>> action(String name) =>
      runtime().runWorkspaceAction(record: record, action: name);
  Future<void> grant() async {
    final view = await action('open');
    final previous = await runtime().readWorkspaceExecution(record);
    await runtime().setWorkspaceExecution(
      record: record,
      enabled: true,
      expiresAtMs: null,
      expectedRevision: previous?['revision'] as int?,
      approvedScope: Map<String, dynamic>.from(view['schedule'] as Map),
      credentialBindings: {
        'account': {'token': 'fixture-reference'},
      },
      settings: {
        'repository': 'fixture/public',
        'community': 'general',
        'instructions': 'Use public source facts',
        'interval_minutes': 1,
        'mode': 'news_and_replies',
      },
    );
  }

  try {
    await grant();
    final preview = await action('preview');
    if (!preview['message'].toString().contains('nothing sent') ||
        writes != 0 ||
        ai != 1) {
      throw StateError('Preview path failed: ${preview['message']}');
    }
    final news = await action('cycle');
    if (!news['message'].toString().contains('confirmed published') ||
        writes != 1) {
      throw StateError('News path failed: ${news['message']}');
    }
    await action('cycle');
    if (writes != 1) {
      throw StateError('Restart duplicated a service-observed source');
    }
    activity = true;
    final reply = await action('cycle');
    if (!reply['message'].toString().contains('confirmed reply') ||
        writes != 2) {
      throw StateError('Reply path failed: ${reply['message']}');
    }
    await action('cycle');
    if (writes != 2) {
      throw StateError('Restart duplicated a service-observed reply');
    }
    final directory = await files.capsuleDirForHex(owner);
    final pluginDir = await files.pluginStateDirectory(
      directory,
      record.pluginId!,
    );
    final stored =
        await pluginDir.list().map((e) => e.path.split('/').last).toList();
    if (stored.length != 1 || stored.single != 'workspace-execution.v1.json') {
      throw StateError('Plugin retained product history: $stored');
    }
    final grantData = await runtime().readWorkspaceExecution(record);
    if ((grantData!['settings'] as Map)['repository'] != 'fixture/public') {
      throw StateError('Owner settings were not retained');
    }
    await runtime().setWorkspaceExecution(
      record: record,
      enabled: false,
      expiresAtMs: null,
      revoke: true,
    );
    await action('cycle');
    if (writes != 2) {
      throw StateError('Revoked authority dispatched a publication');
    }
    await grant();
    activity = false;
    posts.clear();
    removeDuringAi = true;
    try {
      await action('preview');
    } catch (_) {}
    if (writes != 2) {
      throw StateError('Removal during inference dispatched content');
    }
    stdout.writeln(
      'PASS actual Moltbook WASM: >64 KiB profile, shared Analyst inference, preview, synthetic post/reply + verification + public receipt, restart deduplication, owner settings, only grant persisted, revocation and removal during queued AI. No live calls.',
    );
    if (largestResponse <= 64 * 1024) {
      throw StateError('Large-response boundary was not exercised');
    }
    stdout.writeln(
      'Observed histories=$histories; synthetic content writes=$writes; AI responses=$ai; largest service body=$largestResponse bytes',
    );
  } finally {
    await home.delete(recursive: true);
  }
}
