// =============================================================================
// NOTITIA — Service Gemini AI (Embedding + Génération)
// API gratuite Google Gemini pour le RAG
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service unifié Gemini : embeddings + génération de réponses
class GeminiService {
  static GeminiService? _instance;
  static GeminiService get instance => _instance ??= GeminiService._();

  GeminiService._();

  // ---------------------------------------------------------------------------
  // Configuration — Clé API Gemini gratuite
  // Obtenir une clé sur : https://aistudio.google.com/app/apikey
  // ---------------------------------------------------------------------------
  static const String _apiKey = 'AIzaSyC4JXkfK5lEDG89DzdQV_REgzL7fQ7odF8';

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
              return (parts[0]['text'] as String).trim();
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
              return (parts[0]['text'] as String).trim();
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

  void dispose() {
    _client.close();
  }
}
