// =============================================================================
// NOTITIA — Service Génération Mind Map
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/mind_map.dart';
import '../models/transcription.dart';
import 'claude_service.dart';

/// Service de génération de Mind Maps à partir de transcriptions
class MindMapService {
  static final MindMapService _instance = MindMapService._internal();
  factory MindMapService() => _instance;
  MindMapService._internal();
  
  final ClaudeService _claude = ClaudeService();
  
  // ---------------------------------------------------------------------------
  // Prompt System Expert pour la génération de Mind Maps
  // ---------------------------------------------------------------------------
  
  static const String _systemPrompt = '''Tu es un expert en extraction d'informations et synthèse visuelle.
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

## FORMAT JSON
{
  "title": "Titre précis et descriptif",
  "summary": "Résumé factuel en 2 phrases",
  "root": {
    "id": "root",
    "label": "TITRE CENTRAL PRÉCIS",
    "description": "Contexte de la discussion",
    "type": "root",
    "tags": [],
    "priority": 5,
    "children": [
      {
        "id": "topic_1",
        "label": "Thème avec mots-clés",
        "description": "Explication détaillée",
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
- Résumés trop vagues''';

  // ---------------------------------------------------------------------------
  // API Publique
  // ---------------------------------------------------------------------------
  
  /// Génère une mind map à partir d'une transcription
  Future<MindMapResult> generateFromTranscription(Transcription transcription) async {
    if (!_claude.isConfigured) {
      return MindMapResult.error('Clé API Claude non configurée. Configurez-la dans les paramètres.');
    }
    
    if (transcription.content.trim().isEmpty) {
      return MindMapResult.error('La transcription est vide.');
    }
    
    debugPrint('🧠 MindMap: Génération en cours pour "${transcription.title}"...');
    
    final userPrompt = '''Analyse cette transcription et génère une mind map structurée.

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
      
      // Parser le JSON
      final jsonData = _parseJsonResponse(response.content!);
      if (jsonData == null) {
        return MindMapResult.error('Impossible de parser la réponse JSON');
      }
      
      // Construire la MindMap
      final mindMap = MindMap(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: jsonData['title'] as String? ?? transcription.title,
        sourceTranscriptionId: transcription.id,
        createdAt: DateTime.now(),
        root: MindMapNode.fromJson(jsonData['root'] as Map<String, dynamic>),
        metadata: {
          'summary': jsonData['summary'],
          'inputTokens': response.inputTokens,
          'outputTokens': response.outputTokens,
        },
      );
      
      debugPrint('✅ MindMap: Générée avec succès (${mindMap.totalNodes} nœuds, profondeur ${mindMap.maxDepth})');
      
      return MindMapResult.success(mindMap);
      
    } catch (e) {
      debugPrint('❌ MindMap: Erreur - $e');
      return MindMapResult.error('Erreur lors de la génération: $e');
    }
  }
  
  /// Génère une mind map à partir de texte brut
  Future<MindMapResult> generateFromText(String text, {String? title}) async {
    final transcription = Transcription.create(
      content: text,
      title: title ?? 'Analyse de texte',
    );
    return generateFromTranscription(transcription);
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
      debugPrint('Contenu reçu: ${content.substring(0, content.length > 500 ? 500 : content.length)}...');
      return null;
    }
  }
}

/// Résultat de génération de mind map
class MindMapResult {
  final bool success;
  final MindMap? mindMap;
  final String? error;
  
  MindMapResult._({
    required this.success,
    this.mindMap,
    this.error,
  });
  
  factory MindMapResult.success(MindMap mindMap) {
    return MindMapResult._(success: true, mindMap: mindMap);
  }
  
  factory MindMapResult.error(String message) {
    return MindMapResult._(success: false, error: message);
  }
}
