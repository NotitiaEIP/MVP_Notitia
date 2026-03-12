import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_recording_service.dart';

const String _iOSAppGroupId = 'group.com.example.notitia';

class HomeWidgetService {
  HomeWidgetService._();

  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(_iOSAppGroupId);
    await checkPendingTranscription();
  }
  static Future<bool> checkPendingTranscription() async {
    try {
      return await WidgetRecordingService.instance.processPendingTranscription();
    } catch (e) {
      debugPrint('[HomeWidget] Erreur vérification pending transcription: $e');
      return false;
    }
  }
}
