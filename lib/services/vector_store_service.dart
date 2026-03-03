// =============================================================================
// NOTITIA — Base de données vectorielle locale
// Stocke les chunks + embeddings en JSON sur le device
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'gemini_service.dart';

// =============================================================================
// MODÈLE — Chunk de texte avec son embedding
// =============================================================================

/// Un morceau de transcription avec son vecteur d'embedding.
class TextChunk {
  final String id;
  final String transcriptionId;
  final String text;
  final List<double> embedding;
  final DateTime createdAt;

  /// Métadonnées optionnelles (titre de la transcription, date, etc.)
  final Map<String, String> metadata;

  TextChunk({
    required this.id,
    required this.transcriptionId,
    required this.text,
    required this.embedding,
    required this.createdAt,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'transcriptionId': transcriptionId,
    'text': text,
    'embedding': embedding,
    'createdAt': createdAt.toIso8601String(),
    'metadata': metadata,
  };

  factory TextChunk.fromJson(Map<String, dynamic> json) => TextChunk(
    id: json['id'] as String,
    transcriptionId: json['transcriptionId'] as String,
    text: json['text'] as String,
    embedding: (json['embedding'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    metadata:
        (json['metadata'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
  );
}

/// Résultat de recherche vectorielle
class VectorSearchResult {
  final TextChunk chunk;
  final double similarity;

  VectorSearchResult({required this.chunk, required this.similarity});
}

// =============================================================================
// SERVICE — VectorStore local
// =============================================================================

class VectorStoreService {
  static VectorStoreService? _instance;
  static VectorStoreService get instance =>
      _instance ??= VectorStoreService._();

  VectorStoreService._();

  static const String _fileName = 'notitia_vectors.json';

  /// Cache en mémoire
  List<TextChunk>? _chunks;

  /// IDs des transcriptions déjà indexées
  final Set<String> _indexedTranscriptionIds = {};

  static Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  // ---------------------------------------------------------------------------
  // CHUNKING — Découpe le texte en morceaux
  // ---------------------------------------------------------------------------

  /// Découpe un texte en chunks avec chevauchement.
  /// Gère les textes sans ponctuation (transcriptions vocales).
  static List<String> chunkText(
    String text, {
    int maxChunkSize = 500,
    int overlap = 80,
  }) {
    if (text.trim().isEmpty) return [];

    final cleanText = text.trim();

    // Si le texte est court, un seul chunk
    if (cleanText.length <= maxChunkSize) return [cleanText];

    final chunks = <String>[];

    // Découpe par phrases si la ponctuation existe, sinon par mots
    final hasPunctuation = RegExp(r'[.!?]').hasMatch(cleanText);
    List<String> segments;

    if (hasPunctuation) {
      // Découpe par phrases
      segments = cleanText.split(RegExp(r'(?<=[.!?])\s+'));
    } else {
      // Pas de ponctuation (transcription vocale brute) → découpe par groupes de mots
      final words = cleanText.split(RegExp(r'\s+'));
      segments = [];
      for (int i = 0; i < words.length; i += 30) {
        final end = (i + 30).clamp(0, words.length);
        segments.add(words.sublist(i, end).join(' '));
      }
    }

    var currentChunk = StringBuffer();
    var currentLength = 0;

    for (final segment in segments) {
      if (currentLength + segment.length > maxChunkSize && currentLength > 0) {
        chunks.add(currentChunk.toString().trim());

        // Chevauchement : on reprend les derniers mots
        final overlapText = currentChunk.toString();
        currentChunk = StringBuffer();
        currentLength = 0;

        if (overlapText.length > overlap) {
          final overlapStart = overlapText.substring(
            overlapText.length - overlap,
          );
          final spaceIdx = overlapStart.indexOf(' ');
          if (spaceIdx > 0) {
            final overlapClean = overlapStart.substring(spaceIdx + 1);
            currentChunk.write(overlapClean);
            currentChunk.write(' ');
            currentLength = overlapClean.length + 1;
          }
        }
      }

      currentChunk.write(segment);
      currentChunk.write(' ');
      currentLength += segment.length + 1;
    }

    // Dernier chunk
    final remaining = currentChunk.toString().trim();
    if (remaining.isNotEmpty) {
      chunks.add(remaining);
    }

    // Sécurité : si un chunk est encore trop long, le re-découper
    final safeChunks = <String>[];
    for (final chunk in chunks) {
      if (chunk.length > maxChunkSize * 2) {
        // Découpe brute par caractères avec chevauchement
        for (int i = 0; i < chunk.length; i += maxChunkSize - overlap) {
          final end = (i + maxChunkSize).clamp(0, chunk.length);
          safeChunks.add(chunk.substring(i, end).trim());
          if (end >= chunk.length) break;
        }
      } else {
        safeChunks.add(chunk);
      }
    }

    debugPrint(
      '[VectorStore] Chunking: ${safeChunks.length} chunks créés (texte: ${cleanText.length} chars, ponctuation: $hasPunctuation)',
    );
    return safeChunks;
  }

  // ---------------------------------------------------------------------------
  // STOCKAGE — Chargement / Sauvegarde
  // ---------------------------------------------------------------------------

  /// Charge tous les chunks depuis le fichier JSON.
  Future<List<TextChunk>> loadAll() async {
    if (_chunks != null) return List.from(_chunks!);
    try {
      final path = await _filePath;
      final file = File(path);
      if (!file.existsSync()) {
        _chunks = [];
        return [];
      }
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _chunks = jsonList
          .map((j) => TextChunk.fromJson(j as Map<String, dynamic>))
          .toList();
      // Remplir le set des IDs indexés
      for (final chunk in _chunks!) {
        _indexedTranscriptionIds.add(chunk.transcriptionId);
      }
      return List.from(_chunks!);
    } catch (e) {
      debugPrint('[VectorStore] Erreur chargement: $e');
      _chunks = [];
      return [];
    }
  }

  Future<void> _saveAll() async {
    if (_chunks == null) return;
    final path = await _filePath;
    final file = File(path);
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(_chunks!.map((c) => c.toJson()).toList());
    await file.writeAsString(jsonString);
  }

  // ---------------------------------------------------------------------------
  // INDEXATION — Transforme une transcription en chunks vectorisés
  // ---------------------------------------------------------------------------

  /// Vérifie si une transcription a déjà été indexée.
  Future<bool> isIndexed(String transcriptionId) async {
    await loadAll();
    return _indexedTranscriptionIds.contains(transcriptionId);
  }

  /// Indexe une transcription : chunking + embedding + stockage.
  /// Retourne le nombre de chunks créés.
  ///
  /// [transcriptionId] — ID unique de la transcription
  /// [text] — texte complet de la transcription
  /// [metadata] — infos supplémentaires (titre, date, etc.)
  /// [onProgress] — callback pour suivre la progression
  Future<int> indexTranscription({
    required String transcriptionId,
    required String text,
    Map<String, String> metadata = const {},
    void Function(int current, int total)? onProgress,
  }) async {
    await loadAll();

    // Supprimer les anciens chunks de cette transcription (re-indexation)
    _chunks!.removeWhere((c) => c.transcriptionId == transcriptionId);

    // 1. Chunking
    final textChunks = chunkText(text);
    if (textChunks.isEmpty) return 0;

    debugPrint(
      '[VectorStore] Indexation: ${textChunks.length} chunks pour transcription $transcriptionId',
    );

    // 2. Embedding de chaque chunk
    int indexed = 0;
    for (int i = 0; i < textChunks.length; i++) {
      debugPrint(
        '[VectorStore] Embedding chunk ${i + 1}/${textChunks.length} (${textChunks[i].length} chars)...',
      );
      final embedding = await GeminiService.instance.embed(textChunks[i]);
      if (embedding != null) {
        final chunk = TextChunk(
          id: '${transcriptionId}_chunk_$i',
          transcriptionId: transcriptionId,
          text: textChunks[i],
          embedding: embedding,
          createdAt: DateTime.now(),
          metadata: metadata,
        );
        _chunks!.add(chunk);
        indexed++;
        debugPrint(
          '[VectorStore] ✓ Chunk ${i + 1} embedé (${embedding.length} dims)',
        );
      } else {
        debugPrint('[VectorStore] ✗ Chunk ${i + 1} ÉCHEC embedding');
      }
      onProgress?.call(i + 1, textChunks.length);

      // Rate limiting (API gratuite Gemini : ~100 req/min)
      if (i < textChunks.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // Ne marquer comme indexé QUE si au moins 1 chunk a été créé
    if (indexed > 0) {
      _indexedTranscriptionIds.add(transcriptionId);
    } else {
      debugPrint(
        '[VectorStore] ⚠ AUCUN chunk créé pour $transcriptionId — non marqué comme indexé',
      );
    }

    // 3. Sauvegarde
    await _saveAll();

    debugPrint('[VectorStore] $indexed/${textChunks.length} chunks indexés');
    return indexed;
  }

  /// Indexe toutes les transcriptions non encore indexées.
  Future<int> indexAllNew({
    required List<Map<String, dynamic>> transcriptions,
    void Function(int current, int total, String title)? onProgress,
  }) async {
    int totalChunks = 0;
    int current = 0;

    for (final t in transcriptions) {
      current++;
      final id = t['id'] as String;
      final text = t['content'] as String;
      final title = t['title'] as String? ?? '';

      if (await isIndexed(id) && text.isNotEmpty) {
        onProgress?.call(current, transcriptions.length, title);
        continue;
      }

      onProgress?.call(current, transcriptions.length, title);

      final count = await indexTranscription(
        transcriptionId: id,
        text: text,
        metadata: {'title': title},
      );
      totalChunks += count;
    }

    return totalChunks;
  }

  // ---------------------------------------------------------------------------
  // RECHERCHE VECTORIELLE — Trouve les chunks les plus similaires
  // ---------------------------------------------------------------------------

  /// Recherche les K chunks les plus similaires à la requête.
  ///
  /// [queryEmbedding] — le vecteur de la question
  /// [topK] — nombre de résultats (défaut: 4)
  /// [minSimilarity] — seuil minimum de similarité (défaut: 0.3)
  Future<List<VectorSearchResult>> search({
    required List<double> queryEmbedding,
    int topK = 4,
    double minSimilarity = 0.3,
  }) async {
    final allChunks = await loadAll();
    if (allChunks.isEmpty) return [];

    // Calcul de similarité cosinus pour chaque chunk
    final results = <VectorSearchResult>[];
    for (final chunk in allChunks) {
      final similarity = GeminiService.cosineSimilarity(
        queryEmbedding,
        chunk.embedding,
      );
      if (similarity >= minSimilarity) {
        results.add(VectorSearchResult(chunk: chunk, similarity: similarity));
      }
    }

    // Tri par similarité décroissante
    results.sort((a, b) => b.similarity.compareTo(a.similarity));

    // Retourner les top-K
    return results.take(topK).toList();
  }

  // ---------------------------------------------------------------------------
  // SUPPRESSION
  // ---------------------------------------------------------------------------

  /// Supprime les chunks d'une transcription.
  Future<void> deleteByTranscriptionId(String transcriptionId) async {
    await loadAll();
    _chunks!.removeWhere((c) => c.transcriptionId == transcriptionId);
    _indexedTranscriptionIds.remove(transcriptionId);
    await _saveAll();
  }

  /// Supprime toute la base vectorielle.
  Future<void> deleteAll() async {
    _chunks = [];
    _indexedTranscriptionIds.clear();
    await _saveAll();
  }

  /// Vérifie si une transcription a des chunks réels (pas juste marquée).
  Future<bool> hasChunksFor(String transcriptionId) async {
    final all = await loadAll();
    return all.any((c) => c.transcriptionId == transcriptionId);
  }

  /// Force la ré-indexation : supprime tout et remet à zéro.
  Future<void> forceReset() async {
    debugPrint('[VectorStore] Force reset — suppression de toute la base');
    _chunks = [];
    _indexedTranscriptionIds.clear();
    final path = await _filePath;
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
    await _saveAll();
  }

  /// Force le prochain loadAll à relire le disque.
  void invalidateCache() {
    _chunks = null;
    _indexedTranscriptionIds.clear();
  }

  /// Nombre total de chunks indexés
  Future<int> get chunkCount async {
    final all = await loadAll();
    return all.length;
  }

  /// Nombre de transcriptions indexées
  Future<int> get indexedCount async {
    await loadAll();
    return _indexedTranscriptionIds.length;
  }
}
