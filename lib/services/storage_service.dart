// =============================================================================
// NOTITIA — Service de stockage local (JSON)
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transcription.dart';

class StorageService {
  static const String _fileName = 'notitia_transcriptions.json';
  static List<Transcription>? _cache;

  static Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  /// Charge toutes les transcriptions (les plus récentes en premier).
  static Future<List<Transcription>> loadAll() async {
    if (_cache != null) return List.from(_cache!);
    try {
      final path = await _filePath;
      final file = File(path);
      if (!file.existsSync()) {
        _cache = [];
        return [];
      }
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _cache =
          jsonList
              .map((j) => Transcription.fromJson(j as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.from(_cache!);
    } catch (e) {
      debugPrint('Error loading transcriptions: $e');
      _cache = [];
      return [];
    }
  }

  static Future<void> _saveAll(List<Transcription> transcriptions) async {
    _cache = List.from(transcriptions);
    final path = await _filePath;
    final file = File(path);
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(transcriptions.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString);
  }

  /// Sauvegarde (insertion ou mise à jour) une transcription.
  static Future<void> save(Transcription transcription) async {
    final all = await loadAll();
    final index = all.indexWhere((t) => t.id == transcription.id);
    if (index >= 0) {
      all[index] = transcription;
    } else {
      all.insert(0, transcription);
    }
    await _saveAll(all);
  }

  /// Supprime une transcription par ID.
  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((t) => t.id == id);
    await _saveAll(all);
  }

  /// Force le prochain loadAll à relire le disque.
  static void invalidateCache() => _cache = null;
}
