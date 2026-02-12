// =============================================================================
// NOTITIA — Recherche sémantique (approche keyword-ranked pour le PoC)
//
// Scoring :
//   • Phrase exacte dans le contenu : +10
//   • Phrase exacte dans le titre   : +8
//   • Tous les termes présents      : +5 (bonus)
//   • Chaque terme dans le contenu  : +2 / occurrence (plafonné)
//   • Chaque terme dans le titre    : +3
//
// Prêt à être remplacé par un vrai moteur d'embeddings (ex. Qdrant, Pinecone)
// lorsque l'on connectera un backend IA.
// =============================================================================
import '../models/transcription.dart';

class SearchResult {
  final Transcription transcription;
  final double score;
  final List<String> matchedTerms;
  final String excerpt;

  SearchResult({
    required this.transcription,
    required this.score,
    required this.matchedTerms,
    required this.excerpt,
  });
}

class SearchService {
  /// Mots vides français filtrés des requêtes.
  static const _stopWords = {
    'le',
    'la',
    'les',
    'un',
    'une',
    'des',
    'du',
    'de',
    'd',
    'et',
    'ou',
    'mais',
    'donc',
    'car',
    'ni',
    'que',
    'qui',
    'quoi',
    'dont',
    'où',
    'je',
    'tu',
    'il',
    'elle',
    'on',
    'nous',
    'vous',
    'ils',
    'elles',
    'me',
    'te',
    'se',
    'ce',
    'cette',
    'ces',
    'mon',
    'ton',
    'son',
    'ma',
    'ta',
    'sa',
    'mes',
    'tes',
    'ses',
    'notre',
    'votre',
    'leur',
    'leurs',
    'en',
    'dans',
    'sur',
    'sous',
    'avec',
    'sans',
    'pour',
    'par',
    'est',
    'sont',
    'être',
    'avoir',
    'fait',
    'faire',
    'a',
    'ai',
    'pas',
    'ne',
    'plus',
    'très',
    'aussi',
    'bien',
    'au',
    'aux',
    'à',
    'y',
    'si',
    'ça',
    'c',
    'l',
    'j',
    'n',
    's',
    'qu',
  };

  /// Recherche par mots-clés avec scoring de pertinence.
  static List<SearchResult> search(
    List<Transcription> transcriptions,
    String query,
  ) {
    if (query.trim().isEmpty) return [];

    final queryLower = query.toLowerCase().trim();
    final allTerms = queryLower.split(RegExp(r'\s+'));
    final terms = allTerms
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();

    // Si tous les mots étaient des stop-words, on garde les originaux
    if (terms.isEmpty) {
      terms.addAll(allTerms.where((t) => t.length >= 2));
    }
    if (terms.isEmpty) return [];

    final results = <SearchResult>[];

    for (final t in transcriptions) {
      final contentLower = t.content.toLowerCase();
      final titleLower = t.title.toLowerCase();
      double score = 0;
      final matchedTerms = <String>{};
      String? excerpt;

      // ── Correspondance phrase exacte ──
      if (contentLower.contains(queryLower)) {
        score += 10;
        final idx = contentLower.indexOf(queryLower);
        excerpt = _extractExcerpt(t.content, idx, queryLower.length);
      }
      if (titleLower.contains(queryLower)) {
        score += 8;
      }

      // ── Score par terme ──
      for (final term in terms) {
        final termRegex = RegExp(RegExp.escape(term), caseSensitive: false);

        final contentMatches = termRegex.allMatches(contentLower).length;
        if (contentMatches > 0) {
          score += 2 + (contentMatches - 1).clamp(0, 5) * 0.5;
          matchedTerms.add(term);
          if (excerpt == null) {
            final idx = contentLower.indexOf(term);
            if (idx >= 0) {
              excerpt = _extractExcerpt(t.content, idx, term.length);
            }
          }
        }

        if (titleLower.contains(term)) {
          score += 3;
          matchedTerms.add(term);
        }
      }

      // ── Bonus : tous les termes présents ──
      if (terms.length > 1 &&
          terms.every((term) => contentLower.contains(term))) {
        score += 5;
      }

      if (score > 0) {
        results.add(
          SearchResult(
            transcription: t,
            score: score,
            matchedTerms: matchedTerms.toList(),
            excerpt:
                excerpt ??
                (t.content.length > 150
                    ? '${t.content.substring(0, 150)}…'
                    : t.content),
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Extrait un passage autour de la correspondance.
  static String _extractExcerpt(
    String content,
    int matchIndex,
    int matchLength,
  ) {
    const contextChars = 80;
    final start = (matchIndex - contextChars).clamp(0, content.length);
    final end = (matchIndex + matchLength + contextChars).clamp(
      0,
      content.length,
    );
    var excerpt = content.substring(start, end).trim();
    if (start > 0) excerpt = '…$excerpt';
    if (end < content.length) excerpt = '$excerpt…';
    return excerpt;
  }
}
