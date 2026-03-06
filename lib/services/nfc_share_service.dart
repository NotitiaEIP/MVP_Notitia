// =============================================================================
// NOTITIA — NfcShareService (Platform Channel Bridge — NFC uniquement)
// =============================================================================
// Bridge Flutter ↔ natif pour le partage par NFC tag.
// Canal : "com.notitia/nfc_share"
//
// Méthodes sortantes (Flutter → natif) :
//   - isNfcAvailable() → bool
//   - writeToTag(data base64) → bool
//   - readFromTag() → bool
//   - stopSession() → void
//
// Callbacks entrants (natif → Flutter) :
//   - onStateChanged(String state)
//   - onWriteComplete()
//   - onDataRead(String base64Data)
//   - onError(String message)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// =============================================================================
// ENUMS & MODÈLES
// =============================================================================

enum NfcShareState {
  idle,
  writing,
  reading,
  completed,
  failed,
}

class NfcShareResult {
  final bool success;
  final Uint8List? data;
  final String? errorMessage;

  const NfcShareResult({
    required this.success,
    this.data,
    this.errorMessage,
  });
}

// =============================================================================
// SERVICE
// =============================================================================

class NfcShareService {
  static const MethodChannel _channel = MethodChannel('com.notitia/nfc_share');

  // Streams
  static final StreamController<NfcShareState> _stateController =
      StreamController<NfcShareState>.broadcast();
  static final StreamController<NfcShareResult> _resultController =
      StreamController<NfcShareResult>.broadcast();

  static Stream<NfcShareState> get stateStream => _stateController.stream;
  static Stream<NfcShareResult> get resultStream => _resultController.stream;

  // ---------------------------------------------------------------------------
  // INIT — Enregistrer les callbacks natifs → Flutter
  // ---------------------------------------------------------------------------

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onStateChanged':
          final name = call.arguments as String;
          final state = NfcShareState.values
              .firstWhere((e) => e.name == name, orElse: () => NfcShareState.idle);
          _stateController.add(state);
          break;

        case 'onWriteComplete':
          _stateController.add(NfcShareState.completed);
          _resultController.add(const NfcShareResult(success: true));
          break;

        case 'onDataRead':
          final base64Data = call.arguments as String;
          final bytes = base64Decode(base64Data);
          _stateController.add(NfcShareState.completed);
          _resultController.add(NfcShareResult(
            success: true,
            data: Uint8List.fromList(bytes),
          ));
          break;

        case 'onError':
          final msg = call.arguments as String? ?? 'Erreur NFC inconnue';
          _stateController.add(NfcShareState.failed);
          _resultController.add(NfcShareResult(
            success: false,
            errorMessage: msg,
          ));
          break;
      }
    });

    debugPrint('[NfcShareService] Initialized (NFC-only)');
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES
  // ---------------------------------------------------------------------------

  /// Vérifie si le NFC est disponible et activé.
  static Future<bool> isNfcAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isNfcAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] isNfcAvailable error: $e');
      return false;
    }
  }

  /// Écrit des données binaires sur un tag NFC.
  /// [data] est envoyé en base64 au plugin natif.
  static Future<bool> writeToTag(Uint8List data) async {
    try {
      final base64Data = base64Encode(data);
      final result = await _channel.invokeMethod<bool>('writeToTag', {
        'data': base64Data,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] writeToTag error: $e');
      return false;
    }
  }

  /// Démarre la lecture d'un tag NFC.
  /// Les données lues seront retournées via le stream [resultStream].
  static Future<bool> readFromTag() async {
    try {
      final result = await _channel.invokeMethod<bool>('readFromTag');
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] readFromTag error: $e');
      return false;
    }
  }

  /// Arrête la session NFC en cours.
  static Future<void> stopSession() async {
    try {
      await _channel.invokeMethod<void>('stopSession');
    } catch (e) {
      debugPrint('[NfcShareService] stopSession error: $e');
    }
  }
}
