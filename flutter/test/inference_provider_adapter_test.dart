import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

void main() {
  group('Cloudflare Workers AI', () {
    const provider = InferenceProviderKind.cloudflareWorkersAi;
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
        final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
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
      final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
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
      expect(
        OpenAiChatCompletionsInferenceProviderAdapter.cloudflareBaseUrlForAccount(
          ' ${account.toUpperCase()} ',
        ),
        baseUrl,
      );
      expect(
        () =>
            OpenAiChatCompletionsInferenceProviderAdapter.cloudflareBaseUrlForAccount(
              'not-an-account',
            ),
        throwsArgumentError,
      );
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
          final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
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
        final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
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
      final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
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
        final adapter = OpenAiChatCompletionsInferenceProviderAdapter(
          clientFactory: () => client,
        );
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
        expect(result.provider, InferenceProviderKind.localOpenAiCompatible);
      },
    );
  });
  group('OpenAiResponsesInferenceProviderAdapter', () {
    test('extracts direct output text', () {
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(
        <String, dynamic>{'output_text': 'Check transport outbox first.'},
      );

      expect(text, 'Check transport outbox first.');
    });

    test('extracts nested response content text', () {
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(<
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
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(
        <String, dynamic>{'output': <Object?>[]},
      );

      expect(text, isNull);
    });

    test('formats quota errors for users', () {
      final message =
          OpenAiResponsesInferenceProviderAdapter.friendlyErrorMessageForTest(<
            String,
            dynamic
          >{
            'error': <String, dynamic>{
              'message':
                  'You exceeded your current quota, please check your plan and billing details.',
              'code': 'insufficient_quota',
            },
          }, statusCode: 429);

      expect(
        message,
        'OpenAI API quota is exhausted for this key. Check billing, limits, or use another restricted key.',
      );
    });

    test('extracts Gemini candidate text', () {
      final text =
          GeminiGenerateContentInferenceProviderAdapter.extractOutputText(
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
      final text =
          OpenAiChatCompletionsInferenceProviderAdapter.extractOutputText(
            <String, dynamic>{
              'choices': <Map<String, dynamic>>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': 'Local model finding.',
                  },
                },
              ],
            },
          );

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
