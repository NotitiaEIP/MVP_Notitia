// =============================================================================
// NOTITIA — Composites Meduza (Mascotte + Bulle)
// Widgets prets a l'emploi pour integrer Meduza dans les pages
// =============================================================================

import 'package:flutter/material.dart';
import '../theme.dart';
import 'meduza_widget.dart';
import 'meduza_speech_bubble.dart';

// =============================================================================
// MeduzaCompanion — Colonne Meduza + bulle (inline dans une page)
// =============================================================================
class MeduzaCompanion extends StatelessWidget {
  final MeduzaState state;
  final String? message;
  final BubbleStyle bubbleStyle;
  final double meduzaSize;

  const MeduzaCompanion({
    super.key,
    required this.state,
    this.message,
    this.bubbleStyle = BubbleStyle.normal,
    this.meduzaSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MeduzaWidget(state: state, size: meduzaSize),
        if (message != null) ...[
          const SizedBox(height: 12),
          MeduzaSpeechBubble(
            text: message!,
            style: bubbleStyle,
            arrowPosition: BubbleArrowPosition.top,
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// MeduzaFloatingOverlay — Overlay positionne en bas a droite
// Apparait / disparait avec une animation slide-in
// Utilise dans MainNavigation pour les evenements contextuels
// =============================================================================
class MeduzaFloatingOverlay extends StatefulWidget {
  final MeduzaState state;
  final String? message;
  final BubbleStyle bubbleStyle;
  final bool visible;
  final VoidCallback? onDismiss;

  const MeduzaFloatingOverlay({
    super.key,
    required this.state,
    this.message,
    this.bubbleStyle = BubbleStyle.normal,
    this.visible = true,
    this.onDismiss,
  });

  @override
  State<MeduzaFloatingOverlay> createState() => _MeduzaFloatingOverlayState();
}

class _MeduzaFloatingOverlayState extends State<MeduzaFloatingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.2, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    if (widget.visible) _slideController.forward();
  }

  @override
  void didUpdateWidget(MeduzaFloatingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _slideController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _slideController.reverse();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.message != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 10),
                    child: MeduzaSpeechBubble(
                      text: widget.message!,
                      style: widget.bubbleStyle,
                      arrowPosition: BubbleArrowPosition.right,
                      maxWidth: 200,
                    ),
                  ),
                MeduzaWidget(state: widget.state, size: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MeduzaCentered — Meduza centree pour pages plein ecran (onboarding, splash)
// =============================================================================
class MeduzaCentered extends StatelessWidget {
  final MeduzaState state;
  final String? message;
  final BubbleStyle bubbleStyle;
  final double meduzaSize;

  const MeduzaCentered({
    super.key,
    required this.state,
    this.message,
    this.bubbleStyle = BubbleStyle.normal,
    this.meduzaSize = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MeduzaWidget(state: state, size: meduzaSize),
          if (message != null) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: MeduzaSpeechBubble(
                text: message!,
                style: bubbleStyle,
                arrowPosition: BubbleArrowPosition.top,
                maxWidth: 300,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// MeduzaMiniAvatar — Petit avatar pour les bulles de chat (assistant)
// =============================================================================
class MeduzaMiniAvatar extends StatelessWidget {
  final MeduzaState state;

  const MeduzaMiniAvatar({super.key, this.state = MeduzaState.idle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            NotitiaTheme.neonPink.withOpacity(0.3),
            NotitiaTheme.neonCyan.withOpacity(0.3),
          ],
        ),
        border: Border.all(
          color: NotitiaTheme.neonCyan.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/mascotte/medusa_idle.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.auto_awesome, size: 18, color: NotitiaTheme.neonPink),
        ),
      ),
    );
  }
}
