// =============================================================================
// NOTITIA — Historique des transcriptions
// =============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transcription.dart';
import '../pages/meeting_page.dart';
import '../services/language_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../pages/tap_to_share_page.dart';
import '../services/auth_service.dart';
import '../widgets/page_header.dart';
import 'edit_page.dart';

class HistoryPage extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;

  /// Si true, filtre l'historique pour n'afficher que les transcriptions de réunions.
  final bool filterMeetingsOnly;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;

  const HistoryPage({
    super.key,
    required this.refreshNotifier,
    this.filterMeetingsOnly = false,
    this.profile,
    this.onProfileTap,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Transcription> _transcriptions = [];
  bool _loading = true;
  String? _selectedTag;
  final LanguageService _languageService = LanguageService();

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_loadData);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterMeetingsOnly != widget.filterMeetingsOnly) {
      _loadData();
    }
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    StorageService.invalidateCache();
    final data = await StorageService.loadAll();

    // Charger les IDs de transcriptions liées aux réunions
    Set<String> meetingIds = {};
    if (widget.filterMeetingsOnly) {
      final meetings = await MeetingPage.loadMeetingHistory();
      meetingIds = meetings
          .where((m) => m.transcriptionId != null)
          .map((m) => m.transcriptionId!)
          .toSet();
    }

    if (mounted) {
      setState(() {
        if (widget.filterMeetingsOnly) {
          _transcriptions = data
              .where((t) => meetingIds.contains(t.id))
              .toList();
        } else {
          _transcriptions = data;
        }
        _loading = false;
      });
    }
  }

  Future<void> _deleteTranscription(Transcription t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.5)),
        ),
        title: Text(
          _languageService.translate('delete'),
          style: GoogleFonts.orbitron(
            fontSize: 16,
            color: NotitiaTheme.redRecording,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          '${_languageService.translate('delete_confirm')} « ${t.title} » ?',
          style: GoogleFonts.poppins(fontSize: 14, color: NotitiaTheme.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _languageService.translate('cancel'),
              style: GoogleFonts.orbitron(
                fontSize: 11,
                color: NotitiaTheme.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: NotitiaTheme.redRecording,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _languageService.translate('delete'),
              style: GoogleFonts.orbitron(
                fontSize: 11,
                color: NotitiaTheme.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.delete(t.id);
      _loadData();
    }
  }

  Future<void> _openEditor(Transcription t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditPage(transcription: t)),
    );
    if (changed == true) _loadData();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final headerTitle = widget.filterMeetingsOnly
        ? _languageService.translate('meetings_title')
        : _languageService.translate('history_title');
    final headerIcon = widget.filterMeetingsOnly
        ? Icons.groups_rounded
        : Icons.history_rounded;

    final filtered = _selectedTag == null
        ? _transcriptions
        : _transcriptions.where((t) => t.tag == _selectedTag).toList();

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Header uniforme
          NotitiaPageHeader(
            icon: headerIcon,
            title: headerTitle,
            profile: widget.profile,
            onProfileTap: widget.onProfileTap,
            actions: [NfcReceiveButton(onReceived: _loadData)],
          ),
          const SizedBox(height: 6),
          Divider(
            color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
            indent: 20,
            endIndent: 20,
          ),
          // Tag filter chips
          if (!widget.filterMeetingsOnly) _buildTagFilters(),
          const SizedBox(height: 8),
          // Liste
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: NotitiaTheme.neonPink,
                    ),
                  )
                : filtered.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: NotitiaTheme.neonPink,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 16,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildCard(filtered[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64,
            color: NotitiaTheme.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTag != null
                ? _languageService.translate('no_transcriptions_for_tag')
                : _languageService.translate('no_transcriptions'),
            style: GoogleFonts.poppins(fontSize: 16, color: NotitiaTheme.grey),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedTag != null
                ? '${_languageService.translate('no_results_tag_prefix')} $_selectedTag'
                : _languageService.translate('saved_transcriptions_here'),
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

  Widget _buildTagFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: _languageService.translate('filter_all'),
              selected: _selectedTag == null,
              onTap: () => setState(() => _selectedTag = null),
            ),
            const SizedBox(width: 8),
            ...TranscriptionTag.all.map(
              (tag) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildFilterChip(
                  label: tag,
                  selected: _selectedTag == tag,
                  onTap: () => setState(() {
                    _selectedTag = _selectedTag == tag ? null : tag;
                  }),
                  icon: _iconForTag(tag),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
              : NotitiaTheme.darkBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? NotitiaTheme.neonPink
                : NotitiaTheme.grey.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? NotitiaTheme.neonPink : NotitiaTheme.grey,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? NotitiaTheme.neonPink : NotitiaTheme.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForTag(String tag) {
    switch (tag) {
      case TranscriptionTag.transcription:
        return Icons.mic_rounded;
      case TranscriptionTag.reunion:
        return Icons.groups_rounded;
      case TranscriptionTag.nfc:
        return Icons.nfc_rounded;
      case TranscriptionTag.widget:
        return Icons.widgets_rounded;
      default:
        return Icons.label_rounded;
    }
  }

  Color _colorForTag(String tag) {
    switch (tag) {
      case TranscriptionTag.transcription:
        return NotitiaTheme.neonPink;
      case TranscriptionTag.reunion:
        return NotitiaTheme.neonCyan;
      case TranscriptionTag.nfc:
        return const Color(0xFFFFA726); // orange
      case TranscriptionTag.widget:
        return const Color(0xFF66BB6A); // vert
      default:
        return NotitiaTheme.grey;
    }
  }

  Widget _buildCard(Transcription t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _openEditor(t),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NotitiaTheme.darkBlue,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: NotitiaTheme.neonPink.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _colorForTag(t.tag).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _colorForTag(t.tag).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconForTag(t.tag),
                          size: 10,
                          color: _colorForTag(t.tag),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          t.tag,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: _colorForTag(t.tag),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.title,
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        color: NotitiaTheme.neonPink,
                        letterSpacing: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  NfcShareButton(transcription: t),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deleteTranscription(t),
                    child: Icon(
                      Icons.delete_outline,
                      color: NotitiaTheme.grey.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                t.formattedDate,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: NotitiaTheme.grey,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t.preview,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: NotitiaTheme.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
