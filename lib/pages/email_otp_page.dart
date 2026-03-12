// =============================================================================
// NOTITIA — Connexion OTP Email (code à 8 chiffres)
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/email_otp_args.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';
import 'onboarding_page.dart';

class EmailOtpPage extends StatefulWidget {
  const EmailOtpPage({super.key});

  @override
  State<EmailOtpPage> createState() => _EmailOtpPageState();
}

class _EmailOtpPageState extends State<EmailOtpPage>
    with SingleTickerProviderStateMixin {
  static const int _emailOtpLength = 8;

  final _authService = AuthService();
  final _languageService = LanguageService();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;
  bool _codeSent = false;
  String? _error;

  bool _shouldCreateUser = false;
  String? _pendingUsername;
  bool _argsLoaded = false;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as EmailOtpRouteArgs?;

    _shouldCreateUser = args?.shouldCreateUser ?? false;
    _pendingUsername = args?.username;

    final email = args?.email?.trim();
    if (email != null && email.isNotEmpty) {
      _emailController.text = email;
    }

    if (args?.codeAlreadySent == true) {
      _codeSent = true;
    }

    if (args?.autoSend == true && !_codeSent) {
      // Déclenche l'envoi après le premier build.
      scheduleMicrotask(_sendCode);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = _languageService.translate('enter_email'));
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _authService.sendEmailOTP(
        email: email,
        shouldCreateUser: _shouldCreateUser,
      );
      if (!mounted) return;

      setState(() {
        _codeSent = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_languageService.translate('code_sent_to').replaceAll('{email}', email), style: GoogleFonts.rajdhani()),
          backgroundColor: NotitiaTheme.neonPink,
        ),
      );
    } on AuthException catch (e) {
      setState(() {
        // Mode connexion strict: si l'email n'existe pas, on affiche un message clair.
        if (!_shouldCreateUser &&
            (e.message.toLowerCase().contains('user') &&
                e.message.toLowerCase().contains('not found'))) {
          _error = _languageService.translate('no_account_found_signup');
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      setState(() {
        _error = _languageService.translate('error_occurred').replaceAll('{error}', e.toString());
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _pinController.text.trim();
    final navigator = Navigator.of(context);

    if (email.isEmpty) {
      setState(() => _error = _languageService.translate('enter_email'));
      return;
    }
    if (code.length != _emailOtpLength) {
      setState(() => _error = _languageService.translate('enter_otp_code').replaceAll('{length}', _emailOtpLength.toString()));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _authService.verifyEmailOTP(
        email: email,
        token: code,
        isSignup: _shouldCreateUser,
      );
      if (!mounted) return;

      if (res.session != null) {
        if (_pendingUsername != null && _pendingUsername!.trim().isNotEmpty) {
          // On tente de sauvegarder le username; on ne bloque pas la navigation si ça échoue.
          try {
            await _authService.upsertProfile(username: _pendingUsername);
          } catch (_) {}
        }
        unawaited(_authService.markAuthSeen());
        if (!mounted) return;

        // Si c'est une inscription, verifier si l'onboarding a deja ete fait
        if (_shouldCreateUser) {
          final alreadyOnboarded = await OnboardingService.isOnboarded();
          if (!alreadyOnboarded) {
            navigator.pushNamedAndRemoveUntil('/onboarding', (route) => false);
            return;
          }
        }
        navigator.pushNamedAndRemoveUntil('/main', (route) => false);
      } else {
        setState(() {
          _error = _languageService.translate('session_error_supabase');
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = _languageService.translate('invalid_expired_code').replaceAll('{error}', e.toString());
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                _buildEmailField(),
                const SizedBox(height: 16),
                if (_codeSent) ...[
                  _buildOtpInput(),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  _buildErrorMessage(_error!),
                  const SizedBox(height: 16),
                ],
                _buildPrimaryButton(
                  _codeSent ? _languageService.translate('verify_code_button') : _languageService.translate('send_code_button'),
                  _codeSent ? _verifyCode : _sendCode,
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _sendCode,
                    child: Text(
                      _languageService.translate('resend_code'),
                      style: GoogleFonts.rajdhani(
                        color: NotitiaTheme.neonPink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
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
        child: const Icon(
          Icons.arrow_back,
          color: NotitiaTheme.neonPink,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _shouldCreateUser ? _languageService.translate('signup_by_code') : _languageService.translate('signin_by_code'),
          style: GoogleFonts.orbitron(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: NotitiaTheme.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _shouldCreateUser
              ? _languageService.translate('signup_otp_description').replaceAll('{length}', _emailOtpLength.toString())
              : _languageService.translate('signin_otp_description').replaceAll('{length}', _emailOtpLength.toString()),
          style: GoogleFonts.rajdhani(fontSize: 16, color: NotitiaTheme.grey),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      enabled: !_codeSent && !_isLoading,
      style: GoogleFonts.rajdhani(color: NotitiaTheme.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: _languageService.translate('email'),
        hintText: 'votre@email.com',
        labelStyle: GoogleFonts.rajdhani(color: NotitiaTheme.grey),
        hintStyle: GoogleFonts.rajdhani(
          color: NotitiaTheme.grey.withOpacity(0.6),
        ),
        prefixIcon: Icon(
          Icons.email_outlined,
          color: NotitiaTheme.neonPink.withOpacity(0.8),
        ),
        filled: true,
        fillColor: NotitiaTheme.darkBlue.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NotitiaTheme.neonPink.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NotitiaTheme.neonPink.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NotitiaTheme.neonPink, width: 2),
        ),
      ),
    );
  }

  Widget _buildOtpInput() {
    final defaultPinTheme = PinTheme(
      width: 44,
      height: 54,
      textStyle: GoogleFonts.orbitron(
        fontSize: 18,
        color: NotitiaTheme.white,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NotitiaTheme.neonPink.withOpacity(0.3)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _languageService.translate('otp_code_label').replaceAll('{length}', _emailOtpLength.toString()),
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            color: NotitiaTheme.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Pinput(
          controller: _pinController,
          length: _emailOtpLength,
          autofocus: true,
          enabled: !_isLoading,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: defaultPinTheme.copyWith(
            decoration: defaultPinTheme.decoration!.copyWith(
              border: Border.all(color: NotitiaTheme.neonPink, width: 2),
            ),
          ),
          onCompleted: (_) {
            // Optionnel: validation auto
          },
        ),
      ],
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
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

  Widget _buildErrorMessage(String message) {
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
              message,
              style: GoogleFonts.rajdhani(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
