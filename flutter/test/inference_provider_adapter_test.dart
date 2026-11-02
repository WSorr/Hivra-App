import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

void main() {
  for (final protocol in InferenceProtocol.values) {
    test(
      'a new name uses ${protocol.name} without a service adapter',
      () async {
        final connection = InferenceConnection(
          id: 'owner-id',
          label: 'Unlisted owner service',
          defaultModel: 'model-v2',
          protocol: protocol,
          baseUrl: 'https://owner.example/protocol?api-version=2026-01-01',
        );
        final body = switch (protocol) {
          InferenceProtocol.responses => '{"output_text":"answer"}',
          InferenceProtocol.chatCompletions =>
            '{"choices":[{"message":{"content":"answer"}}]}',
          InferenceProtocol.generateContent =>
            '{"candidates":[{"content":{"parts":[{"text":"answer"}]}}]}',
        };
        final client = _Client(body: body);
        final adapter = InferenceProtocolAdapter(
          provider: connection,
          clientFactory: () => client,
        );
        final result = await adapter.ask(
          apiKey: 'bound-key',
          model: 'model-v2',
          prompt: const InferencePrompt(
            instructions: 'Explain',
            inputJson: '{}',
          ),
        );
        final suffix = switch (protocol) {
          InferenceProtocol.responses => 'responses',
          InferenceProtocol.chatCompletions => 'chat/completions',
          InferenceProtocol.generateContent => 'model-v2:generateContent',
        };
        expect(
          client.endpoint.toString(),
          'https://owner.example/protocol/$suffix?api-version=2026-01-01',
        );
        expect(client.request.followRedirects, isFalse);
        expect(
          client.request.headers.values[protocol ==
                  InferenceProtocol.generateContent
              ? 'x-goog-api-key'
              : HttpHeaders.authorizationHeader],
          protocol == InferenceProtocol.generateContent
              ? 'bound-key'
              : 'Bearer bound-key',
        );
        expect(result.provider, connection);
        expect(result.model, 'model-v2');
        expect(result.text, 'answer');
        expect(
          inferenceProviderAdapterFor(connection),
          isA<InferenceProtocolAdapter>(),
        );
        expect(client.closed, isTrue);
      },
    );

    test(
      '${protocol.name} incompatibility has no fallback or echoed secret',
      () async {
        for (final status in [200, 401, 302, 503]) {
          final client = _Client(
            status: status,
            body: '{"error":{"message":"bound-key private-context"}}',
          );
          final connection = InferenceConnection(
            id: 'custom',
            label: 'Owner service',
            defaultModel: 'model',
            protocol: protocol,
            baseUrl: 'https://owner.example/v1',
            requiresApiKey: false,
          );
          final adapter = InferenceProtocolAdapter(
            provider: connection,
            clientFactory: () => client,
          );
          await expectLater(
            adapter.ask(
              apiKey: '',
              model: 'model',
              prompt: const InferencePrompt(
                instructions: 'Explain',
                inputJson: '{}',
              ),
            ),
            throwsA(
              predicate(
                (e) =>
                    e is StateError &&
                    !e.toString().contains('bound-key') &&
                    !e.toString().contains('private-context'),
              ),
            ),
          );
          expect(client.calls, 1);
          expect(client.request.headers.values, isEmpty);
          expect(client.closed, isTrue);
        }
      },
    );
  }

  group('Cloudflare Workers AI', () {
    const provider = InferenceConnection.cloudflareWorkersAi;
    const account = '0123456789abcdef0123456789abcdef';
    const baseUrl = 'https://api.cloudflare.com/client/v4/accounts/$account/ai';
    const prompt = InferencePrompt(
      instructions: 'Explain public facts',
      inputJson: '{"fact":"Chat resumes"}',
    );

    test(
      'uses the pinned account endpoint and shared Chat Completions wire format',
      () async {
        final client = _Client(
          body: '{"choices":[{"message":{"content":"A useful update"}}]}',
        );
        final adapter = InferenceProtocolAdapter(
          provider: provider,
          clientFactory: () => client,
        );

        final result = await adapter.ask(
          apiKey: ' test-token ',
          model: provider.defaultModel,
          prompt: prompt,
          baseUrl: baseUrl,
        );

        expect(client.endpoint.toString(), '$baseUrl/v1/chat/completions');
        expect(
          client.request.headers.values[HttpHeaders.authorizationHeader],
          'Bearer test-token',
        );
        expect(client.request.followRedirects, isFalse);
        final body =
            jsonDecode(client.request.body.toString()) as Map<String, dynamic>;
        expect(body['model'], provider.defaultModel);
        expect(body['messages'], [
          {'role': 'system', 'content': prompt.instructions},
          {'role': 'user', 'content': prompt.inputJson},
        ]);
        expect(body['stream'], isFalse);
        expect(body['max_tokens'], 2048);
        expect(body['options'], {'rejectIfBusy': true});
        expect(body.toString(), isNot(contains('test-token')));
        expect(result.provider, provider);
        expect(result.text, 'A useful update');
        expect(client.closed, isTrue);
      },
    );

    test('requires a token and valid account before creating a client', () async {
      var created = false;
      final adapter = InferenceProtocolAdapter(
        provider: provider,
        clientFactory: () {
          created = true;
          return _Client();
        },
      );
      for (final url in [
        null,
        '',
        'http://api.cloudflare.com/client/v4/accounts/$account/ai',
        'https://evil.example/client/v4/accounts/$account/ai',
        '$baseUrl?token=bad',
        '$baseUrl#fragment',
        'https://user:password@api.cloudflare.com/client/v4/accounts/$account/ai',
        'https://api.cloudflare.com:444/client/v4/accounts/$account/ai',
        'https://api.cloudflare.com/client/v4/accounts/invalid/ai',
      ]) {
        await expectLater(
          adapter.ask(
            apiKey: 'test-token',
            model: provider.defaultModel,
            prompt: prompt,
            baseUrl: url,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        adapter.ask(
          apiKey: '',
          model: provider.defaultModel,
          prompt: prompt,
          baseUrl: baseUrl,
        ),
        throwsArgumentError,
      );
      expect(created, isFalse);
    });

    for (final status in [401, 403, 429, 503, 302]) {
      test(
        'HTTP $status fails once without echoing provider credentials or context',
        () async {
          final client = _Client(
            status: status,
            body:
                '{"errors":[{"message":"Bearer secret-token and private context"}]}',
          );
          final adapter = InferenceProtocolAdapter(
            provider: provider,
            clientFactory: () => client,
          );
          await expectLater(
            adapter.ask(
              apiKey: 'secret-token',
              model: provider.defaultModel,
              prompt: prompt,
              baseUrl: baseUrl,
            ),
            throwsA(
              predicate(
                (e) =>
                    e is StateError &&
                    e.toString().contains('Cloudflare Workers AI') &&
                    !e.toString().contains('secret-token') &&
                    !e.toString().contains('private context'),
              ),
            ),
          );
          expect(client.calls, 1);
          expect(client.closed, isTrue);
        },
      );
    }

    test('malformed or empty success cannot become a proposal', () async {
      for (final body in ['not-json secret-token', '{"choices":[]}']) {
        final client = _Client(body: body);
        final adapter = InferenceProtocolAdapter(
          provider: provider,
          clientFactory: () => client,
        );
        await expectLater(
          adapter.ask(
            apiKey: 'secret-token',
            model: provider.defaultModel,
            prompt: prompt,
            baseUrl: baseUrl,
          ),
          throwsA(
            predicate(
              (e) => e is StateError && !e.toString().contains('secret-token'),
            ),
          ),
        );
        expect(client.closed, isTrue);
      }
    });

    test('timeout closes the client without another attempt', () async {
      final client = _Client(neverComplete: true);
      final adapter = InferenceProtocolAdapter(
        provider: provider,
        timeout: const Duration(milliseconds: 5),
        clientFactory: () => client,
      );
      await expectLater(
        adapter.ask(
          apiKey: 'test-token',
          model: provider.defaultModel,
          prompt: prompt,
          baseUrl: baseUrl,
        ),
        throwsStateError,
      );
      expect(client.calls, 1);
      expect(client.closed, isTrue);
    });

    test(
      'local provider still uses its configured endpoint without a token',
      () async {
        final client = _Client(
          body: '{"choices":[{"message":{"content":"Local answer"}}]}',
        );
        final adapter = InferenceProtocolAdapter(clientFactory: () => client);
        final result = await adapter.ask(
          apiKey: '',
          model: 'local-model',
          prompt: prompt,
          baseUrl: 'http://127.0.0.1:11434',
        );
        expect(
          client.endpoint.toString(),
          'http://127.0.0.1:11434/v1/chat/completions',
        );
        expect(
          client.request.headers.values,
          isNot(contains(HttpHeaders.authorizationHeader)),
        );
        expect(result.provider, InferenceConnection.localOpenAiCompatible);
      },
    );
  });
  group('protocol text decoding', () {
    test('extracts direct output text', () {
      final text = InferenceProtocolAdapter.extractResponsesText(
        <String, dynamic>{'output_text': 'Check transport outbox first.'},
      );

      expect(text, 'Check transport outbox first.');
    });

    test('extracts nested response content text', () {
      final text = InferenceProtocolAdapter.extractResponsesText(<
        String,
        dynamic
      >{
        'output': <Map<String, dynamic>>[
          <String, dynamic>{
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'output_text', 'text': 'Finding one.'},
              <String, dynamic>{'type': 'output_text', 'text': 'Finding two.'},
            ],
          },
        ],
      });

      expect(text, 'Finding one.\nFinding two.');
    });

    test('rejects malformed response without text', () {
      final text = InferenceProtocolAdapter.extractResponsesText(
        <String, dynamic>{'output': <Object?>[]},
      );

      expect(text, isNull);
    });

    test('extracts Gemini candidate text', () {
      final text = InferenceProtocolAdapter.extractGenerateContentText(
        <String, dynamic>{
          'candidates': <Map<String, dynamic>>[
            <String, dynamic>{
              'content': <String, dynamic>{
                'parts': <Map<String, dynamic>>[
                  <String, dynamic>{'text': 'Gemini finding.'},
                ],
              },
            },
          ],
        },
      );

      expect(text, 'Gemini finding.');
    });

    test('extracts local OpenAI-compatible chat text', () {
      final text = InferenceProtocolAdapter.extractChatText(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': 'Local model finding.'},
          },
        ],
      });

      expect(text, 'Local model finding.');
    });
  });
}

class _Client implements HttpClient {
  final _Request request;
  Uri? endpoint;
  bool closed = false;
  int calls = 0;
  _Client({int status = 200, String body = '{}', bool neverComplete = false})
    : request = _Request(status, body, neverComplete);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    calls++;
    endpoint = url;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  final int status;
  final String responseBody;
  final bool neverComplete;
  final body = StringBuffer();
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  _Request(this.status, this.responseBody, this.neverComplete);
  @override
  void write(Object? value) => body.write(value);
  @override
  Future<HttpClientResponse> close() =>
      neverComplete
          ? Completer<HttpClientResponse>().future
          : Future.value(_Response(status, responseBody));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
