import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Common transport primitives. Service paths, bodies and response semantics
/// belong to packages. Authorization is rechecked at the dispatch boundary.
class PluginCapabilityDispatcher {
  static const version = 2;
  static const maxBodyBytes = 24 * 1024;
  static const maxResponseBodyBytes = 256 * 1024;
  final Future<Map<String, dynamic>> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  )?
  send;

  const PluginCapabilityDispatcher({this.send});

  static const catalog = <String, Map<String, dynamic>>{
    'ai.infer': {
      'version': 2,
      'permission': 'inference.request',
      'required': ['instructions', 'input'],
      'optional': ['max_output_bytes'],
    },
    'runtime.yield': {'version': 2, 'permission': 'workspace.continue'},
    'runtime.wait': {
      'version': 2,
      'permission': 'workspace.continue',
      'required': ['milliseconds'],
      'max_milliseconds': 60000,
    },
    'api.describe': {'version': 2, 'permission': null},
    'http.request': {
      'version': 2,
      'permission': 'network.http',
      'max_body_bytes': maxBodyBytes,
      'required': ['url', 'method'],
      'optional': [
        'headers',
        'body',
        'credential',
        'auth',
        'max_response_bytes',
      ],
      'max_response_bytes': maxResponseBodyBytes,
      'outcomes': ['response', 'not_dispatched', 'unknown'],
    },
    'storage.read': {
      'version': 2,
      'permission': 'state.plugin.read_write',
      'required': ['key'],
    },
    'storage.write': {
      'version': 2,
      'permission': 'state.plugin.read_write',
      'required': ['key', 'value'],
    },
  };

  static void validateAccess(dynamic access) {
    if (access is! Map ||
        access['version'] != version ||
        access['network'] is! List ||
        (access['network'] as List).length > 16) {
      throw const FormatException('Invalid capability access scope');
    }
    for (final raw in access['network'] as List) {
      if (raw is! Map ||
          raw['origin'] is! String ||
          raw['methods'] is! List ||
          (raw['methods'] as List).isEmpty ||
          (raw['methods'] as List).length > 7 ||
          (raw['methods'] as List).any(
            (m) =>
                !{
                  'GET',
                  'HEAD',
                  'POST',
                  'PUT',
                  'PATCH',
                  'DELETE',
                  'OPTIONS',
                }.contains(m),
          ) ||
          (raw['credential'] != null && !safeId(raw['credential']))) {
        throw const FormatException('Invalid network permission');
      }
      final uri = Uri.parse(raw['origin']);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          uri.origin != raw['origin']) {
        throw const FormatException(
          'Permission requires an exact HTTPS origin',
        );
      }
    }
    if (access['inference'] != null && access['inference'] is! bool) {
      throw const FormatException('Invalid inference permission');
    }
    if (access['credential_fields'] != null) {
      throw const FormatException('Use owner-connected Keychain credentials');
    }
    final connections = access['credentials'] ?? const {};
    if (connections is! Map || connections.length > 8) {
      throw const FormatException('Invalid credential connections');
    }
    for (final connection in connections.entries) {
      final fields = connection.value;
      if (!safeId(connection.key) ||
          fields is! List ||
          fields.isEmpty ||
          fields.length > 8 ||
          fields.any(
            (f) =>
                f is! Map ||
                !safeId(f['id']) ||
                f['label'] is! String ||
                (f['label'] as String).length > 128,
          ) ||
          fields.map((f) => f['id']).toSet().length != fields.length) {
        throw const FormatException('Invalid credential fields');
      }
    }
    if ((access['network'] as List).any(
      (n) =>
          n['credential'] != null && !connections.containsKey(n['credential']),
    )) {
      throw const FormatException(
        'Network credential connection is undeclared',
      );
    }
    if (utf8.encode(jsonEncode(access)).length > 4096) {
      throw const FormatException('Access scope exceeds its bound');
    }
  }

  static bool safeId(dynamic value) =>
      value is String && RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(value);

  static bool allows(Map access, Map request) {
    try {
      validateAccess(access);
      if (request['kind'] == 'ai.infer') return access['inference'] == true;
      final uri = Uri.parse(request['url'] as String);
      return uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment &&
          (access['network'] as List).any(
            (p) =>
                p['origin'] == uri.origin &&
                (p['methods'] as List).contains(request['method']) &&
                p['credential'] == request['credential'],
          );
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> http(
    Map<String, dynamic> request, {
    required Map<String, dynamic> access,
    required Future<Map<String, String>> Function() readCredentials,
    required Future<void> Function() authorize,
  }) async {
    var admitted = false;
    final secretValues = <String>[];
    try {
      final responseLimit = request['max_response_bytes'] ?? maxBodyBytes;
      if (responseLimit is! int ||
          responseLimit < 1 ||
          responseLimit > maxResponseBodyBytes) {
        throw const FormatException('Invalid response bound');
      }
      if (!allows(access, request) ||
          request['url'].length > 2048 ||
          (request['body'] != null && request['body'] is! String)) {
        throw const FormatException('Network request exceeds permission');
      }
      var uri = Uri.parse(request['url']);
      final headers = Map<String, String>.from(
        request['headers'] as Map? ?? {},
      );
      if (headers.length > 16 ||
          headers.entries.any(
            (e) =>
                !RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(e.key) ||
                e.value.length > 1024 ||
                e.value.contains('\r') ||
                e.value.contains('\n') ||
                {
                  'host',
                  'connection',
                  'content-length',
                  'transfer-encoding',
                  'proxy-authorization',
                }.contains(e.key.toLowerCase()),
          )) {
        throw const FormatException('Invalid request headers');
      }
      final body = request['body'] as String?;
      if (body != null && utf8.encode(body).length > maxBodyBytes) {
        throw const FormatException('Request body exceeds its bound');
      }
      final auth = request['auth'];
      if (auth != null) {
        if (request['credential'] == null || auth is! Map) {
          throw const FormatException(
            'Authentication requires a credential permission',
          );
        }
        final values = await readCredentials();
        String secret(dynamic field) {
          final value = values[field];
          if (!safeId(field) ||
              value == null ||
              value.isEmpty ||
              value.length > 4096) {
            throw const FormatException('Credential field unavailable');
          }
          secretValues.add(value);
          return value;
        }

        final assignments = auth['headers'] as Map? ?? {};
        if (assignments.length > 8) {
          throw const FormatException('Too many protected headers');
        }
        for (final entry in assignments.entries) {
          if (!RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(entry.key) ||
              {
                'host',
                'connection',
                'content-length',
                'transfer-encoding',
                'proxy-authorization',
              }.contains(entry.key.toLowerCase())) {
            throw const FormatException('Invalid protected header');
          }
          final descriptor = entry.value as Map;
          final prefix = descriptor['prefix'] as String? ?? '';
          final value = '$prefix${secret(descriptor['field'])}';
          if (value.contains('\r') || value.contains('\n')) {
            throw const FormatException();
          }
          headers[entry.key as String] = value;
        }
        if (auth['hmac_query'] != null) {
          final signature = auth['hmac_query'] as Map;
          final field = signature['parameter'];
          if (!safeId(field) ||
              uri.queryParametersAll.values.any((v) => v.length != 1) ||
              uri.queryParameters.containsKey(field)) {
            throw const FormatException('Invalid signature parameter');
          }
          final params = Map<String, String>.from(uri.queryParameters);
          final keys = params.keys.toList()..sort();
          final canonical = keys.map((k) => '$k=${params[k]}').join('&');
          params[field as String] =
              Hmac(
                sha256,
                utf8.encode(secret(signature['field'])),
              ).convert(utf8.encode(canonical)).toString();
          secretValues.add(params[field]!);
          uri = uri.replace(queryParameters: params);
        }
      }
      // No await between the final authority check and entering the transport.
      await authorize();
      admitted = true;
      final result =
          await (send == null
              ? _send(
                request['method'] as String,
                uri,
                headers,
                body,
                responseLimit,
              )
              : send!(request['method'] as String, uri, headers, body));
      if (result['status'] is! int ||
          result['status'] < 100 ||
          result['status'] > 599 ||
          result['body'] is! String ||
          utf8.encode(result['body']).length > responseLimit) {
        throw const FormatException('Transport response exceeds its bound');
      }
      final responseHeaders = Map<String, String>.from(
        result['headers'] as Map? ?? {},
      );
      if (responseHeaders.length > 64 ||
          utf8.encode(jsonEncode(responseHeaders)).length > 8192 ||
          responseHeaders.entries.any(
            (e) =>
                !RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(e.key) ||
                e.value.contains('\r') ||
                e.value.contains('\n'),
          )) {
        throw const FormatException('Response headers exceed their bound');
      }
      // Services may echo authentication. Neither text nor response headers may
      // carry protected values or the signed destination back into WASM.
      final visible = jsonEncode([result['body'], responseHeaders]);
      if (secretValues.any(visible.contains) ||
          (auth != null && visible.contains(uri.toString()))) {
        return {'outcome': 'unknown', 'error': 'protected_response'};
      }
      return {
        'outcome': 'response',
        'status': result['status'],
        'headers': responseHeaders,
        'body': result['body'],
      };
    } catch (_) {
      return {
        'outcome': admitted ? 'unknown' : 'not_dispatched',
        'error': admitted ? 'transport_unavailable' : 'access_unavailable',
      };
    }
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    int responseLimit,
  ) async {
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > responseLimit) {
          throw const FormatException('Response exceeds its bound');
        }
        bytes.addAll(chunk);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return {
        'status': response.statusCode,
        'headers': responseHeaders,
        'body': utf8.decode(bytes),
      };
    } finally {
      client.close(force: true);
    }
  }
}
