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
- Nœuds sans sourceText (sauf la racine si le sujet est implicite)
- Caractères spéciaux de contrôle (tabs, retours chariot) dans les strings JSON''';

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
- Réponds UNIQUEMENT avec le JSON, rien d'autre
- PAS de caractères de contrôle (tabs, retours chariot) dans les strings''';

  // ---------------------------------------------------------------------------
  // API Publique
  // ---------------------------------------------------------------------------

  /// Génère une mind map avec le moteur choisi (défaut: Claude)
  Future<MindMapResult> generateFromTranscription(
    Transcription transcription, {
    MindMapEngine engine = MindMapEngine.claude,
  }) async {
    return generateFromTranscriptions([transcription], engine: engine);
  }

  /// Génère une mind map à partir de PLUSIEURS transcriptions
  Future<MindMapResult> generateFromTranscriptions(
    List<Transcription> transcriptions, {
    MindMapEngine engine = MindMapEngine.claude,
  }) async {
    if (transcriptions.isEmpty) {
      return MindMapResult.error('Aucune transcription fournie.');
    }
    final nonEmpty = transcriptions
        .where((t) => t.content.trim().isNotEmpty)
        .toList();
    if (nonEmpty.isEmpty) {
      return MindMapResult.error('Toutes les transcriptions sont vides.');
    }

    switch (engine) {
      case MindMapEngine.claude:
        return _generateWithClaude(nonEmpty);
      case MindMapEngine.gemini:
        return _generateWithGemini(nonEmpty);
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
  Future<MindMapResult> _generateWithClaude(
    List<Transcription> transcriptions,
  ) async {
    if (!_claude.isConfigured) {
      return MindMapResult.error('Clé API Claude non configurée.');
    }

    final titles = transcriptions.map((t) => t.title).join(', ');
    debugPrint(
      '🧠 MindMap [Claude Premium]: Génération pour $titles (${transcriptions.length} source(s))...',
    );

    final transcriptionBlocks = transcriptions
        .map(
          (t) =>
              '''
### ${t.title} (${t.formattedDate})
---
${t.content}
---''',
        )
        .join('\n\n');

    final plural = transcriptions.length > 1;
    final userPrompt =
        '''Analyse ${plural ? 'ces ${transcriptions.length} transcriptions' : 'cette transcription'} et génère une mind map structurée${plural ? ' qui synthétise l\'ensemble des sources' : ''}.

## ${plural ? 'TRANSCRIPTIONS' : 'TRANSCRIPTION'}
$transcriptionBlocks

Génère la mind map en JSON selon le format spécifié.${plural ? ' Regroupe les thèmes communs et mentionne les différences entre les sources.' : ''}''';

    try {
      final response = await _claude.generateJson(
        prompt: userPrompt,
        systemPrompt: _systemPrompt,
        maxTokens: 8192,
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
        title: jsonData['title'] as String? ?? transcriptions.first.title,
        sourceTranscriptionIds: transcriptions.map((t) => t.id).toList(),
        createdAt: DateTime.now(),
        root: MindMapNode.fromJson(jsonData['root'] as Map<String, dynamic>),
        metadata: {
          'summary': jsonData['summary'],
          'engine': 'claude',
          'inputTokens': response.inputTokens,
          'outputTokens': response.outputTokens,
          'sourceCount': transcriptions.length,
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
  Future<MindMapResult> _generateWithGemini(
    List<Transcription> transcriptions,
  ) async {
    final titles = transcriptions.map((t) => t.title).join(', ');
    debugPrint(
      '🧠 MindMap [Gemini Gratuit]: Génération pour $titles (${transcriptions.length} source(s))...',
    );

    final transcriptionBlocks = transcriptions
        .map(
          (t) =>
              '''
Titre: ${t.title}
Date: ${t.formattedDate}
---
${t.content}
---''',
        )
        .join('\n\n');

    final plural = transcriptions.length > 1;
    final userPrompt =
        '''Analyse ${plural ? 'ces ${transcriptions.length} transcriptions' : 'cette transcription'} et génère une mind map structurée en JSON.
$transcriptionBlocks

Réponds UNIQUEMENT avec le JSON, sans texte avant ni après.${plural ? ' Regroupe les thèmes communs.' : ''}''';

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
                'maxOutputTokens': 8192,
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
          title: jsonData['title'] as String? ?? transcriptions.first.title,
          sourceTranscriptionIds: transcriptions.map((t) => t.id).toList(),
          createdAt: DateTime.now(),
          root: MindMapNode.fromJson(jsonData['root'] as Map<String, dynamic>),
          metadata: {
            'summary': jsonData['summary'],
            'engine': 'gemini',
            'sourceCount': transcriptions.length,
          },
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

      // Sanitiser les caractères de contrôle dans les valeurs JSON
      // (tabs, retours chariot, etc. que l'IA peut insérer dans sourceText)
      cleaned = _sanitizeJsonControlChars(cleaned);

      // Tenter le parsing
      try {
        return jsonDecode(cleaned) as Map<String, dynamic>;
      } on FormatException catch (e) {
        // Si JSON tronqué ("Unexpected end of input"), tenter de réparer
        if (e.toString().contains('end of input') ||
            e.toString().contains('Unexpected')) {
          debugPrint('⚠️ MindMap: JSON tronqué, tentative de réparation...');
          final repaired = _repairTruncatedJson(cleaned);
          if (repaired != null) {
            return jsonDecode(repaired) as Map<String, dynamic>;
          }
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('⚠️ MindMap: Erreur parsing JSON - $e');
      debugPrint(
        'Contenu reçu: ${content.substring(0, content.length > 500 ? 500 : content.length)}...',
      );
      return null;
    }
  }

  /// Remplace les caractères de contrôle (tab, CR, etc.) DANS les strings JSON
  /// par des espaces, sans casser la structure JSON.
  String _sanitizeJsonControlChars(String jsonStr) {
    final buf = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < jsonStr.length; i++) {
      final char = jsonStr[i];
      final code = jsonStr.codeUnitAt(i);

      if (escaped) {
        buf.write(char);
        escaped = false;
        continue;
      }

      if (char == '\\' && inString) {
        buf.write(char);
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        buf.write(char);
        continue;
      }

      if (inString && code < 0x20) {
        // Caractère de contrôle dans une string → remplacer par espace
        buf.write(' ');
      } else {
        buf.write(char);
      }
    }
    return buf.toString();
  }

  /// Tente de fermer un JSON tronqué en trouvant le dernier point de coupure
  /// valide (après un } ou ] complet) puis en fermant les délimiteurs ouverts.
  String? _repairTruncatedJson(String json) {
    try {
      // Stratégie : trouver la dernière position où on a un } ou ] valide
      // (pas dans une string), couper là, puis fermer ce qui reste ouvert.

      // D'abord, trouver tous les indices de } et ] hors string
      final closingPositions = <int>[];
      bool inStr = false;
      bool esc = false;

      for (int i = 0; i < json.length; i++) {
        final c = json[i];
        if (esc) {
          esc = false;
          continue;
        }
        if (c == '\\' && inStr) {
          esc = true;
          continue;
        }
        if (c == '"') {
          inStr = !inStr;
          continue;
        }
        if (inStr) continue;
        if (c == '}' || c == ']') {
          closingPositions.add(i);
        }
      }

      // Tenter depuis le point de coupure le plus loin possible
      for (int attempt = closingPositions.length - 1; attempt >= 0; attempt--) {
        final cutIndex = closingPositions[attempt] + 1;
        String repaired = json.substring(0, cutIndex);

        // Compter les délimiteurs ouverts restants
        int braces = 0;
        int brackets = 0;
        inStr = false;
        esc = false;

        for (int i = 0; i < repaired.length; i++) {
          final c = repaired[i];
          if (esc) {
            esc = false;
            continue;
          }
          if (c == '\\' && inStr) {
            esc = true;
            continue;
          }
          if (c == '"') {
            inStr = !inStr;
            continue;
          }
          if (inStr) continue;
          if (c == '{') braces++;
          if (c == '}') braces--;
          if (c == '[') brackets++;
          if (c == ']') brackets--;
        }

        // Si on est dans une string non fermée, skip
        if (inStr) continue;

        // Fermer les délimiteurs ouverts (brackets d'abord, puis braces)
        for (int i = 0; i < brackets; i++) {
          repaired += ']';
        }
        for (int i = 0; i < braces; i++) {
          repaired += '}';
        }

        // Tenter le parsing
        try {
          jsonDecode(repaired);
          debugPrint(
            '✅ MindMap: JSON réparé (coupé à position $cutIndex/${json.length})',
          );
          return repaired;
        } catch (_) {
          // Ce point de coupure ne marche pas, essayer le précédent
          continue;
        }
      }

      debugPrint('❌ MindMap: Aucun point de coupure valide trouvé');
      return null;
    } catch (e) {
      debugPrint('❌ MindMap: Impossible de réparer le JSON tronqué - $e');
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
