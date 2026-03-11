// =============================================================================
// NOTITIA — Page Réunion (onglet principal)
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meeting.dart';
import '../models/transcription.dart';
import '../services/deepgram_service.dart';
import '../services/meeting_service.dart';
import '../services/mistral_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/meduza_speech_bubble.dart';

class MeetingPage extends StatefulWidget {
  final ValueNotifier<int> refreshNotifier;
  final void Function(MeduzaState state, {String? message, BubbleStyle style})?
  onMeduzaStateChanged;

  /// Callback pour naviguer vers l'onglet historique filtré sur les réunions.
  final VoidCallback? onNavigateToHistory;

  const MeetingPage({
    super.key,
    required this.refreshNotifier,
    this.onMeduzaStateChanged,
    this.onNavigateToHistory,
  });

  /// Charge l'historique des réunions.
  static Future<List<Meeting>> loadMeetingHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notitia_meetings') ?? [];
    return list
        .map((s) => Meeting.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  // ---------------------------------------------------------------------------
  // État
  // ---------------------------------------------------------------------------
  _MeetingView _currentView = _MeetingView.home;

  // Host
  final MeetingHostService _hostService = MeetingHostService();
  String? _qrData;
  DateTime? _meetingStartedAt;
  Timer? _durationTimer;
  Duration _meetingDuration = Duration.zero;
  bool _isRecording = false;
  bool _isStopping = false;

  // Deepgram pour l'enregistrement
  late DeepgramService _deepgram;
  String _liveText = '';
  String _fullTranscript = '';

  // Participant (join)
  final MeetingClientService _clientService = MeetingClientService();
  bool _joining = false;
  String? _joinError;

  // Localization
  final _languageService = LanguageService();

  // ---------------------------------------------------------------------------
  // Cycle de vie
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _deepgram = DeepgramService();
    _deepgram.onTranscript = _onDeepgramTranscript;
    _deepgram.onError = (err) => debugPrint('Deepgram erreur: $err');
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _hostService.stopServer();
    _clientService.disconnect();
    _deepgram.stopListening();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Deepgram callbacks
  // ---------------------------------------------------------------------------
  void _onDeepgramTranscript(String text, bool isFinal) {
    if (!mounted) return;
    setState(() {
      if (isFinal && text.isNotEmpty) {
        _fullTranscript += '${_fullTranscript.isEmpty ? '' : ' '}$text';
        _liveText = '';
      } else {
        _liveText = text;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // LANCER UNE RÉUNION (Host) — Crée le serveur + affiche QR code
  // ---------------------------------------------------------------------------
  Future<void> _startMeeting() async {
    final userName = await _getUserName();
    final qrData = await _hostService.startServer(hostName: userName);
    if (qrData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('server_start_error'),
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            backgroundColor: NotitiaTheme.redRecording,
          ),
        );
      }
      return;
    }

    _hostService.onParticipantJoined = (p) {
      if (mounted) setState(() {});
    };

    setState(() {
      _qrData = qrData;
      _isRecording = false;
      _currentView = _MeetingView.hosting;
    });

    widget.onMeduzaStateChanged?.call(
      MeduzaState.idle,
      message: _languageService.translate('waiting_for_participants'),
      style: BubbleStyle.normal,
    );
  }

  // ---------------------------------------------------------------------------
  // LANCER L'ENREGISTREMENT (Host appuie sur "Lancer")
  // ---------------------------------------------------------------------------
  Future<void> _launchRecording() async {
    _fullTranscript = '';
    _liveText = '';
    await _deepgram.startListening();

    _hostService.startRecording();

    _meetingStartedAt = DateTime.now();
    _meetingDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _meetingDuration = DateTime.now().difference(_meetingStartedAt!);
        });
      }
    });

    setState(() => _isRecording = true);

    widget.onMeduzaStateChanged?.call(
      MeduzaState.listening,
      message: _languageService.translate('meeting_recording_in_progress'),
      style: BubbleStyle.normal,
    );
  }

  // ---------------------------------------------------------------------------
  // STOPPER LA RÉUNION (Host)
  // ---------------------------------------------------------------------------
  Future<void> _stopMeeting() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.5)),
        ),
        title: Text(
          _languageService.translate('end_meeting_dialog_title'),
          style: GoogleFonts.orbitron(
            fontSize: 14,
            color: NotitiaTheme.neonPink,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          _languageService.translate('end_meeting_dialog_confirm'),
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
              _languageService.translate('confirm'),
              style: GoogleFonts.orbitron(
                fontSize: 11,
                color: NotitiaTheme.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isStopping = true);

    widget.onMeduzaStateChanged?.call(
      MeduzaState.processing,
      message: _languageService.translate('processing_transcription'),
      style: BubbleStyle.normal,
    );

    _durationTimer?.cancel();
    await _deepgram.stopListening();

    // Correction Mistral du transcript
    String finalContent = _fullTranscript;
    if (finalContent.isNotEmpty) {
      try {
        finalContent = await MistralService.instance.correctTranscription(
          finalContent,
        );
      } catch (e) {
        debugPrint('Erreur Mistral: $e');
      }
    }

    // Créer la transcription
    final participantNames = _hostService.participants
        .map((p) => p.name)
        .join(', ');
    final hostName = await _getUserName();
    final title = _languageService
        .translate('meeting_title_template')
        .replaceAll('{hostname}', hostName)
        .replaceAll(
          '{participants}',
          participantNames.isNotEmpty ? ' + $participantNames' : '',
        );

    final transcription = Transcription.create(
      content: finalContent.isEmpty
          ? _languageService.translate('no_transcription_recorded')
          : finalContent,
      title: title,
      tag: TranscriptionTag.reunion,
    );

    // Sauvegarder localement (host)
    await StorageService.save(transcription);

    // Rendre la transcription disponible aux participants via le serveur
    _hostService.endMeeting(transcription);

    // Sauvegarder les métadonnées de la réunion
    final meeting = _hostService.buildMeetingRecord(
      startedAt: _meetingStartedAt!,
      transcriptionId: transcription.id,
    );
    await _saveMeetingRecord(meeting);

    widget.refreshNotifier.value++;

    widget.onMeduzaStateChanged?.call(
      MeduzaState.happy,
      message: _languageService
          .translate('meeting_ended_success_message')
          .replaceAll('{count}', _hostService.participants.length.toString()),
      style: BubbleStyle.success,
    );

    // Laisser le temps aux WebSockets de livrer la transcription
    await Future.delayed(const Duration(seconds: 3));
    await _hostService.stopServer();

    if (mounted) {
      setState(() {
        _currentView = _MeetingView.home;
        _qrData = null;
        _fullTranscript = '';
        _liveText = '';
        _isRecording = false;
        _isStopping = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // REJOINDRE UNE RÉUNION (Participant — Scan QR)
  // ---------------------------------------------------------------------------
  Future<void> _openQrScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );

    if (result == null || !mounted) return;

    setState(() {
      _joining = true;
      _joinError = null;
      _currentView = _MeetingView.joined;
    });

    final userName = await _getUserName();
    final success = await _clientService.joinMeeting(
      qrData: result,
      participantName: userName,
    );

    if (!success) {
      setState(() {
        _joinError = _languageService.translate('join_meeting_error');
        _joining = false;
        _currentView = _MeetingView.home;
      });
      return;
    }

    _clientService.onStatusChanged = (status) {
      if (mounted) setState(() {});
    };

    _clientService.onTranscriptionReceived = (transcription) async {
      await StorageService.save(transcription);

      // Sauvegarder les métadonnées de la réunion côté participant
      final meeting = Meeting(
        id:
            _clientService.meetingId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        hostName: _clientService.hostName ?? 'Hôte',
        startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        endedAt: DateTime.now(),
        participants: _clientService.participants.toList(),
        transcriptionId: transcription.id,
      );
      await _saveMeetingRecord(meeting);

      widget.refreshNotifier.value++;

      widget.onMeduzaStateChanged?.call(
        MeduzaState.happy,
        message: _languageService.translate('transcription_received'),
        style: BubbleStyle.success,
      );

      _clientService.disconnect();
      if (mounted) {
        setState(() => _currentView = _MeetingView.home);
      }
    };

    _clientService.onParticipantsUpdated = (_) {
      if (mounted) setState(() {});
    };

    setState(() => _joining = false);
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------
  Future<String> _getUserName() async {
    final authService = AuthService();
    if (authService.isAuthenticated) {
      final profile = await authService.getProfile();
      if (profile?.username != null && profile!.username!.isNotEmpty) {
        return profile.username!;
      }
      if (profile?.email != null) {
        return profile!.email!.split('@').first;
      }
    }
    // Guest mode
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('notitia_guest_name') ?? 'Participant';
  }

  /// Sauvegarde un enregistrement de réunion dans le stockage local.
  Future<void> _saveMeetingRecord(Meeting meeting) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('notitia_meetings') ?? [];
    existing.insert(0, jsonEncode(meeting.toJson()));
    await prefs.setStringList('notitia_meetings', existing);
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Bloquer l'onglet pour les utilisateurs non connectés
    final authService = AuthService();
    if (!authService.isAuthenticated) {
      return _buildAuthRequiredPage();
    }

    switch (_currentView) {
      case _MeetingView.home:
        return _buildHomePage();
      case _MeetingView.hosting:
        return _buildHostingPage();
      case _MeetingView.joined:
        return _buildJoinedPage();
    }
  }

  // ===== PAGE — Compte requis =====
  Widget _buildAuthRequiredPage() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NotitiaTheme.neonPink.withValues(alpha: 0.12),
                  border: Border.all(
                    color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: NotitiaTheme.neonPink,
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _languageService.translate('authentication_required_title'),
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  color: NotitiaTheme.neonPink,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _languageService.translate('meeting_requires_account'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: NotitiaTheme.grey,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/auth');
                  },
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: Text(
                    _languageService.translate('sign_in_button_label'),
                    style: GoogleFonts.orbitron(
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NotitiaTheme.neonPink,
                    foregroundColor: NotitiaTheme.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== PAGE D'ACCUEIL RÉUNION =====
  Widget _buildHomePage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Header
            Row(
              children: [
                const Icon(
                  Icons.groups_rounded,
                  color: NotitiaTheme.neonPink,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  _languageService.translate('meeting_section_title'),
                  style: GoogleFonts.orbitron(
                    fontSize: 18,
                    color: NotitiaTheme.white,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(color: NotitiaTheme.neonPink.withValues(alpha: 0.3)),
            const SizedBox(height: 32),

            // Description
            Text(
              _languageService.translate('meeting_home_description'),
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: NotitiaTheme.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),

            // Bouton LANCER
            _buildActionButton(
              icon: Icons.play_circle_outline_rounded,
              label: _languageService.translate('start_meeting_button'),
              subtitle: _languageService.translate('start_meeting_subtitle'),
              color: NotitiaTheme.neonPink,
              onTap: _startMeeting,
            ),
            const SizedBox(height: 20),

            // Bouton REJOINDRE
            _buildActionButton(
              icon: Icons.qr_code_scanner_rounded,
              label: _languageService.translate('join_meeting_button'),
              subtitle: _languageService.translate('join_meeting_subtitle'),
              color: NotitiaTheme.neonCyan,
              onTap: _openQrScanner,
            ),
            const SizedBox(height: 20),

            // Bouton HISTORIQUE
            _buildActionButton(
              icon: Icons.history_rounded,
              label: _languageService.translate('meeting_history_button'),
              subtitle: _languageService.translate('meeting_history_subtitle'),
              color: NotitiaTheme.grey,
              onTap: widget.onNavigateToHistory,
            ),

            // Afficher erreur de join si présente
            if (_joinError != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NotitiaTheme.redRecording.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NotitiaTheme.redRecording.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: NotitiaTheme.redRecording,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _joinError!,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: NotitiaTheme.redRecording,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: NotitiaTheme.darkBlue,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.orbitron(
                      fontSize: 12,
                      color: color,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: NotitiaTheme.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  // ===== PAGE HOST — Salle d'attente + Réunion en cours =====
  Widget _buildHostingPage() {
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (!_isRecording)
                      GestureDetector(
                        onTap: () async {
                          await _hostService.stopServer();
                          if (mounted) {
                            setState(() {
                              _currentView = _MeetingView.home;
                              _qrData = null;
                            });
                          }
                        },
                        child: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: NotitiaTheme.white,
                          size: 20,
                        ),
                      ),
                    if (_isRecording)
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NotitiaTheme.redRecording,
                          boxShadow: [
                            BoxShadow(
                              color: NotitiaTheme.redRecording.withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 10),
                    Text(
                      _isRecording
                          ? _languageService.translate(
                              'meeting_in_progress_label',
                            )
                          : _languageService.translate('waiting_room_label'),
                      style: GoogleFonts.orbitron(
                        fontSize: 16,
                        color: _isRecording
                            ? NotitiaTheme.redRecording
                            : NotitiaTheme.neonCyan,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    if (_isRecording)
                      Text(
                        Meeting.formatDuration(_meetingDuration),
                        style: GoogleFonts.orbitron(
                          fontSize: 16,
                          color: NotitiaTheme.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Divider(
                color:
                    (_isRecording
                            ? NotitiaTheme.redRecording
                            : NotitiaTheme.neonCyan)
                        .withValues(alpha: 0.3),
                indent: 20,
                endIndent: 20,
              ),
              const SizedBox(height: 16),

              // QR Code
              if (_qrData != null) ...[
                Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: _isRecording ? 60 : 40,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: NotitiaTheme.neonPink.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _QrCodeWidget(
                    data: _qrData!,
                    size: _isRecording ? 140.0 : 220.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _languageService.translate('scan_qr_instruction'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: NotitiaTheme.grey,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Liste des participants
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_outline,
                      color: NotitiaTheme.neonCyan,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _languageService
                          .translate('participants_label')
                          .replaceAll(
                            '{count}',
                            (_hostService.participants.length + 1).toString(),
                          ),
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        color: NotitiaTheme.neonCyan,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 16,
                  ),
                  children: [
                    _buildParticipantTile(
                      name: _languageService.translate('you_host_label'),
                      isHost: true,
                    ),
                    ..._hostService.participants.map(
                      (p) => _buildParticipantTile(name: p.name),
                    ),

                    // Transcription en direct (seulement en enregistrement)
                    if (_isRecording &&
                        (_fullTranscript.isNotEmpty ||
                            _liveText.isNotEmpty)) ...[
                      const SizedBox(height: 20),
                      Divider(
                        color: NotitiaTheme.neonPink.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _languageService.translate('live_transcription_label'),
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          color: NotitiaTheme.neonPink,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: NotitiaTheme.darkBlue,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: NotitiaTheme.neonPink.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        ),
                        child: Text(
                          '$_fullTranscript${_liveText.isNotEmpty ? ' $_liveText' : ''}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: NotitiaTheme.white.withValues(alpha: 0.85),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Bouton LANCER ou STOPPER
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: _isRecording
                      ? ElevatedButton.icon(
                          onPressed: _isStopping ? null : _stopMeeting,
                          icon: const Icon(Icons.stop_rounded, size: 28),
                          label: Text(
                            _languageService.translate('stop_recording_button'),
                            style: GoogleFonts.orbitron(
                              fontSize: 13,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NotitiaTheme.redRecording,
                            foregroundColor: NotitiaTheme.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                            shadowColor: NotitiaTheme.redRecording.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _launchRecording,
                          icon: const Icon(Icons.mic_rounded, size: 26),
                          label: Text(
                            _languageService.translate(
                              'start_recording_button',
                            ),
                            style: GoogleFonts.orbitron(
                              fontSize: 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NotitiaTheme.neonPink,
                            foregroundColor: NotitiaTheme.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                            shadowColor: NotitiaTheme.neonPink.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),

        // Overlay de chargement lors de l'arrêt
        if (_isStopping)
          Container(
            color: NotitiaTheme.deepBlue.withValues(alpha: 0.85),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: NotitiaTheme.neonPink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _languageService.translate('processing_label'),
                    style: GoogleFonts.orbitron(
                      fontSize: 14,
                      color: NotitiaTheme.neonPink,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _languageService.translate('processing_detail'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: NotitiaTheme.grey,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantTile({required String name, bool isHost = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NotitiaTheme.darkBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHost
                ? NotitiaTheme.neonPink.withValues(alpha: 0.3)
                : NotitiaTheme.neonCyan.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isHost
                    ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
                    : NotitiaTheme.neonCyan.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    color: isHost
                        ? NotitiaTheme.neonPink
                        : NotitiaTheme.neonCyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: NotitiaTheme.white,
                ),
              ),
            ),
            if (isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NotitiaTheme.neonPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _languageService.translate('host_label'),
                  style: GoogleFonts.orbitron(
                    fontSize: 9,
                    color: NotitiaTheme.neonPink,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== PAGE PARTICIPANT — Réunion rejointe =====
  Widget _buildJoinedPage() {
    if (_joining) {
      return const Center(
        child: CircularProgressIndicator(color: NotitiaTheme.neonCyan),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _clientService.status == MeetingStatus.ended
                        ? NotitiaTheme.neonPink
                        : NotitiaTheme.neonCyan,
                    boxShadow: [
                      BoxShadow(
                        color: _clientService.status == MeetingStatus.ended
                            ? NotitiaTheme.neonPink.withValues(alpha: 0.5)
                            : NotitiaTheme.neonCyan.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _clientService.status == MeetingStatus.waiting
                      ? _languageService.translate('status_waiting')
                      : _clientService.status == MeetingStatus.ended
                      ? _languageService.translate('status_meeting_ended')
                      : _languageService.translate(
                          'status_meeting_in_progress',
                        ),
                  style: GoogleFonts.orbitron(
                    fontSize: 16,
                    color: _clientService.status == MeetingStatus.ended
                        ? NotitiaTheme.neonPink
                        : NotitiaTheme.neonCyan,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Divider(
            color: NotitiaTheme.neonCyan.withValues(alpha: 0.3),
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 20),

          // Info host
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NotitiaTheme.darkBlue,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: NotitiaTheme.neonCyan.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _languageService
                        .translate('host_info_label')
                        .replaceAll(
                          '{hostname}',
                          _clientService.hostName ?? '…',
                        ),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: NotitiaTheme.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _languageService.translate('host_recording_info'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: NotitiaTheme.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Participants
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.people_outline,
                  color: NotitiaTheme.neonCyan,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _languageService
                      .translate('participants_label')
                      .replaceAll(
                        '{count}',
                        _clientService.participants.length.toString(),
                      ),
                  style: GoogleFonts.orbitron(
                    fontSize: 12,
                    color: NotitiaTheme.neonCyan,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              children: _clientService.participants
                  .map((p) => _buildParticipantTile(name: p.name))
                  .toList(),
            ),
          ),

          // Message d'attente
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NotitiaTheme.neonCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: NotitiaTheme.neonCyan.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _clientService.status == MeetingStatus.ended
                          ? NotitiaTheme.neonPink.withValues(alpha: 0.6)
                          : NotitiaTheme.neonCyan.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _clientService.status == MeetingStatus.waiting
                          ? _languageService.translate('waiting_host_launch')
                          : _clientService.status == MeetingStatus.ended
                          ? _languageService.translate(
                              'receiving_transcription',
                            )
                          : _languageService.translate('waiting_meeting_end'),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _clientService.status == MeetingStatus.ended
                            ? NotitiaTheme.neonPink.withValues(alpha: 0.8)
                            : NotitiaTheme.neonCyan.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Vue interne
// =============================================================================
enum _MeetingView { home, hosting, joined }

// =============================================================================
// Widget QR Code — Stylisé aux couleurs Notitia
// =============================================================================
class _QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  const _QrCodeWidget({required this.data, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFFFF0178), // Neon Pink
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.circle,
            color: Color(0xFF00003F), // Deep Blue
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'NOTITIA',
          style: GoogleFonts.orbitron(
            fontSize: size > 180 ? 14 : 10,
            color: const Color(0xFFFF0178),
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Scanner QR — Interface avec viseur
// =============================================================================
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _hasScanned = false;
  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;
  final _languageService = LanguageService();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double scanSize = 250;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth;
          final fullHeight = constraints.maxHeight;
          final centerY = fullHeight / 2 - 30;
          final centerX = fullWidth / 2;

          return Stack(
            children: [
              // Caméra plein écran
              SizedBox(
                width: fullWidth,
                height: fullHeight,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (_hasScanned) return;
                    final barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final value = barcode.rawValue;
                      if (value != null && value.isNotEmpty) {
                        try {
                          final data = jsonDecode(value);
                          if (data is Map && data.containsKey('meetingId')) {
                            _hasScanned = true;
                            Navigator.pop(context, value);
                            return;
                          }
                        } catch (_) {}
                      }
                    }
                  },
                ),
              ),

              // Overlay sombre avec découpe transparente
              Positioned.fill(
                child: CustomPaint(
                  size: Size(fullWidth, fullHeight),
                  painter: _ViewfinderOverlayPainter(
                    scanSize: scanSize,
                    screenSize: Size(fullWidth, fullHeight),
                  ),
                ),
              ),

              // Coins du viseur (L-shapes)
              Positioned.fill(
                child: CustomPaint(
                  size: Size(fullWidth, fullHeight),
                  painter: _ViewfinderCornersPainter(
                    scanSize: scanSize,
                    screenSize: Size(fullWidth, fullHeight),
                  ),
                ),
              ),

              // Ligne de scan animée
              AnimatedBuilder(
                animation: _scanLineAnimation,
                builder: (context, _) {
                  final top = centerY - scanSize / 2;
                  final lineY = top + scanSize * _scanLineAnimation.value;
                  return Positioned(
                    left: centerX - scanSize / 2 + 20,
                    top: lineY,
                    child: Container(
                      width: scanSize - 40,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            NotitiaTheme.neonPink.withValues(alpha: 0.0),
                            NotitiaTheme.neonPink.withValues(alpha: 0.8),
                            NotitiaTheme.neonPink.withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NotitiaTheme.neonPink.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Barre du haut
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NotitiaTheme.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _languageService.translate('scanner_title'),
                        style: GoogleFonts.orbitron(
                          fontSize: 15,
                          color: NotitiaTheme.white,
                          letterSpacing: 4,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 42),
                    ],
                  ),
                ),
              ),

              // Texte d'instruction en bas
              Positioned(
                bottom: 60,
                left: 30,
                right: 30,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: NotitiaTheme.deepBlue.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: NotitiaTheme.neonCyan.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          color: NotitiaTheme.neonCyan.withValues(alpha: 0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _languageService.translate('scanner_instruction'),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// Painters pour le viseur du scanner
// =============================================================================
class _ViewfinderOverlayPainter extends CustomPainter {
  final double scanSize;
  final Size screenSize;
  _ViewfinderOverlayPainter({required this.scanSize, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);
    final scanRect = Rect.fromCenter(
      center: center,
      width: scanSize,
      height: scanSize,
    );

    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ViewfinderCornersPainter extends CustomPainter {
  final double scanSize;
  final Size screenSize;
  _ViewfinderCornersPainter({required this.scanSize, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);
    final rect = Rect.fromCenter(
      center: center,
      width: scanSize,
      height: scanSize,
    );

    const cornerLen = 35.0;
    const radius = 16.0;
    final paint = Paint()
      ..color =
          const Color(0xFFFF0178) // Neon Pink
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    final tlPath = Path()
      ..moveTo(rect.left, rect.top + cornerLen)
      ..lineTo(rect.left, rect.top + radius)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top)
      ..lineTo(rect.left + cornerLen, rect.top);
    canvas.drawPath(tlPath, paint);

    // Top-right corner
    final trPath = Path()
      ..moveTo(rect.right - cornerLen, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius)
      ..lineTo(rect.right, rect.top + cornerLen);
    canvas.drawPath(trPath, paint);

    // Bottom-left corner
    final blPath = Path()
      ..moveTo(rect.left, rect.bottom - cornerLen)
      ..lineTo(rect.left, rect.bottom - radius)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left + radius,
        rect.bottom,
      )
      ..lineTo(rect.left + cornerLen, rect.bottom);
    canvas.drawPath(blPath, paint);

    // Bottom-right corner
    final brPath = Path()
      ..moveTo(rect.right - cornerLen, rect.bottom)
      ..lineTo(rect.right - radius, rect.bottom)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right,
        rect.bottom - radius,
      )
      ..lineTo(rect.right, rect.bottom - cornerLen);
    canvas.drawPath(brPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
