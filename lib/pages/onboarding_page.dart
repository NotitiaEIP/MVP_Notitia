// =============================================================================
// NOTITIA — Onboarding immersif
// Parcours utilisateur cinematique avec Meduza comme guide narratif
// 5 etapes: Bienvenue, Capture, Organisation, Recherche, Lancement
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/pricing_cards.dart';

// =============================================================================
// Service de persistence de l'onboarding
// =============================================================================
class OnboardingService {
  static const String _onboardedKey = 'notitia_onboarded';
  static const String _onboardedKeyPrefix = 'notitia_onboarded_user_';

  static String _resolveUserScopedKey() {
    final userId = AuthService().currentUser?.id;
    if (userId == null || userId.isEmpty) return _onboardedKey;
    return '$_onboardedKeyPrefix$userId';
  }

  /// Verifie si l'utilisateur a deja complete l'onboarding
  static Future<bool> isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _resolveUserScopedKey();

    // Pour un utilisateur connecte, on regarde uniquement son flag dedie.
    // Cela evite qu'un ancien flag global bloque le guide pour un nouveau compte.
    if (scopedKey != _onboardedKey) {
      return prefs.getBool(scopedKey) ?? false;
    }

    // Fallback legacy (mode invite / ancien comportement).
    return prefs.getBool(_onboardedKey) ?? false;
  }

  /// Marque l'onboarding comme termine
  static Future<void> markOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _resolveUserScopedKey();
    await prefs.setBool(scopedKey, true);

    // Compatibilite: on conserve aussi la cle globale pour les anciens flux.
    await prefs.setBool(_onboardedKey, true);
  }

  /// Reset l'onboarding (utile pour les tests)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _resolveUserScopedKey();
    await prefs.remove(scopedKey);
    await prefs.remove(_onboardedKey);
  }
}

// =============================================================================
// Page d'onboarding
// =============================================================================
// =============================================================================
// Modele d'une etape
// =============================================================================
class _JourneyStep {
  final MeduzaState meduzaState;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;

  const _JourneyStep({
    required this.meduzaState,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
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
  int _direction = 1; // 1 = forward, -1 = backward
  String _username = '';
  final _authService = AuthService();

  // Animation controllers
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  AnimationController? _exitController;

  // Animations
  late Animation<double> _entranceFade;
  late Animation<double> _entranceScale;
  late Animation<double> _pulseAnimation;
  bool _isExiting = false;

  String get _displayName => _username.isNotEmpty ? _username : 'explorateur';
  bool get _isPricingStep => _currentStep == _steps.length - 1;

  List<_JourneyStep> get _steps => [
    _JourneyStep(
      meduzaState: MeduzaState.hello,
      title: 'Salut $_displayName',
      subtitle: 'BIENVENUE DANS NOTITIA',
      description:
          'Je suis Meduza, ton assistante memoire. '
          'Ensemble, on va transformer ta voix en connaissances organisees.',
      icon: Icons.auto_awesome,
      accentColor: NotitiaTheme.neonPink,
    ),
    _JourneyStep(
      meduzaState: MeduzaState.listening,
      title: 'Capture vocale',
      subtitle: 'TA VOIX, TRANSCRITE EN TEMPS REEL',
      description:
          'Parle naturellement. Notre moteur IA transcrit tout '
          'instantanement avec une precision chirurgicale.',
      icon: Icons.mic_rounded,
      accentColor: NotitiaTheme.neonCyan,
    ),
    _JourneyStep(
      meduzaState: MeduzaState.processing,
      title: 'Organisation',
      subtitle: 'MIND MAPS & HISTORIQUE',
      description:
          'Tes notes se structurent en cartes mentales. '
          'Retrouve, edite et partage tout depuis ton historique.',
      icon: Icons.account_tree_rounded,
      accentColor: const Color(0xFF7C4DFF),
    ),
    _JourneyStep(
      meduzaState: MeduzaState.idle,
      title: 'Recherche IA',
      subtitle: 'RETROUVE N\'IMPORTE QUELLE IDEE',
      description:
          'Une recherche semantique ultra-rapide dans toutes tes notes. '
          'Decris ce que tu cherches, je le trouve.',
      icon: Icons.search_rounded,
      accentColor: const Color(0xFF00E676),
    ),
    _JourneyStep(
      meduzaState: MeduzaState.happy,
      title: 'C\'est parti !',
      subtitle: 'TON ASSISTANT EST PRET',
      description:
          'Pose-moi des questions, dicte tes idees, explore tes notes. '
          'Je suis la pour toi, $_displayName.',
      icon: Icons.rocket_launch_rounded,
      accentColor: NotitiaTheme.neonPink,
    ),
    _JourneyStep(
      meduzaState: MeduzaState.happy,
      title: 'Choisis ton plan',
      subtitle: 'OFFRES & TARIFS',
      description: '',
      icon: Icons.workspace_premium_rounded,
      accentColor: NotitiaTheme.neonCyan,
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Entrance: fade+scale reveal
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _entranceScale = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.7, curve: Curves.easeOutBack),
      ),
    );

    // Pulse for CTA button + Meduza glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Particle background loop
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Load username BEFORE starting entrance to avoid mid-animation rebuild
    _loadUsername().then((_) {
      if (mounted) _entranceController.forward();
    });
  }

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

  void _goToStep(int index) {
    if (index == _currentStep || index < 0 || index >= _steps.length) return;
    setState(() {
      _direction = index > _currentStep ? 1 : -1;
      _currentStep = index;
    });
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    if (_isExiting) return;
    _isExiting = true;
    await OnboardingService.markOnboarded();

    // Prepare exit animation (longer for smooth cinematic feel)
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    setState(() {});

    await _exitController!.forward();
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/main',
      (route) => false,
      arguments: {'fromOnboarding': true},
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _exitController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: Stack(
        children: [
          // Main onboarding content
          FadeTransition(
            opacity: _entranceFade,
            child: ScaleTransition(
              scale: _entranceScale,
              child: Stack(
                children: [
                  // Animated particle background
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _particleController,
                      builder: (context, _) => CustomPaint(
                        painter: _ParticlePainter(
                          progress: _particleController.value,
                          accentColor: step.accentColor,
                        ),
                      ),
                    ),
                  ),
                  // Main content — no PageView, pure animated transitions
                  SafeArea(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _isExiting
                          ? null
                          : (details) {
                              final v = details.primaryVelocity ?? 0;
                              if (v < -200) {
                                _nextStep();
                              } else if (v > 200 && _currentStep > 0) {
                                _goToStep(_currentStep - 1);
                              }
                            },
                      child: Column(
                        children: [
                          _buildTopBar(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              child: _isPricingStep
                                  ? _buildPricingContent(step)
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Meduza — scale+fade switcher
                                        _buildMeduzaSection(step),
                                        const SizedBox(height: 36),
                                        // Feature card — directional slide+fade
                                        _buildFeatureCard(step),
                                      ],
                                    ),
                            ),
                          ),
                          _buildTimeline(),
                          _buildCTA(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Cinematic exit overlay
          if (_isExiting && _exitController != null) _buildExitOverlay(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cinematic exit overlay — Meduza scales up, content fades, flash
  // ---------------------------------------------------------------------------
  Widget _buildExitOverlay() {
    final controller = _exitController!;

    // Meduza scales up and moves to center-top
    final meduzaScale = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.1, 0.7, curve: Curves.easeInOutCubic),
      ),
    );

    // Meduza slides up toward top of screen
    final meduzaSlide =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.3)).animate(
          CurvedAnimation(
            parent: controller,
            curve: const Interval(0.2, 0.8, curve: Curves.easeInOutCubic),
          ),
        );

    // Background darkens then flash fades in
    final bgDarken = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    // Cyan flash at the end
    final flash = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          children: [
            // Fade out underlying content
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: NotitiaTheme.deepBlue.withValues(
                    alpha: bgDarken.value,
                  ),
                ),
              ),
            ),

            // Meduza scaling up and floating to top-center
            Center(
              child: SlideTransition(
                position: meduzaSlide,
                child: ScaleTransition(
                  scale: meduzaScale,
                  child: const MeduzaWidget(
                    state: MeduzaState.happy,
                    size: 120,
                  ),
                ),
              ),
            ),

            // Flash overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: NotitiaTheme.neonCyan.withValues(
                    alpha: flash.value * 0.3,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Top bar: animated step counter + skip
  // ---------------------------------------------------------------------------
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            child: Text(
              '${_currentStep + 1} / ${_steps.length}',
              key: ValueKey('counter_$_currentStep'),
              style: GoogleFonts.orbitron(
                fontSize: 12,
                color: _steps[_currentStep].accentColor.withValues(alpha: 0.8),
                letterSpacing: 3,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _currentStep < _steps.length - 1 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: _currentStep >= _steps.length - 1,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: Text(
                  'PASSER',
                  style: GoogleFonts.orbitron(
                    fontSize: 11,
                    color: NotitiaTheme.grey.withValues(alpha: 0.7),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Meduza — smooth scale+fade transition between states
  // ---------------------------------------------------------------------------
  Widget _buildMeduzaSection(_JourneyStep step) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: AnimatedBuilder(
        key: ValueKey('meduza_$_currentStep'),
        animation: _pulseAnimation,
        builder: (context, child) {
          final glowRadius = 20 + _pulseAnimation.value * 15;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: step.accentColor.withValues(
                    alpha: 0.15 + _pulseAnimation.value * 0.1,
                  ),
                  blurRadius: glowRadius,
                  spreadRadius: glowRadius * 0.3,
                ),
              ],
            ),
            child: child,
          );
        },
        child: MeduzaWidget(state: step.meduzaState, size: 150),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Feature card — directional slide + fade
  // ---------------------------------------------------------------------------
  Widget _buildFeatureCard(_JourneyStep step) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Determine direction for the entering/leaving element
        final isEntering = animation.status == AnimationStatus.forward;
        final slideDir = isEntering ? _direction : -_direction;
        final slide = Tween<Offset>(
          begin: Offset(0.15 * slideDir, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        );
      },
      child: Container(
        key: ValueKey('card_$_currentStep'),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: NotitiaTheme.darkBlue.withValues(alpha: 0.6),
          border: Border.all(
            color: step.accentColor.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: step.accentColor.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(step.icon, color: step.accentColor, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    step.subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: step.accentColor,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.orbitron(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: NotitiaTheme.white,
                letterSpacing: 0.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              step.description,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: NotitiaTheme.white.withValues(alpha: 0.75),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline progress indicator
  // ---------------------------------------------------------------------------
  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final segmentIndex = i ~/ 2;
            final filled = segmentIndex < _currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: filled
                      ? _steps[_currentStep].accentColor.withValues(alpha: 0.6)
                      : NotitiaTheme.grey.withValues(alpha: 0.15),
                ),
              ),
            );
          }
          final dotIndex = i ~/ 2;
          final isActive = dotIndex == _currentStep;
          final isPast = dotIndex < _currentStep;
          final step = _steps[dotIndex];
          return GestureDetector(
            onTap: () => _goToStep(dotIndex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: isActive ? 14 : 10,
              height: isActive ? 14 : 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? step.accentColor
                    : isPast
                    ? step.accentColor.withValues(alpha: 0.5)
                    : NotitiaTheme.grey.withValues(alpha: 0.2),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: step.accentColor.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pricing content — replaces Meduza + feature card on last step
  // ---------------------------------------------------------------------------
  Widget _buildPricingContent(_JourneyStep step) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slideDir = _direction;
        final slide = Tween<Offset>(
          begin: Offset(0.15 * slideDir, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: SingleChildScrollView(
        key: const ValueKey('pricing_scroll'),
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          children: [
            Text(
              'Choisis ton plan',
              style: GoogleFonts.orbitron(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: NotitiaTheme.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tu pourras changer à tout moment',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: NotitiaTheme.grey,
              ),
            ),
            const SizedBox(height: 20),
            const NotitiaPricingCards(showCTAs: false, compact: false),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CTA button — animated color + text crossfade
  // ---------------------------------------------------------------------------
  Widget _buildCTA() {
    final isLast = _currentStep == _steps.length - 1;
    final step = _steps[_currentStep];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final shadowOpacity = isLast
              ? 0.25 + _pulseAnimation.value * 0.2
              : 0.2;
          return GestureDetector(
            onTap: _nextStep,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    step.accentColor,
                    step.accentColor.withValues(alpha: 0.7),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: step.accentColor.withValues(alpha: shadowOpacity),
                    blurRadius: 20,
                    spreadRadius: isLast ? 2 : 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey('cta_$_currentStep'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLast) ...[
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      isLast ? 'LANCER NOTITIA' : 'CONTINUER',
                      style: GoogleFonts.orbitron(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    if (!isLast) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Particle background painter
// =============================================================================
class _ParticlePainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  _ParticlePainter({required this.progress, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint();

    for (int i = 0; i < 45; i++) {
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final phase = rng.nextDouble() * 2 * pi;
      final radius = 1.0 + rng.nextDouble() * 2.5;

      final x = baseX + sin((progress * 2 * pi * speed) + phase) * 20;
      final y = baseY + cos((progress * 2 * pi * speed) + phase * 0.7) * 15;

      final opacity = 0.08 + rng.nextDouble() * 0.15;
      final useAccent = rng.nextDouble() > 0.6;

      paint.color = (useAccent ? accentColor : NotitiaTheme.neonCyan)
          .withValues(alpha: opacity);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Connecting lines between nearby particles
    final positions = <Offset>[];
    final rng2 = Random(42);
    for (int i = 0; i < 45; i++) {
      final baseX = rng2.nextDouble() * size.width;
      final baseY = rng2.nextDouble() * size.height;
      final speed = 0.3 + rng2.nextDouble() * 0.7;
      final phase = rng2.nextDouble() * 2 * pi;
      final x = baseX + sin((progress * 2 * pi * speed) + phase) * 20;
      final y = baseY + cos((progress * 2 * pi * speed) + phase * 0.7) * 15;
      positions.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final dist = (positions[i] - positions[j]).distance;
        if (dist < 80) {
          linePaint.color = accentColor.withValues(
            alpha: 0.04 * (1 - dist / 80),
          );
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.progress != progress || old.accentColor != accentColor;
}
