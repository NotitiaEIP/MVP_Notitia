// =============================================================================
// NOTITIA — Page Assistant IA (Chat RAG)
// Interface conversationnelle basée sur les transcriptions indexées
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';
import '../services/rag_service.dart';
import '../theme.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/meduza_companion.dart';
import '../widgets/meduza_speech_bubble.dart';
import '../widgets/page_header.dart';
import '../services/auth_service.dart';

class AssistantPage extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;
  final void Function(MeduzaState state, {String? message, BubbleStyle style})?
  onMeduzaStateChanged;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;
  const AssistantPage({
    super.key,
    required this.refreshNotifier,
    this.onMeduzaStateChanged,
    this.profile,
    this.onProfileTap,
  });

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final RAGService _rag = RAGService.instance;
  final LanguageService _languageService = LanguageService();

  bool _isLoading = false;
  bool _isIndexing = false;
  IndexationStatus? _indexationStatus;

  // Statistiques
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onDataChanged);
    _loadStats();
    _checkAndIndex();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onDataChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    _checkAndIndex();
  }

  Future<void> _loadStats() async {
    final stats = await _rag.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  /// Vérifie et indexe les nouvelles transcriptions automatiquement
  Future<void> _checkAndIndex() async {
    if (_isIndexing) return;

    setState(() => _isIndexing = true);

    try {
      final status = await _rag.indexAllTranscriptions(
        onProgress: (s) {
          if (mounted) {
            setState(() => _indexationStatus = s);
          }
        },
      );
      if (mounted) {
        setState(() {
          _indexationStatus = status;
          _isIndexing = false;
        });
      }
      await _loadStats();
    } catch (e) {
      if (mounted) setState(() => _isIndexing = false);
    }
  }

  /// Force la ré-indexation complète de toutes les transcriptions
  Future<void> _forceReindex() async {
    if (_isIndexing) return;

    setState(() => _isIndexing = true);

    try {
      final status = await _rag.forceReindexAll(
        onProgress: (s) {
          if (mounted) {
            setState(() => _indexationStatus = s);
          }
        },
      );
      if (mounted) {
        setState(() {
          _indexationStatus = status;
          _isIndexing = false;
        });
      }
      await _loadStats();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('reindex_completed').replaceAll('{count}', status.totalChunks.toString()),
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: NotitiaTheme.neonCyan,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isIndexing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('reindex_error').replaceAll('{error}', e.toString()),
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Envoie un message à l'assistant
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _messageController.clear();
    setState(() => _isLoading = true);

    // Meduza - recherche en cours
    widget.onMeduzaStateChanged?.call(
      MeduzaState.processing,
      message: _languageService.translate('searching_notes'),
    );

    _scrollToBottom();

    try {
      await _rag.ask(text);
      // Meduza - reponse trouvee
      widget.onMeduzaStateChanged?.call(
        MeduzaState.happy,
        message: _languageService.translate('answer_generated_from_notes'),
        style: BubbleStyle.success,
      );
    } catch (e) {
      // Meduza - erreur
      widget.onMeduzaStateChanged?.call(
        MeduzaState.confused,
        message: _languageService.translate('no_relevant_answer_available'),
        style: BubbleStyle.error,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearConversation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.3)),
        ),
        title: Text(
          _languageService.translate('new_conversation'),
          style: GoogleFonts.orbitron(color: NotitiaTheme.white, fontSize: 16),
        ),
        content: Text(
          _languageService.translate('clear_history_question'),
          style: GoogleFonts.poppins(color: NotitiaTheme.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _languageService.translate('cancel'),
              style: GoogleFonts.poppins(color: NotitiaTheme.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _rag.clearConversation();
              setState(() {});
            },
            child: Text(
              _languageService.translate('clear'),
              style: GoogleFonts.poppins(color: NotitiaTheme.neonPink),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final messages = _rag.conversationHistory;

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          // ── Header ──
          _buildHeader(),
          const SizedBox(height: 8),
          // ── Bandeau d'indexation ──
          if (_isIndexing) _buildIndexingBanner(),
          // ── Stats rapides ──
          _buildStatsBar(),
          Divider(
            color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
            indent: 20,
            endIndent: 20,
          ),
          // ── Messages ──
          Expanded(
            child: messages.isEmpty
                ? _buildWelcomeState()
                : _buildMessageList(messages),
          ),
          // ── Indicateur de chargement ──
          if (_isLoading) _buildTypingIndicator(),
          // ── Barre de saisie ──
          _buildInputBar(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return NotitiaPageHeader(
      leading: const MeduzaMiniAvatar(state: MeduzaState.idle),
      title: 'MEDUZA',
      subtitle: 'Pose-moi une question sur tes conversations',
      profile: widget.profile,
      onProfileTap: widget.onProfileTap,
      actions: [
        IconButton(
          onPressed: _forceReindex,
          icon: const Icon(Icons.sync_rounded, color: NotitiaTheme.neonCyan),
          tooltip: 'Re-indexer les conversations',
        ),
        IconButton(
          onPressed: _clearConversation,
          icon: const Icon(Icons.refresh_rounded, color: NotitiaTheme.grey),
          tooltip: 'Nouvelle conversation',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BANDEAU D'INDEXATION
  // ---------------------------------------------------------------------------
  Widget _buildIndexingBanner() {
    final status = _indexationStatus;
    if (status == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: NotitiaTheme.neonCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NotitiaTheme.neonCyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: status.progress > 0 ? status.progress : null,
              color: NotitiaTheme.neonCyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status.currentTitle != null
                  ? 'Indexation : ${status.currentTitle}...'
                  : _languageService.translate('indexing_conversations'),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: NotitiaTheme.neonCyan,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${status.indexedTranscriptions}/${status.totalTranscriptions}',
            style: GoogleFonts.orbitron(
              fontSize: 11,
              color: NotitiaTheme.neonCyan,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BARRE DE STATS
  // ---------------------------------------------------------------------------
  Widget _buildStatsBar() {
    final chunks = _stats['totalChunks'] ?? 0;
    final indexed = _stats['indexedTranscriptions'] ?? 0;
    final total = _stats['totalTranscriptions'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          _buildStatChip(Icons.memory, _languageService.translate('fragments_label').replaceAll('{count}', chunks.toString())),
          const SizedBox(width: 8),
          _buildStatChip(Icons.check_circle_outline, _languageService.translate('indexed_label').replaceAll('{indexed}', indexed.toString()).replaceAll('{total}', total.toString())),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: NotitiaTheme.deepBlue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NotitiaTheme.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: NotitiaTheme.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(fontSize: 11, color: NotitiaTheme.grey),
          ),
        ],
      ),
    );
  }

  // ÉTAT D'ACCUEIL (pas de messages)
  // ---------------------------------------------------------------------------
  Widget _buildWelcomeState() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MeduzaWidget(state: MeduzaState.hello, size: 120),
              const SizedBox(height: 24),
              Text(
                _languageService.translate('hi_memory_assistant'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: NotitiaTheme.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _languageService.translate('i_know_conversations'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: NotitiaTheme.grey,
                ),
              ),
              const SizedBox(height: 24),
              // Suggestions de questions
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestionChip(_languageService.translate('recent_discussions')),
                  _buildSuggestionChip(_languageService.translate('summarize_conversations')),
                  _buildSuggestionChip(_languageService.translate('budget_discussion')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(
        text,
        style: GoogleFonts.poppins(fontSize: 12, color: NotitiaTheme.neonPink),
      ),
      backgroundColor: NotitiaTheme.neonPink.withValues(alpha: 0.1),
      side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        _messageController.text = text;
        _sendMessage();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // LISTE DES MESSAGES
  // ---------------------------------------------------------------------------
  Widget _buildMessageList(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MeduzaMiniAvatar(state: MeduzaState.idle),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
                        : NotitiaTheme.darkBlue,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(
                      color: isUser
                          ? NotitiaTheme.neonPink.withValues(alpha: 0.3)
                          : NotitiaTheme.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: SelectableText(
                    message.content,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: NotitiaTheme.white,
                      height: 1.5,
                    ),
                  ),
                ),
                // Sources supprimées
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INDICATEUR DE FRAPPE
  // ---------------------------------------------------------------------------
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const MeduzaMiniAvatar(state: MeduzaState.processing),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: NotitiaTheme.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
                const SizedBox(width: 8),
                Text(
                  _languageService.translate('searching_conversations'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: NotitiaTheme.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: NotitiaTheme.neonPink.withValues(alpha: 0.3 + value * 0.7),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BARRE DE SAISIE
  // ---------------------------------------------------------------------------
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue,
        border: Border(
          top: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: GoogleFonts.poppins(
                color: NotitiaTheme.white,
                fontSize: 14,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _languageService.translate('ask_question'),
                hintStyle: GoogleFonts.poppins(
                  color: NotitiaTheme.grey,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: NotitiaTheme.grey.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: NotitiaTheme.neonPink),
                ),
                filled: true,
                fillColor: Colors.transparent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: _isLoading
                  ? NotitiaTheme.grey.withValues(alpha: 0.3)
                  : NotitiaTheme.neonPink,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: Icon(
                _isLoading ? Icons.hourglass_empty : Icons.send_rounded,
                color: NotitiaTheme.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
