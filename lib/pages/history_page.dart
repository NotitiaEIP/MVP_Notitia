// =============================================================================
// NOTITIA — Historique des transcriptions
// =============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transcription.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../pages/tap_to_share_page.dart';
import '../services/auth_service.dart';
import '../widgets/page_header.dart';
import 'edit_page.dart';

class HistoryPage extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;
  const HistoryPage({
    super.key,
    required this.refreshNotifier,
    this.profile,
    this.onProfileTap,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Transcription> _transcriptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    StorageService.invalidateCache();
    final data = await StorageService.loadAll();
    if (mounted) {
      setState(() {
        _transcriptions = data;
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
          'SUPPRIMER',
          style: GoogleFonts.orbitron(
            fontSize: 16,
            color: NotitiaTheme.redRecording,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          'Supprimer « ${t.title} » ?',
          style: GoogleFonts.poppins(fontSize: 14, color: NotitiaTheme.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'ANNULER',
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
              'SUPPRIMER',
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
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Header
          NotitiaPageHeader(
            icon: Icons.history_rounded,
            title: 'HISTORIQUE',
            profile: widget.profile,
            onProfileTap: widget.onProfileTap,
            actions: [
              NfcReceiveButton(onReceived: _loadData),
              const SizedBox(width: 12),
              Text(
                '${_transcriptions.length}',
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  color: NotitiaTheme.neonPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(
            color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 8),
          // Liste
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: NotitiaTheme.neonPink,
                    ),
                  )
                : _transcriptions.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: NotitiaTheme.neonPink,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _transcriptions.length,
                      itemBuilder: (context, index) =>
                          _buildCard(_transcriptions[index]),
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
            'Aucune transcription',
            style: GoogleFonts.poppins(fontSize: 16, color: NotitiaTheme.grey),
          ),
          const SizedBox(height: 6),
          Text(
            'Vos transcriptions sauvegardées\napparaîtront ici',
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
