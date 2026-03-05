// =============================================================================
// NOTITIA — NfcShareService (Platform Channel Bridge)
// =============================================================================
// Bridge Flutter ↔ natif pour le NFC handshake + P2P data transfer.
// Canal : "com.notitia/nfc_share"
//
// Méthodes sortantes (Flutter → natif) :
//   - isNfcAvailable() → bool
//   - startAdvertising(file_path, session_id, file_size, checksum) → bool
//   - startDiscovery() → bool
//   - stopSession() → void
//
// Callbacks entrants (natif → Flutter) :
//   - onStateChanged(String state)
//   - onHandshakeReceived(Map handshake)
//   - onTransferProgress(Map progress)
//   - onTransferComplete(Map result)
//   - onError(String message)
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// =============================================================================
// ENUMS & MODÈLES
// =============================================================================

enum NfcShareState {
  idle,
  advertising,
  discovering,
  connecting,
  transferring,
  completed,
  failed,
}

class NfcHandshakeData {
  final String sessionId;
  final String deviceName;
  final int fileSize;
  final String checksum;
  final String transportType;

  const NfcHandshakeData({
    required this.sessionId,
    required this.deviceName,
    required this.fileSize,
    required this.checksum,
    this.transportType = 'nearby',
  });
}

class TransferProgress {
  final int bytesTransferred;
  final int totalBytes;
  double get percentage =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;

  const TransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
  });
}

class NfcShareResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;

  const NfcShareResult({
    required this.success,
    this.filePath,
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
  static final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();
  static final StreamController<NfcHandshakeData> _handshakeController =
      StreamController<NfcHandshakeData>.broadcast();
  static final StreamController<NfcShareResult> _resultController =
      StreamController<NfcShareResult>.broadcast();

  static Stream<NfcShareState> get stateStream => _stateController.stream;
  static Stream<TransferProgress> get progressStream =>
      _progressController.stream;
  static Stream<NfcHandshakeData> get handshakeStream =>
      _handshakeController.stream;
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

        case 'onHandshakeReceived':
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _handshakeController.add(NfcHandshakeData(
            sessionId: map['session_id'] as String? ?? '',
            deviceName: map['device_name'] as String? ?? 'Unknown',
            fileSize: map['file_size'] as int? ?? 0,
            checksum: map['checksum'] as String? ?? '',
            transportType: map['transport_type'] as String? ?? 'nearby',
          ));
          break;

        case 'onTransferProgress':
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _progressController.add(TransferProgress(
            bytesTransferred: map['bytes_transferred'] as int? ?? 0,
            totalBytes: map['total_bytes'] as int? ?? 0,
          ));
          break;

        case 'onTransferComplete':
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _resultController.add(NfcShareResult(
            success: true,
            filePath: map['file_path'] as String?,
          ));
          break;

        case 'onError':
          final msg = call.arguments as String? ?? 'Erreur inconnue';
          _stateController.add(NfcShareState.failed);
          _resultController.add(NfcShareResult(
            success: false,
            errorMessage: msg,
          ));
          break;
      }
    });

    debugPrint('[NfcShareService] Initialized');
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES
  // ---------------------------------------------------------------------------

  static Future<bool> isNfcAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isNfcAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] isNfcAvailable error: $e');
      return false;
    }
  }

  static Future<bool> startAdvertising({
    required String filePath,
    required String sessionId,
    required int fileSize,
    required String checksum,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startAdvertising', {
        'file_path': filePath,
        'session_id': sessionId,
        'file_size': fileSize,
        'checksum': checksum,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] startAdvertising error: $e');
      return false;
    }
  }

  static Future<bool> startDiscovery() async {
    try {
      final result = await _channel.invokeMethod<bool>('startDiscovery');
      return result ?? false;
    } catch (e) {
      debugPrint('[NfcShareService] startDiscovery error: $e');
      return false;
    }
  }

  static Future<void> stopSession() async {
    try {
      await _channel.invokeMethod<void>('stopSession');
    } catch (e) {
      debugPrint('[NfcShareService] stopSession error: $e');
    }
  }
}
