// =============================================================================
// NOTITIA — Recherche sémantique dans les transcriptions
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transcription.dart';
import '../services/language_service.dart';
import '../services/search_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../widgets/page_header.dart';
import 'edit_page.dart';

class SearchPage extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;
  const SearchPage({
    super.key,
    required this.refreshNotifier,
    this.profile,
    this.onProfileTap,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Transcription> _allTranscriptions = [];
  List<SearchResult> _results = [];
  Timer? _debounce;
  bool _loading = false;
  bool _hasSearched = false;
  final LanguageService _languageService = LanguageService();

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onDataChanged);
    _loadTranscriptions();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onDataChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onDataChanged() => _loadTranscriptions();

  Future<void> _loadTranscriptions() async {
    StorageService.invalidateCache();
    _allTranscriptions = await StorageService.loadAll();
    // Relance la recherche si un texte est saisi
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _hasSearched = true;
    });
    final results = SearchService.search(_allTranscriptions, query);
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _openTranscription(Transcription t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditPage(transcription: t)),
    );
    if (changed == true) await _loadTranscriptions();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Header
          NotitiaPageHeader(
            icon: Icons.search_rounded,
            title: 'RECHERCHE',
            profile: widget.profile,
            onProfileTap: widget.onProfileTap,
          ),
          const SizedBox(height: 16),
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.poppins(
                color: NotitiaTheme.white,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: _languageService.translate('search_hint'),
                hintStyle: GoogleFonts.poppins(
                  color: NotitiaTheme.grey,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: NotitiaTheme.neonPink,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: NotitiaTheme.grey,
                          size: 20,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: NotitiaTheme.neonPink),
                ),
                filled: true,
                fillColor: NotitiaTheme.darkBlue,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(
            color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 8),
          // Résultats
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: NotitiaTheme.neonPink,
                    ),
                  )
                : !_hasSearched
                ? _buildInitialState()
                : _results.isEmpty
                ? _buildNoResults()
                : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 64,
            color: NotitiaTheme.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _languageService.translate('semantic_search'),
            style: GoogleFonts.poppins(fontSize: 16, color: NotitiaTheme.grey),
          ),
          const SizedBox(height: 6),
          Text(
            _allTranscriptions.isEmpty
                ? _languageService.translate('record_transcriptions_to_search')
                : _languageService.translate('type_keyword_phrase_question'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: NotitiaTheme.grey.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: NotitiaTheme.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _languageService.translate('no_results'),
            style: GoogleFonts.poppins(fontSize: 16, color: NotitiaTheme.grey),
          ),
          const SizedBox(height: 6),
          Text(
            _languageService.translate('try_other_terms'),
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: NotitiaTheme.grey.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              '${_results.length} ${_languageService.translate('results_found')}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: NotitiaTheme.grey,
              ),
            ),
          );
        }
        return _buildResultCard(_results[index - 1]);
      },
    );
  }

  Widget _buildResultCard(SearchResult result) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _openTranscription(result.transcription),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NotitiaTheme.darkBlue,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: NotitiaTheme.neonPink.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titre + score
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.transcription.title,
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        color: NotitiaTheme.neonPink,
                        letterSpacing: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: NotitiaTheme.neonPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      result.score.toStringAsFixed(1),
                      style: GoogleFonts.orbitron(
                        fontSize: 10,
                        color: NotitiaTheme.neonPink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                result.transcription.formattedDate,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: NotitiaTheme.grey,
                ),
              ),
              const SizedBox(height: 10),
              // Extrait avec termes surlignés
              _buildHighlightedExcerpt(result.excerpt, result.matchedTerms),
              // Tags des termes
              if (result.matchedTerms.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: result.matchedTerms.map((term) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: NotitiaTheme.neonPink.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        term,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: NotitiaTheme.neonPink,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Construit un RichText avec les termes de recherche surlignés.
  Widget _buildHighlightedExcerpt(String excerpt, List<String> terms) {
    if (terms.isEmpty) {
      return Text(
        excerpt,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: NotitiaTheme.white.withValues(alpha: 0.8),
          height: 1.4,
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final pattern = terms.map(RegExp.escape).join('|');
    final regex = RegExp('($pattern)', caseSensitive: false);
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in regex.allMatches(excerpt)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: excerpt.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: excerpt.substring(match.start, match.end),
          style: TextStyle(
            color: NotitiaTheme.neonPink,
            fontWeight: FontWeight.bold,
            backgroundColor: NotitiaTheme.neonPink.withValues(alpha: 0.15),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < excerpt.length) {
      spans.add(TextSpan(text: excerpt.substring(lastEnd)));
    }

    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: NotitiaTheme.white.withValues(alpha: 0.8),
          height: 1.4,
        ),
        children: spans,
      ),
    );
  }
}
