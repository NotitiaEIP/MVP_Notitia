#!/bin/bash
# =============================================================================
# NOTITIA - Setup Automatisé
# Script d'installation pour les collaborateurs
# =============================================================================

set -e  # Exit on error

echo "🚀 Notitia - Setup Automatisé"
echo "=============================="
echo ""

# Vérifier que Flutter est installé
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter n'est pas installé!"
    echo "Téléchargez-le depuis https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter détecté: $(flutter --version)"
echo ""

# Étape 1: Récupérer les dépendances
echo "📦 Récupération des dépendances..."
flutter pub get
echo "✅ Dépendances installées"
echo ""

# Étape 2: Générer les icônes
echo "🎨 Génération des icônes de l'application..."
if dart run flutter_launcher_icons; then
    echo "✅ Icônes générées avec succès"
else
    echo "⚠️  Erreur lors de la génération des icônes"
    echo "Vérifiez que assets/notitia_logo.png existe"
fi
echo ""

# Étape 3: Générer le splash screen
echo "🌊 Génération de l'écran de splash..."
if dart run flutter_native_splash:create; then
    echo "✅ Splash screen généré avec succès"
else
    echo "⚠️  Erreur lors de la génération du splash screen"
fi
echo ""

# Étape 4: Setup plateforme spécifique
echo "🔧 Configuration spécifique par plateforme..."

# Android
if [ -d "android" ]; then
    echo "  • Android: Nettoyage du cache..."
    cd android
    ./gradlew clean > /dev/null 2>&1 || echo "    ⚠️  Gradlew non disponible"
    cd ..
    echo "  ✅ Android configuré"
fi

# iOS
if [ -d "ios" ]; then
    if command -v pod &> /dev/null; then
        echo "  • iOS: Installation des pods..."
        cd ios
        pod install --repo-update > /dev/null 2>&1 || echo "    ⚠️  Erreur pods"
        cd ..
        echo "  ✅ iOS configuré"
    else
        echo "  ⚠️  CocoaPods non installé (macOS/iOS uniquement)"
    fi
fi

echo ""
echo "=============================="
echo "✨ Setup terminé avec succès!"
echo ""
echo "Prochaines étapes:"
echo "  1. flutter run              (Lancer l'app)"
echo "  2. flutter run -d android   (Android)"
echo "  3. flutter run -d ios       (iOS)"
echo "  4. flutter run -d chrome    (Web)"
echo ""
echo "Pour plus d'info: cat SETUP.md"
echo "=============================="
