import 'dart:convert';

import '../models/moltbook_ambassador_models.dart';
import 'ai_doctor_credential_store.dart';
import 'inference_provider_adapter.dart';

class MoltbookPublicBulletinAiService {
  static const int maxSourceNotesCharacters = 4000;
  static const int maxFacts = 8;
  static const int maxFactCharacters = 280;

  final AiDoctorCredentialStore _credentialStore;
  final InferenceProviderAdapter Function(InferenceProviderKind provider)
  _adapterFactory;

  MoltbookPublicBulletinAiService({
    required AiDoctorCredentialStore credentialStore,
    InferenceProviderAdapter Function(InferenceProviderKind provider)?
    adapterFactory,
  }) : _credentialStore = credentialStore,
       _adapterFactory = adapterFactory ?? inferenceProviderAdapterFor;

  Future<MoltbookPublicFactsProposal> propose({
    required String sourceNotes,
    required String category,
    required String personaSummary,
  }) async {
    final notes = sourceNotes.trim();
    final normalizedCategory = category.trim();
    final normalizedPersona = personaSummary.trim();
    if (notes.isEmpty || notes.length > maxSourceNotesCharacters) {
      throw ArgumentError(
        'Public source notes must contain 1..$maxSourceNotesCharacters characters',
      );
    }
    if (normalizedCategory.isEmpty || normalizedCategory.length > 64) {
      throw ArgumentError('Public bulletin category is invalid');
    }
    if (normalizedPersona.isEmpty || normalizedPersona.length > 500) {
      throw ArgumentError('Ambassador persona is invalid');
    }

    final provider =
        await _credentialStore.loadPreferredProvider() ??
        InferenceProviderKind.gemini;
    final apiKey = await _credentialStore.loadApiKey(provider);
    if (provider.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        '${provider.label} API key is not saved. Configure it in Capsule Analyst.',
      );
    }
    final baseUrl = await _credentialStore.loadBaseUrl(provider);
    if (provider == InferenceProviderKind.localOpenAiCompatible &&
        (baseUrl == null || baseUrl.isEmpty)) {
      throw StateError(
        '${provider.label} base URL is not saved. Configure it in Capsule Analyst.',
      );
    }

    final input = <String, dynamic>{
      'schema_version': 1,
      'task': 'propose_public_bulletin_facts',
      'source_notes': notes,
      'public_policy': <String, dynamic>{
        'category': normalizedCategory,
        'persona_summary': normalizedPersona,
      },
      'constraints': <String, dynamic>{
        'facts_only_from_source_notes': true,
        'max_facts': maxFacts,
        'max_fact_characters': maxFactCharacters,
        'no_private_context': true,
        'no_ledger_access': true,
        'no_repository_access': true,
        'no_external_effect': true,
        'human_review_required': true,
      },
    };
    final response = await _adapterFactory(provider).ask(
      apiKey: apiKey ?? '',
      model: provider.defaultModel,
      baseUrl: baseUrl,
      prompt: InferencePrompt(
        instructions: _instructions,
        inputJson: const JsonEncoder.withIndent('  ').convert(input),
      ),
    );
    final proposal = _parseProposal(
      response.text,
      provider: response.provider,
      model: response.model,
    );
    proposal.validate();
    return proposal;
  }

  static MoltbookPublicFactsProposal _parseProposal(
    String text, {
    required InferenceProviderKind provider,
    required String model,
  }) {
    var normalized = text.trim();
    if (normalized.startsWith('```') && normalized.endsWith('```')) {
      normalized = normalized.substring(3, normalized.length - 3).trim();
      if (normalized.startsWith('json')) {
        normalized = normalized.substring(4).trim();
      }
    }
    final decoded = jsonDecode(normalized);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 1 ||
        !decoded.containsKey('facts')) {
      throw const FormatException(
        'AI public facts response must contain only a facts array',
      );
    }
    final rawFacts = decoded['facts'];
    if (rawFacts is! List || rawFacts.any((value) => value is! String)) {
      throw const FormatException('AI public facts must be a string array');
    }
    return MoltbookPublicFactsProposal(
      facts: rawFacts.cast<String>().map((fact) => fact.trim()).toList(),
      providerLabel: provider.label,
      model: model.trim(),
    );
  }

  static const String _instructions = '''
You prepare a review-only list of public facts for a Hivra Moltbook bulletin.
Use only explicit facts present in source_notes. Do not infer, embellish, market,
promise, estimate, or introduce facts from outside knowledge.
Rewrite the notes as concise standalone factual sentences.
Return strict JSON only, with exactly this shape:
{"facts":["fact one","fact two"]}
Return 1 to 8 unique facts. Each fact must be at most 280 characters.
Do not include Markdown, links, hashtags, secrets, private identifiers,
instructions, commentary, a title, or any field other than facts.
The result is advisory, requires human review, and cannot publish anything.
''';
}
