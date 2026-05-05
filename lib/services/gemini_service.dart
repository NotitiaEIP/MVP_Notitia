// =============================================================================
// NOTITIA — Service Gemini AI (Embedding + Génération)
// API gratuite Google Gemini pour le RAG
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/rich_summary.dart';

/// Service unifié Gemini : embeddings + génération de réponses
class GeminiService {
  static GeminiService? _instance;
  static GeminiService get instance => _instance ??= GeminiService._();

  GeminiService._();

  // ---------------------------------------------------------------------------
  // Configuration — Clé API Gemini gratuite
  // Obtenir une clé sur : https://aistudio.google.com/app/apikey
  // ---------------------------------------------------------------------------
  static const String _apiKey = 'AIzaSyCnTV8AT4kRLwb0IXfL852VLNkoiSu_sZk';

  // Modèles
  static const String _embeddingModel = 'gemini-embedding-001';
  static const String _generationModel = 'gemini-2.5-flash';

  // URLs
  static String get _embeddingUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_embeddingModel:embedContent?key=$_apiKey';
  static String get _generateUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_generationModel:generateContent?key=$_apiKey';

  final http.Client _client = http.Client();

  // ---------------------------------------------------------------------------
  // EMBEDDING — Transforme du texte en vecteur
  // ---------------------------------------------------------------------------

  /// Génère un vecteur d'embedding pour un texte donné.
  /// Retourne une liste de doubles (768 dimensions pour text-embedding-004).
  Future<List<double>?> embed(String text) async {
    if (text.trim().isEmpty) {
      debugPrint('[Gemini Embed] Texte vide, skip');
      return null;
    }

    // Tronquer si trop long (limit ~10000 chars pour l'API)
    final safeText = text.length > 8000 ? text.substring(0, 8000) : text;

    // Retry avec backoff en cas de rate limit (429)
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        debugPrint(
          '[Gemini Embed] Envoi ${safeText.length} chars (tentative ${attempt + 1})...',
        );
        final response = await _client
            .post(
              Uri.parse(_embeddingUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'model': 'models/$_embeddingModel',
                'content': {
                  'parts': [
                    {'text': safeText},
                  ],
                },
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final embedding = data['embedding'] as Map<String, dynamic>?;
          if (embedding != null) {
            final values = (embedding['values'] as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList();
            debugPrint('[Gemini Embed] ✓ OK (${values.length} dimensions)');
            return values;
          } else {
            debugPrint(
              '[Gemini Embed] ✗ Pas de champ "embedding": ${response.body.substring(0, min(200, response.body.length))}',
            );
          }
        } else if (response.statusCode == 429) {
          // Rate limit → attendre et réessayer
          final waitSec = (attempt + 1) * 10;
          debugPrint('[Gemini Embed] ⏳ Rate limit 429, attente ${waitSec}s...');
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        } else {
          debugPrint(
            '[Gemini Embed] ✗ Erreur HTTP ${response.statusCode}: ${response.body}',
          );
        }
      } catch (e) {
        debugPrint('[Gemini Embed] ✗ Exception: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 5));
          continue;
        }
      }
      break; // Pas de retry si pas 429
    }
    return null;
  }

  /// Génère des embeddings pour plusieurs textes (batch).
  /// Respecte le rate limit en ajoutant un petit délai.
  Future<List<List<double>?>> embedBatch(List<String> texts) async {
    final results = <List<double>?>[];
    for (int i = 0; i < texts.length; i++) {
      final embedding = await embed(texts[i]);
      results.add(embedding);
      // Petit délai pour respecter le rate limit (15 req/min gratuit)
      if (i < texts.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return results;
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

    // Construire les messages
    final messages = <Map<String, dynamic>>[];

    // Historique de conversation (si présent)
    if (conversationHistory != null) {
      for (final msg in conversationHistory) {
        messages.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [
            {'text': msg['content']},
          ],
        });
      }
    }

    // Message courant
    messages.add({
      'role': 'user',
      'parts': [
        {'text': question},
      ],
    });

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        debugPrint('[Gemini Gen] Envoi requête (tentative ${attempt + 1})...');
        final response = await _client
            .post(
              Uri.parse(_generateUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'system_instruction': {
                  'parts': [
                    {'text': systemPrompt},
                  ],
                },
                'contents': messages,
                'generationConfig': {
                  'temperature': 0.3,
                  'maxOutputTokens': 1024,
                  'topP': 0.8,
                },
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = (parts[0]['text'] as String).trim();
              return _cleanMarkdown(rawText);
            }
          }
        } else if (response.statusCode == 429) {
          final waitSec = (attempt + 1) * 10;
          debugPrint('[Gemini Gen] ⏳ Rate limit 429, attente ${waitSec}s...');
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        } else {
          debugPrint(
            '[Gemini Gen] Erreur ${response.statusCode}: ${response.body}',
          );
          return 'Désolé, je n\'ai pas pu générer une réponse. Erreur API (${response.statusCode}).';
        }
      } catch (e) {
        debugPrint('[Gemini Gen] Erreur: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 5));
          continue;
        }
        return 'Désolé, une erreur est survenue. Vérifiez votre connexion.';
      }
    }

    return 'Je n\'ai pas pu traiter votre demande (rate limit). Réessayez dans quelques secondes.';
  }

  /// Réponse simple quand aucun contexte n'est trouvé
  Future<String> _generateSimpleResponse(String question) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse(_generateUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'system_instruction': {
                  'parts': [
                    {
                      'text':
                          'Tu es Notitia, un assistant mémoire. L\'utilisateur te pose une question mais aucune conversation enregistrée ne correspond. Dis-lui poliment que tu n\'as pas trouvé d\'information pertinente dans ses enregistrements, et suggère-lui d\'enregistrer plus de conversations ou de reformuler sa question. Réponds en français, sois concis.',
                    },
                  ],
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': question},
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': 0.5,
                  'maxOutputTokens': 512,
                },
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = (parts[0]['text'] as String).trim();
              return _cleanMarkdown(rawText);
            }
          }
        } else if (response.statusCode == 429) {
          final waitSec = (attempt + 1) * 10;
          debugPrint('[Gemini Simple] ⏳ Rate limit, attente ${waitSec}s...');
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        }
      } catch (e) {
        debugPrint('[Gemini] Erreur: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 5));
          continue;
        }
      }
      break;
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

  /// Vérifie que l'API Gemini est accessible
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey',
            ),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Gemini] API non accessible: $e');
      return false;
    }
  }

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

  /// Génère un résumé riche d'une transcription via Gemini + Google Search grounding.
  ///
  /// Retourne un [RichSummary] avec titre, intro narrative, sections thématiques,
  /// images Unsplash gratuites et vraies sources web.
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

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        debugPrint(
          '[Gemini Summary] Génération du résumé (tentative ${attempt + 1})...',
        );

        final response = await _client
            .post(
              Uri.parse(_generateUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'system_instruction': {
                  'parts': [
                    {'text': systemPrompt},
                  ],
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {
                        'text':
                            'Voici la transcription "$transcriptionTitle" à résumer :\n\n$safeContent',
                      },
                    ],
                  },
                ],
                'generationConfig': {
                  'temperature': 0.7,
                  'maxOutputTokens': 4096,
                  'topP': 0.9,
                  'responseMimeType': 'application/json',
                },
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = (parts[0]['text'] as String).trim();
              return _parseRichSummary(rawText, transcriptionId, safeContent);
            }
          }
        } else if (response.statusCode == 429) {
          final waitSec = (attempt + 1) * 10;
          debugPrint(
            '[Gemini Summary] ⏳ Rate limit 429, attente ${waitSec}s...',
          );
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        } else {
          debugPrint(
            '[Gemini Summary] ✗ Erreur ${response.statusCode}: ${response.body}',
          );
        }
      } catch (e) {
        debugPrint('[Gemini Summary] ✗ Exception: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 5));
          continue;
        }
      }
      break;
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

  /// Parse le JSON Gemini et enrichit avec images + recherche Google
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

        // Image — recherche via Gemini grounding (vraies URLs)
        String? imageUrl;
        if (imageKeyword.isNotEmpty) {
          imageUrl = await _findImageUrl(imageKeyword);
        }

        // Recherche Google via Gemini grounding
        final sources = <SummarySource>[];
        for (final query in searchQueries.take(2)) {
          final searchResults = await _searchGoogleGrounding(query);
          sources.addAll(searchResults);
        }

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
        '[Gemini Summary] ✓ Résumé généré : $title (${sections.length} sections, ${topFigures.length} figures)',
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
      debugPrint('[Gemini Summary] ✗ Erreur parsing JSON: $e');
      debugPrint(
        '[Gemini Summary] Raw: ${rawJson.substring(0, min(500, rawJson.length))}',
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

  /// Recherche une image pertinente via Pexels (gratuit, pas de clé requise pour les URLs de recherche)
  /// puis fallback sur Unsplash source redirect
  Future<String?> _findImageUrl(String keyword) async {
    // Méthode 1 : Gemini grounding pour trouver une vraie URL de stock photo
    try {
      final response = await _client
          .post(
            Uri.parse(_generateUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          'Search for a high-quality stock photo on Unsplash or Pexels that matches EXACTLY this topic: "$keyword". '
                          'The image MUST be directly related to this specific topic, not a random image. '
                          'Return ONLY the direct image URL (must contain unsplash.com/photos or images.pexels.com), nothing else.',
                    },
                  ],
                },
              ],
              'tools': [
                {'google_search': {}},
              ],
              'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 256},
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates[0] as Map<String, dynamic>;

          // Vérifier le grounding metadata
          final groundingMeta =
              candidate['groundingMetadata'] as Map<String, dynamic>?;
          if (groundingMeta != null) {
            final chunks =
                groundingMeta['groundingChunks'] as List<dynamic>? ?? [];
            for (final chunk in chunks) {
              final web =
                  (chunk as Map<String, dynamic>)['web']
                      as Map<String, dynamic>?;
              if (web != null) {
                final uri = web['uri'] as String? ?? '';
                if (_isImageUrl(uri) ||
                    uri.contains('unsplash.com') ||
                    uri.contains('pexels.com')) {
                  debugPrint('[Gemini Image] ✓ Grounding: $uri');
                  return uri;
                }
              }
            }
          }

          // Parser le texte de la réponse
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = (parts[0]['text'] as String).trim();
            final urlMatch = RegExp(
              r'https?://(?:images\.unsplash\.com|images\.pexels\.com|www\.pexels\.com)[^\s\)\]"]*',
            ).firstMatch(text);
            if (urlMatch != null) {
              final url = urlMatch.group(0)!;
              debugPrint('[Gemini Image] ✓ Texte: $url');
              return url;
            }
            // URL d'image générique en dernier recours
            final anyImgMatch = RegExp(
              r'https?://\S+\.(?:jpg|jpeg|png|webp)[^\s\)\]]*',
            ).firstMatch(text);
            if (anyImgMatch != null) {
              debugPrint(
                '[Gemini Image] ✓ Img générique: ${anyImgMatch.group(0)}',
              );
              return anyImgMatch.group(0)!;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Gemini Image] ✗ Erreur pour "$keyword": $e');
    }

    // Fallback : Unsplash source redirect (images gratuites + pertinentes)
    final words = keyword.trim().split(RegExp(r'\s+')).take(3).join(',');
    final encoded = Uri.encodeComponent(words);
    final fallback = 'https://loremflickr.com/800/400/$encoded';
    debugPrint('[Gemini Image] → Fallback: $fallback');
    return fallback;
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp');
  }

  /// Utilise Gemini avec Google Search grounding pour trouver de vraies sources
  Future<List<SummarySource>> _searchGoogleGrounding(String query) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_generateUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          'Recherche web : "$query". Donne-moi 1-2 sources fiables avec titre et URL réelle. Réponds en JSON : [{"title":"...","url":"https://...","snippet":"..."}]',
                    },
                  ],
                },
              ],
              'tools': [
                {'google_search': {}},
              ],
              'generationConfig': {
                'temperature': 0.1,
                'maxOutputTokens': 1024,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Vérifier d'abord les groundingMetadata pour les vrais liens
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates[0] as Map<String, dynamic>;

          // Extraire les sources du grounding metadata (liens réels Google)
          final groundingMeta =
              candidate['groundingMetadata'] as Map<String, dynamic>?;
          if (groundingMeta != null) {
            final chunks =
                groundingMeta['groundingChunks'] as List<dynamic>? ?? [];
            final sources = <SummarySource>[];
            for (final chunk in chunks.take(2)) {
              final web =
                  (chunk as Map<String, dynamic>)['web']
                      as Map<String, dynamic>?;
              if (web != null) {
                sources.add(
                  SummarySource(
                    title: web['title'] as String? ?? query,
                    url: web['uri'] as String? ?? '',
                    snippet: '',
                  ),
                );
              }
            }
            if (sources.isNotEmpty) {
              debugPrint(
                '[Gemini Search] ✓ ${sources.length} sources grounding pour "$query"',
              );
              return sources;
            }
          }

          // Fallback : parser le texte JSON de la réponse
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = (parts[0]['text'] as String).trim();
            try {
              final parsed = json.decode(text) as List<dynamic>;
              return parsed
                  .take(2)
                  .map((s) {
                    final src = s as Map<String, dynamic>;
                    return SummarySource(
                      title: src['title'] as String? ?? query,
                      url: src['url'] as String? ?? '',
                      snippet: src['snippet'] as String? ?? '',
                    );
                  })
                  .where((s) => s.url.startsWith('http'))
                  .toList();
            } catch (_) {
              // Pas de JSON parseable
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Gemini Search] ✗ Erreur pour "$query": $e');
    }
    return [];
  }

  void dispose() {
    _client.close();
  }
}
