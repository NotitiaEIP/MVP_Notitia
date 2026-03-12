// =============================================================================
// NOTITIA — Composites Meduza (Mascotte + Bulle)
// Widgets prets a l'emploi pour integrer Meduza dans les pages
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
// MeduzaFloatingOverlay — Mascotte draggable qui se colle au bord le plus proche
// Bulle de texte positionnee vers l'interieur de l'ecran
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
  static const double _avatarSize = 56;
  static const double _edgeMargin = 4;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  Offset _offset = Offset.zero;
  bool _initialized = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    if (widget.visible) _animController.forward();
  }

  @override
  void didUpdateWidget(MeduzaFloatingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _animController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _getGlowColor() {
    switch (widget.bubbleStyle) {
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

  /// Snap to the nearest horizontal edge (left or right)
  Offset _snapToEdge(Offset current, Size screenSize) {
    final centerX = current.dx + _avatarSize / 2;
    final midScreen = screenSize.width / 2;
    final targetX = centerX < midScreen
        ? _edgeMargin
        : screenSize.width - _avatarSize - _edgeMargin;
    final targetY = current.dy.clamp(
      _edgeMargin,
      screenSize.height - _avatarSize - _edgeMargin,
    );
    return Offset(targetX, targetY);
  }

  /// True if avatar is on the left side of the screen
  bool get _isOnLeft {
    return _offset.dx < _avatarSize;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    if (!_initialized) {
      _offset = Offset(_edgeMargin, screenSize.height - 180);
      _initialized = true;
    }

    final isLeft = _isOnLeft;
    // Keep text fully visible by resizing to available side space.
    final availableWidth = isLeft
        ? screenSize.width - _offset.dx - _avatarSize - 18
        : _offset.dx - 18;
    final bubbleMaxWidth = availableWidth.clamp(90.0, 200.0);

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: _offset.dx,
      top: _offset.dy,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _isDragging = true),
            onPanUpdate: (details) {
              setState(() {
                _offset = Offset(
                  (_offset.dx + details.delta.dx).clamp(
                    0,
                    screenSize.width - _avatarSize,
                  ),
                  (_offset.dy + details.delta.dy).clamp(
                    0,
                    screenSize.height - _avatarSize - 40,
                  ),
                );
              });
            },
            onPanEnd: (_) {
              setState(() {
                _isDragging = false;
                _offset = _snapToEdge(_offset, screenSize);
              });
            },
            onTap: widget.onDismiss,
            child: SizedBox(
              width: _avatarSize,
              height: _avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.message != null)
                    Positioned(
                      top: 8,
                      left: isLeft ? _avatarSize + 6 : null,
                      right: isLeft ? null : _avatarSize + 6,
                      child: _buildBubble(bubbleMaxWidth),
                    ),
                  // Avatar remains fully anchored inside screen bounds.
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _getGlowColor().withValues(alpha: 0.3),
                          blurRadius: _isDragging ? 24 : 16,
                          spreadRadius: _isDragging ? 4 : 2,
                        ),
                      ],
                    ),
                    child: MeduzaWidget(
                      state: widget.state,
                      size: _avatarSize,
                      showGlow: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(double maxWidth) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getGlowColor().withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _getGlowColor().withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        widget.message!,
        style: GoogleFonts.poppins(
          fontSize: 11,
          color: NotitiaTheme.white.withValues(alpha: 0.9),
          height: 1.3,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
          errorBuilder: (_, _, _) =>
              Icon(Icons.auto_awesome, size: 18, color: NotitiaTheme.neonPink),
        ),
      ),
    );
  }
}
