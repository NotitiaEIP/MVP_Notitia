// =============================================================================
// NOTITIA — LocalShareManager (Orchestrateur Tap-to-Share)
// =============================================================================
// Gère le flux complet du partage par NFC + Nearby Connections :
//
// ÉMETTEUR :
//   1. Prépare le fichier .notitia (compress + optionnel encrypt)
//   2. Calcule le checksum SHA-256 du fichier
//   3. Génère un sessionId unique
//   4. Active le mode Nearby advertising
//   5. Envoie le fichier via P2P (BLE/WiFi Direct)
//   6. Confirmation + nettoyage
//
// RÉCEPTEUR :
//   1. Active le mode NFC discovery + Nearby discovery
//   2. Attend le tap → reçoit les métadonnées (sessionId, checksum, fileSize)
//   3. Se connecte au P2P du sender
//   4. Reçoit le fichier
//   5. Valide la taille
//   6. Importe automatiquement dans l'app
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/transcription.dart';
import 'nfc_share_service.dart';
import 'notitia_file_service.dart';
import 'storage_service.dart';

// =============================================================================
// SHARE SESSION — État complet d'une session de partage
// =============================================================================

class ShareSession {
  final String sessionId;
  final ShareMode mode;
  final DateTime startedAt;
  NfcShareState state;
  NfcHandshakeData? handshake;
  TransferProgress? progress;
  String? filePath;
  String? errorMessage;
  Transcription? receivedTranscription;

  ShareSession({
    required this.sessionId,
    required this.mode,
  })  : startedAt = DateTime.now(),
        state = NfcShareState.idle;

  bool get isActive =>
      state == NfcShareState.advertising ||
      state == NfcShareState.discovering ||
      state == NfcShareState.connecting ||
      state == NfcShareState.transferring;

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
  StreamSubscription<TransferProgress>? _progressSub;
  StreamSubscription<NfcHandshakeData>? _handshakeSub;
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
    _progressSub = NfcShareService.progressStream.listen(_onProgress);
    _handshakeSub = NfcShareService.handshakeStream.listen(_onHandshake);
    _resultSub = NfcShareService.resultStream.listen(_onResult);
  }

  // ---------------------------------------------------------------------------
  // NFC AVAILABILITY CHECK
  // ---------------------------------------------------------------------------

  /// Vérifie si le NFC est disponible.
  Future<bool> isNfcAvailable() => NfcShareService.isNfcAvailable();

  // ---------------------------------------------------------------------------
  // MODE ÉMETTEUR — Envoyer une transcription
  // ---------------------------------------------------------------------------

  /// Démarre le partage d'une transcription en mode émetteur.
  Future<bool> startSending(Transcription transcription,
      {String? password}) async {
    if (_session != null && _session!.isActive) {
      debugPrint('[LocalShareManager] Session already active');
      return false;
    }

    try {
      // 1. Créer le fichier .notitia
      final notitiaFile =
          NotitiaFileService.createFromTranscription(transcription);
      final filePath = await NotitiaFileService.exportToFile(
        notitiaFile,
        password: password,
      );

      // 2. Lire le fichier et calculer le checksum SHA-256 des bytes bruts
      final fileBytes = await File(filePath).readAsBytes();
      final checksum = NotitiaFileService.sha256Bytes(Uint8List.fromList(fileBytes));

      // 3. Générer un session ID unique
      final sessionId = _generateSessionId();

      // 4. Créer la session
      _session = ShareSession(
        sessionId: sessionId,
        mode: ShareMode.sender,
      );
      _session!.filePath = filePath;
      _session!.state = NfcShareState.advertising;
      _safeNotify();

      // 5. Démarrer le Nearby advertising
      final started = await NfcShareService.startAdvertising(
        filePath: filePath,
        sessionId: sessionId,
        fileSize: fileBytes.length,
        checksum: checksum,
      );

      if (!started) {
        _session!.state = NfcShareState.failed;
        _session!.errorMessage = 'Impossible de démarrer le partage.';
        _safeNotify();
        return false;
      }

      debugPrint(
          '[LocalShareManager] Sender ready — session=$sessionId, file=${fileBytes.length} bytes');
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
  // MODE RÉCEPTEUR — Recevoir une transcription
  // ---------------------------------------------------------------------------

  /// Démarre le mode récepteur : scan NFC + Nearby discovery.
  Future<bool> startReceiving() async {
    if (_session != null && _session!.isActive) {
      debugPrint('[LocalShareManager] Session already active');
      return false;
    }

    try {
      _session = ShareSession(
        sessionId: '', // Sera rempli après le handshake
        mode: ShareMode.receiver,
      );
      _session!.state = NfcShareState.discovering;
      _safeNotify();

      final started = await NfcShareService.startDiscovery();

      if (!started) {
        _session!.state = NfcShareState.failed;
        _session!.errorMessage = 'Impossible de démarrer le scan.';
        _safeNotify();
        return false;
      }

      debugPrint('[LocalShareManager] Receiver scanning for NFC...');
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

    // Nettoyage du fichier temporaire si émetteur
    if (_session?.mode == ShareMode.sender && _session?.filePath != null) {
      NotitiaFileService.cleanupFile(_session!.filePath!);
    }

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

  void _onProgress(TransferProgress progress) {
    if (_session == null) return;
    _session!.progress = progress;
    _safeNotify();
  }

  void _onHandshake(NfcHandshakeData handshake) {
    if (_session == null) return;
    _session!.handshake = handshake;
    _safeNotify();
    debugPrint(
        '[LocalShareManager] Handshake: device=${handshake.deviceName}, size=${handshake.fileSize}');
  }

  void _onResult(NfcShareResult result) async {
    if (_session == null) return;

    if (result.success) {
      _session!.state = NfcShareState.completed;

      // Mode récepteur : valider et importer
      if (_session!.mode == ShareMode.receiver && result.filePath != null) {
        await _handleReceivedFile(result.filePath!);
      }
    } else {
      _session!.state = NfcShareState.failed;
      _session!.errorMessage = result.errorMessage;
    }

    _safeNotify();

    // Nettoyage automatique après un délai
    if (_session?.mode == ShareMode.sender && _session?.filePath != null) {
      Future.delayed(const Duration(seconds: 5), () {
        if (_session?.filePath != null) {
          NotitiaFileService.cleanupFile(_session!.filePath!);
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORT AUTOMATIQUE (récepteur)
  // ---------------------------------------------------------------------------

  /// Valide la taille et importe le fichier reçu.
  Future<void> _handleReceivedFile(String filePath) async {
    try {
      // 1. Lire le fichier reçu
      final fileBytes = await File(filePath).readAsBytes();

      // 2. Valider la taille si le handshake existe
      if (_session?.handshake != null) {
        final expectedSize = _session!.handshake!.fileSize;
        if (expectedSize > 0 && fileBytes.length != expectedSize) {
          _session!.errorMessage =
              'Taille du fichier incorrecte (${fileBytes.length} vs $expectedSize attendus). '
              'Le transfert a peut-être été interrompu.';
          _session!.state = NfcShareState.failed;
          _safeNotify();
          return;
        }
      }

      // 3. Importer via le NotitiaFileService
      final importResult = await NotitiaFileService.importFile(filePath);

      if (importResult.success && importResult.transcription != null) {
        final now = DateTime.now();

        // Sauvegarder automatiquement avec un nouvel ID
        final imported = Transcription(
          id: now.millisecondsSinceEpoch.toString(),
          title: 'Importation — ${importResult.transcription!.title}',
          content: importResult.transcription!.content,
          createdAt: importResult.transcription!.createdAt,
          updatedAt: now,
        );
        await StorageService.save(imported);

        debugPrint('[LocalShareManager] File imported: ${imported.title}');

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
      debugPrint('[LocalShareManager] Handle received file error: $e');
      _session!.errorMessage = 'Erreur de validation : ${e.toString()}';
      _session!.state = NfcShareState.failed;
      _safeNotify();
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITAIRES
  // ---------------------------------------------------------------------------

  /// Génère un ID de session unique (16 caractères hex).
  String _generateSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _progressSub?.cancel();
    _handshakeSub?.cancel();
    _resultSub?.cancel();
    // Fire-and-forget : nettoyage natif sans notifier les listeners
    NfcShareService.stopSession();
    if (_session?.mode == ShareMode.sender && _session?.filePath != null) {
      NotitiaFileService.cleanupFile(_session!.filePath!);
    }
    _session = null;
    super.dispose();
  }
}
