// =============================================================================
// NOTITIA — Service de correction des transcriptions
// Correction, amélioration et titres via le modèle "fast" de la passerelle IA
// (Mistral Small, open source)
// =============================================================================

import 'package:flutter/foundation.dart';

import '../config/ai_config.dart';
import '../models/transcription.dart';
import 'ai_client.dart';
import 'storage_service.dart';

/// Service IA pour améliorer les transcriptions
class CorrectionService {
  static CorrectionService? _instance;
  static CorrectionService get instance => _instance ??= CorrectionService._();

  CorrectionService._();

  final AiClient _ai = AiClient.instance;

  // ---------------------------------------------------------------------------
  // Prompts système pour chaque niveau de correction
  // ---------------------------------------------------------------------------
  static const String _systemPromptMedium =
      '''Tu es un assistant expert en correction de transcriptions audio en français.

RÈGLES:
1. Corrige les fautes d'orthographe
2. Ajoute la ponctuation appropriée (points, virgules, points d'interrogation)
3. Corrige les erreurs de grammaire évidentes
4. Si un mot semble mal transcrit, devine le mot correct selon le contexte
5. Garde le sens et le style de l'original
6. Réponds UNIQUEMENT avec le texte corrigé, sans explication ni commentaire

INDICES COURANTS D'ERREURS DE TRANSCRIPTION:
- Homophones confondus (a/à, et/est, ou/où, ce/se, son/sont)
- Mots coupés ou fusionnés
- Noms propres mal orthographiés
- Chiffres mal transcrits
- Termes techniques déformés
- Hésitations retranscrites (euh, hum)''';

  static const String _systemPromptFull =
      '''Tu es un assistant expert en amélioration de transcriptions audio en français.

RÈGLES:
1. Corrige toutes les fautes d'orthographe et de grammaire
2. Ajoute une ponctuation correcte et naturelle
3. Restructure les phrases si elles sont confuses
4. Devine et corrige les mots mal transcrits selon le contexte
5. Améliore la clarté tout en préservant le sens original
6. Supprime les hésitations (euh, hum) et répétitions inutiles
7. Garde un style naturel et conversationnel
8. Réponds UNIQUEMENT avec le texte corrigé, sans explication ni commentaire

INDICES COURANTS D'ERREURS DE TRANSCRIPTION:
- Homophones confondus
- Mots coupés ou fusionnés
- Noms propres mal orthographiés
- Chiffres mal transcrits
- Termes techniques déformés''';

  /// Retourne le prompt système selon le niveau
  String _getSystemPrompt(CorrectionLevel level) {
    switch (level) {
      case CorrectionLevel.full:
        return _systemPromptFull;
      case CorrectionLevel.medium:
        return _systemPromptMedium;
    }
  }

  // ---------------------------------------------------------------------------
  // API publique
  // ---------------------------------------------------------------------------

  /// Vérifie que la passerelle IA est accessible
  Future<bool> isAvailable() => _ai.isAvailable();

  /// Corrige/améliore un texte transcrit
  ///
  /// [text] — le texte brut de la transcription
  /// [level] — niveau de correction (medium par défaut)
  ///
  /// Retourne le texte corrigé, ou le texte original si erreur.
  Future<String> correctTranscription(
    String text, {
    CorrectionLevel level = CorrectionLevel.medium,
  }) async {
    if (text.trim().isEmpty) return text;

    // Pas la peine d'appeler l'IA pour moins de 3 mots
    if (text.trim().split(' ').length < 3) return text;

    try {
      final corrected = await _ai.complete(
        model: AiConfig.fastModel,
        system: _getSystemPrompt(level),
        prompt: 'Corrige cette transcription audio:\n\n$text',
        temperature: 0.1,
        maxTokens: 2048,
        timeout: const Duration(seconds: 30),
      );
      debugPrint('[Correction] Correction appliquée');
      return corrected;
    } catch (e) {
      debugPrint('[Correction] Erreur: $e');
    }

    // En cas d'erreur, on retourne l'original — pas de perte de données
    return text;
  }

  /// Corrige un segment partiel (pour correction en temps réel des phrases
  /// finales au fur et à mesure)
  Future<String> correctSegment(String segment) async {
    return correctTranscription(segment, level: CorrectionLevel.medium);
  }

  // ---------------------------------------------------------------------------
  // Génération de titre automatique
  // ---------------------------------------------------------------------------

  static const String _titleSystemPrompt =
      '''Tu génères un titre court (5 mots max) pour une transcription audio.
RÈGLES:
- Réponds UNIQUEMENT avec le titre, sans guillemets ni ponctuation finale
- Le titre doit résumer le sujet principal
- Reste concis et descriptif
- Langue: identique au texte fourni''';

  /// Génère un titre court à partir du contenu d'une transcription.
  /// Retourne null en cas d'erreur (pour utiliser un titre par défaut).
  Future<String?> generateTitle(String content) async {
    if (content.trim().isEmpty) return null;

    // Prendre les 500 premiers caractères pour être rapide
    final excerpt = content.length > 500 ? content.substring(0, 500) : content;

    try {
      final title = await _ai.complete(
        model: AiConfig.fastModel,
        system: _titleSystemPrompt,
        prompt: 'Génère un titre pour cette transcription:\n\n$excerpt',
        temperature: 0.3,
        maxTokens: 30,
        timeout: const Duration(seconds: 10),
      );
      final cleaned = title.replaceAll(RegExp(r'''^["'«\s]+|["'»\s.]+$'''), '');
      if (cleaned.isNotEmpty) {
        debugPrint('[Correction] Titre généré: $cleaned');
        return cleaned;
      }
    } catch (e) {
      debugPrint('[Correction] Erreur génération titre: $e');
    }

    return null;
  }

  /// Génère un titre IA et met à jour la transcription en arrière-plan.
  /// Relit depuis le disque pour éviter les conflits de cache.
  static Future<void> updateTitleInBackground(
    Transcription transcription,
  ) async {
    try {
      final aiTitle = await instance.generateTitle(transcription.content);
      if (aiTitle != null && aiTitle.isNotEmpty) {
        // Relire les données fraîches depuis le disque
        StorageService.invalidateCache();
        final all = await StorageService.loadAll();
        final index = all.indexWhere((t) => t.id == transcription.id);
        if (index >= 0) {
          final fresh = all[index];
          final updated = fresh.copyWith(
            title: aiTitle,
            updatedAt: DateTime.now(),
          );
          await StorageService.save(updated);
          StorageService.invalidateCache();
          debugPrint('[Correction] Titre mis à jour en arrière-plan: $aiTitle');
        }
      }
    } catch (e) {
      debugPrint('[Correction] Erreur mise à jour titre: $e');
    }
  }
}

/// Niveau de correction
enum CorrectionLevel {
  /// Orthographe + ponctuation + grammaire
  medium,

  /// + restructuration + suppression hésitations
  full,
}
