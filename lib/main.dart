// =============================================================================
// NOTITIA - PoC Flutter v2.0
// Assistant mémoire IA - Benchmark technique
// Fonctionnalités : Transcription vocale, Sauvegarde locale, Édition,
//                   Recherche sémantique
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pages/assistant_page.dart';
import 'pages/auth_choice_page.dart';
import 'pages/capture_page.dart';
import 'pages/email_otp_page.dart';
import 'pages/history_page.dart';
import 'pages/login_page.dart';
import 'pages/mind_map_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/profile_page.dart';
import 'pages/register_page.dart';
import 'pages/search_page.dart';
import 'pages/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/foreground_service.dart';
import 'services/home_widget_service.dart';
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
      routes: {
        '/main': (context) => const WithForegroundTask(child: MainNavigation()),
        '/auth': (context) => const AuthChoicePage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/email-otp': (context) => const EmailOtpPage(),
        '/profile': (context) => const ProfilePage(),
        '/onboarding': (context) => const OnboardingPage(),
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
  int _currentIndex = 0;
  final _authService = AuthService();
  UserProfile? _profile;

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

  void _onTranscriptionSaved() {
    _refreshNotifier.value++;
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
      debugPrint('[MainNavigation] Widget pending transcription traitée → refresh');
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
    setState(() => _currentIndex = index);
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
    return Scaffold(
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Contenu principal
          IndexedStack(
            index: _currentIndex,
            children: [
              CapturePage(
                onTranscriptionSaved: _onTranscriptionSaved,
                onMeduzaStateChanged: _setMeduzaState,
              ),
              HistoryPage(refreshNotifier: _refreshNotifier),
              MindMapPage(
                refreshNotifier: _refreshNotifier,
                onMeduzaStateChanged: _setMeduzaState,
              ),
              SearchPage(refreshNotifier: _refreshNotifier),
              AssistantPage(
                refreshNotifier: _refreshNotifier,
                onMeduzaStateChanged: _setMeduzaState,
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
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: NotitiaTheme.deepBlue,
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  NotitiaTheme.neonPink,
                  NotitiaTheme.neonPink.withOpacity(0.6),
                ],
              ),
            ),
            child: const Icon(Icons.memory, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(
            'NOTITIA',
            style: GoogleFonts.orbitron(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: NotitiaTheme.white,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
      actions: [
        // Bouton profil
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: _openProfile,
            child: _buildProfileAvatar(),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar() {
    final isLoggedIn = _authService.isAuthenticated;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLoggedIn
            ? LinearGradient(
                colors: [
                  NotitiaTheme.neonPink,
                  NotitiaTheme.neonPink.withOpacity(0.6),
                ],
              )
            : null,
        border: !isLoggedIn
            ? Border.all(
                color: NotitiaTheme.neonPink.withOpacity(0.5),
                width: 2,
              )
            : null,
        boxShadow: isLoggedIn
            ? [
                BoxShadow(
                  color: NotitiaTheme.neonPink.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: _profile?.avatarUrl != null
          ? ClipOval(
              child: Image.network(
                _profile!.avatarUrl!,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (_, __, ___) => _buildDefaultAvatarContent(),
              ),
            )
          : _buildDefaultAvatarContent(),
    );
  }

  Widget _buildDefaultAvatarContent() {
    if (_authService.isAuthenticated) {
      final initial =
          (_profile?.username ??
                  _profile?.email ??
                  _authService.currentUser?.email ??
                  'U')[0]
              .toUpperCase();
      return Center(
        child: Text(
          initial,
          style: GoogleFonts.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    } else {
      return Icon(Icons.person_outline, color: NotitiaTheme.neonPink, size: 22);
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue,
        border: Border(
          top: BorderSide(color: NotitiaTheme.neonPink.withValues(alpha: 0.3)),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabChanged,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: NotitiaTheme.neonPink,
        unselectedItemColor: NotitiaTheme.grey,
        selectedLabelStyle: GoogleFonts.orbitron(fontSize: 10),
        unselectedLabelStyle: GoogleFonts.orbitron(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_rounded),
            label: 'CAPTURE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'HISTORIQUE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree_rounded),
            label: 'MIND MAP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_rounded),
            label: 'RECHERCHE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'ASSISTANT',
          ),
        ],
      ),
    );
  }
}
