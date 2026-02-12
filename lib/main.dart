// =============================================================================
// NOTITIA - PoC Flutter v2.0
// Assistant mémoire IA - Benchmark technique
// Fonctionnalités : Transcription vocale, Sauvegarde locale, Édition,
//                   Recherche sémantique
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pages/capture_page.dart';
import 'pages/history_page.dart';
import 'pages/search_page.dart';
import 'services/foreground_service.dart';
import 'theme.dart';

// =============================================================================
// POINT D'ENTRÉE
// =============================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Port de communication pour le foreground service
  FlutterForegroundTask.initCommunicationPort();
  // Pré-initialisation du service
  ActiveListeningService.init();
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
      title: 'Notitia PoC',
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
      home: const WithForegroundTask(child: MainNavigation()),
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

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  /// Notifie les pages enfants qu'une nouvelle transcription a été sauvegardée.
  final ValueNotifier<int> _refreshNotifier = ValueNotifier(0);

  void _onTranscriptionSaved() {
    _refreshNotifier.value++;
  }

  @override
  void dispose() {
    _refreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CapturePage(onTranscriptionSaved: _onTranscriptionSaved),
          HistoryPage(refreshNotifier: _refreshNotifier),
          SearchPage(refreshNotifier: _refreshNotifier),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
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
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: NotitiaTheme.neonPink,
        unselectedItemColor: NotitiaTheme.grey,
        selectedLabelStyle: GoogleFonts.orbitron(fontSize: 10),
        unselectedLabelStyle: GoogleFonts.orbitron(fontSize: 10),
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
            icon: Icon(Icons.search_rounded),
            label: 'RECHERCHE',
          ),
        ],
      ),
    );
  }
}
