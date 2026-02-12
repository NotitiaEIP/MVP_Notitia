// =============================================================================
// NOTITIA — Service d'écoute active (Foreground Service)
//
// Maintient l'application en vie lorsque le téléphone est verrouillé ou
// l'application est en arrière-plan. Utilise un Foreground Service Android
// avec notification persistante + wake lock CPU.
// =============================================================================
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ---------------------------------------------------------------------------
// Callback top-level requis par flutter_foreground_task
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(NotitiaTaskHandler());
}

/// TaskHandler minimal — on n'a besoin que du service pour garder le process
/// en vie, la reconnaissance vocale tourne dans le main isolate.
class NotitiaTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[Notitia] Foreground task started ($starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat — rien à faire, le service tourne.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[Notitia] Foreground task destroyed (timeout=$isTimeout)');
  }
}

// ---------------------------------------------------------------------------
// Service wrapper utilisé par la couche UI
// ---------------------------------------------------------------------------
class ActiveListeningService {
  static bool _initialized = false;
  static bool _running = false;

  static bool get isRunning => _running;

  /// Initialise le service. À appeler une seule fois (idempotent).
  static void init() {
    if (_initialized) return;
    // Le foreground service n'est pertinent que sur Android (et iOS).
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notitia_active_listening',
        channelName: 'Écoute Active Notitia',
        channelDescription: 'Transcription vocale en continu',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: true,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000), // heartbeat 1 min
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// Demande les permissions nécessaires (notifications, batterie).
  static Future<void> requestPermissions() async {
    // Android 13+ : permission de notification
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Exclusion de l'optimisation batterie — critique pour le background
    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
  }

  /// Démarre le foreground service avec notification persistante.
  static Future<bool> start() async {
    init();

    if (_running) return true;

    await requestPermissions();

    final ServiceRequestResult result;
    if (await FlutterForegroundTask.isRunningService) {
      result = await FlutterForegroundTask.restartService();
    } else {
      result = await FlutterForegroundTask.startService(
        serviceId: 42,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: 'Notitia — Écoute Active',
        notificationText: 'Transcription en cours…',
        callback: startCallback,
      );
    }

    _running = result is ServiceRequestSuccess;
    debugPrint('[Notitia] Foreground service started: $_running');
    return _running;
  }

  /// Met à jour le texte de la notification (durée, etc.).
  static Future<void> updateNotification(String text) async {
    if (!_running) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Notitia — Écoute Active',
      notificationText: text,
    );
  }

  /// Arrête le foreground service.
  static Future<void> stop() async {
    if (!_running) return;
    await FlutterForegroundTask.stopService();
    _running = false;
    debugPrint('[Notitia] Foreground service stopped');
  }
}
