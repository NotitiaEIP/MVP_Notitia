// =============================================================================
// NOTITIA — Page d'inscription
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/email_otp_args.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'onboarding_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();

    // Gère OAuth/OTP: après création, on lance l'onboarding si nécessaire.
    _authSub = _authService.authStateChanges.listen((state) async {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.signedIn) {
        _authService.markAuthSeen();
        final alreadyOnboarded = await OnboardingService.isOnboarded();
        if (!mounted) return;
        if (!alreadyOnboarded) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
        } else {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/main', (route) => false);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _animationController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUpWithEmailAndPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
      );

      if (!mounted) return;

      // Rediriger vers la page OTP pour confirmer l'email
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/onboarding',
        (route) => false,
      );
      //   arguments: EmailOtpRouteArgs(
      //     email: _emailController.text.trim(),
      //     username: _usernameController.text.trim(),
      //     shouldCreateUser: true,
      //     codeAlreadySent: true,
      //   ),
      // );
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.message);
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            'Erreur: ${e.toString().replaceFirst('Exception: ', '').trim()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithGoogle();
      await _authService.markAuthSeen();
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur de connexion avec Google';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUpWithGitHub() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithGitHub();
      await _authService.markAuthSeen();
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur de connexion avec GitHub';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(String message) {
    if (message.contains('User already registered')) {
      return 'Cet email est déjà utilisé';
    }
    if (message.contains('Password should be')) {
      return 'Le mot de passe doit contenir au moins 6 caractères';
    }
    if (message.contains('Error sending confirmation email') ||
        message.contains('unexpected_failure')) {
      return 'Impossible d\'envoyer l\'email de confirmation. Veuillez vérifier la configuration email dans Supabase ou désactiver temporairement la confirmation d\'email.';
    }
    if (message.contains('Invalid email')) {
      return 'Adresse email invalide';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildBackButton(),
                const SizedBox(height: 30),
                _buildHeader(),
                const SizedBox(height: 24),
                _buildEmailForm(),
                const SizedBox(height: 24),
                _buildOAuthButtons(),
                const SizedBox(height: 24),
                _buildFooter(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: NotitiaTheme.neonPink.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.arrow_back, color: NotitiaTheme.neonPink, size: 20),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Créer un compte',
          style: GoogleFonts.orbitron(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: NotitiaTheme.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Rejoignez Notitia pour synchroniser vos notes',
          style: GoogleFonts.rajdhani(fontSize: 16, color: NotitiaTheme.grey),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Username
          _CyberpunkTextField(
            controller: _usernameController,
            label: 'Nom d\'utilisateur',
            hint: 'votre_pseudo',
            icon: Icons.person_outline,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Entrez un nom d\'utilisateur';
              }
              if (value.length < 3) {
                return 'Minimum 3 caractères';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Email
          _CyberpunkTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'votre@email.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Entrez votre email';
              }
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value)) {
                return 'Email invalide';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Mot de passe
          _CyberpunkTextField(
            controller: _passwordController,
            label: 'Mot de passe',
            hint: '••••••••',
            icon: Icons.lock_outlined,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: NotitiaTheme.grey,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Entrez un mot de passe';
              }
              if (value.length < 6) {
                return 'Minimum 6 caractères';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirmer mot de passe
          _CyberpunkTextField(
            controller: _confirmPasswordController,
            label: 'Confirmer le mot de passe',
            hint: '••••••••',
            icon: Icons.lock_outlined,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: NotitiaTheme.grey,
                size: 20,
              ),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Les mots de passe ne correspondent pas';
              }
              return null;
            },
          ),

          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Un code à 8 chiffres sera envoyé à votre email pour confirmation.',
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                color: NotitiaTheme.grey,
              ),
            ),
          ),

          // Message d'erreur
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _buildErrorMessage(),
          ],

          const SizedBox(height: 24),

          // Bouton inscription
          _buildSubmitButton('S\'INSCRIRE', _signUpWithEmailAndPassword),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.rajdhani(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(String label, VoidCallback onPressed) {
    return GestureDetector(
      onTap: _isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOAuthButtons() {
    return Column(
      children: [
        // Séparateur
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: NotitiaTheme.grey.withOpacity(0.3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'ou inscrivez-vous avec',
                style: GoogleFonts.rajdhani(
                  color: NotitiaTheme.grey,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: NotitiaTheme.grey.withOpacity(0.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Boutons OAuth
        Row(
          children: [
            Expanded(
              child: _OAuthButton(
                onPressed: _isLoading ? null : _signUpWithGoogle,
                icon: 'G',
                iconWidget: const FaIcon(
                  FontAwesomeIcons.google,
                  size: 20,
                  color: Colors.white,
                ),
                label: 'Google',
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _OAuthButton(
                onPressed: _isLoading ? null : _signUpWithGitHub,
                icon: '',
                iconWidget: const FaIcon(
                  FontAwesomeIcons.github,
                  size: 20,
                  color: Colors.white,
                ),
                label: 'GitHub',
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Déjà un compte?',
          style: GoogleFonts.rajdhani(color: NotitiaTheme.grey, fontSize: 14),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pushReplacementNamed('/login');
          },
          child: Text(
            'Connectez-vous',
            style: GoogleFonts.rajdhani(
              color: NotitiaTheme.neonPink,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Widgets réutilisables
// =============================================================================
class _CyberpunkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final bool enabled = true;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _CyberpunkTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            color: NotitiaTheme.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          validator: validator,
          style: GoogleFonts.rajdhani(color: NotitiaTheme.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.rajdhani(
              color: NotitiaTheme.grey.withOpacity(0.5),
            ),
            prefixIcon: Icon(icon, color: NotitiaTheme.neonPink, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: NotitiaTheme.darkBlue.withOpacity(enabled ? 0.5 : 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: NotitiaTheme.neonPink.withOpacity(0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: NotitiaTheme.neonPink.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NotitiaTheme.neonPink, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NotitiaTheme.grey.withOpacity(0.2)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _OAuthButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String icon;
  final Widget? iconWidget;
  final String label;
  final Color color;

  const _OAuthButton({
    required this.onPressed,
    required this.icon,
    this.iconWidget,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: NotitiaTheme.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child:
                    iconWidget ??
                    Text(
                      icon,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                color: NotitiaTheme.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
