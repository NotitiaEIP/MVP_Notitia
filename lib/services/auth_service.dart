// =============================================================================
// NOTITIA — Service d'authentification Supabase
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

/// Modèle représentant un profil utilisateur
class UserProfile {
  final String id;
  final String? email;
  final String? username;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserProfile({
    required this.id,
    this.email,
    this.username,
    this.avatarUrl,
    required this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

/// Service d'authentification Supabase
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _guestModeKey = 'notitia_guest_mode';
  static const String _skipAuthKey = 'notitia_skip_auth';

  SupabaseClient get _supabase => Supabase.instance.client;
  
  /// Stream d'état d'authentification
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  
  /// Utilisateur actuel
  User? get currentUser => _supabase.auth.currentUser;
  
  /// Session actuelle
  Session? get currentSession => _supabase.auth.currentSession;
  
  /// Est connecté
  bool get isAuthenticated => currentUser != null;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------
  
  /// Initialise Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    debugPrint('[AuthService] Supabase initialisé');
  }

  // ---------------------------------------------------------------------------
  // Gestion du mode invité
  // ---------------------------------------------------------------------------
  
  /// Vérifie si l'utilisateur a choisi d'utiliser l'app sans compte
  Future<bool> isGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestModeKey) ?? false;
  }

  /// Active le mode invité
  Future<void> setGuestMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestModeKey, value);
  }

  /// Vérifie si c'est la première ouverture
  Future<bool> shouldShowAuthChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final skipAuth = prefs.getBool(_skipAuthKey) ?? false;
    
    // Si l'utilisateur est connecté, pas besoin de montrer le choix
    if (isAuthenticated) return false;
    
    // Si l'utilisateur a choisi de sauter l'auth, ne pas montrer
    if (skipAuth) return false;
    
    return true;
  }

  /// Marque que l'utilisateur a vu l'écran d'auth
  Future<void> markAuthSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipAuthKey, true);
  }

  // ---------------------------------------------------------------------------
  // Authentification Email/Password
  // ---------------------------------------------------------------------------
  
  /// Inscription avec email et mot de passe
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? username,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: username != null ? {'username': username} : null,
      emailRedirectTo: kIsWeb ? null : 'notitia://callback',
    );

    // Important: si la confirmation email est activée côté Supabase,
    // `response.session` peut être null et l'utilisateur n'est pas connecté.
    // Dans ce cas, on NE DOIT PAS tenter d'écrire dans `profiles`.
    if (response.session != null && username != null) {
      await _upsertProfile(username: username);
    }

    return response;
  }

  Future<void> _upsertProfile({String? username}) async {
    final user = currentUser;
    if (user == null) return;

    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'id': user.id,
      'email': user.email,
      'updated_at': now,
    };
    if (username != null && username.trim().isNotEmpty) {
      payload['username'] = username.trim();
    }

    try {
      await _supabase.from('profiles').upsert(payload);
    } catch (e) {
      // Ne pas faire échouer l'inscription si la table/policy n'est pas prête.
      debugPrint('[AuthService] upsert profile failed: $e');
    }
  }

  /// Connexion avec email et mot de passe
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ---------------------------------------------------------------------------
  // Authentification OAuth (Google, GitHub)
  // ---------------------------------------------------------------------------
  
  /// Connexion avec Google
  Future<bool> signInWithGoogle() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'notitia://callback',
      scopes: 'email profile',
    );
  }

  /// Connexion avec GitHub
  Future<bool> signInWithGitHub() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: kIsWeb ? null : 'notitia://callback',
    );
  }

  // ---------------------------------------------------------------------------
  // Authentification par téléphone
  // ---------------------------------------------------------------------------
  
  /// Envoie un OTP par SMS
  Future<void> sendOTP({required String phone}) async {
    await _supabase.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: true,
    );
  }

  /// Vérifie l'OTP reçu par SMS
  Future<AuthResponse> verifyOTP({
    required String phone,
    required String token,
  }) async {
    return await _supabase.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  // ---------------------------------------------------------------------------
  // Magic Link (Email sans mot de passe)
  // ---------------------------------------------------------------------------
  
  /// Envoie un OTP par email (code à 6 chiffres selon votre template)
  Future<void> sendEmailOTP({
    required String email,
    required bool shouldCreateUser,
  }) async {
    await _supabase.auth.signInWithOtp(
      email: email,
      shouldCreateUser: shouldCreateUser,
      // Gardé pour compat (selon config Supabase / plateformes)
      emailRedirectTo: kIsWeb ? null : 'notitia://callback',
    );
  }

  /// Alias rétro-compatibilité (ancien bouton "lien magique")
  Future<void> sendMagicLink({required String email}) async {
    await sendEmailOTP(
      email: email,
      // Par défaut on laisse Supabase créer si nécessaire.
      // (Les écrans OTP dédiés utilisent un mode strict pour la connexion.)
      shouldCreateUser: true,
    );
  }

  /// Met à jour/initialise le profil applicatif (ex: username) après authentification.
  ///
  /// Utile après une inscription par OTP email (le compte est créé sans passer par signUp).
  Future<void> upsertProfile({String? username}) async {
    await _upsertProfile(username: username);
  }

  /// Vérifie un OTP reçu par email (si Supabase envoie un code)
  Future<AuthResponse> verifyEmailOTP({
    required String email,
    required String token,
    bool isSignup = false,
  }) async {
    return await _supabase.auth.verifyOTP(
      email: email,
      token: token,
      type: isSignup ? OtpType.signup : OtpType.email,
    );
  }

  /// Renvoie le code de confirmation d'email pour un compte non confirmé
  Future<void> resendSignupCode({required String email}) async {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  // ---------------------------------------------------------------------------
  // Gestion du profil
  // ---------------------------------------------------------------------------
  
  /// Récupère le profil de l'utilisateur connecté
  Future<UserProfile?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      return UserProfile.fromJson(response);
    } catch (e) {
      debugPrint('[AuthService] Erreur récupération profil: $e');
      return null;
    }
  }

  /// Met à jour le profil utilisateur
  Future<void> updateProfile({
    String? username,
    String? avatarUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (username != null) updates['username'] = username;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', user.id);
  }

  /// Upload une image de profil
  Future<String?> uploadAvatar(List<int> imageBytes, String fileName) async {
    final user = currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final filePath = '${user.id}/$fileName';
    
    await _supabase.storage
        .from('avatars')
        .uploadBinary(filePath, imageBytes as dynamic);
    
    final publicUrl = _supabase.storage
        .from('avatars')
        .getPublicUrl(filePath);
    
    // Met à jour le profil avec l'URL
    await updateProfile(avatarUrl: publicUrl);
    
    return publicUrl;
  }

  // ---------------------------------------------------------------------------
  // Déconnexion et réinitialisation
  // ---------------------------------------------------------------------------
  
  /// Déconnecte l'utilisateur
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    
    // Réinitialise les préférences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestModeKey);
    await prefs.remove(_skipAuthKey);
  }

  /// Réinitialise le mot de passe
  Future<void> resetPassword({required String email}) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : 'io.supabase.notitia://reset-callback/',
    );
  }
}
