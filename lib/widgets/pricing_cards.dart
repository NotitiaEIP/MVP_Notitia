// =============================================================================
// NOTITIA — Pricing Cards Widget
// 5 tiers: Découverte, Essentiel (recommandé), Premium, Entreprise, Notitia Hub
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
  /// If true, show CTA buttons
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
        _buildDecouvertePlan(),
        const SizedBox(height: 16),
        _buildEssentielPlan(),
        const SizedBox(height: 16),
        _buildPremiumPlan(),
        const SizedBox(height: 16),
        _buildEntreprisePlan(),
        const SizedBox(height: 16),
        _buildHubPlan(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DÉCOUVERTE (Free)
  // ---------------------------------------------------------------------------
  Widget _buildDecouvertePlan() {
    const features = [
      _PlanFeature(
        Icons.mic_outlined,
        'Enregistrement & Transcription Illimités',
      ),
      _PlanFeature(Icons.account_tree_outlined, 'Création Limitée (5/mois)'),
      _PlanFeature(Icons.search_rounded, 'Recherche Sémantique'),
      _PlanFeature(Icons.timer_outlined, 'Stockage éphémère (30 jours)'),
    ];

    return _buildCard(
      title: 'Découverte',
      price: '0 €',
      priceSuffix: '/ mois',
      subtitle: 'L\'offre d\'entrée',
      accentColor: NotitiaTheme.grey,
      features: features,
      isRecommended: false,
      ctaLabel: widget.showCTAs ? 'Essayer Gratuitement' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // ESSENTIEL (recommended)
  // ---------------------------------------------------------------------------
  Widget _buildEssentielPlan() {
    const features = [
      _PlanFeature(
        Icons.all_inclusive_rounded,
        'Tout illimité (Mindmap, Résumés)',
      ),
      _PlanFeature(Icons.cloud_done_outlined, 'Stockage Cloud illimité'),
      _PlanFeature(
        Icons.saved_search_rounded,
        'Recherche Sémantique Avancée (Historique)',
      ),
      _PlanFeature(Icons.block, 'Sans Publicité'),
    ];

    return _buildCard(
      title: 'Essentiel',
      price: '9,99 €',
      priceSuffix: '/ mois',
      subtitle: 'Le choix recommandé',
      accentColor: NotitiaTheme.neonCyan,
      features: features,
      isRecommended: true,
      badgeLabel: 'Populaire',
      ctaLabel: widget.showCTAs ? 'Essayer Gratuitement' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // PREMIUM
  // ---------------------------------------------------------------------------
  Widget _buildPremiumPlan() {
    const features = [
      _PlanFeature(Icons.hearing_rounded, 'IA écoute Active (Temps réel)'),
      _PlanFeature(
        Icons.integration_instructions_outlined,
        'Intégrations (Notion, Slack, etc.)',
      ),
      _PlanFeature(
        Icons.sync_rounded,
        'Synchronisation Notitia (Hardware personnel)',
      ),
    ];

    return _buildCard(
      title: 'Premium',
      price: '19,99 €',
      priceSuffix: '/ mois',
      subtitle: 'Pour les power users',
      accentColor: const Color(0xFF7C4DFF),
      features: features,
      isRecommended: false,
      ctaLabel: widget.showCTAs ? 'Passer Premium' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // ENTREPRISE
  // ---------------------------------------------------------------------------
  Widget _buildEntreprisePlan() {
    const features = [
      _PlanFeature(
        Icons.admin_panel_settings_outlined,
        '1 compte admin Premium + 20 invités',
      ),
      _PlanFeature(
        Icons.router_outlined,
        'Notitia Hub Inclus (Boîtier réunion)',
      ),
      _PlanFeature(
        Icons.saved_search_rounded,
        'Recherche Sémantique Avancée (Historique)',
      ),
      _PlanFeature(Icons.block, 'Sans Publicité'),
    ];

    return _buildCard(
      title: 'Entreprise',
      price: '49,99 €',
      priceSuffix: '/ mois',
      subtitle: 'Le choix des équipes',
      accentColor: const Color(0xFFFF6D00),
      features: features,
      isRecommended: false,
      ctaLabel: widget.showCTAs ? 'Contacter les Ventes' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // NOTITIA HUB (one-time purchase)
  // ---------------------------------------------------------------------------
  Widget _buildHubPlan() {
    const features = [
      _PlanFeature(Icons.qr_code_2_rounded, 'Boîtier intelligent avec QR Code'),
      _PlanFeature(
        Icons.sync_alt_rounded,
        'Synchronisation instantanée des réunions',
      ),
    ];

    return _buildCard(
      title: 'Notitia Hub',
      price: '149,99 €',
      priceSuffix: '(achat unique)',
      subtitle: 'Formule entreprise : 2 mois offerts',
      accentColor: NotitiaTheme.neonPink,
      features: features,
      isRecommended: false,
      ctaLabel: widget.showCTAs ? 'Commander le Hub' : null,
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
    String badgeLabel = 'Recommandé',
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
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.orbitron(
                    fontSize: widget.compact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    letterSpacing: 2,
                  ),
                ),
              ),
              if (isRecommended) ...[
                const SizedBox(width: 8),
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
                        badgeLabel,
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

    // Wrap recommended card in animated glow
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
