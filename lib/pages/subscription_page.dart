// =============================================================================
// NOTITIA — Page Abonnement
// Affiche les 5 plans en plein écran
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';
import '../theme.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/pricing_cards.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _languageService = LanguageService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: SafeArea(
        child: Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NotitiaTheme.darkBlue,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: NotitiaTheme.neonCyan.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: NotitiaTheme.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _languageService.translate('subscription_title'),
                    style: GoogleFonts.orbitron(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: NotitiaTheme.neonCyan,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // balance the back button
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const MeduzaWidget(state: MeduzaState.happy, size: 70),
                    const SizedBox(height: 16),
                    Text(
                      _languageService.translate('subscription_choose_plan'),
                      style: GoogleFonts.orbitron(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: NotitiaTheme.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _languageService.translate('subscription_can_change_anytime'),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: NotitiaTheme.grey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const NotitiaPricingCards(showCTAs: true, compact: false),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
