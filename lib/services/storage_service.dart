// =============================================================================
// NOTITIA — Service de stockage local (JSON)
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mind_map.dart';
import '../models/transcription.dart';

class StorageService {
  // ---------------------------------------------------------------------------
  // Transcriptions
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Mind Maps
  // ---------------------------------------------------------------------------
  static const String _mindMapsFileName = 'notitia_mindmaps.json';
  static List<MindMap>? _mindMapsCache;

  static Future<String> get _mindMapsFilePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_mindMapsFileName';
  }

  /// Charge toutes les mind maps sauvegardées (les plus récentes en premier).
  static Future<List<MindMap>> loadAllMindMaps() async {
    if (_mindMapsCache != null) return List.from(_mindMapsCache!);
    try {
      final path = await _mindMapsFilePath;
      final file = File(path);
      if (!file.existsSync()) {
        _mindMapsCache = [];
        return [];
      }
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _mindMapsCache =
          jsonList
              .map((j) => MindMap.fromJson(j as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.from(_mindMapsCache!);
    } catch (e) {
      debugPrint('Error loading mind maps: $e');
      _mindMapsCache = [];
      return [];
    }
  }

  static Future<void> _saveAllMindMaps(List<MindMap> mindMaps) async {
    _mindMapsCache = List.from(mindMaps);
    final path = await _mindMapsFilePath;
    final file = File(path);
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(mindMaps.map((m) => m.toJson()).toList());
    await file.writeAsString(jsonString);
  }

  /// Sauvegarde (insertion ou mise à jour) une mind map.
  static Future<void> saveMindMap(MindMap mindMap) async {
    final all = await loadAllMindMaps();
    final index = all.indexWhere((m) => m.id == mindMap.id);
    if (index >= 0) {
      all[index] = mindMap;
    } else {
      all.insert(0, mindMap);
    }
    await _saveAllMindMaps(all);
  }

  /// Supprime une mind map par ID.
  static Future<void> deleteMindMap(String id) async {
    final all = await loadAllMindMaps();
    all.removeWhere((m) => m.id == id);
    await _saveAllMindMaps(all);
  }

  /// Force le prochain loadAllMindMaps à relire le disque.
  static void invalidateMindMapsCache() => _mindMapsCache = null;
}
