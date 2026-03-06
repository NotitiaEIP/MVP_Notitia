// =============================================================================
// NOTITIA — Page Tap-to-Share (NFC + P2P Transfer)
// =============================================================================
// UI complète pour le partage par contact NFC entre deux téléphones.
// Deux modes : Émetteur (Partager) et Récepteur (Recevoir).
// Animations cyberpunk, feedback temps réel, progression du transfert.
// =============================================================================

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transcription.dart';
import '../services/local_share_manager.dart';
import '../services/nfc_share_service.dart';
import '../theme.dart';
import 'edit_page.dart';

// =============================================================================
// PAGE PRINCIPALE TAP-TO-SHARE
// =============================================================================

class TapToSharePage extends StatefulWidget {
  /// Si non null, on est en mode émetteur avec cette transcription.
  final Transcription? transcription;

  /// Callback quand une transcription est reçue (mode récepteur).
  final void Function(Transcription)? onReceived;

  const TapToSharePage({
    super.key,
    this.transcription,
    this.onReceived,
  });

  @override
  State<TapToSharePage> createState() => _TapToSharePageState();
}

class _TapToSharePageState extends State<TapToSharePage>
    with TickerProviderStateMixin {
  late final LocalShareManager _manager;
  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _nfcAvailable = false;
  bool _isCheckingNfc = true;
  NfcShareState? _lastState;

  @override
  void initState() {
    super.initState();
    _manager = LocalShareManager();
    _manager.addListener(_onManagerUpdate);
    _manager.onTranscriptionReceived = _onTranscriptionReceived;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _checkNfc();
  }

  Future<void> _checkNfc() async {
    final available = await _manager.isNfcAvailable();
    if (mounted) {
      setState(() {
        _nfcAvailable = available;
        _isCheckingNfc = false;
      });

      // Si une transcription est passée, on démarre automatiquement en mode sender
      if (available && widget.transcription != null) {
        _startSending();
      }
    }
  }

  void _onManagerUpdate() {
    if (!mounted) return;

    final session = _manager.session;
    final currentState = session?.state;

    // Détecter la transition vers "completed" pour jouer son + vibration
    if (currentState == NfcShareState.completed &&
        _lastState != NfcShareState.completed) {
      _playCompletionFeedback(session!.mode);
    }
    // Détecter la transition vers "failed" pour vibrer (erreur)
    if (currentState == NfcShareState.failed &&
        _lastState != NfcShareState.failed) {
      HapticFeedback.heavyImpact();
    }

    _lastState = currentState;
    setState(() {});
  }

  /// Joue le son de confirmation + vibration selon le mode (sender/receiver).
  Future<void> _playCompletionFeedback(ShareMode mode) async {
    // Vibration de succès (double tap haptique)
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.mediumImpact();

    // Son uniquement pour l'émetteur
    if (mode == ShareMode.sender) {
      try {
        await _audioPlayer.play(AssetSource('sounds/sent.mp3'));
      } catch (e) {
        debugPrint('[TapToShare] Audio playback error: $e');
      }
    }
  }

  void _onTranscriptionReceived(Transcription transcription) {
    widget.onReceived?.call(transcription);
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerUpdate);
    _manager.dispose();
    _audioPlayer.dispose();
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _startSending() async {
    if (widget.transcription == null) return;
    await _manager.startSending(widget.transcription!);
  }

  Future<void> _startReceiving() async {
    await _manager.startReceiving();
  }

  Future<void> _cancel() async {
    await _manager.cancelSession();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      appBar: _buildAppBar(),
      body: _isCheckingNfc
          ? _buildLoading()
          : !_nfcAvailable
              ? _buildNfcUnavailable()
              : _buildContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: NotitiaTheme.darkBlue,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () {
          _cancel();
          Navigator.of(context).pop();
        },
      ),
      title: Text(
        'TAP TO SHARE',
        style: GoogleFonts.orbitron(
          color: NotitiaTheme.neonCyan,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                NotitiaTheme.neonCyan.withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: NotitiaTheme.neonCyan),
    );
  }

  Widget _buildNfcUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.nfc_rounded,
              size: 80,
              color: NotitiaTheme.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'NFC NON DISPONIBLE',
              style: GoogleFonts.orbitron(
                color: NotitiaTheme.neonPink,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Activez le NFC dans les paramètres de votre téléphone ou vérifiez que votre appareil le supporte.',
              style: GoogleFonts.poppins(
                color: NotitiaTheme.grey,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text('RETOUR', style: GoogleFonts.orbitron(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: NotitiaTheme.neonPink,
                side: const BorderSide(color: NotitiaTheme.neonPink),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTENU PRINCIPAL
  // ---------------------------------------------------------------------------

  Widget _buildContent() {
    final session = _manager.session;
    if (session != null && session.isActive ||
        session?.state == NfcShareState.completed ||
        session?.state == NfcShareState.failed) {
      return _buildActiveSession(session!);
    }
    return _buildModeSelection();
  }

  // ---------------------------------------------------------------------------
  // SÉLECTION DU MODE (émetteur / récepteur)
  // ---------------------------------------------------------------------------

  Widget _buildModeSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // NFC Icon animé
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + _pulseController.value * 0.1;
              return Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.nfc_rounded,
                  size: 80,
                  color: NotitiaTheme.neonCyan
                      .withValues(alpha: 0.5 + _pulseController.value * 0.5),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'PARTAGE PAR NFC',
            style: GoogleFonts.orbitron(
              color: NotitiaTheme.white,
              fontSize: 18,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Collez deux téléphones pour transférer\nune transcription instantanément',
            style: GoogleFonts.poppins(
              color: NotitiaTheme.grey,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // Carte Émetteur
          if (widget.transcription != null) ...[
            _buildModeCard(
              icon: Icons.upload_rounded,
              title: 'ENVOYER',
              subtitle: widget.transcription!.title,
              color: NotitiaTheme.neonPink,
              onTap: _startSending,
            ),
            const SizedBox(height: 20),
          ],

          // Carte Récepteur
          _buildModeCard(
            icon: Icons.download_rounded,
            title: 'RECEVOIR',
            subtitle: 'Scanner un appareil à proximité',
            color: NotitiaTheme.neonCyan,
            onTap: _startReceiving,
          ),

          const SizedBox(height: 40),

          // Instructions
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: NotitiaTheme.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMMENT ÇA MARCHE',
                  style: GoogleFonts.orbitron(
                    color: NotitiaTheme.grey,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildStep('1', 'L\'émetteur choisit ENVOYER'),
                _buildStep('2', 'Le récepteur choisit RECEVOIR'),
                _buildStep('3', 'Collez les deux téléphones dos à dos'),
                _buildStep('4',
                    'La transcription est transférée instantanément'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NotitiaTheme.darkBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.orbitron(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      color: NotitiaTheme.grey,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: NotitiaTheme.neonCyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.orbitron(
                  color: NotitiaTheme.neonCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                color: NotitiaTheme.grey,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SESSION ACTIVE
  // ---------------------------------------------------------------------------

  Widget _buildActiveSession(ShareSession session) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animation NFC / État
                _buildStateVisual(session),

                const SizedBox(height: 32),

                // État textuel
                _buildStateText(session),

                const SizedBox(height: 24),

                // Message d'erreur
                if (session.errorMessage != null) ...[
                  const SizedBox(height: 24),
                  _buildErrorMessage(session.errorMessage!),
                ],

                const SizedBox(height: 32),

                // Boutons d'action
                _buildActionButtons(session),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStateVisual(ShareSession session) {
    final isWaiting = session.state == NfcShareState.writing ||
        session.state == NfcShareState.reading;
    final isDone = session.state == NfcShareState.completed;
    final isFailed = session.state == NfcShareState.failed;

    Color color;
    IconData icon;
    if (isDone) {
      color = Colors.green;
      icon = Icons.check_circle_rounded;
    } else if (isFailed) {
      color = NotitiaTheme.redRecording;
      icon = Icons.error_rounded;
    } else {
      color = session.mode == ShareMode.sender
          ? NotitiaTheme.neonPink
          : NotitiaTheme.neonCyan;
      icon = Icons.nfc_rounded;
    }

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple animé en mode attente
          if (isWaiting)
            AnimatedBuilder(
              animation: _rippleController,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(200, 200),
                  painter: _RipplePainter(
                    progress: _rippleController.value,
                    color: color,
                  ),
                );
              },
            ),
          // Icône centrale
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final scale =
                  isWaiting ? 1.0 + _pulseController.value * 0.15 : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 48),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStateText(ShareSession session) {
    String title;
    String subtitle;

    switch (session.state) {
      case NfcShareState.writing:
        title = 'ÉMISSION NFC';
        subtitle = 'Approchez l\'autre téléphone pour partager';
        break;
      case NfcShareState.reading:
        title = 'RÉCEPTION NFC';
        subtitle = 'Approchez l\'autre téléphone pour recevoir';
        break;
      case NfcShareState.completed:
        title = 'TERMINÉ';
        subtitle = session.mode == ShareMode.sender
            ? 'Transcription envoyée !'
            : 'Transcription reçue et importée !';
        break;
      case NfcShareState.failed:
        title = 'ERREUR';
        subtitle = 'Le partage NFC a échoué';
        break;
      default:
        title = '';
        subtitle = '';
    }

    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.orbitron(
            color: NotitiaTheme.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            color: NotitiaTheme.grey,
            fontSize: 14,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NotitiaTheme.redRecording.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: NotitiaTheme.redRecording.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded,
              color: NotitiaTheme.redRecording, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                color: NotitiaTheme.redRecording,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ShareSession session) {
    if (session.state == NfcShareState.completed) {
      // Récepteur avec transcription reçue → bouton "VOIR"
      if (session.mode == ShareMode.receiver &&
          session.receivedTranscription != null) {
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                // Pop avec la transcription reçue pour que l'appelant puisse rafraîchir
                Navigator.of(context).pop(session.receivedTranscription);
              },
              icon: const Icon(Icons.visibility_rounded),
              label: Text('VOIR LA TRANSCRIPTION',
                  style: GoogleFonts.orbitron(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: NotitiaTheme.neonCyan,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('FERMER',
                  style: GoogleFonts.orbitron(
                      fontSize: 11, color: NotitiaTheme.grey)),
            ),
          ],
        );
      }

      // Émetteur → bouton "TERMINÉ"
      return ElevatedButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.check_rounded),
        label: Text('TERMINÉ', style: GoogleFonts.orbitron(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    if (session.state == NfcShareState.failed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              _cancel();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close_rounded),
            label: Text('FERMER', style: GoogleFonts.orbitron(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: NotitiaTheme.grey,
              side: const BorderSide(color: NotitiaTheme.grey),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () {
              _cancel();
              if (session.mode == ShareMode.sender) {
                _startSending();
              } else {
                _startReceiving();
              }
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text('RÉESSAYER', style: GoogleFonts.orbitron(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: NotitiaTheme.neonPink,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      );
    }

    // Session en cours — bouton Annuler
    return OutlinedButton.icon(
      onPressed: _cancel,
      icon: const Icon(Icons.close_rounded),
      label: Text('ANNULER', style: GoogleFonts.orbitron(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: NotitiaTheme.redRecording,
        side: const BorderSide(color: NotitiaTheme.redRecording),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UTILITAIRES
  // ---------------------------------------------------------------------------
}

// =============================================================================
// RIPPLE PAINTER — Animation NFC
// =============================================================================

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const rippleCount = 3;

    for (var i = 0; i < rippleCount; i++) {
      final rippleProgress = (progress + i / rippleCount) % 1.0;
      final radius = rippleProgress * size.width / 2;
      final opacity = (1.0 - rippleProgress).clamp(0.0, 0.4);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.progress != progress;
}

// =============================================================================
// BOUTONS RÉUTILISABLES — NfcShareButton & NfcReceiveButton
// =============================================================================

/// Bouton "Partager via NFC" à placer dans les pages.
class NfcShareButton extends StatelessWidget {
  final Transcription transcription;
  final VoidCallback? onShared;

  const NfcShareButton({
    super.key,
    required this.transcription,
    this.onShared,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.nfc_rounded, color: NotitiaTheme.neonCyan),
      tooltip: 'Partager via NFC',
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TapToSharePage(transcription: transcription),
          ),
        );
        onShared?.call();
      },
    );
  }
}

/// Bouton "Recevoir via NFC" à placer dans les pages.
class NfcReceiveButton extends StatelessWidget {
  final VoidCallback? onReceived;

  const NfcReceiveButton({
    super.key,
    this.onReceived,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.contactless_rounded, color: NotitiaTheme.neonCyan),
      tooltip: 'Recevoir via NFC',
      onPressed: () async {
        final result = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(
            builder: (_) => TapToSharePage(
              onReceived: (_) => onReceived?.call(),
            ),
          ),
        );
        // Si on reçoit une Transcription, ouvrir l'éditeur puis rafraîchir
        if (result is Transcription && context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditPage(transcription: result),
            ),
          );
          onReceived?.call();
        } else if (result == true) {
          // FERMER pressé après réception réussie → rafraîchir l'historique
          onReceived?.call();
        }
      },
    );
  }
}
