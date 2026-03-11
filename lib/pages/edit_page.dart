// =============================================================================
// NOTITIA — Édition d'une transcription
// =============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transcription.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../pages/rich_summary_page.dart';
import 'tap_to_share_page.dart';

class EditPage extends StatefulWidget {
  final Transcription transcription;
  const EditPage({super.key, required this.transcription});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.transcription.title);
    _contentController = TextEditingController(
      text: widget.transcription.content,
    );
    _titleController.addListener(_markChanged);
    _contentController.addListener(_markChanged);
  }

  void _markChanged() {
    setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    final updated = widget.transcription.copyWith(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      updatedAt: DateTime.now(),
    );
    await StorageService.save(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transcription mise à jour ✓',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: NotitiaTheme.neonPink,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
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
          'Supprimer cette transcription ?',
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
      await StorageService.delete(widget.transcription.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.5)),
        ),
        title: Text(
          'MODIFICATIONS NON SAUVÉES',
          style: GoogleFonts.orbitron(
            fontSize: 13,
            color: NotitiaTheme.neonPink,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'Vous avez des modifications non sauvées. Quitter ?',
          style: GoogleFonts.poppins(fontSize: 14, color: NotitiaTheme.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'RESTER',
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
              'QUITTER',
              style: GoogleFonts.orbitron(
                fontSize: 11,
                color: NotitiaTheme.white,
              ),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final wordCount = _contentController.text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (shouldPop && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        backgroundColor: NotitiaTheme.deepBlue,
        appBar: AppBar(
          backgroundColor: NotitiaTheme.darkBlue,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: NotitiaTheme.white,
            ),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _confirmDiscard();
                if (shouldPop && context.mounted) {
                  Navigator.pop(context, false);
                }
              } else {
                Navigator.pop(context, false);
              }
            },
          ),
          title: Text(
            'ÉDITION',
            style: GoogleFonts.orbitron(
              fontSize: 16,
              color: NotitiaTheme.white,
              letterSpacing: 3,
            ),
          ),
          actions: [
            // ── Bouton Résumé Intelligent ──
            IconButton(
              icon: const Icon(
                Icons.auto_awesome,
                color: NotitiaTheme.neonCyan,
              ),
              tooltip: 'Résumé intelligent',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RichSummaryPage(transcription: widget.transcription),
                  ),
                );
              },
            ),
            NfcShareButton(transcription: widget.transcription),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: NotitiaTheme.redRecording,
              ),
              onPressed: _delete,
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _hasChanges ? _save : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _hasChanges
                        ? NotitiaTheme.neonPink
                        : NotitiaTheme.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SAUVER',
                    style: GoogleFonts.orbitron(
                      fontSize: 11,
                      color: NotitiaTheme.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dates
              Text(
                'Créé le ${widget.transcription.formattedDate}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: NotitiaTheme.grey,
                ),
              ),
              if (widget.transcription.updatedAt !=
                  widget.transcription.createdAt)
                Text(
                  'Modifié le ${widget.transcription.formattedUpdateDate}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: NotitiaTheme.grey,
                  ),
                ),
              const SizedBox(height: 20),

              // ── Titre ──
              Text(
                'TITRE',
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  color: NotitiaTheme.neonPink,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                style: GoogleFonts.poppins(
                  color: NotitiaTheme.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: NotitiaTheme.neonPink),
                  ),
                  filled: true,
                  fillColor: NotitiaTheme.darkBlue,
                ),
              ),
              const SizedBox(height: 24),

              // ── Contenu ──
              Text(
                'CONTENU',
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  color: NotitiaTheme.neonPink,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                style: GoogleFonts.poppins(
                  color: NotitiaTheme.white,
                  fontSize: 15,
                  height: 1.6,
                ),
                maxLines: null,
                minLines: 10,
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: NotitiaTheme.neonPink),
                  ),
                  filled: true,
                  fillColor: NotitiaTheme.darkBlue,
                ),
              ),
              const SizedBox(height: 16),

              // Compteur de mots
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$wordCount mot${wordCount > 1 ? 's' : ''}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: NotitiaTheme.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
