// =============================================================================
// NOTITIA - PoC Flutter v2.0
// Assistant mémoire IA - Benchmark technique
// Fonctionnalités : Transcription vocale, Sauvegarde locale, Édition,
//                   Recherche sémantique
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pages/assistant_page.dart';
import 'pages/auth_choice_page.dart';
import 'pages/capture_page.dart';
import 'pages/email_otp_page.dart';
import 'pages/history_page.dart';
import 'pages/login_page.dart';
import 'pages/meeting_page.dart';
import 'pages/mind_map_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/subscription_page.dart';
import 'pages/profile_page.dart';
import 'pages/register_page.dart';
import 'pages/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/foreground_service.dart';
import 'services/home_widget_service.dart';
import 'services/language_service.dart';
import 'services/nfc_share_service.dart';
import 'services/notitia_file_service.dart';
import 'theme.dart';
import 'widgets/meduza_widget.dart';
import 'widgets/meduza_companion.dart';
import 'widgets/meduza_speech_bubble.dart';

/// Clé de navigation globale.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// =============================================================================
// POINT D'ENTRÉE
// =============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Notitia] ===== BUILD 2026-03-11 v2 =====');

  // Initialisation de Supabase
  await AuthService.initialize();

  // Initialisation du service de langue
  await LanguageService().initialize();

  // Port de communication pour le foreground service
  FlutterForegroundTask.initCommunicationPort();
  // Pré-initialisation du service
  ActiveListeningService.init();
  // Initialiser le canal NFC
  NfcShareService.init();
  // Nettoyer les fichiers temporaires de sessions précédentes
  NotitiaFileService.cleanupAllTempFiles();

  // Initialiser le Home Widget (vérifie aussi les transcriptions en attente)
  await HomeWidgetService.initialize();

  runApp(const NotitiaApp());
}

// =============================================================================
// APPLICATION
// =============================================================================
class NotitiaApp extends StatelessWidget {
  const NotitiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Notitia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: NotitiaTheme.deepBlue,
        colorScheme: ColorScheme.dark(
          primary: NotitiaTheme.neonPink,
          secondary: NotitiaTheme.neonPink,
          surface: NotitiaTheme.deepBlue,
        ),
        textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        final routes = <String, WidgetBuilder>{
          '/main': (context) =>
              const WithForegroundTask(child: MainNavigation()),
          '/auth': (context) => const AuthChoicePage(),
          '/login': (context) => const LoginPage(),
          '/register': (context) => const RegisterPage(),
          '/email-otp': (context) => const EmailOtpPage(),
          '/profile': (context) => const ProfilePage(),
          '/onboarding': (context) => const OnboardingPage(),
          '/subscription': (context) => const SubscriptionPage(),
        };

        final builder = routes[settings.name];
        if (builder == null) return null;

        // Smooth fade transition when arriving from onboarding
        final args = settings.arguments;
        if (settings.name == '/main' &&
            args is Map &&
            args['fromOnboarding'] == true) {
          return PageRouteBuilder(
            settings: settings,
            pageBuilder: (context, _, __) => builder(context),
            transitionDuration: const Duration(milliseconds: 600),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (context, animation, _, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              );
            },
          );
        }

        return MaterialPageRoute(settings: settings, builder: builder);
      },
    );
  }
}

// =============================================================================
// NAVIGATION PRINCIPALE — Bottom Navigation Bar
// =============================================================================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _currentIndex = 2; // Capture au centre
  final _authService = AuthService();
  UserProfile? _profile;
  bool _fromOnboarding = false;
  bool _isViewingMindMap = false;

  // --- Meduza state management (event-driven) ---
  MeduzaState _meduzaState = MeduzaState.idle;
  String? _meduzaMessage;
  BubbleStyle _meduzaBubbleStyle = BubbleStyle.normal;

  /// Meduza n'apparait que quand un evenement actif la declenche (pas idle)
  bool get _showMeduza => _meduzaState != MeduzaState.idle;

  void _setMeduzaState(
    MeduzaState state, {
    String? message,
    BubbleStyle style = BubbleStyle.normal,
  }) {
    if (!mounted) return;
    setState(() {
      _meduzaState = state;
      _meduzaMessage = message;
      _meduzaBubbleStyle = style;
    });

    // Auto-dismiss les etats transitoires apres 4 secondes
    if (state == MeduzaState.happy || state == MeduzaState.confused) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _meduzaState == state) {
          setState(() {
            _meduzaState = MeduzaState.idle;
            _meduzaMessage = null;
          });
        }
      });
    }
  }

  void _dismissMeduza() {
    setState(() {
      _meduzaState = MeduzaState.idle;
      _meduzaMessage = null;
    });
  }

  /// Notifie les pages enfants qu'une nouvelle transcription a été sauvegardée.
  final ValueNotifier<int> _refreshNotifier = ValueNotifier(0);

  /// Filtre l'historique pour n'afficher que les réunions.
  bool _filterHistoryMeetings = false;

  void _onTranscriptionSaved() {
    _refreshNotifier.value++;
  }

  /// Navigue vers l'onglet historique en filtrant sur les réunions.
  void _navigateToHistoryMeetings() {
    setState(() {
      _filterHistoryMeetings = true;
      _currentIndex = 0; // Index de l'onglet Historique
    });
  }

  void _onMindMapViewingChanged(bool isViewing) {
    if (_isViewingMindMap == isViewing) return;
    setState(() {
      _isViewingMindMap = isViewing;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();

    // Écouter les changements d'état d'authentification
    _authService.authStateChanges.listen((state) {
      if (mounted) {
        _loadProfile();
      }
    });
  }

  /// Quand l'app revient au premier plan, on vérifie si le service natif
  /// a sauvegardé une transcription widget pendant qu'on était en background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWidgetPendingTranscription();
    }
  }

  Future<void> _checkWidgetPendingTranscription() async {
    final saved = await HomeWidgetService.checkPendingTranscription();
    if (saved && mounted) {
      _refreshNotifier.value++;
      debugPrint(
        '[MainNavigation] Widget pending transcription traitée → refresh',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['fromOnboarding'] == true && !_fromOnboarding) {
      _fromOnboarding = true;
    }
  }

  Future<void> _loadProfile() async {
    if (_authService.isAuthenticated) {
      final profile = await _authService.getProfile();
      if (mounted) {
        setState(() => _profile = profile);
      }
    } else {
      setState(() => _profile = null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshNotifier.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      // Réinitialiser le filtre réunion si on quitte manuellement l'historique
      if (index != 0) _filterHistoryMeetings = false;
    });
  }

  void _openProfile() {
    if (_authService.isAuthenticated) {
      Navigator.of(context).pushNamed('/profile').then((_) => _loadProfile());
    } else {
      Navigator.of(context).pushNamed('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideDock = _currentIndex == 3 && _isViewingMindMap;
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Contenu principal — scroll sous la dock flottante
          IndexedStack(
            index: _currentIndex,
            children: [
              // 0 — Historique
              HistoryPage(
                refreshNotifier: _refreshNotifier,
                profile: _profile,
                onProfileTap: _openProfile,
                filterMeetingsOnly: _filterHistoryMeetings,
              ),
              // 1 — Réunion
              MeetingPage(
                refreshNotifier: _refreshNotifier,
                onMeduzaStateChanged: _setMeduzaState,
                onNavigateToHistory: _navigateToHistoryMeetings,
              ),
              // 2 — Capture (centre)
              CapturePage(
                onTranscriptionSaved: _onTranscriptionSaved,
                onMeduzaStateChanged: _setMeduzaState,
                profile: _profile,
                onProfileTap: _openProfile,
                fromOnboarding: _fromOnboarding,
              ),
              // 3 — MindMap
              MindMapPage(
                refreshNotifier: _refreshNotifier,
                onMeduzaStateChanged: _setMeduzaState,
                onViewingMindMapChanged: _onMindMapViewingChanged,
                profile: _profile,
                onProfileTap: _openProfile,
              ),
              // 4 — Assistant
              AssistantPage(
                refreshNotifier: _refreshNotifier,
                onMeduzaStateChanged: _setMeduzaState,
                profile: _profile,
                onProfileTap: _openProfile,
              ),
            ],
          ),
          // Meduza floating overlay (event-driven)
          if (_showMeduza)
            MeduzaFloatingOverlay(
              state: _meduzaState,
              message: _meduzaMessage,
              bubbleStyle: _meduzaBubbleStyle,
              visible: _showMeduza,
              onDismiss: _dismissMeduza,
            ),
          // ── Floating Glass Dock ──
          if (!hideDock)
            Positioned(
              left: 20,
              right: 20,
              bottom: 10 + bottomSafe,
              child: _buildFloatingDock(),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FLOATING GLASS DOCK (iPadOS / Dynamic Island style)
  // ===========================================================================

  static const _navIcons = [
    Icons.history_rounded,
    Icons.groups_rounded,
    Icons.mic_rounded, // centre
    Icons.account_tree_rounded,
    Icons.auto_awesome,
  ];

  Widget _buildFloatingDock() {
    const double dockHeight = 56;
    const double borderWidth = 1.5;
    const double dockTotalHeight = dockHeight + borderWidth * 2;
    const double centerBtnSize = 64;
    const double dockRadius = 32;
    const int centerIndex = 2;

    return SizedBox(
      height: centerBtnSize + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ── Glass dock body with gradient border ──
          Container(
            height: dockTotalHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(dockRadius),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  NotitiaTheme.neonPink.withValues(alpha: 0.6),
                  NotitiaTheme.neonPink.withValues(alpha: 0.15),
                  NotitiaTheme.neonCyan.withValues(alpha: 0.15),
                  NotitiaTheme.neonCyan.withValues(alpha: 0.6),
                ],
              ),
            ),
            padding: const EdgeInsets.all(borderWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(dockRadius - borderWidth),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: NotitiaTheme.darkBlue.withValues(alpha: 0.55),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDockIcon(0),
                      _buildDockIcon(1),
                      SizedBox(width: centerBtnSize + 8),
                      _buildDockIcon(3),
                      _buildDockIcon(4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Center floating button (protrudes above & below) ──
          _buildDockCenterButton(centerIndex),
        ],
      ),
    );
  }

  Widget _buildDockIcon(int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? NotitiaTheme.neonPink : NotitiaTheme.grey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTabChanged(index),
      child: SizedBox(
        width: 50,
        height: 50,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? NotitiaTheme.neonPink.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_navIcons[index], size: 26, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildDockCenterButton(int index) {
    final isSelected = _currentIndex == index;
    const double size = 64;

    return GestureDetector(
      onTap: () => _onTabChanged(index),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NotitiaTheme.neonPink, Color(0xFFAA0055)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    NotitiaTheme.darkBlue.withValues(alpha: 0.9),
                    NotitiaTheme.deepBlue,
                  ],
                ),
          border: Border.all(
            color: isSelected
                ? NotitiaTheme.neonPink
                : NotitiaTheme.grey.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            if (isSelected) ...[
              BoxShadow(
                color: NotitiaTheme.neonPink.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: NotitiaTheme.neonPink.withValues(alpha: 0.2),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ] else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Icon(
          Icons.mic_rounded,
          size: 30,
          color: isSelected ? NotitiaTheme.white : NotitiaTheme.grey,
        ),
      ),
    );
  }
}
