# Chargé automatiquement par le plugin Gradle de Flutter pour les builds release.

# shared_preferences_android >= 2.5.0 (Pigeon JNI) : Dart appelle ces classes Kotlin
# par leur nom via JNI. R8 ne voit pas l'appel et les supprime ou les renomme, d'où
# un NoSuchMethodError au démarrage (app bloquée sur l'écran d'accueil).
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Classes Kotlin que le package Dart `jni` cherche par leur nom pour appeler des
# fonctions suspend (voir les chaînes 'kotlin/...' dans jni/lib). Le package ne
# fournit de règles que pour ses propres classes (com.github.dart_lang.jni.**).
-keep interface kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
