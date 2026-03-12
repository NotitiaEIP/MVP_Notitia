// =============================================================================
// NOTITIA — Page de choix d'authentification
// Première page affichée aux nouveaux utilisateurs
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';

class AuthChoicePage extends StatefulWidget {
  const AuthChoicePage({super.key});

  @override
  State<AuthChoicePage> createState() => _AuthChoicePageState();
}

class _AuthChoicePageState extends State<AuthChoicePage>
    with SingleTickerProviderStateMixin {
  final _languageService = LanguageService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _navigateToLogin() {
    Navigator.of(context).pushNamed('/login');
  }

  void _navigateToRegister() {
    Navigator.of(context).pushNamed('/register');
  }

  Future<void> _continueAsGuest() async {
    await AuthService().setGuestMode(true);
    await AuthService().markAuthSeen();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  
                  // Logo et titre
                  _buildHeader(),
                  
                  const Spacer(flex: 1),
                  
                  // Boutons d'action
                  _buildActionButtons(),
                  
                  const SizedBox(height: 24),
                  
                  // Continuer sans compte
                  _buildGuestOption(),
                  
                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo animé
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                NotitiaTheme.deepBlue,
                NotitiaTheme.deepBlue.withOpacity(0.6),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: NotitiaTheme.neonPink.withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          // On garde le ClipOval pour forcer l'image à rester dans le cercle
          child: ClipOval(
            child: Image.asset(
              'assets/notitia_logo.png',
              fit: BoxFit.cover, // 👈 'cover' permet de remplir 100% du cercle sans laisser d'espace
            ),
          ),
        ),
        const SizedBox(height: 32),
        
        // Titre
        Text(
          _languageService.translate('app_title'),
          style: GoogleFonts.orbitron(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: NotitiaTheme.white,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 12),
        
        // Sous-titre
        Text(
          _languageService.translate('your_ai_memory_assistant'),
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            color: NotitiaTheme.grey,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 48),
      
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Bouton Inscription
        _CyberpunkButton(
          onPressed: _navigateToRegister,
          label: _languageService.translate('create_account'),
          isPrimary: true,
          icon: Icons.person_add_outlined,
        ),
        const SizedBox(height: 16),
        
        // Bouton Connexion
        _CyberpunkButton(
          onPressed: _navigateToLogin,
          label: _languageService.translate('sign_in'),
          isPrimary: false,
          icon: Icons.login_outlined,
        ),
      ],
    );
  }

  Widget _buildGuestOption() {
    return TextButton(
      onPressed: _continueAsGuest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_forward,
            color: NotitiaTheme.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _languageService.translate('continue_without_account'),
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              color: NotitiaTheme.grey,
              decoration: TextDecoration.underline,
              decorationColor: NotitiaTheme.grey.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Bouton style Cyberpunk
// =============================================================================
class _CyberpunkButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final bool isPrimary;
  final IconData icon;

  const _CyberpunkButton({
    required this.onPressed,
    required this.label,
    required this.isPrimary,
    required this.icon,
  });

  @override
  State<_CyberpunkButton> createState() => _CyberpunkButtonState();
}

class _CyberpunkButtonState extends State<_CyberpunkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: widget.isPrimary
                ? LinearGradient(
                    colors: [
                      NotitiaTheme.neonPink,
                      NotitiaTheme.neonPink.withOpacity(0.8),
                    ],
                  )
                : null,
            color: widget.isPrimary ? null : Colors.transparent,
            border: Border.all(
              color: widget.isPrimary
                  ? Colors.transparent
                  : NotitiaTheme.neonPink.withOpacity(_isHovered ? 1 : 0.6),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: NotitiaTheme.neonPink.withOpacity(_isHovered ? 0.5 : 0.3),
                      blurRadius: _isHovered ? 20 : 10,
                      spreadRadius: _isHovered ? 2 : 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: widget.isPrimary
                    ? NotitiaTheme.white
                    : NotitiaTheme.neonPink,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: widget.isPrimary
                      ? NotitiaTheme.white
                      : NotitiaTheme.neonPink,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
