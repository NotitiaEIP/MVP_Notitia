# 🎨 Assets et Configuration Visuelle - Notitia

## 📁 Structure des Assets

```
assets/
└── notitia_logo.png          # Logo principal de l'application
                               # Dimensions: 512x512px (recommandé)
                               # Format: PNG avec transparence
```

---

## 🖼️ Logo de l'Application

### Fichier Source
- **Chemin**: `assets/notitia_logo.png`
- **Utilisation**: 
  - Splash screen (écran de chargement)
  - Icône de l'application (iOS, Android, Web, Desktop)
  - Écran d'accueil (page principale)

### Dimensions Recommandées
- **Carré**: 512x512 pixels minimum
- **Rapport**: 1:1
- **Format**: PNG avec transparence

---

## 🔄 Génération des Icônes

### Configuration (pubspec.yaml)
```yaml
flutter_launcher_icons:
  image_path: "assets/notitia_logo.png"
  android:
    notification_icon: "ic_notification"
    generate: true
  ios:
    generate: true
  windows:
    generate: true
  macos:
    generate: true
  linux:
    generate: true
  web:
    generate: true
```

### Commande de Génération
```bash
dart run flutter_launcher_icons
```

### Fichiers Générés

#### Android
```
android/app/src/main/res/
├── mipmap-hdpi/ic_launcher.png
├── mipmap-mdpi/ic_launcher.png
├── mipmap-xhdpi/ic_launcher.png
├── mipmap-xxhdpi/ic_launcher.png
└── mipmap-xxxhdpi/ic_launcher.png
```

#### iOS
```
ios/Runner/Assets.xcassets/AppIcon.appiconset/
├── Icon-App-20x20@1x.png
├── Icon-App-20x20@2x.png
├── Icon-App-20x20@3x.png
├── Icon-App-60x60@2x.png
├── Icon-App-60x60@3x.png
├── Icon-App-76x76@1x.png
├── Icon-App-76x76@2x.png
├── Icon-App-83.5x83.5@2x.png
├── Icon-App-1024x1024@1x.png
└── Contents.json
```

#### Web
```
web/
├── favicon.png
├── icons/
│   ├── Icon-192.png
│   ├── Icon-512.png
│   └── Icon-maskable-192.png
└── manifest.json (auto-updated)
```

#### Windows/macOS/Linux
- Icônes natives générées automatiquement

---

## 🌊 Splash Screen

### Configuration (pubspec.yaml)
```yaml
flutter_native_splash:
  color: "#001a33"              # Couleur de fond (bleu foncé)
  image: assets/notitia_logo.png # Image centrée
  color_dark: "#001a33"          # Mode sombre
  image_dark: assets/notitia_logo.png
  android_12:
    image: assets/notitia_logo.png
  ios: true
  web: false
```

### Commande de Génération
```bash
dart run flutter_native_splash:create
```

### Fichiers Générés

#### Android
```
android/app/src/main/res/
├── values/
│   └── colors.xml (splash_color added)
├── values-night/
│   └── colors.xml
└── drawable/
    └── launch_background.xml
```

#### iOS
```
ios/Runner/
├── Assets.xcassets/LaunchImage.imageset/
└── LaunchScreen.storyboard (updated)
```

---

## 📱 Affichage du Logo en App

### Splash Screen (Automatique au démarrage)
Le fichier [lib/pages/splash_screen.dart](lib/pages/splash_screen.dart) gère l'affichage du splash :
- **Durée**: 2.5 secondes
- **Animation**: Fade + Scale
- **Logo**: 200x200 pixels

```dart
Image.asset(
  'assets/notitia_logo.png',
  width: 200,
  height: 200,
  fit: BoxFit.contain,
)
```

### Écran d'Accueil (Page Capture)
Vous pouvez ajouter le logo en haut de la page d'accueil :

```dart
Image.asset(
  'assets/notitia_logo.png',
  width: 80,
  height: 80,
)
```

---

## ✅ Checklist pour les Collaborateurs

- [ ] `assets/notitia_logo.png` existe
- [ ] `flutter pub get` exécuté
- [ ] `dart run flutter_launcher_icons` exécuté
- [ ] `dart run flutter_native_splash:create` exécuté
- [ ] Fichiers générés visibles dans les dossiers natifs
- [ ] `flutter run` fonctionne et affiche le splash screen

---

## 🎨 Modification du Logo

Si vous devez changer le logo:

1. **Remplacez** `assets/notitia_logo.png` par votre nouvelle image
2. **Générez** les nouvelles icônes:
   ```bash
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```
3. **Testez** avec `flutter run`

---

## 🌈 Personnalisation Avancée

### Couleurs du Splash Screen
Modifiez `pubspec.yaml`:
```yaml
flutter_native_splash:
  color: "#001a33"        # Votre couleur
  color_dark: "#001a33"   # Mode sombre
```

### Animations du Splash
Modifiez [lib/pages/splash_screen.dart](lib/pages/splash_screen.dart):
```dart
_animationController = AnimationController(
  duration: const Duration(milliseconds: 1500),  // Durée
  vsync: this,
);
```

### Délai avant Navigation
Modifiez dans `splash_screen.dart`:
```dart
Future.delayed(const Duration(milliseconds: 2500), () {  // 2.5 sec
  // Navigation
});
```

---

## 📚 Ressources

- [Flutter Launcher Icons](https://pub.dev/packages/flutter_launcher_icons)
- [Flutter Native Splash](https://pub.dev/packages/flutter_native_splash)
- [Asset Management](https://flutter.dev/docs/development/ui/assets-and-images)

---

**Dernière mise à jour**: Février 2026
