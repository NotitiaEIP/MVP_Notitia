// =============================================================================
// NOTITIA — Client IA unique (API compatible OpenAI)
//
// Seul point de l'app qui parle HTTP à un modèle. Il cible la passerelle
// Notitia (LiteLLM) mais fonctionne avec toute API compatible OpenAI.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

/// Erreur renvoyée par la passerelle IA.
class AiException implements Exception {
  final String message;
  final int? statusCode;

  AiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'AiException${statusCode != null ? ' ($statusCode)' : ''}: $message';
}

/// Réponse texte d'un modèle.
class AiChatResult {
  final String content;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;

  AiChatResult({
    required this.content,
    this.model,
    this.inputTokens,
    this.outputTokens,
  });
}

/// Résultat de recherche web.
class AiSearchResult {
  final String title;
  final String url;
  final String snippet;

  AiSearchResult({required this.title, required this.url, this.snippet = ''});
}

class AiClient {
  AiClient({http.Client? httpClient, String? baseUrl, String? apiKey})
    : _http = httpClient ?? http.Client(),
      _baseUrl = (baseUrl ?? AiConfig.baseUrl).replaceAll(RegExp(r'/+$'), ''),
      _apiKey = apiKey ?? AiConfig.apiKey;

  static AiClient? _instance;
  static AiClient get instance => _instance ??= AiClient();

  final http.Client _http;
  final String _baseUrl;
  final String _apiKey;

  static const int _maxAttempts = 3;

  bool get isConfigured => _apiKey.isNotEmpty;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ---------------------------------------------------------------------------
  // CHAT
  // ---------------------------------------------------------------------------

  /// Envoie une conversation au modèle [model].
  ///
  /// [messages] — liste de `{'role': 'user'|'assistant', 'content': ...}`
  /// [jsonMode] — force une réponse JSON valide (response_format json_object)
  Future<AiChatResult> chat({
    required String model,
    required List<Map<String, String>> messages,
    String? system,
    double temperature = 0.3,
    int maxTokens = 1024,
    bool jsonMode = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        if (system != null && system.isNotEmpty)
          {'role': 'system', 'content': system},
        ...messages,
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    final data = await _post('/v1/chat/completions', body, timeout);

    final choices = data['choices'] as List<dynamic>?;
    final message = choices != null && choices.isNotEmpty
        ? (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>?
        : null;
    final raw = message?['content'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      throw AiException('Réponse vide du modèle $model');
    }

    final usage = data['usage'] as Map<String, dynamic>?;
    return AiChatResult(
      content: stripReasoning(raw),
      model: data['model'] as String?,
      inputTokens: usage?['prompt_tokens'] as int?,
      outputTokens: usage?['completion_tokens'] as int?,
    );
  }

  /// Raccourci : un prompt utilisateur unique, renvoie le texte.
  Future<String> complete({
    required String model,
    required String prompt,
    String? system,
    double temperature = 0.3,
    int maxTokens = 1024,
    bool jsonMode = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await chat(
      model: model,
      system: system,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      temperature: temperature,
      maxTokens: maxTokens,
      jsonMode: jsonMode,
      timeout: timeout,
    );
    return result.content;
  }

  // ---------------------------------------------------------------------------
  // EMBEDDINGS
  // ---------------------------------------------------------------------------

  /// Vectorise [inputs] (un vecteur par texte, dans le même ordre).
  Future<List<List<double>>> embed(
    List<String> inputs, {
    String? model,
    int? dimensions,
  }) async {
    if (inputs.isEmpty) return [];
    final dims = dimensions ?? AiConfig.embedDimensions;
    final data = await _post('/v1/embeddings', {
      'model': model ?? AiConfig.embedModel,
      'input': inputs,
      if (dims > 0) 'dimensions': dims,
    }, const Duration(seconds: 30));

    final items =
        (data['data'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) =>
                (a['index'] as int? ?? 0).compareTo(b['index'] as int? ?? 0),
          );
    if (items.length != inputs.length) {
      throw AiException(
        '${items.length} embeddings reçus pour ${inputs.length} textes',
      );
    }
    return items
        .map(
          (e) => (e['embedding'] as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList(),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // RECHERCHE WEB
  // ---------------------------------------------------------------------------

  /// Recherche web via l'outil [AiConfig.searchTool] de la passerelle.
  /// Renvoie une liste vide si la recherche est désactivée ou échoue.
  Future<List<AiSearchResult>> search(
    String query, {
    int maxResults = 2,
  }) async {
    if (AiConfig.searchTool.isEmpty || query.trim().isEmpty) return [];
    try {
      final data = await _post('/v1/search/${AiConfig.searchTool}', {
        'query': query,
        'max_results': maxResults,
      }, const Duration(seconds: 15));
      return (data['results'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .where((r) => (r['url'] as String? ?? '').startsWith('http'))
          .map(
            (r) => AiSearchResult(
              title: r['title'] as String? ?? query,
              url: r['url'] as String,
              snippet: r['snippet'] as String? ?? '',
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[AI Search] ✗ "$query": $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // SANTÉ
  // ---------------------------------------------------------------------------

  /// Vérifie que la passerelle répond et que la clé est valide.
  Future<bool> isAvailable() async {
    if (!isConfigured) return false;
    try {
      final response = await _http
          .get(Uri.parse('$_baseUrl/v1/models'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[AI] Passerelle injoignable: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    if (!isConfigured) {
      throw AiException(
        'AI_API_KEY non configurée (flutter run --dart-define-from-file=env/ai.json)',
      );
    }

    final uri = Uri.parse('$_baseUrl$path');
    AiException? lastError;

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _http
            .post(uri, headers: _headers, body: json.encode(body))
            .timeout(timeout);

        if (response.statusCode == 200) {
          return json.decode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;
        }

        lastError = AiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
        // 429 (rate limit / budget) et 5xx : on réessaie. Le reste est définitif.
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        if (!retryable) break;
      } on TimeoutException {
        lastError = AiException('Délai dépassé (${timeout.inSeconds}s)');
      } catch (e) {
        lastError = AiException('Erreur réseau: $e');
      }

      if (attempt < _maxAttempts) {
        debugPrint(
          '[AI] $path tentative $attempt échouée: ${lastError.message}',
        );
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    debugPrint('[AI] ✗ $path: $lastError');
    throw lastError!;
  }

  static String _errorMessage(http.Response response) {
    try {
      final data = json.decode(utf8.decode(response.bodyBytes));
      final error = (data as Map<String, dynamic>)['error'];
      if (error is Map<String, dynamic>) {
        return (error['message'] ?? error.toString()).toString();
      }
      if (error != null) return error.toString();
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  /// Retire les blocs de raisonnement que certains modèles open source
  /// renvoient dans le contenu (`<think>…</think>`).
  @visibleForTesting
  static String stripReasoning(String text) => text
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
      .trim();

  /// Extrait l'objet JSON d'une réponse (tolère ```json … ``` et du texte autour).
  static String extractJsonObject(String text) {
    var cleaned = stripReasoning(text);
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
    if (fence != null) cleaned = fence.group(1)!.trim();
    final start = cleaned.indexOf('{');
    if (start > 0) cleaned = cleaned.substring(start);
    return cleaned.trim();
  }

  void dispose() => _http.close();
}
