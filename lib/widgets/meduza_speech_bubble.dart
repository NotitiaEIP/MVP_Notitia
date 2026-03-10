// =============================================================================
// NOTITIA — Bulle de dialogue Meduza
// Bulle avec effet typewriter et styles contextuels
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// Position de la fleche de la bulle
enum BubbleArrowPosition { top, bottom, left, right }

/// Style visuel de la bulle
enum BubbleStyle { normal, success, error, info }

class MeduzaSpeechBubble extends StatefulWidget {
  final String text;
  final BubbleStyle style;
  final BubbleArrowPosition arrowPosition;
  final double maxWidth;
  final bool animate;
  final Duration typewriterSpeed;

  const MeduzaSpeechBubble({
    super.key,
    required this.text,
    this.style = BubbleStyle.normal,
    this.arrowPosition = BubbleArrowPosition.bottom,
    this.maxWidth = 260,
    this.animate = true,
    this.typewriterSpeed = const Duration(milliseconds: 30),
  });

  @override
  State<MeduzaSpeechBubble> createState() => _MeduzaSpeechBubbleState();
}

class _MeduzaSpeechBubbleState extends State<MeduzaSpeechBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Color _getBorderColor() {
    switch (widget.style) {
      case BubbleStyle.normal:
        return NotitiaTheme.neonCyan.withOpacity(0.4);
      case BubbleStyle.success:
        return const Color(0xFF00FF88).withOpacity(0.5);
      case BubbleStyle.error:
        return NotitiaTheme.redRecording.withOpacity(0.5);
      case BubbleStyle.info:
        return NotitiaTheme.neonPink.withOpacity(0.5);
    }
  }

  Color _getGlowColor() {
    switch (widget.style) {
      case BubbleStyle.normal:
        return NotitiaTheme.neonCyan;
      case BubbleStyle.success:
        return const Color(0xFF00FF88);
      case BubbleStyle.error:
        return NotitiaTheme.redRecording;
      case BubbleStyle.info:
        return NotitiaTheme.neonPink;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: _getAlignmentForArrow(),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _getBorderColor(), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: _getGlowColor().withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: widget.animate
                ? _AnimatedText(
                    text: widget.text,
                    speed: widget.typewriterSpeed,
                  )
                : Text(
                    widget.text,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: NotitiaTheme.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Alignment _getAlignmentForArrow() {
    switch (widget.arrowPosition) {
      case BubbleArrowPosition.top:
        return Alignment.topCenter;
      case BubbleArrowPosition.bottom:
        return Alignment.bottomCenter;
      case BubbleArrowPosition.left:
        return Alignment.centerLeft;
      case BubbleArrowPosition.right:
        return Alignment.centerRight;
    }
  }
}

// =============================================================================
// Texte anime mot par mot avec fondu progressif
// Evite les sauts de ligne brusques du mode caractere par caractere
// =============================================================================
class _AnimatedText extends StatefulWidget {
  final String text;
  final Duration speed;

  const _AnimatedText({required this.text, required this.speed});

  @override
  State<_AnimatedText> createState() => _AnimatedTextState();
}

class _AnimatedTextState extends State<_AnimatedText> {
  late List<String> _words;
  int _visibleWordCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(' ');
    _startTypewriter();
  }

  @override
  void didUpdateWidget(_AnimatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _words = widget.text.split(' ');
      _visibleWordCount = 0;
      _startTypewriter();
    }
  }

  void _startTypewriter() {
    // Vitesse adaptee : ~60ms par mot pour un debit naturel
    final wordSpeed = Duration(milliseconds: widget.speed.inMilliseconds * 2);
    _timer = Timer.periodic(wordSpeed, (timer) {
      if (_visibleWordCount < _words.length) {
        setState(() => _visibleWordCount++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = GoogleFonts.poppins(
      fontSize: 13,
      color: NotitiaTheme.white.withOpacity(0.9),
      height: 1.4,
    );

    return Text.rich(
      TextSpan(
        children: List.generate(_words.length, (i) {
          final isVisible = i < _visibleWordCount;
          final isLast = i == _visibleWordCount - 1;
          return TextSpan(
            text: i == 0 ? _words[i] : ' ${_words[i]}',
            style: baseStyle.copyWith(
              color: isVisible
                  ? baseStyle.color!.withOpacity(isLast ? 0.7 : 1.0)
                  : Colors.transparent,
            ),
          );
        }),
      ),
    );
  }
}
