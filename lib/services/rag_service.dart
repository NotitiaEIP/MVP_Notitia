// =============================================================================
// NOTITIA — Service RAG (Retrieval-Augmented Generation)
// Orchestre : Embedding question → Recherche vectorielle → Génération réponse
// =============================================================================

import 'package:flutter/foundation.dart';

import '../models/transcription.dart';
import 'ai_service.dart';
import 'storage_service.dart';
import 'vector_store_service.dart';

/// Message dans la conversation avec l'assistant
class ChatMessage {
  final String role; // 'user' ou 'assistant'
  final String content;
  final DateTime timestamp;
  final List<VectorSearchResult>?
  sources; // Sources utilisées (pour l'assistant)

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.sources,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, String> toApiFormat() => {'role': role, 'content': content};
}

/// État de l'indexation
class IndexationStatus {
  final int totalTranscriptions;
  final int indexedTranscriptions;
  final int totalChunks;
  final bool isIndexing;
  final String? currentTitle;

  IndexationStatus({
    this.totalTranscriptions = 0,
    this.indexedTranscriptions = 0,
    this.totalChunks = 0,
    this.isIndexing = false,
    this.currentTitle,
  });

  double get progress => totalTranscriptions > 0
      ? indexedTranscriptions / totalTranscriptions
      : 0.0;

  bool get isComplete =>
      totalTranscriptions > 0 && indexedTranscriptions >= totalTranscriptions;
}

// =============================================================================
// SERVICE RAG PRINCIPAL
// =============================================================================

class RAGService {
  static RAGService? _instance;
  static RAGService get instance => _instance ??= RAGService._();

  RAGService._();

  final AiService _ai = AiService.instance;
  final VectorStoreService _vectorStore = VectorStoreService.instance;

  /// Historique de conversation en cours
  final List<ChatMessage> _conversationHistory = [];

  /// Getter pour l'historique
  List<ChatMessage> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  // ---------------------------------------------------------------------------
  // INDEXATION — Indexer toutes les transcriptions dans le vector store
  // ---------------------------------------------------------------------------

  /// Indexe toutes les transcriptions non encore indexées.
  /// Retourne le statut d'indexation en temps réel via le callback.
  Future<IndexationStatus> indexAllTranscriptions({
    void Function(IndexationStatus status)? onProgress,
  }) async {
    final transcriptions = await StorageService.loadAll();

    if (transcriptions.isEmpty) {
      return IndexationStatus(
        totalTranscriptions: 0,
        indexedTranscriptions: 0,
        totalChunks: 0,
      );
    }

    int indexed = 0;
    int totalChunks = await _vectorStore.chunkCount;

    onProgress?.call(
      IndexationStatus(
        totalTranscriptions: transcriptions.length,
        indexedTranscriptions: indexed,
        totalChunks: totalChunks,
        isIndexing: true,
      ),
    );

    for (final t in transcriptions) {
      // Vérifier si la transcription a de VRAIS chunks (pas juste le flag)
      final hasRealChunks = await _vectorStore.hasChunksFor(t.id);

      if (!hasRealChunks && t.content.trim().isNotEmpty) {
        onProgress?.call(
          IndexationStatus(
            totalTranscriptions: transcriptions.length,
            indexedTranscriptions: indexed,
            totalChunks: totalChunks,
            isIndexing: true,
            currentTitle: t.title,
          ),
        );

        debugPrint(
          '[RAG] Indexation de "${t.title}" (${t.content.length} chars)...',
        );
        final count = await _vectorStore.indexTranscription(
          transcriptionId: t.id,
          text: t.content,
          metadata: {'title': t.title, 'date': t.formattedDate},
        );
        totalChunks += count;
        if (count > 0) indexed++;
        debugPrint('[RAG] → $count chunks créés pour "${t.title}"');
      } else if (hasRealChunks) {
        indexed++;
      }

      onProgress?.call(
        IndexationStatus(
          totalTranscriptions: transcriptions.length,
          indexedTranscriptions: indexed,
          totalChunks: totalChunks,
          isIndexing: true,
          currentTitle: t.title,
        ),
      );
    }

    return IndexationStatus(
      totalTranscriptions: transcriptions.length,
      indexedTranscriptions: indexed,
      totalChunks: totalChunks,
      isIndexing: false,
    );
  }

  /// Indexe une seule transcription (appelé après une nouvelle sauvegarde).
  Future<void> indexSingleTranscription(Transcription transcription) async {
    if (transcription.content.trim().isEmpty) return;

    final count = await _vectorStore.indexTranscription(
      transcriptionId: transcription.id,
      text: transcription.content,
      metadata: {
        'title': transcription.title,
        'date': transcription.formattedDate,
      },
    );
    debugPrint('[RAG] Transcription "${transcription.title}" → $count chunks');
  }

  /// Force la ré-indexation complète (supprime tout et recommence).
  Future<IndexationStatus> forceReindexAll({
    void Function(IndexationStatus status)? onProgress,
  }) async {
    debugPrint('[RAG] === FORCE RE-INDEX ===');
    await _vectorStore.forceReset();
    return indexAllTranscriptions(onProgress: onProgress);
  }

  // ---------------------------------------------------------------------------
  // QUESTION-RÉPONSE — Pipeline RAG complet
  // ---------------------------------------------------------------------------

  /// Pose une question à l'assistant. Pipeline complet :
  /// 1. Embedding de la question
  /// 2. Recherche des chunks similaires
  /// 3. Génération de la réponse avec contexte
  ///
  /// Retourne le message de l'assistant.
  Future<ChatMessage> ask(String question) async {
    // Ajouter la question à l'historique
    final userMessage = ChatMessage(role: 'user', content: question);
    _conversationHistory.add(userMessage);

    try {
      // 1. Embedding de la question
      debugPrint('[RAG] Embedding de la question...');
      final queryEmbedding = await _ai.embed(question, isQuery: true);

      List<VectorSearchResult> results = [];
      List<String> contextTexts = [];

      if (queryEmbedding != null) {
        // 2. Recherche vectorielle
        debugPrint('[RAG] Recherche vectorielle...');
        results = await _vectorStore.search(
          queryEmbedding: queryEmbedding,
          topK: 5,
          minSimilarity: 0.25,
        );

        debugPrint(
          '[RAG] ${results.length} chunks trouvés (similarité: '
          '${results.map((r) => r.similarity.toStringAsFixed(2)).join(", ")})',
        );

        // Extraire les textes pour le contexte
        contextTexts = results.map((r) {
          final meta = r.chunk.metadata;
          final title = meta['title'] ?? '';
          final date = meta['date'] ?? '';
          return '📝 $title ($date)\n${r.chunk.text}';
        }).toList();
      }

      // 3. Préparer l'historique de conversation (limité aux 6 derniers messages)
      final recentHistory = _conversationHistory.length > 7
          ? _conversationHistory
                .sublist(
                  _conversationHistory.length - 7,
                  _conversationHistory.length - 1,
                )
                .map((m) => m.toApiFormat())
                .toList()
          : _conversationHistory
                .sublist(0, _conversationHistory.length - 1)
                .map((m) => m.toApiFormat())
                .toList();

      // 4. Génération de la réponse
      debugPrint('[RAG] Génération de la réponse...');
      final response = await _ai.generateRAGResponse(
        context: contextTexts,
        question: question,
        conversationHistory: recentHistory.isNotEmpty ? recentHistory : null,
      );

      // Créer le message assistant
      final assistantMessage = ChatMessage(
        role: 'assistant',
        content: response,
        sources: results.isNotEmpty ? results : null,
      );
      _conversationHistory.add(assistantMessage);

      return assistantMessage;
    } catch (e) {
      debugPrint('[RAG] Erreur: $e');
      final errorMessage = ChatMessage(
        role: 'assistant',
        content:
            'Désolé, une erreur est survenue. Vérifiez votre connexion internet et réessayez.',
      );
      _conversationHistory.add(errorMessage);
      return errorMessage;
    }
  }

  // ---------------------------------------------------------------------------
  // GESTION CONVERSATION
  // ---------------------------------------------------------------------------

  /// Efface l'historique de conversation.
  void clearConversation() {
    _conversationHistory.clear();
  }

  /// Supprime le dernier échange (question + réponse).
  void undoLastExchange() {
    if (_conversationHistory.length >= 2) {
      _conversationHistory.removeLast(); // assistant
      _conversationHistory.removeLast(); // user
    }
  }

  // ---------------------------------------------------------------------------
  // STATISTIQUES
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> getStats() async {
    final chunkCount = await _vectorStore.chunkCount;
    final indexedCount = await _vectorStore.indexedCount;
    final transcriptions = await StorageService.loadAll();

    return {
      'totalTranscriptions': transcriptions.length,
      'indexedTranscriptions': indexedCount,
      'totalChunks': chunkCount,
      'conversationMessages': _conversationHistory.length,
    };
  }
}
