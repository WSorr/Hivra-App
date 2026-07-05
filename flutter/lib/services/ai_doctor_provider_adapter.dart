import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_doctor_prompt_service.dart';

typedef AiDoctorHttpClientFactory = HttpClient Function();

class AiDoctorProviderResponse {
  final String text;
  final String model;

  const AiDoctorProviderResponse({
    required this.text,
    required this.model,
  });
}

abstract class AiDoctorProviderAdapter {
  Future<AiDoctorProviderResponse> ask({
    required String apiKey,
    required String model,
    required AiDoctorPrompt prompt,
  });
}

class OpenAiResponsesDoctorProviderAdapter implements AiDoctorProviderAdapter {
  final Uri endpoint;
  final Duration timeout;
  final AiDoctorHttpClientFactory _clientFactory;

  OpenAiResponsesDoctorProviderAdapter({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
    AiDoctorHttpClientFactory? clientFactory,
  })  : endpoint = endpoint ?? Uri.https('api.openai.com', '/v1/responses'),
        _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<AiDoctorProviderResponse> ask({
    required String apiKey,
    required String model,
    required AiDoctorPrompt prompt,
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
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $normalizedKey');
      request.write(jsonEncode(<String, dynamic>{
        'model': normalizedModel,
        'store': false,
        'instructions': prompt.instructions,
        'input': prompt.inputJson,
      }));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      final decoded = jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _errorMessage(decoded) ?? 'HTTP ${response.statusCode}';
        throw StateError('AI provider request failed: $message');
      }
      final text = extractOutputText(decoded);
      if (text == null || text.trim().isEmpty) {
        throw StateError('AI provider returned no text output');
      }
      return AiDoctorProviderResponse(
        text: text.trim(),
        model: normalizedModel,
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

  static String? _errorMessage(Object? decoded) {
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
}
