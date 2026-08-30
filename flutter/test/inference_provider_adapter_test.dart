import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/inference_provider_adapter.dart';

void main() {
  group('OpenAiResponsesInferenceProviderAdapter', () {
    test('extracts direct output text', () {
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(
        <String, dynamic>{
          'output_text': 'Check transport outbox first.',
        },
      );

      expect(text, 'Check transport outbox first.');
    });

    test('extracts nested response content text', () {
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(
        <String, dynamic>{
          'output': <Map<String, dynamic>>[
            <String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'output_text',
                  'text': 'Finding one.',
                },
                <String, dynamic>{
                  'type': 'output_text',
                  'text': 'Finding two.',
                },
              ],
            },
          ],
        },
      );

      expect(text, 'Finding one.\nFinding two.');
    });

    test('rejects malformed response without text', () {
      final text = OpenAiResponsesInferenceProviderAdapter.extractOutputText(
        <String, dynamic>{
          'output': <Object?>[],
        },
      );

      expect(text, isNull);
    });

    test('formats quota errors for users', () {
      final message =
          OpenAiResponsesInferenceProviderAdapter.friendlyErrorMessageForTest(
        <String, dynamic>{
          'error': <String, dynamic>{
            'message':
                'You exceeded your current quota, please check your plan and billing details.',
            'code': 'insufficient_quota',
          },
        },
        statusCode: 429,
      );

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
          LocalOpenAiCompatibleInferenceProviderAdapter.extractOutputText(
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
