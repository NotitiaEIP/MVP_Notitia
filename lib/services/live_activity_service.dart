// =============================================================================
// NOTITIA — Live Activity Service (iOS uniquement)
//
// Pilote la Live Activity / Dynamic Island pendant un enregistrement.
// Utilise le plugin `live_activities` pour créer, mettre à jour et terminer
// l'activité, et surveille le flag "stop" posé par le StopTranscriptionIntent
// côté Swift (via App Group UserDefaults).
// =============================================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:flutter_app_group_directory/flutter_app_group_directory.dart';

const String _kAppGroupId = 'group.com.example.notitia';

class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  final LiveActivities _plugin = LiveActivities();
  String? _activityId;
  Timer? _stopPollTimer;

  /// Callback déclenché quand l'utilisateur appuie sur Stop depuis la
  /// Live Activity (Dynamic Island / Lock Screen).
  VoidCallback? onStopRequested;

  /// Démarre une Live Activity avec le titre donné.
  Future<void> start(String noteTitle) async {
    if (!Platform.isIOS) return;

    try {
      debugPrint('[LiveActivity] Initialisation avec appGroupId=$_kAppGroupId');
      await _plugin.init(appGroupId: _kAppGroupId);

      final enabled = await _plugin.areActivitiesEnabled();
      debugPrint('[LiveActivity] areActivitiesEnabled = $enabled');
      if (!enabled) {
        debugPrint('[LiveActivity] ⚠ Live Activities désactivées par l\'utilisateur !');
        return;
      }

      _activityId = await _plugin.createActivity(
        'notitia-recording',
        {
          'noteTitle': noteTitle,
          'duration': '00:00',
          'isRecording': 'true',
        },
        removeWhenAppIsKilled: true,
        iOSEnableRemoteUpdates: false,
      );
      debugPrint('[LiveActivity] ✓ Démarrée avec id=$_activityId');
      debugPrint('[LiveActivity] Démarrée : $_activityId');

      // Remettre le flag stop à false au démarrage
      await _clearStopFlag();

      // Commencer à surveiller le flag stop posé par le widget Swift
      _startStopPolling();
    } catch (e) {
      debugPrint('[LiveActivity] Erreur start : $e');
    }
  }

  /// Met à jour la durée affichée.
  Future<void> updateDuration(String formattedDuration) async {
    if (!Platform.isIOS || _activityId == null) return;
    try {
      await _plugin.updateActivity(
        _activityId!,
        {
          'duration': formattedDuration,
          'isRecording': 'true',
        },
      );
    } catch (e) {
      debugPrint('[LiveActivity] Erreur update : $e');
    }
  }

  /// Termine la Live Activity.
  Future<void> stop() async {
    if (!Platform.isIOS) return;
    _stopPollTimer?.cancel();
    _stopPollTimer = null;

    if (_activityId != null) {
      try {
        await _plugin.endActivity(_activityId!);
        debugPrint('[LiveActivity] Terminée : $_activityId');
      } catch (e) {
        debugPrint('[LiveActivity] Erreur stop : $e');
      }
      _activityId = null;
    }

    await _clearStopFlag();
  }

  // ---------------------------------------------------------------------------
  // Surveillance du flag "stop" posé par le StopTranscriptionIntent Swift
  // ---------------------------------------------------------------------------
  void _startStopPolling() {
    _stopPollTimer?.cancel();
    _stopPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (await _isStopRequested()) {
        debugPrint('[LiveActivity] Stop demandé depuis la Live Activity !');
        await _clearStopFlag();
        _stopPollTimer?.cancel();
        _stopPollTimer = null;
        onStopRequested?.call();
      }
    });
  }

  Future<bool> _isStopRequested() async {
    try {
      final dir = await FlutterAppGroupDirectory.getAppGroupDirectory(_kAppGroupId);
      if (dir == null) return false;
      final flagFile = File('${dir.path}/live_activity_stop_requested');
      if (await flagFile.exists()) {
        await flagFile.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearStopFlag() async {
    try {
      final dir = await FlutterAppGroupDirectory.getAppGroupDirectory(_kAppGroupId);
      if (dir == null) return;
      final flagFile = File('${dir.path}/live_activity_stop_requested');
      if (await flagFile.exists()) {
        await flagFile.delete();
      }
    } catch (_) {}
  }
}
