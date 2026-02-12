// =============================================================================
// NOTITIA — Service Mistral AI (appel direct à l'API cloud)
// Correction et amélioration des transcriptions vocales
// Aucun serveur Python nécessaire — appel HTTPS direct
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service Mistral AI pour améliorer les transcriptions
class MistralService {
  static MistralService? _instance;
  static MistralService get instance => _instance ??= MistralService._();

  MistralService._();

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  static const String _apiKey = 'Y2ZuTtCH0vJHlkZL2Y0MRoTmGpRsfZmT';
  static const String _model = 'mistral-small-latest';
  static const String _apiUrl = 'https://api.mistral.ai/v1/chat/completions';

  final http.Client _client = http.Client();

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

  /// Vérifie que l'API Mistral est accessible
  Future<bool> isAvailable() async {
    try {
      // Un petit appel rapide pour vérifier la clé
      final response = await _client
          .get(
            Uri.parse('https://api.mistral.ai/v1/models'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Mistral] API non accessible: $e');
      return false;
    }
  }

  /// Corrige/améliore un texte transcrit via Mistral AI
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

    // Pas la peine d'appeler Mistral pour moins de 3 mots
    if (text.trim().split(' ').length < 3) return text;

    try {
      final response = await _client
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': _getSystemPrompt(level)},
                {
                  'role': 'user',
                  'content': 'Corrige cette transcription audio:\n\n$text',
                },
              ],
              'temperature': 0.1,
              'max_tokens': 2048,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          final corrected = message?['content'] as String?;
          if (corrected != null && corrected.trim().isNotEmpty) {
            debugPrint('[Mistral] Correction appliquée');
            return corrected.trim();
          }
        }
      } else {
        debugPrint(
          '[Mistral] Erreur API ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[Mistral] Erreur: $e');
    }

    // En cas d'erreur, on retourne l'original — pas de perte de données
    return text;
  }

  /// Corrige un segment partiel (pour correction en temps réel des phrases
  /// finales au fur et à mesure)
  Future<String> correctSegment(String segment) async {
    return correctTranscription(segment, level: CorrectionLevel.medium);
  }

  void dispose() {
    _client.close();
  }
}

/// Niveau de correction Mistral
enum CorrectionLevel {
  /// Orthographe + ponctuation + grammaire
  medium,

  /// + restructuration + suppression hésitations
  full,
}
