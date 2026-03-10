// =============================================================================
// NOTITIA — Header uniforme pour toutes les pages
// Icône + Titre à gauche, actions optionnelles + Profil à droite
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'profile_button.dart';

class NotitiaPageHeader extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;
  final List<Widget> actions;

  const NotitiaPageHeader({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.profile,
    this.onProfileTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Icon(icon, color: NotitiaTheme.neonPink, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: subtitle != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.orbitron(
                          fontSize: 18,
                          color: NotitiaTheme.white,
                          letterSpacing: 4,
                        ),
                      ),
                      Text(
                        subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: NotitiaTheme.grey,
                        ),
                      ),
                    ],
                  )
                : Text(
                    title,
                    style: GoogleFonts.orbitron(
                      fontSize: 18,
                      color: NotitiaTheme.white,
                      letterSpacing: 4,
                    ),
                  ),
          ),
          ...actions,
          if (onProfileTap != null) ...[
            if (actions.isNotEmpty) const SizedBox(width: 4),
            NotitiaProfileButton(profile: profile, onTap: onProfileTap!),
          ],
        ],
      ),
    );
  }
}
