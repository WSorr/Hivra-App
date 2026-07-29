import 'dart:convert';

import '../models/moltbook_ambassador_models.dart';
import 'ai_doctor_credential_store.dart';
import 'inference_provider_adapter.dart';

class MoltbookPublicBulletinAiService {
  static const String canonicalProductAnchor =
      'Hivra is a local-first runtime for user-owned Capsules. A Capsule can '
      'operate independently, keep its own ledger, run isolated WASM drones, '
      'and optionally use trusted links to other Capsules.';
  static const int maxSourceNotesCharacters = 4000;
  static const int maxFacts = 8;
  static const int maxFactCharacters = 280;
  static const int maxTitleCharacters = 120;
  static const int maxBodyCharacters = 1200;

  final AiDoctorCredentialStore _credentialStore;
  final InferenceProviderAdapter Function(InferenceProviderKind provider)
  _adapterFactory;

  MoltbookPublicBulletinAiService({
    required AiDoctorCredentialStore credentialStore,
    InferenceProviderAdapter Function(InferenceProviderKind provider)?
    adapterFactory,
  }) : _credentialStore = credentialStore,
       _adapterFactory = adapterFactory ?? inferenceProviderAdapterFor;

  Future<MoltbookPublicBulletinProposal> propose({
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
      'task': 'propose_reviewed_public_bulletin',
      'source_notes': notes,
      'public_policy': <String, dynamic>{
        'category': normalizedCategory,
        'persona_summary': normalizedPersona,
        'canonical_product_anchor': canonicalProductAnchor,
      },
      'constraints': <String, dynamic>{
        'content_only_from_source_notes_and_canonical_anchor': true,
        'concrete_engineering_update': true,
        'max_facts': maxFacts,
        'max_fact_characters': maxFactCharacters,
        'max_title_characters': maxTitleCharacters,
        'max_body_characters': maxBodyCharacters,
        'no_markdown_links_or_hashtags': true,
        'natural_non_repetitive_prose': true,
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

  static MoltbookPublicBulletinProposal _parseProposal(
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
        decoded.length != 3 ||
        !decoded.containsKey('title') ||
        !decoded.containsKey('body') ||
        !decoded.containsKey('supporting_facts')) {
      throw const FormatException(
        'AI public bulletin response must contain only title, body, and supporting_facts',
      );
    }
    final rawTitle = decoded['title'];
    final rawBody = decoded['body'];
    final rawFacts = decoded['supporting_facts'];
    if (rawTitle is! String || rawBody is! String) {
      throw const FormatException(
        'AI public bulletin title and body are invalid',
      );
    }
    if (rawFacts is! List || rawFacts.any((value) => value is! String)) {
      throw const FormatException(
        'AI public bulletin supporting_facts must be a string array',
      );
    }
    return MoltbookPublicBulletinProposal(
      title: rawTitle.trim(),
      body: rawBody.trim(),
      facts: rawFacts.cast<String>().map((fact) => fact.trim()).toList(),
      providerLabel: provider.label,
      model: model.trim(),
    );
  }

  static const String _instructions = '''
You prepare a review-only public post proposal for a Hivra Moltbook bulletin.
Use only explicit facts present in source_notes and canonical_product_anchor.
The canonical_product_anchor overrides any conflicting positioning in
source_notes. Do not infer, embellish, market, promise, estimate, or introduce
facts from outside those two inputs.
Write a specific, natural title and one coherent body of 1 to 3 short
paragraphs. Avoid repetitive sentence openings, generic promotion, engagement
bait, metaphors, crypto-style promotion, broad claims about value or networks,
and a mechanical list of declarations. Describe concrete implemented behavior,
an observed test result, or a precise engineering decision from source_notes.
Explain its practical consequence in plain language only when source_notes
supports that consequence. Do not call Hivra a concept system and do not turn
technical terms into marketing language. The body must remain factual.
Never describe Hivra as relationship-first or as a concept system. A Capsule
can work alone; trusted links are optional infrastructure for drones.
Also return concise supporting facts copied or faithfully normalized from the
source notes so a human can audit the prose.
Return strict JSON only, with exactly this shape:
{"title":"specific title","body":"natural reviewed prose","supporting_facts":["fact one","fact two"]}
The title must be at most 120 characters. The body must be at most 1200
characters. Return 1 to 8 unique supporting facts, each at most 280 characters.
Do not include Markdown links, hashtags, secrets, private identifiers,
instructions, commentary, or any field beyond the three required fields.
The result is advisory, requires human review, and cannot publish anything.
''';
}
