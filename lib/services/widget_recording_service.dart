// =============================================================================
// NOTITIA — Widget Recording Service (Flutter side)
//
// Ce service ne fait PAS l'enregistrement lui-même — c'est le Foreground
// Service natif Android (NotitiaRecordingService.kt) qui s'en charge et
// dépose un fichier WAV par enregistrement (pending_audio_paths).
//
// Ce service Flutter :
//   1. Transcrit les enregistrements en attente (Whisper via la passerelle)
//   2. Applique la correction IA
//   3. Sauvegarde via StorageService
//   4. Indexe dans le RAG
//   5. Nettoie les données en attente (ou les garde si la passerelle est
//      injoignable, pour réessayer à la prochaine ouverture)
//
// Appelé automatiquement quand l'app Flutter est ouverte/reprise.
// =============================================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/transcription.dart';
import 'correction_service.dart';
import 'language_service.dart';
import 'open_stt_service.dart';
import 'rag_service.dart';
import 'storage_service.dart';

class WidgetRecordingService {
  WidgetRecordingService._();
  static final WidgetRecordingService instance = WidgetRecordingService._();

  /// Callback optionnel pour notifier l'UI qu'une nouvelle transcription
  /// widget a été sauvegardée (pour rafraîchir l'historique).
  VoidCallback? onNewTranscriptionSaved;

  /// Évite de traiter deux fois les mêmes fichiers (ouverture + reprise).
  bool _processing = false;

  /// Traite tout ce que le widget a laissé en attente.
  ///
  /// Retourne `true` si au moins une transcription a été sauvegardée.
  Future<bool> processPendingTranscription() async {
    if (_processing) return false;
    _processing = true;
    try {
      final fromAudio = await _processPendingAudio();
      final fromText = await _processPendingText();
      return fromAudio || fromText;
    } catch (e) {
      debugPrint(
        '[WidgetRecording] Erreur traitement des enregistrements en attente: $e',
      );
      return false;
    } finally {
      _processing = false;
    }
  }

  /// Enregistrements audio du widget : transcrits ici, puis supprimés.
  Future<bool> _processPendingAudio() async {
    final raw = await HomeWidget.getWidgetData<String>('pending_audio_paths');
    final paths = _splitPaths(raw);
    if (paths.isEmpty) return false;

    debugPrint(
      '[WidgetRecording] ${paths.length} enregistrement(s) en attente',
    );
    final language = LanguageService().currentLanguage;
    final remaining = <String>[];
    var saved = false;

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final wav = await file.readAsBytes();
        // En-tête WAV de 44 octets écrit par le service natif
        final pcm = wav.length > 44
            ? Uint8List.sublistView(wav, 44)
            : Uint8List(0);
        final text = await OpenSttService.transcribeRecording(
          pcm,
          language: language,
        );
        if (text.isNotEmpty) {
          await _saveWidgetTranscription(text, _recordedAt(path));
          saved = true;
        }
        await file.delete();
      } catch (e) {
        debugPrint('[WidgetRecording] Transcription reportée ($path): $e');
        remaining.add(path);
      }
    }

    // Le widget a pu ajouter un enregistrement pendant le traitement
    final latest = _splitPaths(
      await HomeWidget.getWidgetData<String>('pending_audio_paths'),
    );
    remaining.addAll(latest.where((p) => !paths.contains(p)));
    await HomeWidget.saveWidgetData<String?>(
      'pending_audio_paths',
      remaining.isEmpty ? null : remaining.join('\n'),
    );
    return saved;
  }

  /// Ancien format : texte déjà transcrit par une version précédente du widget.
  Future<bool> _processPendingText() async {
    final pending = await HomeWidget.getWidgetData<String>(
      'pending_transcription',
    );
    if (pending == null || pending.trim().isEmpty) return false;

    final dateStr = await HomeWidget.getWidgetData<String>(
      'pending_transcription_date',
    );
    debugPrint(
      '[WidgetRecording] Transcript en attente détecté (${pending.length} chars)',
    );
    await _saveWidgetTranscription(
      pending.trim(),
      dateStr != null ? DateTime.tryParse(dateStr) : null,
    );

    await HomeWidget.saveWidgetData<String?>('pending_transcription', null);
    await HomeWidget.saveWidgetData<String?>(
      'pending_transcription_date',
      null,
    );
    return true;
  }

  Future<void> _saveWidgetTranscription(String text, DateTime? date) async {
    // Correction IA
    String finalText = text;
    if (finalText.length > 10) {
      try {
        debugPrint('[WidgetRecording] Correction IA en cours...');
        final corrected = await CorrectionService.instance.correctTranscription(
          finalText,
        );
        if (corrected.isNotEmpty) {
          finalText = corrected;
          debugPrint('[WidgetRecording] Correction IA appliquée');
        }
      } catch (e) {
        debugPrint(
          '[WidgetRecording] Erreur correction (sauvegarde brute): $e',
        );
      }
    }

    // Créer la transcription avec titre temporaire
    final now = date ?? DateTime.now();
    final title =
        'Widget ${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final transcription = Transcription.create(
      content: finalText,
      title: title,
      tag: TranscriptionTag.widget,
    );

    // Sauvegarder
    await StorageService.save(transcription);

    // Générer un titre IA en arrière-plan
    unawaited(CorrectionService.updateTitleInBackground(transcription));

    // Indexation RAG
    RAGService.instance.indexSingleTranscription(transcription);

    debugPrint(
      '[WidgetRecording] ✅ Transcription widget sauvegardée: "$title"',
    );

    // Notifier l'UI
    onNewTranscriptionSaved?.call();
  }

  static List<String> _splitPaths(String? raw) => (raw ?? '')
      .split('\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// Date d'enregistrement, lue dans le nom du fichier (`widget_<millis>.wav`).
  static DateTime? _recordedAt(String path) {
    final millis = RegExp(r'widget_(\d+)\.wav$').firstMatch(path)?.group(1);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.parse(millis));
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
