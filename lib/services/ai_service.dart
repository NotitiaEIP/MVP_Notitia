// =============================================================================
// NOTITIA — Service IA (Embedding + Génération)
// Modèles open source servis par la passerelle Notitia (voir AiClient)
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_config.dart';
import '../models/rich_summary.dart';
import 'ai_client.dart';

/// Service unifié : embeddings + génération de réponses
class AiService {
  static AiService? _instance;
  static AiService get instance => _instance ??= AiService._();

  AiService._();

  final AiClient _ai = AiClient.instance;
  final http.Client _client = http.Client();

  /// Instruction recommandée par Qwen3-Embedding pour les requêtes
  /// (les documents indexés, eux, sont embedés sans instruction).
  static const String _queryInstruction =
      'Instruct: Given a question, retrieve passages from personal voice notes that answer it\nQuery: ';

  // ---------------------------------------------------------------------------
  // EMBEDDING — Transforme du texte en vecteur
  // ---------------------------------------------------------------------------

  /// Génère un vecteur d'embedding pour un texte donné.
  /// [isQuery] — true pour une question utilisateur (améliore la recherche).
  Future<List<double>?> embed(String text, {bool isQuery = false}) async {
    if (text.trim().isEmpty) {
      debugPrint('[AI Embed] Texte vide, skip');
      return null;
    }
    final results = await embedBatch([text], isQuery: isQuery);
    return results.first;
  }

  /// Génère des embeddings pour plusieurs textes en une seule requête.
  /// Retourne null pour chaque texte en cas d'échec.
  Future<List<List<double>?>> embedBatch(
    List<String> texts, {
    bool isQuery = false,
  }) async {
    if (texts.isEmpty) return [];
    final inputs = texts.map((t) {
      final safe = t.length > 8000 ? t.substring(0, 8000) : t;
      return isQuery ? '$_queryInstruction$safe' : safe;
    }).toList();

    try {
      final vectors = await _ai.embed(inputs);
      debugPrint(
        '[AI Embed] ✓ ${vectors.length} vecteur(s) (${vectors.first.length} dims)',
      );
      return vectors;
    } catch (e) {
      debugPrint('[AI Embed] ✗ $e');
      return List<List<double>?>.filled(texts.length, null);
    }
  }

  // ---------------------------------------------------------------------------
  // GÉNÉRATION — Réponse IA augmentée par le contexte (RAG)
  // ---------------------------------------------------------------------------

  /// Génère une réponse basée sur le contexte extrait et la question.
  ///
  /// [context] — les chunks de transcription pertinents
  /// [question] — la question de l'utilisateur
  /// [conversationHistory] — historique de la conversation (optionnel)
  Future<String> generateRAGResponse({
    required List<String> context,
    required String question,
    List<Map<String, String>>? conversationHistory,
  }) async {
    if (context.isEmpty) {
      return _generateSimpleResponse(question);
    }

    final contextText = context
        .asMap()
        .entries
        .map((e) {
          return '[Extrait ${e.key + 1}]\n${e.value}';
        })
        .join('\n\n');

    final systemPrompt =
        '''Tu es Notitia, un assistant mémoire intelligent. Tu aides l'utilisateur à retrouver et comprendre les informations de ses conversations enregistrées.

RÈGLES STRICTES :
1. Réponds UNIQUEMENT avec les informations des extraits fournis ci-dessous
2. Si les extraits ne contiennent pas l'information demandée, dis-le clairement
3. Cite les passages pertinents quand c'est utile
4. Sois concis, précis et naturel en français
5. Si l'utilisateur pose une question vague, résume les points clés des extraits
6. Ne fabrique JAMAIS d'information non présente dans les extraits

EXTRAITS DE CONVERSATIONS :
$contextText''';

    try {
      debugPrint('[AI Gen] Envoi requête RAG...');
      final result = await _ai.chat(
        model: AiConfig.smartModel,
        system: systemPrompt,
        messages: [
          ...?conversationHistory?.map(
            (m) => {
              'role': m['role'] == 'user' ? 'user' : 'assistant',
              'content': m['content'] ?? '',
            },
          ),
          {'role': 'user', 'content': question},
        ],
        temperature: 0.3,
        maxTokens: 1024,
      );
      return _cleanMarkdown(result.content);
    } on AiException catch (e) {
      debugPrint('[AI Gen] Erreur: $e');
      if (e.statusCode == null) {
        return 'Désolé, une erreur est survenue. Vérifiez votre connexion.';
      }
      return 'Désolé, je n\'ai pas pu générer une réponse. Erreur API (${e.statusCode}).';
    }
  }

  /// Réponse simple quand aucun contexte n'est trouvé
  Future<String> _generateSimpleResponse(String question) async {
    try {
      final text = await _ai.complete(
        model: AiConfig.smartModel,
        system:
            'Tu es Notitia, un assistant mémoire. L\'utilisateur te pose une question mais aucune conversation enregistrée ne correspond. Dis-lui poliment que tu n\'as pas trouvé d\'information pertinente dans ses enregistrements, et suggère-lui d\'enregistrer plus de conversations ou de reformuler sa question. Réponds en français, sois concis.',
        prompt: question,
        temperature: 0.5,
        maxTokens: 512,
        timeout: const Duration(seconds: 30),
      );
      return _cleanMarkdown(text);
    } catch (e) {
      debugPrint('[AI] Erreur: $e');
    }
    return 'Je n\'ai trouvé aucune information dans tes conversations enregistrées. '
        'Essaie d\'enregistrer plus de conversations ou reformule ta question.';
  }

  // ---------------------------------------------------------------------------
  // UTILITAIRE — Similarité cosinus
  // ---------------------------------------------------------------------------

  /// Calcule la similarité cosinus entre deux vecteurs.
  /// Retourne une valeur entre -1 et 1 (1 = identique).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;

    return dotProduct / denominator;
  }

  /// Vérifie que la passerelle IA est accessible
  Future<bool> isAvailable() => _ai.isAvailable();

  // ---------------------------------------------------------------------------
  // UTILITAIRE — Nettoyage des réponses
  // ---------------------------------------------------------------------------

  /// Supprime les marqueurs Markdown (**, *, #, etc.) de la réponse
  static String _cleanMarkdown(String text) {
    // Supprimer les ** (gras)
    var result = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (m) => m.group(1) ?? '',
    );
    // Supprimer les * simples (italique)
    result = result.replaceAllMapped(
      RegExp(r'\*(.+?)\*'),
      (m) => m.group(1) ?? '',
    );
    // Supprimer les __ (gras alt)
    result = result.replaceAllMapped(
      RegExp(r'__(.+?)__'),
      (m) => m.group(1) ?? '',
    );
    // Supprimer les _ simples (italique alt)
    result = result.replaceAllMapped(
      RegExp(r'_(.+?)_'),
      (m) => m.group(1) ?? '',
    );
    // Supprimer les # (titres) au début de lignes
    result = result.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');
    // Supprimer les > (citations) au début de lignes
    result = result.replaceAll(RegExp(r'^>\s+', multiLine: true), '');
    // Supprimer les listes avec - ou * ou +
    result = result.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '• ');
    // Supprimer les doubles espaces
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
    return result.trim();
  }

  // ---------------------------------------------------------------------------
  // RÉSUMÉ RICHE — Génère un résumé structuré avec sources et images
  // ---------------------------------------------------------------------------

  /// Génère un résumé riche d'une transcription (modèle smart + recherche web).
  ///
  /// Retourne un [RichSummary] avec titre, intro narrative, sections thématiques,
  /// images libres de droits (Openverse) et vraies sources web.
  Future<RichSummary> generateRichSummary({
    required String transcriptionId,
    required String transcriptionContent,
    required String transcriptionTitle,
  }) async {
    final safeContent = transcriptionContent.length > 12000
        ? transcriptionContent.substring(0, 12000)
        : transcriptionContent;

    const systemPrompt =
        '''Tu es un rédacteur expert et data-visualiseur. À partir d'une transcription vocale brute, tu génères un résumé riche, visuellement attractif et structuré.

RÈGLES DE RÉDACTION :
1. Écris un résumé NARRATIF et fluide, PAS de listes à puces sauf si absolument nécessaire
2. Utilise des paragraphes élégants avec des transitions naturelles
3. Divise en 2 à 4 sections thématiques pertinentes
4. Le titre doit être accrocheur et résumer l'essence de la conversation
5. L'introduction doit contextualiser en 2-3 phrases
6. Écris en français

RÈGLES VISUELLES (TRÈS IMPORTANT) :
Pour chaque section, choisis LE visuel le plus pertinent parmi :
- "chart_bar" : si la conversation mentionne des comparaisons, des chiffres, des classements → graphique en barres
- "chart_pie" : si la conversation parle de répartitions, proportions, pourcentages → camembert
- "key_figures" : si des chiffres clés, statistiques, métriques ressortent → cartes de chiffres (2-4 max)
- "flow" : si un processus, des étapes, une chronologie sont décrits → schéma en étapes
- "quote" : si une phrase marquante ou citation importante a été dite → citation mise en valeur
- "none" : si aucun visuel n'est pertinent pour cette section

Choisis "key_figures" pour la 1ère section s'il y a des données intéressantes.
NE FORCE PAS un visuel si le contenu ne s'y prête pas.
Les données des charts doivent être RÉALISTES et basées sur le contenu de la transcription.

Ajoute aussi 2-4 "top_figures" globaux : les chiffres/faits les plus marquants de toute la conversation.

Réponds UNIQUEMENT en JSON valide avec cette structure exacte :
{
  "title": "Titre accrocheur",
  "introduction": "Introduction narrative de 2-3 phrases...",
  "top_figures": [
    {"value": "42%", "label": "Description courte", "icon": "trending_up"},
    {"value": "3h", "label": "Durée totale", "icon": "schedule"}
  ],
  "sections": [
    {
      "heading": "Titre de la section",
      "content": "Paragraphe narratif fluide de 3-5 phrases...",
      "image_keyword": "3-5 mots-clés TRÈS SPÉCIFIQUES en anglais décrivant précisément le sujet de la section (ex: 'cosmetic product laboratory formulation', 'business team strategy meeting', 'data analytics dashboard screen')",
      "search_queries": ["recherche google 1", "recherche google 2"],
      "visual": {
        "type": "chart_bar | chart_pie | key_figures | flow | quote | none",
        "chart_title": "Titre du graphique (si chart)",
        "chart_data": [{"label": "Item A", "value": 45}, {"label": "Item B", "value": 30}],
        "key_figures": [{"value": "120", "label": "Participants", "icon": "people"}],
        "flow_steps": [{"title": "Étape 1", "description": "Description..."}, {"title": "Étape 2", "description": "..."}],
        "quote": "La phrase marquante exacte...",
        "quote_author": "Nom du locuteur (si identifiable)"
      }
    }
  ]
}

ICONS POSSIBLES pour les figures : trending_up, trending_down, schedule, people, euro, star, speed, memory, school, work, check_circle, warning, lightbulb, rocket_launch, analytics''';

    try {
      debugPrint('[AI Summary] Génération du résumé...');
      final rawText = await _ai.complete(
        model: AiConfig.smartModel,
        system: systemPrompt,
        prompt:
            'Voici la transcription "$transcriptionTitle" à résumer :\n\n$safeContent',
        temperature: 0.7,
        maxTokens: 4096,
        jsonMode: true,
        timeout: const Duration(seconds: 90),
      );
      return _parseRichSummary(
        AiClient.extractJsonObject(rawText),
        transcriptionId,
        safeContent,
      );
    } catch (e) {
      debugPrint('[AI Summary] ✗ $e');
    }

    // Fallback : résumé minimal
    return RichSummary(
      transcriptionId: transcriptionId,
      title: transcriptionTitle,
      introduction: 'Résumé automatique non disponible. Veuillez réessayer.',
      sections: [],
      generatedAt: DateTime.now(),
    );
  }

  /// Parse le JSON du modèle et enrichit avec images + recherche web
  Future<RichSummary> _parseRichSummary(
    String rawJson,
    String transcriptionId,
    String content,
  ) async {
    try {
      final summaryData = json.decode(rawJson) as Map<String, dynamic>;
      final title = summaryData['title'] as String? ?? 'Résumé';
      final intro = summaryData['introduction'] as String? ?? '';
      final sectionsJson = summaryData['sections'] as List<dynamic>? ?? [];

      // Parse top figures
      final topFiguresJson = summaryData['top_figures'] as List<dynamic>? ?? [];
      final topFigures = topFiguresJson
          .map((f) => KeyFigure.fromJson(f as Map<String, dynamic>))
          .toList();

      final sections = <SummarySection>[];

      for (final sJson in sectionsJson) {
        final s = sJson as Map<String, dynamic>;
        final heading = s['heading'] as String? ?? '';
        final sContent = s['content'] as String? ?? '';
        final imageKeyword = s['image_keyword'] as String? ?? '';
        final searchQueries =
            (s['search_queries'] as List<dynamic>?)?.cast<String>() ?? [];

        // Parse visual
        SectionVisual? visual;
        final visualJson = s['visual'] as Map<String, dynamic>?;
        if (visualJson != null) {
          final vType = visualJson['type'] as String? ?? 'none';
          if (vType != 'none') {
            visual = SectionVisual.fromJson(visualJson);
          }
        }

        // Image libre de droits (Openverse) + sources web (passerelle) en parallèle
        final enrichment = await Future.wait([
          imageKeyword.isNotEmpty
              ? _findImageUrl(imageKeyword)
              : Future<String?>.value(null),
          _searchSources(searchQueries.take(2).toList()),
        ]);
        final imageUrl = enrichment[0] as String?;
        final sources = enrichment[1] as List<SummarySource>;

        sections.add(
          SummarySection(
            heading: heading,
            content: sContent,
            imageUrl: imageUrl,
            sources: sources,
            visual: visual,
          ),
        );
      }

      debugPrint(
        '[AI Summary] ✓ Résumé généré : $title (${sections.length} sections, ${topFigures.length} figures)',
      );

      return RichSummary(
        transcriptionId: transcriptionId,
        title: title,
        introduction: intro,
        topFigures: topFigures,
        sections: sections,
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[AI Summary] ✗ Erreur parsing JSON: $e');
      debugPrint(
        '[AI Summary] Raw: ${rawJson.substring(0, min(500, rawJson.length))}',
      );
      return RichSummary(
        transcriptionId: transcriptionId,
        title: 'Résumé',
        introduction: content.length > 300
            ? '${content.substring(0, 300)}…'
            : content,
        sections: [],
        generatedAt: DateTime.now(),
      );
    }
  }

  /// Recherche une image libre de droits via Openverse (API ouverte, sans clé),
  /// puis fallback sur LoremFlickr.
  Future<String?> _findImageUrl(String keyword) async {
    try {
      final uri = Uri.https('api.openverse.org', '/v1/images/', {
        'q': keyword,
        'page_size': '1',
        'mature': 'false',
        'aspect_ratio': 'wide',
      });
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final url = (results.first as Map<String, dynamic>)['url'] as String?;
          if (url != null && url.startsWith('http')) {
            debugPrint('[AI Image] ✓ Openverse: $url');
            return url;
          }
        }
      }
    } catch (e) {
      debugPrint('[AI Image] ✗ Erreur pour "$keyword": $e');
    }

    // Fallback : image générique par mots-clés
    final words = keyword.trim().split(RegExp(r'\s+')).take(3).join(',');
    final encoded = Uri.encodeComponent(words);
    final fallback = 'https://loremflickr.com/800/400/$encoded';
    debugPrint('[AI Image] → Fallback: $fallback');
    return fallback;
  }

  /// Recherche web (Brave via la passerelle) : 1 à 2 sources par requête.
  Future<List<SummarySource>> _searchSources(List<String> queries) async {
    final results = await Future.wait(
      queries.map((q) => _ai.search(q, maxResults: 2)),
    );
    return results
        .expand((r) => r)
        .map(
          (r) => SummarySource(title: r.title, url: r.url, snippet: r.snippet),
        )
        .toList();
  }

  void dispose() {
    _client.close();
  }
}
