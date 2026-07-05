import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/ai_doctor_provider_adapter.dart';

void main() {
  group('OpenAiResponsesDoctorProviderAdapter', () {
    test('extracts direct output text', () {
      final text = OpenAiResponsesDoctorProviderAdapter.extractOutputText(
        <String, dynamic>{
          'output_text': 'Check transport outbox first.',
        },
      );

      expect(text, 'Check transport outbox first.');
    });

    test('extracts nested response content text', () {
      final text = OpenAiResponsesDoctorProviderAdapter.extractOutputText(
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
      final text = OpenAiResponsesDoctorProviderAdapter.extractOutputText(
        <String, dynamic>{
          'output': <Object?>[],
        },
      );

      expect(text, isNull);
    });
  });
}
