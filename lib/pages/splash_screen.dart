import 'package:flutter/material.dart';
import 'package:notitia/theme.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';

/// Écran de splash au démarrage de l'application
/// Affiche le logo Notitia pendant 2-3 secondes
/// Vérifie l'état d'authentification et redirige en conséquence
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  final _authService = AuthService();
  final _languageService = LanguageService();

  @override
  void initState() {
    super.initState();

    // Configuration des animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Vérifier l'authentification et naviguer après l'animation
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Attendre que l'animation soit visible
    await Future.delayed(const Duration(milliseconds: 2500));
    
    if (!mounted) return;

    // Si l'utilisateur est déjà connecté, aller à la page principale
    if (_authService.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/main');
      return;
    }

    // Vérifier si c'est la première ouverture ou si l'utilisateur s'est déconnecté
    final shouldShowAuth = await _authService.shouldShowAuthChoice();
    
    if (!mounted) return;

    if (shouldShowAuth) {
      // Première ouverture ou déconnexion : montrer le choix d'authentification
      Navigator.of(context).pushReplacementNamed('/auth');
    } else {
      // L'utilisateur a choisi d'utiliser l'app sans compte
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo avec animation
                Image.asset(
                  'assets/notitia_logo.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 30),
                // Texte de chargement
                Text(
                  _languageService.translate('splash_app_name'),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: NotitiaTheme.neonPink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _languageService.translate('splash_tagline'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
