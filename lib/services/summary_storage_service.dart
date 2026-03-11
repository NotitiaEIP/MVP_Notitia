// =============================================================================
// NOTITIA — Stockage des résumés riches (JSON local)
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/rich_summary.dart';

class SummaryStorageService {
  static const String _fileName = 'notitia_summaries.json';
  static Map<String, RichSummary>? _cache;

  static Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  /// Charge le résumé pour une transcription donnée (null si non existant).
  static Future<RichSummary?> load(String transcriptionId) async {
    final all = await _loadAll();
    return all[transcriptionId];
  }

  /// Sauvegarde un résumé riche.
  static Future<void> save(RichSummary summary) async {
    final all = await _loadAll();
    all[summary.transcriptionId] = summary;
    _cache = all;
    await _writeAll(all);
  }

  /// Supprime le résumé d'une transcription (quand on regénère).
  static Future<void> delete(String transcriptionId) async {
    final all = await _loadAll();
    all.remove(transcriptionId);
    _cache = all;
    await _writeAll(all);
  }

  static Future<Map<String, RichSummary>> _loadAll() async {
    if (_cache != null) return Map.from(_cache!);
    try {
      final path = await _filePath;
      final file = File(path);
      if (!file.existsSync()) {
        _cache = {};
        return {};
      }
      final jsonString = await file.readAsString();
      final Map<String, dynamic> jsonMap =
          json.decode(jsonString) as Map<String, dynamic>;
      _cache = jsonMap.map((key, value) =>
          MapEntry(key, RichSummary.fromJson(value as Map<String, dynamic>)));
      return Map.from(_cache!);
    } catch (e) {
      debugPrint('[SummaryStorage] Erreur chargement: $e');
      _cache = {};
      return {};
    }
  }

  static Future<void> _writeAll(Map<String, RichSummary> all) async {
    final path = await _filePath;
    final file = File(path);
    final jsonMap = all.map((key, value) => MapEntry(key, value.toJson()));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }
}
