import 'package:flutter/material.dart' show ChangeNotifier;

/// Modèle pour gérer les préférences utilisateur (langue, thème, etc.)
class UserPreferences with ChangeNotifier {
  String _language = 'en'; // 'en' ou 'fr'
  
  UserPreferences(String initialLanguage) {
    _language = initialLanguage;
  }
  
  /// Obtenir la langue actuelle
  String get language => _language;
  
  /// Changer la langue
  void setLanguage(String newLanguage) {
    if (_language != newLanguage) {
      _language = newLanguage;
      notifyListeners();
    }
  }
  
  /// Vérifier si la langue est le français
  bool get isFrench => _language == 'fr';
  
  /// Obtenir la langue sous forme de Locale pour Flutter
  String getLanguageLabel() {
    return _language == 'fr' ? 'Français' : 'English';
  }
}
