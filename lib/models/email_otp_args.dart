// =============================================================================
// NOTITIA — Route args: Email OTP
// =============================================================================

/// Arguments de navigation pour [EmailOtpPage].
///
/// - [shouldCreateUser]=false: mode connexion (le compte doit déjà exister)
/// - [shouldCreateUser]=true: mode inscription (création si nécessaire)
class EmailOtpRouteArgs {
  final String? email;
  final bool autoSend;
  final bool shouldCreateUser;
  final bool codeAlreadySent;
  final String? username;

  const EmailOtpRouteArgs({
    this.email,
    this.autoSend = false,
    required this.shouldCreateUser,
    this.codeAlreadySent = false,
    this.username,
  });
}
