import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef InferenceHttpClientFactory = HttpClient Function();

class InferencePrompt {
  final String instructions;
  final String inputJson;

  const InferencePrompt({required this.instructions, required this.inputJson});
}

enum InferenceProtocol {
  responses('Responses'),
  chatCompletions('Chat Completions'),
  generateContent('Generate Content');

  final String label;
  const InferenceProtocol(this.label);
}

/// A saved destination and protocol, independent of the service's name.
/// The built-in connections are presets; they do not define dispatch capability.
class InferenceConnection {
  static const openAi = InferenceConnection(
    id: 'openai',
    label: 'OpenAI',
    defaultModel: 'gpt-5.5',
    protocol: InferenceProtocol.responses,
  );
  static const gemini = InferenceConnection(
    id: 'gemini',
    label: 'Gemini',
    defaultModel: 'gemini-3.8-flash',
    protocol: InferenceProtocol.generateContent,
  );
  static const cloudflareWorkersAi = InferenceConnection(
    id: 'cloudflare_workers_ai',
    label: 'Cloudflare Workers AI',
    defaultModel: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
    protocol: InferenceProtocol.chatCompletions,
  );
  static const localOpenAiCompatible = InferenceConnection(
    id: 'local_openai_compatible',
    label: 'Local OpenAI-compatible',
    defaultModel: 'llama3.1:8b',
    requiresApiKey: false,
    protocol: InferenceProtocol.chatCompletions,
  );
  static const values = [
    openAi,
    gemini,
    cloudflareWorkersAi,
    localOpenAiCompatible,
  ];

  final String id;
  final String label;
  final String defaultModel;
  final InferenceProtocol protocol;

  /// Protocol base: /v1 for Responses/Chat, /v1beta/models for Generate Content.
  final String? baseUrl;
  final bool requiresApiKey;

  bool get requiresBaseUrl =>
      baseUrl != null ||
      this == localOpenAiCompatible ||
      this == cloudflareWorkersAi;
  bool get isCustom => baseUrl != null;

  const InferenceConnection({
    required this.id,
    required this.label,
    required this.defaultModel,
    required this.protocol,
    this.baseUrl,
    this.requiresApiKey = true,
  });

  static Uri validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'Endpoint must be an HTTP(S) URL without credentials, query or fragment',
      );
    }
    return uri;
  }

  Uri endpointFor(String model) {
    final base = validateBaseUrl(baseUrl!);
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    return switch (protocol) {
      InferenceProtocol.responses => base.replace(path: '$path/responses'),
      InferenceProtocol.chatCompletions => base.replace(
        path: '$path/chat/completions',
      ),
      InferenceProtocol.generateContent => Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/+$'), '')}/${Uri.encodeComponent(model)}:generateContent',
      ),
    };
  }
}

class InferenceProviderResponse {
  final String text;
  final String model;
  final InferenceConnection provider;

  const InferenceProviderResponse({
    required this.text,
    required this.model,
    this.provider = InferenceConnection.openAi,
  });
}

abstract class InferenceProviderAdapter {
  InferenceConnection get provider;

  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  });
}

/// One transport owner; only protocol encoding and decoding vary.
class InferenceProtocolAdapter implements InferenceProviderAdapter {
  @override
  final InferenceConnection provider;
  final Duration timeout;
  final InferenceHttpClientFactory _clientFactory;

  InferenceProtocolAdapter({
    this.provider = InferenceConnection.localOpenAiCompatible,
    this.timeout = const Duration(seconds: 60),
    InferenceHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    final key = apiKey.trim();
    final selectedModel = model.trim();
    if (provider.requiresApiKey && key.isEmpty) {
      throw ArgumentError('${provider.label} API key is empty');
    }
    if (selectedModel.isEmpty) throw ArgumentError('AI model is empty');
    final endpoint =
        provider.isCustom
            ? provider.endpointFor(selectedModel)
            : switch (provider.protocol) {
              InferenceProtocol.responses => Uri.https(
                'api.openai.com',
                '/v1/responses',
              ),
              InferenceProtocol.generateContent => Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(selectedModel)}:generateContent',
              ),
              InferenceProtocol.chatCompletions => chatCompletionsEndpoint(
                provider,
                baseUrl,
              ),
            };
    final body = switch (provider.protocol) {
      InferenceProtocol.responses => <String, Object>{
        'model': selectedModel,
        'store': false,
        'instructions': prompt.instructions,
        'input': prompt.inputJson,
      },
      InferenceProtocol.generateContent => <String, Object>{
        'systemInstruction': {
          'parts': [
            {'text': prompt.instructions},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt.inputJson},
            ],
          },
        ],
      },
      InferenceProtocol.chatCompletions => <String, Object>{
        'model': selectedModel,
        'stream': false,
        'messages': [
          {'role': 'system', 'content': prompt.instructions},
          {'role': 'user', 'content': prompt.inputJson},
        ],
        if (provider == InferenceConnection.cloudflareWorkersAi) ...{
          'max_tokens': 2048,
          'options': {'rejectIfBusy': true},
        },
      },
    };
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      if (key.isNotEmpty) {
        if (provider.protocol == InferenceProtocol.generateContent) {
          request.headers.set('x-goog-api-key', key);
        } else {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        }
      }
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final textBody = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // An arbitrary service can echo the request. Do not surface its body.
        throw StateError(
          '${provider.label} request failed (HTTP ${response.statusCode}). '
          'Check the connection, model access and provider status.',
        );
      }
      final decoded = jsonDecode(textBody);
      final text = switch (provider.protocol) {
        InferenceProtocol.responses => extractResponsesText(decoded),
        InferenceProtocol.generateContent => extractGenerateContentText(
          decoded,
        ),
        InferenceProtocol.chatCompletions => extractChatText(decoded),
      };
      if (text == null || text.trim().isEmpty) {
        throw StateError(
          '${provider.label} returned no text for ${provider.protocol.label}',
        );
      }
      return InferenceProviderResponse(
        text: text.trim(),
        model: selectedModel,
        provider: provider,
      );
    } on TimeoutException {
      throw StateError('AI provider request timed out');
    } on FormatException {
      throw StateError(
        '${provider.label} returned an invalid ${provider.protocol.label} response',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Uri chatCompletionsEndpoint(
    InferenceConnection provider,
    String? baseUrl,
  ) {
    final normalized = baseUrl?.trim();
    if (normalized == null || normalized.isEmpty) {
      throw ArgumentError('${provider.label} endpoint is not saved');
    }
    final base = Uri.tryParse(normalized);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw ArgumentError('${provider.label} base URL is invalid');
    }
    if (base.scheme != 'http' && base.scheme != 'https') {
      throw ArgumentError('${provider.label} base URL must use HTTP(S)');
    }
    final cleanPath =
        base.path.endsWith('/')
            ? base.path.substring(0, base.path.length - 1)
            : base.path;
    if (provider == InferenceConnection.cloudflareWorkersAi &&
        (base.scheme != 'https' ||
            base.host != 'api.cloudflare.com' ||
            base.port != 443 ||
            base.userInfo.isNotEmpty ||
            base.hasQuery ||
            base.hasFragment ||
            !RegExp(
              r'^/client/v4/accounts/[0-9a-f]{32}/ai$',
            ).hasMatch(cleanPath))) {
      throw ArgumentError(
        'Cloudflare Workers AI requires its official HTTPS account endpoint',
      );
    }
    if (!provider.requiresBaseUrl) {
      throw ArgumentError('${provider.label} does not use Chat Completions');
    }
    return base.replace(path: '$cleanPath/v1/chat/completions');
  }

  static String? extractResponsesText(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final direct = decoded['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct;
    }

    final fragments = <String>[];
    final output = decoded['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map<String, dynamic>) continue;
        final content = item['content'];
        if (content is! List) continue;
        for (final part in content) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            fragments.add(text);
          }
        }
      }
    }
    if (fragments.isEmpty) return null;
    return fragments.join('\n').trim();
  }

  static String? extractGenerateContentText(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final fragments = <String>[];
    final candidates = decoded['candidates'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final content = candidate['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            fragments.add(text);
          }
        }
      }
    }
    if (fragments.isEmpty) return null;
    return fragments.join('\n').trim();
  }

  static String? extractChatText(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final fragments = <String>[];
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) continue;
      final message = choice['message'];
      if (message is Map<String, dynamic>) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          fragments.add(content);
        }
      }
      final text = choice['text'];
      if (text is String && text.trim().isNotEmpty) {
        fragments.add(text);
      }
    }
    if (fragments.isEmpty) return null;
    return fragments.join('\n').trim();
  }
}

InferenceProviderAdapter inferenceProviderAdapterFor(
  InferenceConnection provider,
) => InferenceProtocolAdapter(provider: provider);
