// =============================================================================
// NOTITIA — Widget Meduza (Mascotte IA)
// Meduse animee avec 6 etats visuels distincts
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Les 6 etats possibles de Meduza
enum MeduzaState {
  hello, // Salutation — apparait au splash / onboarding
  idle, // Repos — flottement doux (etat par defaut, masque en mode event-driven)
  listening, // Ecoute active — pulse cyan, particules
  processing, // Traitement IA — rotation, anneau de progression
  happy, // Succes / validation — rebond, glow vert
  confused, // Erreur / incomprehension — tremblement, glow rouge
}

/// Callback pour propager les changements d'etat de Meduza
typedef MeduzaStateCallback = void Function(MeduzaState state);

class MeduzaWidget extends StatefulWidget {
  final MeduzaState state;
  final double size;
  final bool showGlow;

  const MeduzaWidget({
    super.key,
    this.state = MeduzaState.idle,
    this.size = 100,
    this.showGlow = true,
  });

  @override
  State<MeduzaWidget> createState() => _MeduzaWidgetState();
}

class _MeduzaWidgetState extends State<MeduzaWidget>
    with TickerProviderStateMixin {
  // Controleurs d'animation
  late AnimationController _floatController;
  late AnimationController _glowController;
  late AnimationController _spinController;
  late AnimationController _shakeController;
  late AnimationController _bounceController;
  late AnimationController _pulseController;
  late AnimationController _processController;

  // Animations
  late Animation<double> _floatAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shakeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _applyState(widget.state);
  }

  void _initAnimations() {
    // Flottement doux (idle / hello)
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _floatAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // Glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Rotation (processing)
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Tremblement (confused)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: -4, end: 4).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Rebond (happy)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    // Pulse ecoute (listening)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Anneau de progression (processing)
    _processController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void didUpdateWidget(MeduzaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _applyState(widget.state);
    }
  }

  void _stopAll() {
    _floatController.stop();
    _glowController.stop();
    _spinController.stop();
    _shakeController.stop();
    _bounceController.stop();
    _pulseController.stop();
    _processController.stop();
  }

  void _applyState(MeduzaState state) {
    _stopAll();
    switch (state) {
      case MeduzaState.hello:
        _floatController.repeat(reverse: true);
        _glowController.repeat(reverse: true);
        _bounceController.forward(from: 0);
        break;
      case MeduzaState.idle:
        _floatController.repeat(reverse: true);
        _glowController.repeat(reverse: true);
        break;
      case MeduzaState.listening:
        _floatController.repeat(reverse: true);
        _pulseController.repeat(reverse: true);
        _glowController.repeat(reverse: true);
        break;
      case MeduzaState.processing:
        _spinController.repeat();
        _processController.repeat();
        _glowController.repeat(reverse: true);
        break;
      case MeduzaState.happy:
        _floatController.repeat(reverse: true);
        _bounceController.forward(from: 0);
        _glowController.repeat(reverse: true);
        break;
      case MeduzaState.confused:
        _shakeController.repeat(reverse: true);
        _glowController.repeat(reverse: true);
        break;
    }
  }

  /// Asset image correspondant a l'etat
  String _getAssetPath(MeduzaState state) {
    switch (state) {
      case MeduzaState.hello:
        return 'assets/mascotte/medusa_hello.png';
      case MeduzaState.idle:
        return 'assets/mascotte/medusa_idle.png';
      case MeduzaState.listening:
        return 'assets/mascotte/medusa_listening.png';
      case MeduzaState.processing:
        return 'assets/mascotte/medusa_processing.png';
      case MeduzaState.happy:
        return 'assets/mascotte/medusa_happy.png';
      case MeduzaState.confused:
        return 'assets/mascotte/medusa_confused.png';
    }
  }

  /// Couleur du glow selon l'etat
  Color _getGlowColor(MeduzaState state) {
    switch (state) {
      case MeduzaState.hello:
        return NotitiaTheme.neonPink;
      case MeduzaState.idle:
        return NotitiaTheme.neonCyan.withOpacity(0.4);
      case MeduzaState.listening:
        return NotitiaTheme.neonCyan;
      case MeduzaState.processing:
        return NotitiaTheme.neonPink;
      case MeduzaState.happy:
        return const Color(0xFF00FF88);
      case MeduzaState.confused:
        return NotitiaTheme.redRecording;
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _glowController.dispose();
    _spinController.dispose();
    _shakeController.dispose();
    _bounceController.dispose();
    _pulseController.dispose();
    _processController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _glowController,
        _spinController,
        _shakeController,
        _bounceController,
        _pulseController,
        _processController,
      ]),
      builder: (context, child) {
        final glowColor = _getGlowColor(widget.state);
        final glowOpacity = _glowAnimation.value;

        // Calculer la transformation composite
        double translateY = 0;
        double translateX = 0;
        double scale = 1.0;
        double rotation = 0;

        switch (widget.state) {
          case MeduzaState.hello:
            translateY = _floatAnimation.value;
            scale = _bounceAnimation.value;
            break;
          case MeduzaState.idle:
            translateY = _floatAnimation.value;
            break;
          case MeduzaState.listening:
            translateY = _floatAnimation.value;
            scale = _pulseAnimation.value;
            break;
          case MeduzaState.processing:
            rotation = _spinController.value * 0.05;
            break;
          case MeduzaState.happy:
            translateY = _floatAnimation.value;
            scale = _bounceAnimation.value;
            break;
          case MeduzaState.confused:
            translateX = _shakeAnimation.value;
            break;
        }

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow derriere la mascotte
              if (widget.showGlow)
                Container(
                  width: widget.size * 0.7,
                  height: widget.size * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(glowOpacity * 0.5),
                        blurRadius: widget.size * 0.4,
                        spreadRadius: widget.size * 0.1,
                      ),
                    ],
                  ),
                ),

              // Anneau de progression (processing)
              if (widget.state == MeduzaState.processing)
                CustomPaint(
                  size: Size(widget.size * 0.9, widget.size * 0.9),
                  painter: _ProcessingRingPainter(
                    progress: _processController.value,
                    color: glowColor,
                  ),
                ),

              // Particules (listening)
              if (widget.state == MeduzaState.listening)
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _ParticlesPainter(
                    progress: _pulseController.value,
                    color: NotitiaTheme.neonCyan,
                  ),
                ),

              // Image de la mascotte
              Transform.translate(
                offset: Offset(translateX, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Image.asset(
                      _getAssetPath(widget.state),
                      width: widget.size * 0.8,
                      height: widget.size * 0.8,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.auto_awesome,
                        size: widget.size * 0.5,
                        color: NotitiaTheme.neonPink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Custom Painter — Anneau de progression
// =============================================================================
class _ProcessingRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ProcessingRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final bgPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, radius, bgPaint);

    final arcPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * 0.3;
    final startAngle = 2 * pi * progress - pi / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ProcessingRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// =============================================================================
// Custom Painter — Particules (listening)
// =============================================================================
class _ParticlesPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ParticlesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.45;

    for (int i = 0; i < 8; i++) {
      final angle = (2 * pi / 8) * i + progress * 2 * pi;
      final particleRadius = baseRadius + sin(progress * pi * 2 + i) * 8;
      final x = center.dx + cos(angle) * particleRadius;
      final y = center.dy + sin(angle) * particleRadius;

      final opacity = (0.3 + 0.7 * sin(progress * pi + i * 0.5)).clamp(
        0.0,
        1.0,
      );

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
