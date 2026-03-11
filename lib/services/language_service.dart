import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _languageKey = 'app_language';
  static const String _defaultLanguage = 'fr';
  
  static final LanguageService _instance = LanguageService._internal();
  
  LanguageService._internal();
  
  factory LanguageService() {
    return _instance;
  }
  
  late Map<String, dynamic> _translations;
  late String _currentLanguage;
  
  /// Initialiser le service de langue
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_languageKey) ?? _defaultLanguage;
    await _loadTranslations();
  }
  
  /// Charger les traductions depuis le fichier JSON
  Future<void> _loadTranslations() async {
    try {
      final jsonString = await rootBundle.loadString('lib/l10n/$_currentLanguage.json');
      _translations = json.decode(jsonString);
    } catch (e) {
      print('Erreur lors du chargement des traductions: $e');
      // Charger l'anglais par défaut en cas d'erreur
      final jsonString = await rootBundle.loadString('lib/l10n/en.json');
      _translations = json.decode(jsonString);
    }
  }
  
  /// Obtenir la langue actuelle
  String get currentLanguage => _currentLanguage;
  
  /// Changer la langue
  Future<void> changeLanguage(String languageCode) async {
    if (languageCode == _currentLanguage) return;
    
    _currentLanguage = languageCode;
    
    // Sauvegarder la préférence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    
    // Recharger les traductions
    await _loadTranslations();
  }
  
  /// Obtenir une traduction
  String translate(String key) {
    return _translations[key] ?? key;
  }
  
  /// Obtenir une traduction avec valeur par défaut
  String get(String key, {String defaultValue = ''}) {
    return _translations[key] ?? defaultValue ?? key;
  }
  
  /// Vérifier si la langue est le français
  bool get isFrench => _currentLanguage == 'fr';
  
  /// Obtenir la liste des langues disponibles
  List<String> get availableLanguages => ['en', 'fr'];
  
  /// Obtenir le label de la langue
  String getLanguageLabel(String languageCode) {
    if (languageCode == 'fr') {
      return translate('french');
    } else if (languageCode == 'en') {
      return translate('english');
    }
    return languageCode;
  }
}
