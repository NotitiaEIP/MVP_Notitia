// =============================================================================
// NOTITIA — Page de capture vocale (Speech-to-Text)
// =============================================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/transcription.dart';
import '../services/deepgram_service.dart';
import '../services/foreground_service.dart';
import '../services/language_service.dart';
import '../services/mistral_service.dart';
import '../services/rag_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/meduza_speech_bubble.dart';
import '../widgets/profile_button.dart';
import '../services/auth_service.dart';

/// Choix du moteur de transcription
enum STTEngine {
  native, // speech_to_text (Google/Apple natif)
  deepgram, // Deepgram Nova-3 (cloud, haute précision)
}

class CapturePage extends StatefulWidget {
  final VoidCallback? onTranscriptionSaved;
  final void Function(MeduzaState state, {String? message, BubbleStyle style})?
  onMeduzaStateChanged;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;
  final bool fromOnboarding;
  const CapturePage({
    super.key,
    this.onTranscriptionSaved,
    this.onMeduzaStateChanged,
    this.profile,
    this.onProfileTap,
    this.fromOnboarding = false,
  });

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // Choix du moteur STT
  // ---------------------------------------------------------------------------
  STTEngine _sttEngine = STTEngine.deepgram; // Par défaut: Deepgram Nova-3
  final LanguageService _languageService = LanguageService();

  // ---------------------------------------------------------------------------
  // Speech-to-Text (Natif)
  // ---------------------------------------------------------------------------
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;

  // ---------------------------------------------------------------------------
  // Deepgram Nova-3
  // ---------------------------------------------------------------------------
  late DeepgramService _deepgram;

  // ---------------------------------------------------------------------------
  // État commun
  // ---------------------------------------------------------------------------
  bool _isListening = false;
  String _liveText = '';
  String _fullTranscript = '';
  double _confidence = 0.0;
  Duration _listenDuration = Duration.zero;
  Timer? _durationTimer;

  // ---------------------------------------------------------------------------
  // IA Mistral — correction automatique des transcriptions
  // ---------------------------------------------------------------------------
  bool _isEnhancing = false; // Pendant la correction Mistral
  int _iaCorrectionCount = 0; // Nombre de corrections IA

  // ---------------------------------------------------------------------------
  // Écoute active (background)
  // ---------------------------------------------------------------------------
  bool _isActiveMode = false;

  // ---------------------------------------------------------------------------
  // Animation pulse
  // ---------------------------------------------------------------------------
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Entrance animation (after onboarding)
  AnimationController? _entranceController;
  late Animation<double> _entranceFade;
  late Animation<double> _entranceScale;
  late Animation<double> _entranceTextFade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSpeech();
    _initDeepgram();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _pulseController.reverse();
      if (status == AnimationStatus.dismissed && _isListening) {
        _pulseController.forward();
      }
    });

    // Entrance animation when arriving from onboarding
    if (widget.fromOnboarding) {
      _entranceController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );
      _entranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController!,
          curve: const Interval(0, 0.5, curve: Curves.easeOut),
        ),
      );
      _entranceScale = Tween<double>(begin: 1.8, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController!,
          curve: const Interval(0.05, 0.65, curve: Curves.easeOutCubic),
        ),
      );
      _entranceTextFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController!,
          curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
        ),
      );
      _entranceController!.forward();
    } else {
      _entranceFade = const AlwaysStoppedAnimation(1.0);
      _entranceScale = const AlwaysStoppedAnimation(1.0);
      _entranceTextFade = const AlwaysStoppedAnimation(1.0);
    }
  }

  /// Initialise le service Deepgram Nova-3
  void _initDeepgram() {
    _deepgram = DeepgramService(
      language: 'fr',
      model: 'nova-3',
      punctuate: true,
      smartFormat: true,
      interimResults: true,
    );

    // Callbacks Deepgram
    _deepgram.onTranscript = (text, isFinal) {
      if (!mounted) return;
      setState(() {
        if (isFinal) {
          if (_fullTranscript.isNotEmpty) _fullTranscript += ' ';
          _fullTranscript += text;
          _liveText = '';
        } else {
          _liveText = text;
        }
        _confidence = _deepgram.confidence;
      });
    };

    _deepgram.onError = (error) {
      debugPrint('❌ Deepgram error: $error');
      _showSnackBar('Erreur Deepgram: $error');
    };

    _deepgram.onConnected = () {
      debugPrint('✅ Deepgram connecté');
    };

    _deepgram.onDisconnected = () {
      debugPrint('🔌 Deepgram déconnecté');
    };
  }

  Future<void> _initSpeech() async {
    // Demander explicitement la permission de reconnaissance vocale
    final speechStatus = await Permission.speech.request();
    if (!speechStatus.isGranted) {
      debugPrint('Speech permission denied: $speechStatus');
    }
    // Demander aussi la permission micro (nécessaire pour le STT natif)
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('Microphone permission denied: $micStatus');
    }

    _speechEnabled = await _speechToText.initialize(
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg}');
        if (_isListening &&
            _sttEngine == STTEngine.native &&
            error.errorMsg == 'error_speech_timeout') {
          _restartListening();
        }
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (_isListening &&
            _sttEngine == STTEngine.native &&
            (status == 'done' || status == 'notListening')) {
          _restartListening();
        }
      },
    );
    debugPrint('Speech enabled: $_speechEnabled');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _pulseController.dispose();
    _entranceController?.dispose();
    _speechToText.stop();
    _deepgram.dispose();
    if (_isActiveMode) ActiveListeningService.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle — Détecte quand l'app passe en arrière-plan / revient
  // ---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isListening) {
      // L'app revient au premier plan — rafraîchir l'UI avec le transcript accumulé
      debugPrint('[Notitia] App resumed — refreshing UI');
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------
  Future<bool> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnackBar(_languageService.translate('mic_permission_denied'));
      return false;
    }
    return true;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: NotitiaTheme.neonPink,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Contrôle de la transcription
  // ---------------------------------------------------------------------------
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!await _requestMicPermission()) return;

    // Vérifier la disponibilité selon le moteur
    if (_sttEngine == STTEngine.native && !_speechEnabled) {
      _showSnackBar(_languageService.translate('native_service_unavailable'));
      // Tenter de réinitialiser
      await _initSpeech();
      if (!_speechEnabled) return;
    }

    setState(() {
      _isListening = true;
      _liveText = '';
      _fullTranscript = '';
      _confidence = 0.0;
      _listenDuration = Duration.zero;
    });

    // Meduza - ecoute active
    widget.onMeduzaStateChanged?.call(
      MeduzaState.listening,
      message: _languageService.translate('listening_prompt'),
    );

    _pulseController.forward();

    // Démarrer le foreground service si écoute active
    if (_isActiveMode && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await ActiveListeningService.start();
    }

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _listenDuration += const Duration(seconds: 1));
        // Mettre à jour la notification avec la durée
        if (_isActiveMode && ActiveListeningService.isRunning) {
          ActiveListeningService.updateNotification(
            _languageService
                .translate('transcription_in_progress')
                .replaceAll('{duration}', _formatDuration(_listenDuration)),
          );
        }
      }
    });

    await _doListen();
  }

  Future<void> _doListen() async {
    if (_sttEngine == STTEngine.deepgram) {
      // 🎙️ Deepgram Nova-3
      await _doListenDeepgram();
    } else {
      // 📱 Speech-to-Text natif
      await _doListenNative();
    }
  }

  /// Écoute avec Deepgram Nova-3
  Future<void> _doListenDeepgram() async {
    try {
      final success = await _deepgram.startListening();
      if (!success) {
        _showSnackBar('Impossible de démarrer Deepgram');
        await _stopListening();
      }
    } catch (e) {
      debugPrint('❌ Deepgram listen error: $e');
      _showSnackBar('Erreur Deepgram: $e');
    }
  }

  /// Écoute avec le moteur natif (Google/Apple)
  Future<void> _doListenNative() async {
    try {
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _liveText = result.recognizedWords;
            if (result.hasConfidenceRating && result.confidence > 0) {
              _confidence = result.confidence;
            }
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              if (_fullTranscript.isNotEmpty) _fullTranscript += ' ';
              _fullTranscript += result.recognizedWords;
              _liveText = '';
            }
          });
        },
        localeId: 'fr_FR',
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 10),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          partialResults: true,
          autoPunctuation: true,
          enableHapticFeedback: true,
        ),
      );
    } catch (e) {
      debugPrint('Listen error: $e');
    }
  }

  Future<void> _restartListening() async {
    if (!_isListening || !mounted) return;
    // Ne pas redémarrer si on utilise Deepgram (gère son propre flux)
    if (_sttEngine == STTEngine.deepgram) return;
    await Future.delayed(const Duration(milliseconds: 200));
    if (_isListening && mounted) await _doListen();
  }

  Future<void> _stopListening() async {
    // Arrêter selon le moteur
    if (_sttEngine == STTEngine.deepgram) {
      await _deepgram.stopListening();
      // Récupérer le transcript final depuis Deepgram
      _fullTranscript = _deepgram.fullTranscript;
    } else {
      await _speechToText.stop();
    }

    _durationTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    // Arrêter le foreground service
    if (_isActiveMode && ActiveListeningService.isRunning) {
      await ActiveListeningService.stop();
    }

    if (_liveText.isNotEmpty) {
      if (_fullTranscript.isNotEmpty) _fullTranscript += ' ';
      _fullTranscript += _liveText;
    }

    setState(() {
      _isListening = false;
      _liveText = '';
    });

    // Correction automatique par Mistral AI
    if (_fullTranscript.trim().isNotEmpty) {
      // Meduza - traitement en cours
      widget.onMeduzaStateChanged?.call(
        MeduzaState.processing,
        message: 'Correction IA en cours...',
      );
      await _enhanceWithMistral();
    } else {
      // Rien capture — retour idle
      widget.onMeduzaStateChanged?.call(MeduzaState.idle);
    }
  }

  /// Corrige et améliore la transcription via Mistral AI (appel cloud direct)
  Future<void> _enhanceWithMistral() async {
    if (_fullTranscript.trim().isEmpty) return;

    setState(() {
      _isEnhancing = true;
      _iaCorrectionCount = 0;
    });

    try {
      debugPrint('[Notitia] Correction Mistral en cours...');
      final original = _fullTranscript;
      final corrected = await MistralService.instance.correctTranscription(
        _fullTranscript,
      );

      if (corrected != original && mounted) {
        // Calculer le nombre de différences
        final originalWords = original.split(' ');
        final correctedWords = corrected.split(' ');
        int diffCount = 0;
        final maxLen = correctedWords.length > originalWords.length
            ? correctedWords.length
            : originalWords.length;
        for (int i = 0; i < maxLen; i++) {
          final a = i < originalWords.length ? originalWords[i] : '';
          final b = i < correctedWords.length ? correctedWords[i] : '';
          if (a != b) diffCount++;
        }

        setState(() {
          _fullTranscript = corrected;
          _iaCorrectionCount = diffCount;
          _isEnhancing = false;
        });

        // Meduza - succes correction
        widget.onMeduzaStateChanged?.call(
          MeduzaState.happy,
          message:
              '$diffCount corrections appliquees. Transcription optimisee.',
          style: BubbleStyle.success,
        );

        debugPrint('[Notitia] Mistral: $diffCount corrections appliquées');
      } else {
        if (mounted) setState(() => _isEnhancing = false);
        // Meduza - aucune correction
        widget.onMeduzaStateChanged?.call(
          MeduzaState.happy,
          message: 'Transcription deja propre, aucune correction necessaire.',
          style: BubbleStyle.success,
        );
        debugPrint('[Notitia] Mistral: Aucune correction nécessaire');
      }
    } catch (e) {
      debugPrint('[Notitia] Erreur Mistral: $e');
      if (mounted) setState(() => _isEnhancing = false);
      // Meduza - erreur correction
      widget.onMeduzaStateChanged?.call(
        MeduzaState.confused,
        message: 'Correction IA indisponible, transcription brute conservee.',
        style: BubbleStyle.error,
      );
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ---------------------------------------------------------------------------
  // Sauvegarde
  // ---------------------------------------------------------------------------
  Future<void> _saveTranscription() async {
    if (_fullTranscript.trim().isEmpty) return;

    final now = DateTime.now();
    final defaultTitle =
        'Transcription ${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final titleController = TextEditingController(text: defaultTitle);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.5)),
        ),
        title: Text(
          _languageService.translate('save'),
          style: GoogleFonts.orbitron(
            fontSize: 16,
            color: NotitiaTheme.neonPink,
            letterSpacing: 2,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _languageService.translate('give_transcription_title'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: NotitiaTheme.grey,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              style: GoogleFonts.poppins(
                color: NotitiaTheme.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: _languageService.translate('title_placeholder'),
                hintStyle: GoogleFonts.poppins(color: NotitiaTheme.grey),
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
                fillColor: NotitiaTheme.deepBlue,
              ),
            ),
          ],
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
              backgroundColor: NotitiaTheme.neonPink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _languageService.translate('save'),
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
      final transcription = Transcription.create(
        content: _fullTranscript.trim(),
        title: titleController.text.trim().isEmpty
            ? defaultTitle
            : titleController.text.trim(),
      );
      await StorageService.save(transcription);

      // Indexation RAG automatique (en arrière-plan)
      RAGService.instance.indexSingleTranscription(transcription);

      setState(() {
        _fullTranscript = '';
        _liveText = '';
      });

      _showSnackBar('Transcription sauvegardée ✓');
      widget.onTranscriptionSaved?.call();
    }

    titleController.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            const SizedBox(height: 36),
            _buildSectionTitle(),
            const SizedBox(height: 16),
            _buildEngineSelector(),
            const SizedBox(height: 12),
            _buildActiveToggle(),
            const SizedBox(height: 20),
            _buildMicButton(),
            const SizedBox(height: 16),
            _buildStatusIndicator(),
            const SizedBox(height: 24),
            _buildTranscriptionBox(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ===== SÉLECTEUR MOTEUR STT =====
  Widget _buildEngineSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NotitiaTheme.neonPink.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Bouton Deepgram Nova-3
          Expanded(
            child: GestureDetector(
              onTap: _isListening
                  ? null
                  : () => setState(() => _sttEngine = STTEngine.deepgram),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: _sttEngine == STTEngine.deepgram
                      ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: _sttEngine == STTEngine.deepgram
                      ? Border.all(
                          color: NotitiaTheme.neonPink.withValues(alpha: 0.5),
                        )
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      size: 20,
                      color: _sttEngine == STTEngine.deepgram
                          ? NotitiaTheme.neonPink
                          : NotitiaTheme.grey,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _languageService.translate('engine_deepgram'),
                      style: GoogleFonts.orbitron(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _sttEngine == STTEngine.deepgram
                            ? NotitiaTheme.neonPink
                            : NotitiaTheme.grey,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _languageService.translate('deepgram_subtitle'),
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        color: NotitiaTheme.grey.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Bouton Natif
          Expanded(
            child: GestureDetector(
              onTap: _isListening
                  ? null
                  : () => setState(() => _sttEngine = STTEngine.native),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: _sttEngine == STTEngine.native
                      ? NotitiaTheme.neonCyan.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: _sttEngine == STTEngine.native
                      ? Border.all(
                          color: NotitiaTheme.neonCyan.withValues(alpha: 0.5),
                        )
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.phone_android_outlined,
                      size: 20,
                      color: _sttEngine == STTEngine.native
                          ? NotitiaTheme.neonCyan
                          : NotitiaTheme.grey,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _languageService.translate('engine_native'),
                      style: GoogleFonts.orbitron(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _sttEngine == STTEngine.native
                            ? NotitiaTheme.neonCyan
                            : NotitiaTheme.grey,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      Platform.isAndroid
                          ? _languageService.translate('native_google')
                          : _languageService.translate('native_apple'),
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        color: NotitiaTheme.grey.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== HEADER =====
  Widget _buildHeader() {
    // Meduza change d'etat selon l'activite en cours
    MeduzaState headerState;
    if (_isListening) {
      headerState = MeduzaState.listening;
    } else if (_isEnhancing) {
      headerState = MeduzaState.processing;
    } else {
      headerState = MeduzaState.idle;
    }

    return Column(
      children: [
        // Profile button row at top
        if (widget.onProfileTap != null)
          Align(
            alignment: Alignment.centerRight,
            child: NotitiaProfileButton(
              profile: widget.profile,
              onTap: widget.onProfileTap!,
            ),
          ),
        FadeTransition(
          opacity: _entranceFade,
          child: ScaleTransition(
            scale: _entranceScale,
            child: MeduzaWidget(state: headerState, size: 110),
          ),
        ),
        const SizedBox(height: 14),
        FadeTransition(
          opacity: _entranceTextFade,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _languageService.translate('app_title'),
              style: GoogleFonts.orbitron(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: NotitiaTheme.white,
                letterSpacing: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        FadeTransition(
          opacity: _entranceTextFade,
          child: Text(
            _languageService.translate('ai_memory_assistant_subtitle'),
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: NotitiaTheme.grey,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle() {
    return Text(
      _languageService.translate('voice_to_text'),
      style: GoogleFonts.orbitron(
        fontSize: 13,
        color: NotitiaTheme.grey,
        letterSpacing: 4,
      ),
    );
  }

  // ===== TOGGLE ÉCOUTE ACTIVE =====
  Widget _buildActiveToggle() {
    final bool showToggle = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!showToggle) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isActiveMode
            ? NotitiaTheme.neonCyan.withValues(alpha: 0.08)
            : NotitiaTheme.darkBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isActiveMode
              ? NotitiaTheme.neonCyan.withValues(alpha: 0.5)
              : NotitiaTheme.neonPink.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isActiveMode ? Icons.hearing_rounded : Icons.hearing_disabled,
            color: _isActiveMode ? NotitiaTheme.neonCyan : NotitiaTheme.grey,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _languageService.translate('active_listening'),
                  style: GoogleFonts.orbitron(
                    fontSize: 11,
                    color: _isActiveMode
                        ? NotitiaTheme.neonCyan
                        : NotitiaTheme.grey,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isActiveMode
                      ? _languageService.translate('background_transcription')
                      : _languageService.translate('continue_locked_screen'),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: NotitiaTheme.grey.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isActiveMode,
            onChanged: _isListening
                ? null // Ne pas changer pendant l'écoute
                : (value) => setState(() => _isActiveMode = value),
            activeTrackColor: NotitiaTheme.neonCyan.withValues(alpha: 0.5),
            activeThumbColor: NotitiaTheme.neonCyan,
            inactiveThumbColor: NotitiaTheme.grey,
            inactiveTrackColor: NotitiaTheme.grey.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  // ===== BOUTON MICRO =====
  Widget _buildMicButton() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: _toggleListening,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isListening
                ? NotitiaTheme.redRecording
                : NotitiaTheme.neonPink,
            boxShadow: [
              BoxShadow(
                color:
                    (_isListening
                            ? NotitiaTheme.redRecording
                            : NotitiaTheme.neonPink)
                        .withValues(alpha: 0.6),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(
            _isListening ? Icons.stop_rounded : Icons.mic_rounded,
            size: 64,
            color: NotitiaTheme.white,
          ),
        ),
      ),
    );
  }

  // ===== INDICATEUR D'ÉTAT =====
  Widget _buildStatusIndicator() {
    // État: Amélioration IA en cours
    if (_isEnhancing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NotitiaTheme.neonPink,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _languageService.translate('ai_enhancement_in_progress'),
            style: GoogleFonts.orbitron(
              fontSize: 14,
              color: NotitiaTheme.neonPink,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    // État: Écoute en cours
    if (_isListening) {
      final engineName = _sttEngine == STTEngine.deepgram ? 'NOVA-3' : 'NATIF';
      final engineColor = _sttEngine == STTEngine.deepgram
          ? NotitiaTheme.neonPink
          : NotitiaTheme.neonCyan;

      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NotitiaTheme.redRecording,
                  boxShadow: [
                    BoxShadow(
                      color: NotitiaTheme.redRecording.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _languageService
                    .translate('listening_duration')
                    .replaceAll('{duration}', _formatDuration(_listenDuration)),
                style: GoogleFonts.orbitron(
                  fontSize: 18,
                  color: NotitiaTheme.redRecording,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '[ $engineName ]',
            style: GoogleFonts.orbitron(
              fontSize: 10,
              color: engineColor,
              letterSpacing: 2,
            ),
          ),
        ],
      );
    }

    return Text(
      _fullTranscript.isEmpty
          ? _languageService.translate('press_to_dictate')
          : (_iaCorrectionCount > 0
                ? '${_languageService.translate('ai_enhanced')} ($_iaCorrectionCount ${_languageService.translate('corrections_applied')})'
                : _languageService.translate('transcription_completed')),
      style: GoogleFonts.poppins(
        fontSize: 15,
        color: _iaCorrectionCount > 0
            ? NotitiaTheme.neonPink
            : NotitiaTheme.grey,
      ),
    );
  }

  // ===== BOÎTE DE TRANSCRIPTION EN DIRECT =====
  Widget _buildTranscriptionBox() {
    final String displayText;
    if (_isListening) {
      final buffer = StringBuffer();
      if (_fullTranscript.isNotEmpty) buffer.write(_fullTranscript);
      if (_liveText.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(_liveText);
      }
      displayText = buffer.toString();
    } else {
      displayText = _fullTranscript;
    }

    final bool isEmpty = displayText.isEmpty;
    final bool showSaveButton = !_isListening && _fullTranscript.isNotEmpty;

    // Couleur d'accent : vert quand terminé avec texte, rose sinon
    final Color accentColor = showSaveButton
        ? Colors.greenAccent
        : NotitiaTheme.neonPink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        color: NotitiaTheme.deepBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isListening
              ? NotitiaTheme.neonPink
              : (showSaveButton
                    ? Colors.greenAccent.withValues(alpha: 0.4)
                    : NotitiaTheme.neonPink.withValues(alpha: 0.25)),
          width: _isListening ? 2 : 1,
        ),
        boxShadow: _isListening
            ? [
                BoxShadow(
                  color: NotitiaTheme.neonPink.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isListening
                    ? Icons.auto_awesome
                    : (showSaveButton ? Icons.check_circle : Icons.text_fields),
                color: accentColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isListening
                      ? _languageService.translate('live_transcription')
                      : _languageService.translate('transcription'),
                  style: GoogleFonts.orbitron(
                    fontSize: 10,
                    color: accentColor,
                    letterSpacing: 2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isListening && _confidence > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NotitiaTheme.neonPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${(_confidence * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.orbitron(
                      fontSize: 10,
                      color: NotitiaTheme.neonPink,
                    ),
                  ),
                ),
              ],
              if (showSaveButton) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _saveTranscription,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: NotitiaTheme.neonPink,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: NotitiaTheme.neonPink.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.save_rounded,
                          color: NotitiaTheme.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _languageService.translate('save_button'),
                          style: GoogleFonts.orbitron(
                            fontSize: 10,
                            color: NotitiaTheme.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          showSaveButton
              ? SelectableText(
                  displayText,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    height: 1.6,
                    color: NotitiaTheme.white,
                  ),
                )
              : Text(
                  isEmpty
                      ? (_isListening
                            ? _languageService.translate('waiting_for_speech')
                            : _languageService.translate(
                                'transcribed_text_here',
                              ))
                      : displayText,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    height: 1.6,
                    color: isEmpty ? NotitiaTheme.grey : NotitiaTheme.white,
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
          if (_isListening && isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: PulsingDot(index: i),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
