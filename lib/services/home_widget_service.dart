// =============================================================================
// NOTITIA — Home Widget Service (v3 — entièrement natif côté widget)
//
// Le widget Android lance un Foreground Service Kotlin natif sans ouvrir
// l'app Flutter.  Ce fichier Flutter n'a donc plus qu'un rôle passif :
//   • Initialiser home_widget (App Group iOS + widget update)
//   • Vérifier au resume s'il y a une transcription en attente
//     sauvegardée par le service natif
//
// L'enregistrement, le streaming Deepgram, le timer widget et l'arrêt
// sont TOUS gérés en natif (NotitiaRecordingService.kt).
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_recording_service.dart';

/// Nom du groupe d'app iOS — doit correspondre à l'App Group dans Xcode.
const String _iOSAppGroupId = 'group.com.example.notitia';

class HomeWidgetService {
  HomeWidgetService._();

  /// Initialise le service home widget (appelé une seule fois dans main).
  static Future<void> initialize() async {
    // Configurer le groupe d'app (nécessaire pour iOS WidgetKit).
    await HomeWidget.setAppGroupId(_iOSAppGroupId);

    // Vérifier immédiatement s'il y a une transcription en attente
    // (l'utilisateur a peut-être enregistré depuis le widget pendant que
    // l'app était tuée, puis l'a rouverte).
    await checkPendingTranscription();
  }

  /// Vérifie et traite les transcriptions en attente enregistrées par le
  /// service natif. Retourne `true` si une transcription a été traitée.
  static Future<bool> checkPendingTranscription() async {
    try {
      return await WidgetRecordingService.instance.processPendingTranscription();
    } catch (e) {
      debugPrint('[HomeWidget] Erreur vérification pending transcription: $e');
      return false;
    }
  }
}
