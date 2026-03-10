// =============================================================================
// NOTITIA — Pricing Cards Widget
// 3 tiers: Free, Essential (recommandé), Business
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import 'meduza_widget.dart';

// =============================================================================
// Data model
// =============================================================================
class _PlanFeature {
  final IconData icon;
  final String label;
  const _PlanFeature(this.icon, this.label);
}

// =============================================================================
// Main widget
// =============================================================================
class NotitiaPricingCards extends StatefulWidget {
  /// If true, show CTA buttons under Essential & Business
  final bool showCTAs;

  /// Compact mode for profile page embedding
  final bool compact;

  const NotitiaPricingCards({
    super.key,
    this.showCTAs = true,
    this.compact = false,
  });

  @override
  State<NotitiaPricingCards> createState() => _NotitiaPricingCardsState();
}

class _NotitiaPricingCardsState extends State<NotitiaPricingCards>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFreePlan(),
        const SizedBox(height: 16),
        _buildEssentialPlan(),
        const SizedBox(height: 16),
        _buildBusinessPlan(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FREE
  // ---------------------------------------------------------------------------
  Widget _buildFreePlan() {
    const features = [
      _PlanFeature(Icons.mic_outlined, 'Transcription Standard'),
      _PlanFeature(Icons.account_tree_outlined, 'Mindmap Découverte'),
      _PlanFeature(Icons.timer_outlined, 'Stockage Éphémère (7 jours)'),
    ];

    return _buildCard(
      title: 'Free',
      price: '0 €',
      subtitle: 'Idéal pour tester l\'outil occasionnellement',
      accentColor: NotitiaTheme.grey,
      features: features,
      isRecommended: false,
      ctaLabel: null,
    );
  }

  // ---------------------------------------------------------------------------
  // ESSENTIAL (recommended)
  // ---------------------------------------------------------------------------
  Widget _buildEssentialPlan() {
    const features = [
      _PlanFeature(Icons.auto_awesome, 'Intelligence Supérieure (Claude)'),
      _PlanFeature(
        Icons.dashboard_customize_rounded,
        'Styles Illimités (3 formes de mindmap)',
      ),
      _PlanFeature(Icons.all_inclusive_rounded, 'Mémoire Infinie'),
    ];

    return _buildCard(
      title: 'Essential',
      price: '9,99 €',
      priceSuffix: '/ mois',
      subtitle: '',
      accentColor: NotitiaTheme.neonCyan,
      features: features,
      isRecommended: true,
      ctaLabel: widget.showCTAs ? 'Passer à l\'Essentiel' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // BUSINESS
  // ---------------------------------------------------------------------------
  Widget _buildBusinessPlan() {
    const features = [
      _PlanFeature(Icons.check_circle_outline, 'Tout Essential inclus'),
      _PlanFeature(Icons.qr_code_2_rounded, 'Mode Réunion (QR Sync)'),
      _PlanFeature(Icons.groups_rounded, 'Dashboard d\'Équipe'),
      _PlanFeature(Icons.saved_search_rounded, 'Recherche Sémantique Avancée'),
    ];

    return _buildCard(
      title: 'Business',
      price: '19,99 €',
      priceSuffix: '/ utilisateur / mois',
      subtitle: '',
      accentColor: const Color(0xFF7C4DFF),
      features: features,
      isRecommended: false,
      ctaLabel: widget.showCTAs ? 'Optimiser mon équipe' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Generic card builder
  // ---------------------------------------------------------------------------
  Widget _buildCard({
    required String title,
    required String price,
    String priceSuffix = '',
    required String subtitle,
    required Color accentColor,
    required List<_PlanFeature> features,
    required bool isRecommended,
    String? ctaLabel,
  }) {
    final cardContent = Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.compact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: NotitiaTheme.darkBlue.withValues(alpha: 0.7),
        border: Border.all(
          color: isRecommended
              ? accentColor.withValues(alpha: 0.6)
              : accentColor.withValues(alpha: 0.2),
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + badge
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.orbitron(
                  fontSize: widget.compact ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MeduzaWidget(
                        state: MeduzaState.happy,
                        size: 22,
                        showGlow: false,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Recommandé',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: GoogleFonts.orbitron(
                  fontSize: widget.compact ? 22 : 26,
                  fontWeight: FontWeight.bold,
                  color: NotitiaTheme.white,
                ),
              ),
              if (priceSuffix.isNotEmpty) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    priceSuffix,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: NotitiaTheme.grey,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: NotitiaTheme.grey,
              ),
            ),
          ],

          const SizedBox(height: 16),
          // Divider
          Container(height: 1, color: accentColor.withValues(alpha: 0.15)),
          const SizedBox(height: 14),

          // Features
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(f.icon, color: accentColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: NotitiaTheme.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // CTA
          if (ctaLabel != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: hook up subscription flow
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor.withValues(alpha: 0.15),
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  ctaLabel,
                  style: GoogleFonts.orbitron(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!isRecommended) return cardContent;

    // Wrap Essential in animated glow
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(
                  alpha: 0.12 + _glowAnimation.value * 0.18,
                ),
                blurRadius: 16 + _glowAnimation.value * 12,
                spreadRadius: _glowAnimation.value * 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: cardContent,
    );
  }
}
