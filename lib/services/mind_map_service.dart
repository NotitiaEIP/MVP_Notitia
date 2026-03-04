// =============================================================================
// NOTITIA — Service Génération Mind Map
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/mind_map.dart';
import '../models/transcription.dart';
import 'claude_service.dart';

/// Moteur de génération de Mind Map
enum MindMapEngine {
  gemini, // Gratuit — Google Gemini
  claude, // Premium — Claude Sonnet (plus riche / plus précis)
}

/// Service de génération de Mind Maps à partir de transcriptions
class MindMapService {
  static final MindMapService _instance = MindMapService._internal();
  factory MindMapService() => _instance;
  MindMapService._internal();

  final ClaudeService _claude = ClaudeService();
  final http.Client _httpClient = http.Client();

  // ---------------------------------------------------------------------------
  // Prompt System Expert pour la génération de Mind Maps
  // ---------------------------------------------------------------------------

  static const String _systemPrompt =
      '''Tu es un expert en extraction d'informations et synthèse visuelle.
Ta mission: analyser une transcription et créer une mind map RICHE et DÉTAILLÉE.

## OBJECTIF PRINCIPAL
Extraire TOUTES les informations importantes de la transcription:
- Citations exactes des phrases clés
- Noms, dates, lieux, chiffres mentionnés
- Décisions prises et actions à faire
- Questions et problèmes soulevés
- Idées et propositions

## STRUCTURE OBLIGATOIRE

1. **Root**: Titre précis du sujet (pas générique)
2. **Topics** (4-8 branches): Chaque thème abordé dans la conversation
3. **Subtopics** (3-6 par topic): Détails spécifiques avec contenu réel
4. **Leafs** (2-4 par subtopic): Informations précises extraites

## TYPES DE NŒUDS
- `root`: Centre (1 seul)
- `topic`: Thème principal
- `subtopic`: Sous-thème
- `idea`: Idée/proposition
- `action`: Tâche à faire
- `question`: Question posée
- `decision`: Décision prise
- `person`: Personne citée
- `date`: Date/échéance
- `location`: Lieu

## RÈGLES CRITIQUES

1. **PRÉCISION**: Utilise le vocabulaire EXACT de la transcription
2. **RICHESSE**: Minimum 20-30 nœuds pour une transcription moyenne
3. **CITATIONS**: Reprends des extraits textuels quand pertinent
4. **EXHAUSTIVITÉ**: N'omets aucune info importante
5. **LABELS CLAIRS**: Max 8 mots mais INFORMATIFS (pas vagues)
6. **DESCRIPTIONS**: Ajoute des détails dans le champ description
7. **SOURCE TEXT**: Chaque nœud DOIT contenir un champ "sourceText" avec le PASSAGE EXACT copié-collé mot pour mot de la transcription originale correspondant à ce nœud. C'est CRITIQUE pour permettre la navigation entre la mindmap et le texte source.

## FORMAT JSON
{
  "title": "Titre précis et descriptif",
  "summary": "Résumé factuel en 2 phrases",
  "root": {
    "id": "root",
    "label": "TITRE CENTRAL PRÉCIS",
    "description": "Contexte de la discussion",
    "sourceText": "passage exact copié de la transcription",
    "type": "root",
    "tags": [],
    "priority": 5,
    "children": [
      {
        "id": "topic_1",
        "label": "Thème avec mots-clés",
        "description": "Explication détaillée",
        "sourceText": "extrait textuel exact de la transcription",
        "type": "topic",
        "tags": ["important"],
        "priority": 4,
        "children": [...]
      }
    ]
  }
}

## INTERDITS
- Labels génériques ("Discussion", "Thème 1", "Divers")
- Mind map avec moins de 15 nœuds
- Informations inventées non présentes dans le texte
- Résumés trop vagues
- Nœuds sans sourceText (sauf la racine si le sujet est implicite)''';

  // ---------------------------------------------------------------------------
  // Gemini — Configuration (gratuit)
  // ---------------------------------------------------------------------------
  static const String _geminiApiKey = 'AIzaSyC4JXkfK5lEDG89DzdQV_REgzL7fQ7odF8';
  static const String _geminiModel = 'gemini-2.5-flash';
  static String get _geminiUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_geminiApiKey';

  // ---------------------------------------------------------------------------
  // Prompt simplifié pour Gemini (gratuit)
  // ---------------------------------------------------------------------------
  static const String _geminiSystemPrompt =
      '''Tu es un expert en synthèse visuelle.
Analyse la transcription et crée une mind map structurée en JSON.

## STRUCTURE
1. **Root**: Titre du sujet
2. **Topics** (3-5 branches): Thèmes abordés
3. **Subtopics** (2-4 par topic): Détails
4. **Leafs** (1-3 par subtopic): Informations précises

## TYPES DE NŒUDS
root, topic, subtopic, idea, action, question, decision, person, date, location

## FORMAT JSON STRICT
{
  "title": "Titre",
  "summary": "Résumé en 1-2 phrases",
  "root": {
    "id": "root",
    "label": "TITRE",
    "description": "Contexte",
    "type": "root",
    "tags": [],
    "priority": 5,
    "children": [
      {
        "id": "topic_1",
        "label": "Thème",
        "description": "Détail",
        "type": "topic",
        "tags": [],
        "priority": 3,
        "children": [...]
      }
    ]
  }
}

## RÈGLES
- Vocabulaire EXACT de la transcription
- Minimum 10 nœuds
- Labels INFORMATIFS (pas vagues)
- Réponds UNIQUEMENT avec le JSON, rien d'autre''';

  // ---------------------------------------------------------------------------
  // API Publique
  // ---------------------------------------------------------------------------

  /// Génère une mind map avec le moteur choisi (défaut: Claude)
  Future<MindMapResult> generateFromTranscription(
    Transcription transcription, {
    MindMapEngine engine = MindMapEngine.claude,
  }) async {
    if (transcription.content.trim().isEmpty) {
      return MindMapResult.error('La transcription est vide.');
    }

    switch (engine) {
      case MindMapEngine.claude:
        return _generateWithClaude(transcription);
      case MindMapEngine.gemini:
        return _generateWithGemini(transcription);
    }
  }

  /// Génère une mind map depuis du texte brut
  Future<MindMapResult> generateFromText(
    String text, {
    String? title,
    MindMapEngine engine = MindMapEngine.claude,
  }) async {
    final transcription = Transcription.create(
      content: text,
      title: title ?? 'Analyse de texte',
    );
    return generateFromTranscription(transcription, engine: engine);
  }

  // ---------------------------------------------------------------------------
  // Claude (Premium) — Mind map riche avec sourceText
  // ---------------------------------------------------------------------------
  Future<MindMapResult> _generateWithClaude(Transcription transcription) async {
    if (!_claude.isConfigured) {
      return MindMapResult.error('Clé API Claude non configurée.');
    }

    debugPrint(
      '🧠 MindMap [Claude Premium]: Génération pour "${transcription.title}"...',
    );

    final userPrompt =
        '''Analyse cette transcription et génère une mind map structurée.

## TRANSCRIPTION

Titre: ${transcription.title}
Date: ${transcription.formattedDate}

---
${transcription.content}
---

Génère la mind map en JSON selon le format spécifié.''';

    try {
      final response = await _claude.generateJson(
        prompt: userPrompt,
        systemPrompt: _systemPrompt,
        maxTokens: 4096,
      );

      if (!response.success) {
        return MindMapResult.error(response.error ?? 'Erreur inconnue');
      }

      if (response.content == null || response.content!.isEmpty) {
        return MindMapResult.error('Réponse vide de Claude');
      }

      final jsonData = _parseJsonResponse(response.content!);
      if (jsonData == null) {
        return MindMapResult.error('Impossible de parser la réponse JSON');
      }

      final mindMap = MindMap(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: jsonData['title'] as String? ?? transcription.title,
        sourceTranscriptionId: transcription.id,
        createdAt: DateTime.now(),
        root: MindMapNode.fromJson(jsonData['root'] as Map<String, dynamic>),
        metadata: {
          'summary': jsonData['summary'],
          'engine': 'claude',
          'inputTokens': response.inputTokens,
          'outputTokens': response.outputTokens,
        },
      );

      debugPrint(
        '✅ MindMap [Claude]: ${mindMap.totalNodes} nœuds, profondeur ${mindMap.maxDepth}',
      );
      return MindMapResult.success(mindMap);
    } catch (e) {
      debugPrint('❌ MindMap [Claude]: $e');
      return MindMapResult.error('Erreur Claude: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Gemini (Gratuit) — Mind map plus simple, sans sourceText
  // ---------------------------------------------------------------------------
  Future<MindMapResult> _generateWithGemini(Transcription transcription) async {
    debugPrint(
      '🧠 MindMap [Gemini Gratuit]: Génération pour "${transcription.title}"...',
    );

    final userPrompt =
        '''Analyse cette transcription et génère une mind map structurée en JSON.

Titre: ${transcription.title}
Date: ${transcription.formattedDate}

---
${transcription.content}
---

Réponds UNIQUEMENT avec le JSON, sans texte avant ni après.''';

    try {
      final response = await _httpClient
          .post(
            Uri.parse(_geminiUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'system_instruction': {
                'parts': [
                  {'text': _geminiSystemPrompt},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': userPrompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.4,
                'maxOutputTokens': 4096,
                'topP': 0.9,
              },
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          return MindMapResult.error('Réponse vide de Gemini');
        }

        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) {
          return MindMapResult.error('Contenu vide de Gemini');
        }

        final rawText = (parts[0]['text'] as String).trim();
        final jsonData = _parseJsonResponse(rawText);
        if (jsonData == null) {
          return MindMapResult.error('Impossible de parser le JSON Gemini');
        }

        final mindMap = MindMap(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: jsonData['title'] as String? ?? transcription.title,
          sourceTranscriptionId: transcription.id,
          createdAt: DateTime.now(),
          root: MindMapNode.fromJson(jsonData['root'] as Map<String, dynamic>),
          metadata: {'summary': jsonData['summary'], 'engine': 'gemini'},
        );

        debugPrint(
          '✅ MindMap [Gemini]: ${mindMap.totalNodes} nœuds, profondeur ${mindMap.maxDepth}',
        );
        return MindMapResult.success(mindMap);
      } else if (response.statusCode == 429) {
        return MindMapResult.error(
          'Rate limit Gemini atteint. Réessayez dans quelques secondes.',
        );
      } else {
        debugPrint(
          '❌ MindMap [Gemini] HTTP ${response.statusCode}: ${response.body}',
        );
        return MindMapResult.error('Erreur Gemini (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ MindMap [Gemini]: $e');
      return MindMapResult.error('Erreur Gemini: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _parseJsonResponse(String content) {
    try {
      // Nettoyer le contenu
      String cleaned = content.trim();

      // Supprimer les balises markdown si présentes
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }

      cleaned = cleaned.trim();

      // Parser le JSON
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ MindMap: Erreur parsing JSON - $e');
      debugPrint(
        'Contenu reçu: ${content.substring(0, content.length > 500 ? 500 : content.length)}...',
      );
      return null;
    }
  }
}

/// Résultat de génération de mind map
class MindMapResult {
  final bool success;
  final MindMap? mindMap;
  final String? error;

  MindMapResult._({required this.success, this.mindMap, this.error});

  factory MindMapResult.success(MindMap mindMap) {
    return MindMapResult._(success: true, mindMap: mindMap);
  }

  factory MindMapResult.error(String message) {
    return MindMapResult._(success: false, error: message);
  }
}
