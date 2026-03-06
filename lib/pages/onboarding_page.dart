// =============================================================================
// NOTITIA — Page d'onboarding Meduza
// Tutoriel en 4 etapes avec la mascotte IA
// Declenchee uniquement apres la creation d'un nouveau compte
// Utilise le nom d'utilisateur du compte si disponible
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/meduza_speech_bubble.dart';

// =============================================================================
// Service de persistence de l'onboarding
// =============================================================================
class OnboardingService {
  static const String _onboardedKey = 'notitia_onboarded';

  /// Verifie si l'utilisateur a deja complete l'onboarding
  static Future<bool> isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardedKey) ?? false;
  }

  /// Marque l'onboarding comme termine
  static Future<void> markOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  /// Reset l'onboarding (utile pour les tests)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardedKey);
  }
}

// =============================================================================
// Page d'onboarding
// =============================================================================
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  String _username = '';
  late PageController _pageController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
    _loadUsername();
  }

  /// Charge le nom d'utilisateur depuis le profil Supabase
  Future<void> _loadUsername() async {
    if (_authService.isAuthenticated) {
      final profile = await _authService.getProfile();
      if (mounted) {
        setState(() {
          _username =
              profile?.username ??
              _authService.currentUser?.email?.split('@').first ??
              '';
        });
      }
    }
  }

  /// Retourne le prenom / nom affiche
  String get _displayName => _username.isNotEmpty ? _username : 'visiteur';

  /// Les 4 etapes de l'onboarding
  List<_OnboardingStep> get _steps => [
    _OnboardingStep(
      meduzaState: MeduzaState.hello,
      bubbleStyle: BubbleStyle.info,
      title: 'Bienvenue sur Notitia',
      message:
          'Salut $_displayName, je suis Meduza, ton assistante memoire. '
          'Je vais te guider dans les fonctionnalites de Notitia.',
      icon: Icons.auto_awesome,
    ),
    _OnboardingStep(
      meduzaState: MeduzaState.listening,
      bubbleStyle: BubbleStyle.normal,
      title: 'Capture vocale',
      message:
          'Dicte tes notes et je les transcris en temps reel. '
          'Utilise le moteur Deepgram Nova-3 pour une precision optimale.',
      icon: Icons.mic_rounded,
    ),
    _OnboardingStep(
      meduzaState: MeduzaState.processing,
      bubbleStyle: BubbleStyle.normal,
      title: 'Mind Map et Recherche',
      message:
          'Je peux generer des mind maps a partir de tes notes et '
          'effectuer des recherches semantiques dans tout ton historique.',
      icon: Icons.account_tree_rounded,
    ),
    _OnboardingStep(
      meduzaState: MeduzaState.happy,
      bubbleStyle: BubbleStyle.success,
      title: 'Ton assistant IA',
      message:
          'Pose-moi des questions sur tes notes dans l\'onglet Assistant. '
          'Je serai toujours la pour t\'aider, $_displayName.',
      icon: Icons.auto_awesome,
    ),
  ];

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _skipOnboarding() {
    _finishOnboarding();
  }

  Future<void> _finishOnboarding() async {
    await OnboardingService.markOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // Header avec skip
              _buildHeader(),
              // Contenu principal (PageView)
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) =>
                      _buildStepContent(_steps[index]),
                ),
              ),
              // Indicateurs + bouton
              _buildFooter(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_currentStep + 1} / ${_steps.length}',
            style: GoogleFonts.orbitron(
              fontSize: 12,
              color: NotitiaTheme.grey,
              letterSpacing: 2,
            ),
          ),
          TextButton(
            onPressed: _skipOnboarding,
            child: Text(
              'PASSER',
              style: GoogleFonts.orbitron(
                fontSize: 12,
                color: NotitiaTheme.grey,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent(_OnboardingStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Meduza animee
          MeduzaWidget(state: step.meduzaState, size: 160),
          const SizedBox(height: 32),
          // Bulle de dialogue
          MeduzaSpeechBubble(
            key: ValueKey('bubble_$_currentStep'),
            text: step.message,
            style: step.bubbleStyle,
            arrowPosition: BubbleArrowPosition.top,
            maxWidth: 320,
          ),
          const SizedBox(height: 32),
          // Titre de l'etape
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(step.icon, color: NotitiaTheme.neonPink, size: 22),
              const SizedBox(width: 10),
              Text(
                step.title,
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: NotitiaTheme.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final isLast = _currentStep == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Dots indicateurs
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_steps.length, (index) {
              final isActive = index == _currentStep;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isActive
                      ? NotitiaTheme.neonPink
                      : NotitiaTheme.grey.withOpacity(0.3),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: NotitiaTheme.neonPink.withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
          // Bouton suivant / commencer
          GestureDetector(
            onTap: _nextStep,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    NotitiaTheme.neonPink,
                    NotitiaTheme.neonPink.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: NotitiaTheme.neonPink.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  isLast ? 'COMMENCER' : 'SUIVANT',
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Modele interne pour une etape d'onboarding
// =============================================================================
class _OnboardingStep {
  final MeduzaState meduzaState;
  final BubbleStyle bubbleStyle;
  final String title;
  final String message;
  final IconData icon;

  const _OnboardingStep({
    required this.meduzaState,
    required this.bubbleStyle,
    required this.title,
    required this.message,
    required this.icon,
  });
}
