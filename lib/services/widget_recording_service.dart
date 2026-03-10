// =============================================================================
// NOTITIA — Widget Recording Service (Flutter side)
//
// Ce service ne fait PAS l'enregistrement lui-même — c'est le Foreground
// Service natif Android (NotitiaRecordingService.kt) qui s'en charge.
//
// Ce service Flutter :
//   1. Détecte les transcriptions en attente (sauvées par le service natif)
//   2. Applique la correction Mistral IA
//   3. Sauvegarde via StorageService
//   4. Indexe dans le RAG
//   5. Nettoie les données en attente
//
// Appelé automatiquement quand l'app Flutter est ouverte/reprise.
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/transcription.dart';
import 'mistral_service.dart';
import 'rag_service.dart';
import 'storage_service.dart';

class WidgetRecordingService {
  WidgetRecordingService._();
  static final WidgetRecordingService instance = WidgetRecordingService._();

  /// Callback optionnel pour notifier l'UI qu'une nouvelle transcription
  /// widget a été sauvegardée (pour rafraîchir l'historique).
  VoidCallback? onNewTranscriptionSaved;

  /// Vérifie s'il y a un transcript en attente (enregistré par le
  /// service natif via le widget) et le traite.
  ///
  /// Retourne `true` si une transcription a été traitée et sauvegardée.
  Future<bool> processPendingTranscription() async {
    try {
      // Lire le transcript en attente depuis SharedPreferences (home_widget)
      final pending = await HomeWidget.getWidgetData<String>('pending_transcription');

      if (pending == null || pending.trim().isEmpty) {
        return false;
      }

      final dateStr = await HomeWidget.getWidgetData<String>('pending_transcription_date');
      debugPrint('[WidgetRecording] Transcript en attente détecté (${pending.length} chars)');

      // Correction Mistral IA
      String finalText = pending.trim();
      if (finalText.length > 10) {
        try {
          debugPrint('[WidgetRecording] Correction Mistral en cours...');
          final corrected = await MistralService.instance.correctTranscription(finalText);
          if (corrected.isNotEmpty) {
            finalText = corrected;
            debugPrint('[WidgetRecording] Correction Mistral appliquée');
          }
        } catch (e) {
          debugPrint('[WidgetRecording] Erreur Mistral (sauvegarde brute): $e');
        }
      }

      // Créer la transcription avec titre automatique
      final now = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
      final title =
          'Widget ${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      final transcription = Transcription.create(
        content: finalText,
        title: title,
      );

      // Sauvegarder
      await StorageService.save(transcription);

      // Indexation RAG
      RAGService.instance.indexSingleTranscription(transcription);

      // Nettoyer les données en attente
      await HomeWidget.saveWidgetData<String?>('pending_transcription', null);
      await HomeWidget.saveWidgetData<String?>('pending_transcription_date', null);

      debugPrint('[WidgetRecording] ✅ Transcription widget sauvegardée: "$title"');

      // Notifier l'UI
      onNewTranscriptionSaved?.call();

      return true;
    } catch (e) {
      debugPrint('[WidgetRecording] Erreur traitement transcript en attente: $e');
      return false;
    }
  }

  /// Vérifie si un enregistrement est actuellement en cours
  /// (lu depuis SharedPreferences mises à jour par le service natif).
  Future<bool> isNativeRecording() async {
    try {
      final isRec = await HomeWidget.getWidgetData<bool>('is_recording');
      return isRec ?? false;
    } catch (e) {
      return false;
    }
  }
}
