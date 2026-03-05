// =============================================================================
// NOTITIA - PoC Flutter v2.0
// Assistant mémoire IA - Benchmark technique
// Fonctionnalités : Transcription vocale, Sauvegarde locale, Édition,
//                   Recherche sémantique
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pages/assistant_page.dart';
import 'pages/capture_page.dart';
import 'pages/history_page.dart';
import 'pages/mind_map_page.dart';
import 'pages/search_page.dart';
import 'pages/splash_screen.dart';
import 'services/foreground_service.dart';
import 'services/nfc_share_service.dart';
import 'services/notitia_file_service.dart';
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
  // Initialiser le canal NFC/P2P
  NfcShareService.init();
  // Nettoyer les fichiers temporaires de sessions précédentes
  NotitiaFileService.cleanupAllTempFiles();
  // Demander les permissions Nearby (BLE, WiFi, Location)
  _requestNearbyPermissions();
  runApp(const NotitiaApp());
}

/// Demande les permissions nécessaires pour Nearby Connections (BLE, WiFi, Location).
/// Appelé au démarrage — résultat non bloquant.
Future<void> _requestNearbyPermissions() async {
  await [
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.nearbyWifiDevices,
    Permission.locationWhenInUse,
  ].request();
}

// =============================================================================
// APPLICATION
// =============================================================================
class NotitiaApp extends StatelessWidget {
  const NotitiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  void _onTabChanged(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Contenu principal
          IndexedStack(
            index: _currentIndex,
            children: [
              CapturePage(onTranscriptionSaved: _onTranscriptionSaved),
              HistoryPage(refreshNotifier: _refreshNotifier),
              MindMapPage(refreshNotifier: _refreshNotifier),
              SearchPage(refreshNotifier: _refreshNotifier),
              AssistantPage(refreshNotifier: _refreshNotifier),
            ],
          ),
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
