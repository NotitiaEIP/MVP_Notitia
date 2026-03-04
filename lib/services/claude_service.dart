// =============================================================================
// NOTITIA — Service Claude API (Anthropic)
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Configuration Claude
class ClaudeConfig {
  /// Clé API Anthropic - METTEZ VOTRE CLÉ ICI
  static const String apiKey = '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';
  
  /// Modèle par défaut (claude-3-5-sonnet est optimal pour cette tâche)
  static const String defaultModel = 'claude-sonnet-4-20250514';
  
  /// URL de l'API
  static const String apiUrl = 'https://api.anthropic.com/v1/messages';
  
  /// Version de l'API
  static const String apiVersion = '2023-06-01';
}

/// Réponse de Claude
class ClaudeResponse {
  final bool success;
  final String? content;
  final String? error;
  final int? inputTokens;
  final int? outputTokens;
  
  ClaudeResponse({
    required this.success,
    this.content,
    this.error,
    this.inputTokens,
    this.outputTokens,
  });
}

/// Service pour interagir avec Claude API
class ClaudeService {
  static final ClaudeService _instance = ClaudeService._internal();
  factory ClaudeService() => _instance;
  ClaudeService._internal();
  
  /// Vérifie si l'API est configurée
  bool get isConfigured => 
      ClaudeConfig.apiKey.isNotEmpty && 
      ClaudeConfig.apiKey != 'VOTRE_CLE_API_CLAUDE_ICI';
  
  /// Envoie un message à Claude
  Future<ClaudeResponse> sendMessage({
    required String prompt,
    String? systemPrompt,
    String model = ClaudeConfig.defaultModel,
    int maxTokens = 4096,
    double temperature = 0.7,
  }) async {
    if (!isConfigured) {
      return ClaudeResponse(
        success: false,
        error: 'Clé API Claude non configurée',
      );
    }
    
    try {
      final messages = [
        {
          'role': 'user',
          'content': prompt,
        }
      ];
      
      final body = <String, dynamic>{
        'model': model,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'messages': messages,
      };
      
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        body['system'] = systemPrompt;
      }
      
      debugPrint('🤖 Claude: Envoi requête...');
      
      final response = await http.post(
        Uri.parse(ClaudeConfig.apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ClaudeConfig.apiKey,
          'anthropic-version': ClaudeConfig.apiVersion,
        },
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>?;
        final usage = data['usage'] as Map<String, dynamic>?;
        
        String? text;
        if (content != null && content.isNotEmpty) {
          final firstBlock = content[0] as Map<String, dynamic>;
          text = firstBlock['text'] as String?;
        }
        
        debugPrint('✅ Claude: Réponse reçue (${usage?['output_tokens']} tokens)');
        
        return ClaudeResponse(
          success: true,
          content: text,
          inputTokens: usage?['input_tokens'] as int?,
          outputTokens: usage?['output_tokens'] as int?,
        );
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMsg = errorData['error']?['message'] ?? 'Erreur inconnue';
        
        debugPrint('❌ Claude: Erreur ${response.statusCode} - $errorMsg');
        
        return ClaudeResponse(
          success: false,
          error: 'Erreur API (${response.statusCode}): $errorMsg',
        );
      }
    } catch (e) {
      debugPrint('❌ Claude: Exception - $e');
      return ClaudeResponse(
        success: false,
        error: 'Erreur de connexion: $e',
      );
    }
  }
  
  /// Génère du JSON structuré
  Future<ClaudeResponse> generateJson({
    required String prompt,
    required String systemPrompt,
    int maxTokens = 4096,
  }) async {
    // Ajoute des instructions pour forcer le JSON
    final enhancedSystem = '''$systemPrompt

IMPORTANT: Tu dois répondre UNIQUEMENT avec du JSON valide, sans texte avant ou après.
Pas de ```json, pas de commentaires, juste le JSON brut.''';
    
    return sendMessage(
      prompt: prompt,
      systemPrompt: enhancedSystem,
      maxTokens: maxTokens,
      temperature: 0.5, // Plus déterministe pour le JSON
    );
  }
}
