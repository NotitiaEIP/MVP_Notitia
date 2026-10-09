// =============================================================================
// NOTITIA — Configuration IA
//
// Aucune clé n'est écrite dans le code : tout est injecté au build via
//   flutter run --dart-define-from-file=env/ai.json
// (voir env/ai.example.json et infra/ai-gateway/README.md).
//
// Par défaut l'app parle à la passerelle Notitia (LiteLLM), qui expose des
// alias de modèles open source. On peut aussi pointer directement vers
// n'importe quelle API compatible OpenAI (DeepInfra, Scaleway, Ollama…) en
// changeant AI_BASE_URL et les noms de modèles.
// =============================================================================

class AiConfig {
  AiConfig._();

  /// URL de la passerelle (sans /v1). Ex : http://192.168.1.20:4000
  static const String baseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'http://localhost:4000',
  );

  /// Clé virtuelle de la passerelle (plafonnée côté serveur).
  static const String apiKey = String.fromEnvironment('AI_API_KEY');

  /// Correction de transcription + titres
  static const String fastModel = String.fromEnvironment(
    'AI_MODEL_FAST',
    defaultValue: 'notitia-fast',
  );

  /// Assistant RAG, résumé enrichi, mind map standard
  static const String smartModel = String.fromEnvironment(
    'AI_MODEL_SMART',
    defaultValue: 'notitia-smart',
  );

  /// Mind map premium
  static const String premiumModel = String.fromEnvironment(
    'AI_MODEL_PREMIUM',
    defaultValue: 'notitia-premium',
  );

  /// Embeddings pour la recherche sémantique
  static const String embedModel = String.fromEnvironment(
    'AI_MODEL_EMBED',
    defaultValue: 'notitia-embed',
  );

  /// Dimensions demandées au modèle d'embedding (0 = valeur par défaut du modèle).
  static const int embedDimensions = int.fromEnvironment(
    'AI_EMBED_DIMENSIONS',
    defaultValue: 1024,
  );

  /// Nom de l'outil de recherche web configuré dans la passerelle (vide = désactivé).
  static const String searchTool = String.fromEnvironment(
    'AI_SEARCH_TOOL',
    defaultValue: 'brave-search',
  );

  /// Identifie les vecteurs stockés : si le modèle change, l'index local est
  /// reconstruit automatiquement.
  static String get embeddingSignature => '$embedModel@$embedDimensions';

  static bool get isConfigured => apiKey.isNotEmpty;
}

/// Clés des autres services, injectées de la même façon.
class ServiceKeys {
  ServiceKeys._();

  static const String deepgram = String.fromEnvironment('DEEPGRAM_API_KEY');
}
