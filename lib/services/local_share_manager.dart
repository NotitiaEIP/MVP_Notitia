// =============================================================================
// NOTITIA — LocalShareManager (Orchestrateur Tap-to-Share NFC uniquement)
// =============================================================================
// Gère le flux complet du partage par NFC tag :
//
// ÉMETTEUR :
//   1. Sérialise la transcription au format .notitia (compress)
//   2. Écrit les bytes sur un tag NFC
//   3. Confirmation
//
// RÉCEPTEUR :
//   1. Lit les données depuis un tag NFC
//   2. Décompresse et importe la transcription
//   3. Sauvegarde automatique
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/transcription.dart';
import 'mistral_service.dart';
import 'nfc_share_service.dart';
import 'notitia_file_service.dart';
import 'storage_service.dart';

// =============================================================================
// SHARE SESSION — État complet d'une session de partage
// =============================================================================

class ShareSession {
  final ShareMode mode;
  final DateTime startedAt;
  NfcShareState state;
  String? errorMessage;
  Transcription? receivedTranscription;

  ShareSession({required this.mode})
    : startedAt = DateTime.now(),
      state = NfcShareState.idle;

  bool get isActive =>
      state == NfcShareState.writing || state == NfcShareState.reading;

  Duration get elapsed => DateTime.now().difference(startedAt);
}

enum ShareMode { sender, receiver }

// =============================================================================
// LOCAL SHARE MANAGER — Orchestrateur principal
// =============================================================================

class LocalShareManager extends ChangeNotifier {
  ShareSession? _session;
  ShareSession? get session => _session;

  bool _disposed = false;

  // Subscriptions aux streams du NfcShareService
  StreamSubscription<NfcShareState>? _stateSub;
  StreamSubscription<NfcShareResult>? _resultSub;

  // Callback d'import automatique (récepteur)
  void Function(Transcription transcription)? onTranscriptionReceived;

  // ---------------------------------------------------------------------------
  // INITIALISATION
  // ---------------------------------------------------------------------------

  LocalShareManager() {
    NfcShareService.init();
    _listenToStreams();
  }

  void _listenToStreams() {
    _stateSub = NfcShareService.stateStream.listen(_onStateChanged);
    _resultSub = NfcShareService.resultStream.listen(_onResult);
  }

  // ---------------------------------------------------------------------------
  // NFC AVAILABILITY CHECK
  // ---------------------------------------------------------------------------

  /// Vérifie si le NFC est disponible.
  Future<bool> isNfcAvailable() => NfcShareService.isNfcAvailable();

  // ---------------------------------------------------------------------------
  // MODE ÉMETTEUR — Écrire une transcription sur un tag NFC
  // ---------------------------------------------------------------------------

  /// Démarre le partage d'une transcription en mode émetteur.
  /// Sérialise, compresse et écrit les données sur un tag NFC.
  Future<bool> startSending(Transcription transcription) async {
    if (_session != null && _session!.isActive) {
      debugPrint('[LocalShareManager] Session already active');
      return false;
    }

    try {
      // 1. Créer le fichier .notitia en mémoire
      final notitiaFile = NotitiaFileService.createFromTranscription(
        transcription,
      );
      final bytes = NotitiaFileService.exportToBytes(notitiaFile);

      // 2. Créer la session
      _session = ShareSession(mode: ShareMode.sender);
      _session!.state = NfcShareState.writing;
      _safeNotify();

      // 3. Écrire sur le tag NFC
      final started = await NfcShareService.writeToTag(bytes);

      if (!started) {
        _session!.state = NfcShareState.failed;
        _session!.errorMessage = 'Impossible de démarrer l\'écriture NFC.';
        _safeNotify();
        return false;
      }

      debugPrint(
        '[LocalShareManager] Sender ready — ${bytes.length} bytes to write on NFC tag',
      );
      return true;
    } catch (e) {
      debugPrint('[LocalShareManager] Start sending error: $e');
      _session?.state = NfcShareState.failed;
      _session?.errorMessage = e.toString();
      _safeNotify();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // MODE RÉCEPTEUR — Lire une transcription depuis un tag NFC
  // ---------------------------------------------------------------------------

  /// Démarre le mode récepteur : lecture NFC tag.
  Future<bool> startReceiving() async {
    if (_session != null && _session!.isActive) {
      debugPrint('[LocalShareManager] Session already active');
      return false;
    }

    try {
      _session = ShareSession(mode: ShareMode.receiver);
      _session!.state = NfcShareState.reading;
      _safeNotify();

      final started = await NfcShareService.readFromTag();

      if (!started) {
        _session!.state = NfcShareState.failed;
        _session!.errorMessage = 'Impossible de démarrer la lecture NFC.';
        _safeNotify();
        return false;
      }

      debugPrint('[LocalShareManager] Receiver scanning NFC tag...');
      return true;
    } catch (e) {
      debugPrint('[LocalShareManager] Start receiving error: $e');
      _session?.state = NfcShareState.failed;
      _session?.errorMessage = e.toString();
      _safeNotify();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // ANNULATION
  // ---------------------------------------------------------------------------

  /// Annule la session en cours et nettoie les ressources.
  Future<void> cancelSession() async {
    await NfcShareService.stopSession();
    _session?.state = NfcShareState.idle;
    _session = null;
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // SAFE NOTIFY — empêche le crash "used after disposed"
  // ---------------------------------------------------------------------------

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // CALLBACKS INTERNES
  // ---------------------------------------------------------------------------

  void _onStateChanged(NfcShareState state) {
    if (_session == null) return;
    _session!.state = state;
    _safeNotify();
    debugPrint('[LocalShareManager] State: ${state.name}');
  }

  void _onResult(NfcShareResult result) async {
    if (_session == null) return;

    if (result.success) {
      _session!.state = NfcShareState.completed;

      // Mode récepteur : importer les données lues
      if (_session!.mode == ShareMode.receiver && result.data != null) {
        await _handleReceivedData(result.data!);
      }
    } else {
      _session!.state = NfcShareState.failed;
      _session!.errorMessage = result.errorMessage;
    }

    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // IMPORT AUTOMATIQUE (récepteur)
  // ---------------------------------------------------------------------------

  /// Décode et importe les données reçues via NFC.
  Future<void> _handleReceivedData(Uint8List data) async {
    try {
      // Importer directement depuis les bytes
      final importResult = NotitiaFileService.importFromBytes(data);

      if (importResult.success && importResult.transcription != null) {
        final now = DateTime.now();

        // Sauvegarder automatiquement avec un nouvel ID
        final imported = Transcription(
          id: now.millisecondsSinceEpoch.toString(),
          title:
              'NFC ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          content: importResult.transcription!.content,
          tag: TranscriptionTag.nfc,
          createdAt: importResult.transcription!.createdAt,
          updatedAt: now,
        );
        await StorageService.save(imported);

        // Générer un titre IA en arrière-plan
        unawaited(MistralService.updateTitleInBackground(imported));

        debugPrint('[LocalShareManager] NFC import: ${imported.title}');

        // Stocker la transcription dans la session pour le bouton "VOIR"
        _session?.receivedTranscription = imported;

        // Notifier l'UI
        onTranscriptionReceived?.call(imported);
      } else {
        _session!.errorMessage = importResult.message;
        _session!.state = NfcShareState.failed;
        _safeNotify();
      }
    } catch (e) {
      debugPrint('[LocalShareManager] Handle received data error: $e');
      _session!.errorMessage = 'Erreur de décodage NFC : ${e.toString()}';
      _session!.state = NfcShareState.failed;
      _safeNotify();
    }
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _resultSub?.cancel();
    NfcShareService.stopSession();
    _session = null;
    super.dispose();
  }
}
