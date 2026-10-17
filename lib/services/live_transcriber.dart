// =============================================================================
// NOTITIA — Interface commune des moteurs de transcription « micro → texte »
// (Whisper open source via la passerelle, ou Deepgram)
// =============================================================================

import '../config/ai_config.dart';
import 'deepgram_service.dart';
import 'open_stt_service.dart';

abstract class LiveTranscriber {
  /// Texte reçu : final (ajouté au transcript) ou partiel (affichage en cours).
  void Function(String text, bool isFinal)? onTranscript;
  void Function(String error)? onError;
  void Function()? onConnected;
  void Function()? onDisconnected;

  bool get isListening;
  String get fullTranscript;

  /// 0 si le moteur ne fournit pas de score de confiance.
  double get confidence;

  Future<bool> startListening();

  /// Arrête l'écoute ; une fois terminé, [fullTranscript] est complet.
  Future<void> stopListening();

  void reset();
  Future<void> dispose();

  /// Moteur par défaut, selon AI_STT_ENGINE ('notitia' ou 'deepgram').
  static LiveTranscriber createDefault({String language = 'fr'}) =>
      AiConfig.sttEngine == 'deepgram'
      ? DeepgramService(language: language)
      : OpenSttService(language: language);
}
