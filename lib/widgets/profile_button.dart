// =============================================================================
// NOTITIA — Bouton profil compact pour intégration dans les headers
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../services/auth_service.dart';

class NotitiaProfileButton extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onTap;
  final double size;

  const NotitiaProfileButton({
    super.key,
    required this.profile,
    required this.onTap,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final isLoggedIn = authService.isAuthenticated;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isLoggedIn
              ? LinearGradient(
                  colors: [
                    NotitiaTheme.neonPink,
                    NotitiaTheme.neonPink.withOpacity(0.6),
                  ],
                )
              : null,
          border: !isLoggedIn
              ? Border.all(
                  color: NotitiaTheme.neonPink.withOpacity(0.5),
                  width: 1.5,
                )
              : null,
          boxShadow: isLoggedIn
              ? [
                  BoxShadow(
                    color: NotitiaTheme.neonPink.withOpacity(0.25),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: profile?.avatarUrl != null
            ? ClipOval(
                child: Image.network(
                  profile!.avatarUrl!,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (_, _, _) =>
                      _buildDefault(authService, isLoggedIn),
                ),
              )
            : _buildDefault(authService, isLoggedIn),
      ),
    );
  }

  Widget _buildDefault(AuthService authService, bool isLoggedIn) {
    if (isLoggedIn) {
      final initial =
          (profile?.username ??
                  profile?.email ??
                  authService.currentUser?.email ??
                  'U')[0]
              .toUpperCase();
      return Center(
        child: Text(
          initial,
          style: GoogleFonts.orbitron(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    } else {
      return Icon(
        Icons.person_outline,
        color: NotitiaTheme.neonPink,
        size: size * 0.55,
      );
    }
  }
}
