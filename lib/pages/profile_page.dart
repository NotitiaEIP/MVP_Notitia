// =============================================================================
// NOTITIA — Page de profil et paramètres du compte
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _languageService = LanguageService();
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isUpdating = false;

  final _usernameController = TextEditingController();
  bool _isEditingUsername = false;
  late String _selectedLanguage;

  // Thèmes disponibles
  int _selectedTheme = 0;
  final List<_ThemeOption> _themes = [
    _ThemeOption('Cyberpunk', NotitiaTheme.neonPink, NotitiaTheme.deepBlue),
    _ThemeOption('Ocean', const Color(0xFF00E5FF), const Color(0xFF001E3C)),
    _ThemeOption('Forest', const Color(0xFF00FF88), const Color(0xFF0D1F0D)),
    _ThemeOption('Sunset', const Color(0xFFFF6B35), const Color(0xFF1A0A00)),
    _ThemeOption('Violet', const Color(0xFF9D4EDD), const Color(0xFF10002B)),
  ];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    _selectedLanguage = _languageService.currentLanguage;
    _loadProfile();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _authService.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _usernameController.text = profile?.username ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateUsername() async {
    if (_usernameController.text.isEmpty) return;

    setState(() => _isUpdating = true);

    try {
      await _authService.updateProfile(
        username: _usernameController.text.trim(),
      );
      await _loadProfile();
      setState(() => _isEditingUsername = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('profile_updated'),
              style: GoogleFonts.rajdhani(),
            ),
            backgroundColor: NotitiaTheme.neonPink,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('error'),
              style: GoogleFonts.rajdhani(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (image == null) return;

    setState(() => _isUpdating = true);

    try {
      final bytes = await File(image.path).readAsBytes();
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _authService.uploadAvatar(bytes, fileName);
      await _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('profile_updated'),
              style: GoogleFonts.rajdhani(),
            ),
            backgroundColor: NotitiaTheme.neonPink,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('error'),
              style: GoogleFonts.rajdhani(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withOpacity(0.5)),
        ),
        title: Text(
          _languageService.translate('sign_out'),
          style: GoogleFonts.orbitron(color: NotitiaTheme.white, fontSize: 18),
        ),
        content: Text(
          _languageService.translate('confirm_logout'),
          style: GoogleFonts.rajdhani(color: NotitiaTheme.grey, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              _languageService.translate('cancel'),
              style: GoogleFonts.rajdhani(color: NotitiaTheme.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              _languageService.translate('sign_out'),
              style: GoogleFonts.rajdhani(color: NotitiaTheme.neonPink),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/auth', (route) => false);
      }
    }
  }

  Future<void> _showLanguageDialog() async {
    final selectedLanguage = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NotitiaTheme.neonPink.withOpacity(0.5)),
        ),
        title: Text(
          _languageService.translate('select_language'),
          style: GoogleFonts.orbitron(color: NotitiaTheme.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('en', _languageService.getLanguageLabel('en'), _selectedLanguage == 'en'),
            const SizedBox(height: 12),
            _buildLanguageOption('fr', _languageService.getLanguageLabel('fr'), _selectedLanguage == 'fr'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              _languageService.translate('cancel'),
              style: GoogleFonts.rajdhani(color: NotitiaTheme.grey),
            ),
          ),
        ],
      ),
    );

    if (selectedLanguage != null && selectedLanguage != _selectedLanguage) {
      await _languageService.changeLanguage(selectedLanguage);
      if (mounted) {
        setState(() {
          _selectedLanguage = selectedLanguage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _languageService.translate('language_changed'),
              style: GoogleFonts.rajdhani(),
            ),
            backgroundColor: NotitiaTheme.neonPink,
          ),
        );
      }
    }
  }

  Widget _buildLanguageOption(
    String languageCode,
    String languageName,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(languageCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? NotitiaTheme.neonPink
                : NotitiaTheme.neonPink.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? NotitiaTheme.neonPink.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: NotitiaTheme.neonPink, width: 2),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NotitiaTheme.neonPink,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              languageName,
              style: GoogleFonts.rajdhani(
                color: NotitiaTheme.white,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: NotitiaTheme.neonPink,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildAvatarSection(),
                      const SizedBox(height: 32),
                      _buildAccountSection(),
                      const SizedBox(height: 24),
                      _buildThemeSection(),
                      const SizedBox(height: 24),
                      _buildPlanSection(),
                      const SizedBox(height: 24),
                      _buildSettingsSection(),
                      const SizedBox(height: 24),
                      _buildDangerZone(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: NotitiaTheme.neonPink.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.arrow_back,
              color: NotitiaTheme.neonPink,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          _languageService.translate('profile'),
          style: GoogleFonts.orbitron(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: NotitiaTheme.white,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarSection() {
    return Column(
      children: [
        // Avatar avec bouton d'édition
        Stack(
          children: [
            GestureDetector(
              onTap: _isUpdating ? null : _pickAndUploadAvatar,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      NotitiaTheme.neonPink,
                      NotitiaTheme.neonPink.withOpacity(0.6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NotitiaTheme.neonPink.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _isUpdating
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : _profile?.avatarUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: _profile!.avatarUrl!,
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (context, url, error) =>
                              _buildDefaultAvatar(),
                        ),
                      )
                    : _buildDefaultAvatar(),
              ),
            ),

            // Bouton d'édition
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: NotitiaTheme.darkBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: NotitiaTheme.neonPink, width: 2),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: _isUpdating ? null : _pickAndUploadAvatar,
                  icon: Icon(
                    Icons.camera_alt,
                    color: NotitiaTheme.neonPink,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Nom d'utilisateur
        if (_isEditingUsername)
          _buildUsernameEditor()
        else
          GestureDetector(
            onTap: () => setState(() => _isEditingUsername = true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _profile?.username ?? _languageService.translate('user'),
                  style: GoogleFonts.orbitron(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: NotitiaTheme.white,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit, color: NotitiaTheme.grey, size: 18),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Email
        Text(
          _profile?.email ?? _authService.currentUser?.email ?? '',
          style: GoogleFonts.rajdhani(fontSize: 14, color: NotitiaTheme.grey),
        ),
      ],
    );
  }

  Widget _buildDefaultAvatar() {
    final initial = (_profile?.username ?? _profile?.email ?? 'U')[0]
        .toUpperCase();
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.orbitron(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildUsernameEditor() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          child: TextField(
            controller: _usernameController,
            autofocus: true,
            style: GoogleFonts.orbitron(
              fontSize: 16,
              color: NotitiaTheme.white,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: NotitiaTheme.neonPink),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: NotitiaTheme.neonPink, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isUpdating ? null : _updateUsername,
          icon: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: NotitiaTheme.neonPink,
                    strokeWidth: 2,
                  ),
                )
              : Icon(Icons.check, color: NotitiaTheme.neonPink),
        ),
        IconButton(
          onPressed: () => setState(() {
            _isEditingUsername = false;
            _usernameController.text = _profile?.username ?? '';
          }),
          icon: Icon(Icons.close, color: NotitiaTheme.grey),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    return _buildSection(
      title: _languageService.translate('profile_account_section'),
      icon: Icons.person_outline,
      children: [
        _SettingsTile(
          icon: Icons.email_outlined,
          title: _languageService.translate('profile_email_label'),
          subtitle: _profile?.email ?? _languageService.translate('profile_undefined'),
          onTap: null, // Email non modifiable directement
        ),
        _SettingsTile(
          icon: Icons.calendar_today_outlined,
          title: _languageService.translate('member_since'),
          subtitle: _profile != null
              ? _formatDate(_profile!.createdAt)
              : _languageService.translate('profile_unknown'),
          onTap: null,
        ),
      ],
    );
  }

  Widget _buildThemeSection() {
    return _buildSection(
      title: _languageService.translate('theme'),
      icon: Icons.palette_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _themes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final theme = _themes[index];
                final isSelected = _selectedTheme == index;

                return GestureDetector(
                  onTap: () => setState(() => _selectedTheme = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.accent
                            : theme.accent.withOpacity(0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [theme.accent, theme.background],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: theme.accent.withOpacity(0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          theme.name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            color: isSelected
                                ? theme.accent
                                : NotitiaTheme.grey,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _languageService.translate('custom_themes_coming_soon'),
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            color: NotitiaTheme.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanSection() {
    return _buildSection(
      title: _languageService.translate('profile_subscription_section'),
      icon: Icons.workspace_premium_rounded,
      accentColor: NotitiaTheme.neonCyan,
      children: [
        _SettingsTile(
          icon: Icons.diamond_outlined,
          title: _languageService.translate('profile_my_subscription'),
          subtitle: _languageService.translate('profile_subscription_description'),
          iconColor: NotitiaTheme.neonCyan,
          onTap: () => Navigator.of(context).pushNamed('/subscription'),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return _buildSection(
      title: _languageService.translate('settings'),
      icon: Icons.settings_outlined,
      children: [
        _SettingsTile(
          icon: Icons.notifications_outlined,
          title: _languageService.translate('notifications'),
          subtitle: _languageService.translate('manage_notifications'),
          onTap: () {
            // TODO: Implémenter les paramètres de notifications
          },
          trailing: Switch(
            value: true,
            onChanged: (value) {},
            activeThumbColor: NotitiaTheme.neonPink,
          ),
        ),
        _SettingsTile(
          icon: Icons.language_outlined,
          title: _languageService.translate('language'),
          subtitle: _languageService.getLanguageLabel(_selectedLanguage),
          onTap: _showLanguageDialog,
        ),
        _SettingsTile(
          icon: Icons.storage_outlined,
          title: _languageService.translate('storage'),
          subtitle: _languageService.translate('manage_local_data'),
          onTap: () {
            // TODO: Implémenter la gestion du stockage
          },
        ),
        _SettingsTile(
          icon: Icons.security_outlined,
          title: _languageService.translate('security'),
          subtitle: _languageService.translate('password_and_login'),
          onTap: () {
            // TODO: Implémenter les paramètres de sécurité
          },
        ),
      ],
    );
  }

  Widget _buildDangerZone() {
    return _buildSection(
      title: _languageService.translate('danger_zone'),
      icon: Icons.warning_amber_outlined,
      accentColor: Colors.red,
      children: [
        _SettingsTile(
          icon: Icons.logout,
          title: _languageService.translate('sign_out_title'),
          subtitle: _languageService.translate('sign_out_subtitle'),
          iconColor: Colors.orange,
          onTap: _signOut,
        ),
        _SettingsTile(
          icon: Icons.delete_forever_outlined,
          title: _languageService.translate('delete_account_title'),
          subtitle: _languageService.translate('delete_account_subtitle'),
          iconColor: Colors.red,
          onTap: () {
            // TODO: Implémenter la suppression de compte
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _languageService.translate('feature_coming_soon'),
                  style: GoogleFonts.rajdhani(),
                ),
                backgroundColor: NotitiaTheme.grey,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? accentColor,
  }) {
    final color = accentColor ?? NotitiaTheme.neonPink;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: color.withOpacity(0.2)),
          ...children,
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      _languageService.translate('month_january'),
      _languageService.translate('month_february'),
      _languageService.translate('month_march'),
      _languageService.translate('month_april'),
      _languageService.translate('month_may'),
      _languageService.translate('month_june'),
      _languageService.translate('month_july'),
      _languageService.translate('month_august'),
      _languageService.translate('month_september'),
      _languageService.translate('month_october'),
      _languageService.translate('month_november'),
      _languageService.translate('month_december'),
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

// =============================================================================
// Widgets réutilisables
// =============================================================================

class _ThemeOption {
  final String name;
  final Color accent;
  final Color background;

  _ThemeOption(this.name, this.accent, this.background);
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? NotitiaTheme.neonPink).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor ?? NotitiaTheme.neonPink,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: NotitiaTheme.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      color: NotitiaTheme.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right, color: NotitiaTheme.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
