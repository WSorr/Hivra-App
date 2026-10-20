import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef InferenceHttpClientFactory = HttpClient Function();

class InferencePrompt {
  final String instructions;
  final String inputJson;

  const InferencePrompt({required this.instructions, required this.inputJson});
}

enum InferenceProviderKind {
  openAi(id: 'openai', label: 'OpenAI', defaultModel: 'gpt-5.5'),
  gemini(
    id: 'gemini',
    label: 'Gemini',
    defaultModel: 'gemini-3.8-flash',
    requiresApiKey: true,
  ),
  cloudflareWorkersAi(
    id: 'cloudflare_workers_ai',
    label: 'Cloudflare Workers AI',
    defaultModel: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  ),
  localOpenAiCompatible(
    id: 'local_openai_compatible',
    label: 'Local OpenAI-compatible',
    defaultModel: 'llama3.1:8b',
    requiresApiKey: false,
  );

  final String id;
  final String label;
  final String defaultModel;
  final bool requiresApiKey;

  bool get requiresBaseUrl =>
      this == localOpenAiCompatible || this == cloudflareWorkersAi;

  const InferenceProviderKind({
    required this.id,
    required this.label,
    required this.defaultModel,
    this.requiresApiKey = true,
  });
}

class InferenceProviderResponse {
  final String text;
  final String model;
  final InferenceProviderKind provider;

  const InferenceProviderResponse({
    required this.text,
    required this.model,
    this.provider = InferenceProviderKind.openAi,
  });
}

abstract class InferenceProviderAdapter {
  InferenceProviderKind get provider;

  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  });
}

class OpenAiResponsesInferenceProviderAdapter
    implements InferenceProviderAdapter {
  final Uri endpoint;
  final Duration timeout;
  final InferenceHttpClientFactory _clientFactory;

  OpenAiResponsesInferenceProviderAdapter({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
    InferenceHttpClientFactory? clientFactory,
  }) : endpoint = endpoint ?? Uri.https('api.openai.com', '/v1/responses'),
       _clientFactory = clientFactory ?? HttpClient.new;

  @override
  InferenceProviderKind get provider => InferenceProviderKind.openAi;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedModel = model.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('OpenAI API key is empty');
    }
    if (normalizedModel.isEmpty) {
      throw ArgumentError('OpenAI model is empty');
    }

    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedKey',
      );
      request.write(
        jsonEncode(<String, dynamic>{
          'model': normalizedModel,
          'store': false,
          'instructions': prompt.instructions,
          'input': prompt.inputJson,
        }),
      );
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      final decoded = jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _openAiFriendlyErrorMessage(
              decoded,
              statusCode: response.statusCode,
            ) ??
            'HTTP ${response.statusCode}';
        throw StateError('AI provider request failed: $message');
      }
      final text = extractOutputText(decoded);
      if (text == null || text.trim().isEmpty) {
        throw StateError('AI provider returned no text output');
      }
      return InferenceProviderResponse(
        text: text.trim(),
        model: normalizedModel,
        provider: provider,
      );
    } on TimeoutException {
      throw StateError('AI provider request timed out');
    } finally {
      client.close(force: true);
    }
  }

  static String? extractOutputText(Object? decoded) {
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

  static String? friendlyErrorMessageForTest(
    Object? decoded, {
    required int statusCode,
  }) {
    return _openAiFriendlyErrorMessage(decoded, statusCode: statusCode);
  }
}

class GeminiGenerateContentInferenceProviderAdapter
    implements InferenceProviderAdapter {
  final Uri baseEndpoint;
  final Duration timeout;
  final InferenceHttpClientFactory _clientFactory;

  GeminiGenerateContentInferenceProviderAdapter({
    Uri? baseEndpoint,
    this.timeout = const Duration(seconds: 60),
    InferenceHttpClientFactory? clientFactory,
  }) : baseEndpoint =
           baseEndpoint ??
           Uri.https('generativelanguage.googleapis.com', '/v1beta/models'),
       _clientFactory = clientFactory ?? HttpClient.new;

  @override
  InferenceProviderKind get provider => InferenceProviderKind.gemini;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedModel = model.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('Gemini API key is empty');
    }
    if (normalizedModel.isEmpty) {
      throw ArgumentError('Gemini model is empty');
    }

    final endpoint = baseEndpoint.replace(
      path:
          '${baseEndpoint.path}/${Uri.encodeComponent(normalizedModel)}'
          ':generateContent',
    );
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-goog-api-key', normalizedKey);
      request.write(
        jsonEncode(<String, dynamic>{
          'systemInstruction': <String, dynamic>{
            'parts': <Map<String, String>>[
              <String, String>{'text': prompt.instructions},
            ],
          },
          'contents': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'user',
              'parts': <Map<String, String>>[
                <String, String>{'text': prompt.inputJson},
              ],
            },
          ],
        }),
      );
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      final decoded = jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _geminiFriendlyErrorMessage(
              decoded,
              statusCode: response.statusCode,
            ) ??
            'HTTP ${response.statusCode}';
        throw StateError('AI provider request failed: $message');
      }
      final text = extractOutputText(decoded);
      if (text == null || text.trim().isEmpty) {
        throw StateError('AI provider returned no text output');
      }
      return InferenceProviderResponse(
        text: text.trim(),
        model: normalizedModel,
        provider: provider,
      );
    } on TimeoutException {
      throw StateError('AI provider request timed out');
    } finally {
      client.close(force: true);
    }
  }

  static String? extractOutputText(Object? decoded) {
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
}

class OpenAiChatCompletionsInferenceProviderAdapter
    implements InferenceProviderAdapter {
  @override
  final InferenceProviderKind provider;
  final Duration timeout;
  final InferenceHttpClientFactory _clientFactory;

  OpenAiChatCompletionsInferenceProviderAdapter({
    this.provider = InferenceProviderKind.localOpenAiCompatible,
    this.timeout = const Duration(seconds: 60),
    InferenceHttpClientFactory? clientFactory,
  }) : assert(
         provider == InferenceProviderKind.localOpenAiCompatible ||
             provider == InferenceProviderKind.cloudflareWorkersAi,
       ),
       _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<InferenceProviderResponse> ask({
    required String apiKey,
    required String model,
    required InferencePrompt prompt,
    String? baseUrl,
  }) async {
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw ArgumentError('${provider.label} model is empty');
    }
    final normalizedKey = apiKey.trim();
    if (provider.requiresApiKey && normalizedKey.isEmpty) {
      throw ArgumentError('${provider.label} API token is empty');
    }
    final endpoint = chatCompletionsEndpoint(provider, baseUrl);
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      if (normalizedKey.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $normalizedKey',
        );
      }
      request.write(
        jsonEncode(<String, dynamic>{
          'model': normalizedModel,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'system', 'content': prompt.instructions},
            <String, String>{'role': 'user', 'content': prompt.inputJson},
          ],
          'stream': false,
          if (provider == InferenceProviderKind.cloudflareWorkersAi) ...{
            'max_tokens': 2048,
            'options': <String, bool>{'rejectIfBusy': true},
          },
        }),
      );
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      if (provider == InferenceProviderKind.cloudflareWorkersAi &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        // Provider errors may echo credentials or input. Never surface them.
        throw StateError(switch (response.statusCode) {
          401 || 403 =>
            'Cloudflare Workers AI access denied. Check the API token, Account ID and model access.',
          429 =>
            'Cloudflare Workers AI quota or rate limit reached. Check the dashboard before retrying.',
          _ =>
            'Cloudflare Workers AI request failed (HTTP ${response.statusCode}).',
        });
      }
      final decoded = jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _providerErrorMessage(decoded) ?? 'HTTP ${response.statusCode}';
        throw StateError('AI provider request failed: $message');
      }
      final text = extractOutputText(decoded);
      if (text == null || text.trim().isEmpty) {
        throw StateError('AI provider returned no text output');
      }
      return InferenceProviderResponse(
        text: text.trim(),
        model: normalizedModel,
        provider: provider,
      );
    } on TimeoutException {
      throw StateError('AI provider request timed out');
    } on FormatException {
      throw StateError('${provider.label} returned an invalid response');
    } finally {
      client.close(force: true);
    }
  }

  static String cloudflareBaseUrlForAccount(String accountId) {
    final account = accountId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(account)) {
      throw ArgumentError(
        'Cloudflare Account ID must contain 32 hexadecimal characters',
      );
    }
    return 'https://api.cloudflare.com/client/v4/accounts/$account/ai';
  }

  static Uri chatCompletionsEndpoint(
    InferenceProviderKind provider,
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
    if (provider == InferenceProviderKind.cloudflareWorkersAi &&
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

  static String? extractOutputText(Object? decoded) {
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
  InferenceProviderKind provider,
) {
  return switch (provider) {
    InferenceProviderKind.openAi => OpenAiResponsesInferenceProviderAdapter(),
    InferenceProviderKind.gemini =>
      GeminiGenerateContentInferenceProviderAdapter(),
    InferenceProviderKind.localOpenAiCompatible ||
    InferenceProviderKind.cloudflareWorkersAi =>
      OpenAiChatCompletionsInferenceProviderAdapter(provider: provider),
  };
}

String? _providerErrorMessage(Object? decoded) {
  if (decoded is! Map<String, dynamic>) return null;
  final error = decoded['error'];
  if (error is Map<String, dynamic>) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  return null;
}

String? _providerErrorCode(Object? decoded) {
  if (decoded is! Map<String, dynamic>) return null;
  final error = decoded['error'];
  if (error is Map<String, dynamic>) {
    final code = error['code'];
    if (code is String && code.trim().isNotEmpty) {
      return code.trim();
    }
    final status = error['status'];
    if (status is String && status.trim().isNotEmpty) {
      return status.trim();
    }
    final type = error['type'];
    if (type is String && type.trim().isNotEmpty) {
      return type.trim();
    }
  }
  return null;
}

String? _openAiFriendlyErrorMessage(
  Object? decoded, {
  required int statusCode,
}) {
  final rawMessage = _providerErrorMessage(decoded);
  final code = _providerErrorCode(decoded);
  final normalized = '${code ?? ''} ${rawMessage ?? ''}'.toLowerCase().trim();

  if (normalized.contains('insufficient_quota') ||
      normalized.contains('quota')) {
    return 'OpenAI API quota is exhausted for this key. Check billing, limits, or use another restricted key.';
  }
  if (statusCode == HttpStatus.unauthorized ||
      normalized.contains('invalid_api_key') ||
      normalized.contains('incorrect api key')) {
    return 'OpenAI API key was rejected. Check the key value and project access.';
  }
  if (statusCode == HttpStatus.tooManyRequests ||
      normalized.contains('rate_limit')) {
    return 'OpenAI API rate limit reached. Wait and retry, or lower request frequency.';
  }
  return rawMessage;
}

String? _geminiFriendlyErrorMessage(
  Object? decoded, {
  required int statusCode,
}) {
  final rawMessage = _providerErrorMessage(decoded);
  final code = _providerErrorCode(decoded);
  final normalized = '${code ?? ''} ${rawMessage ?? ''}'.toLowerCase().trim();

  if (normalized.contains('quota') ||
      normalized.contains('resource_exhausted')) {
    return 'Gemini API quota or free-tier limit is exhausted for this key. Check AI Studio rate limits or billing.';
  }
  if (statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.forbidden ||
      normalized.contains('api key not valid') ||
      normalized.contains('permission_denied')) {
    return 'Gemini API key was rejected. Check the key value, project, and API access.';
  }
  if (statusCode == HttpStatus.tooManyRequests ||
      normalized.contains('rate limit')) {
    return 'Gemini API rate limit reached. Wait and retry, or lower request frequency.';
  }
  return rawMessage;
}
