// =============================================================================
// NOTITIA — Modèle Mind Map
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';

/// Types de nœuds pour la mind map
enum MindMapNodeType {
  root,        // Sujet principal
  topic,       // Thème important
  subtopic,    // Sous-thème
  idea,        // Idée
  action,      // Action à faire
  question,    // Question soulevée
  decision,    // Décision prise
  person,      // Personne mentionnée
  date,        // Date/échéance
  location,    // Lieu
  emotion,     // Sentiment/émotion
  reference,   // Référence externe
}

/// Extension pour les propriétés visuelles des types de nœuds
extension MindMapNodeTypeExtension on MindMapNodeType {
  String get label {
    switch (this) {
      case MindMapNodeType.root: return '🎯 Sujet';
      case MindMapNodeType.topic: return '📌 Thème';
      case MindMapNodeType.subtopic: return '📎 Sous-thème';
      case MindMapNodeType.idea: return '💡 Idée';
      case MindMapNodeType.action: return '✅ Action';
      case MindMapNodeType.question: return '❓ Question';
      case MindMapNodeType.decision: return '⚡ Décision';
      case MindMapNodeType.person: return '👤 Personne';
      case MindMapNodeType.date: return '📅 Date';
      case MindMapNodeType.location: return '📍 Lieu';
      case MindMapNodeType.emotion: return '💭 Sentiment';
      case MindMapNodeType.reference: return '🔗 Référence';
    }
  }
  
  Color get color {
    switch (this) {
      case MindMapNodeType.root: return const Color(0xFFFF0178);      // Neon Pink
      case MindMapNodeType.topic: return const Color(0xFF00E5FF);     // Neon Cyan
      case MindMapNodeType.subtopic: return const Color(0xFF7B68EE);  // Medium Purple
      case MindMapNodeType.idea: return const Color(0xFFFFD700);      // Gold
      case MindMapNodeType.action: return const Color(0xFF00FF88);    // Neon Green
      case MindMapNodeType.question: return const Color(0xFFFF6B6B);  // Coral
      case MindMapNodeType.decision: return const Color(0xFFFF9500);  // Orange
      case MindMapNodeType.person: return const Color(0xFF9B59B6);    // Amethyst
      case MindMapNodeType.date: return const Color(0xFF3498DB);      // Blue
      case MindMapNodeType.location: return const Color(0xFF1ABC9C);  // Turquoise
      case MindMapNodeType.emotion: return const Color(0xFFE91E63);   // Pink
      case MindMapNodeType.reference: return const Color(0xFF95A5A6); // Gray
    }
  }
  
  IconData get icon {
    switch (this) {
      case MindMapNodeType.root: return Icons.hub;
      case MindMapNodeType.topic: return Icons.topic;
      case MindMapNodeType.subtopic: return Icons.subdirectory_arrow_right;
      case MindMapNodeType.idea: return Icons.lightbulb;
      case MindMapNodeType.action: return Icons.check_circle;
      case MindMapNodeType.question: return Icons.help;
      case MindMapNodeType.decision: return Icons.flash_on;
      case MindMapNodeType.person: return Icons.person;
      case MindMapNodeType.date: return Icons.calendar_today;
      case MindMapNodeType.location: return Icons.place;
      case MindMapNodeType.emotion: return Icons.sentiment_satisfied;
      case MindMapNodeType.reference: return Icons.link;
    }
  }
}

/// Nœud de la mind map
class MindMapNode {
  final String id;
  final String label;
  final String? description;
  final MindMapNodeType type;
  final List<String> tags;
  final int priority; // 1-5, 5 = très important
  final List<MindMapNode> children;
  
  // Position pour le rendu (calculée dynamiquement)
  double? x;
  double? y;
  
  MindMapNode({
    required this.id,
    required this.label,
    this.description,
    required this.type,
    this.tags = const [],
    this.priority = 3,
    this.children = const [],
    this.x,
    this.y,
  });
  
  factory MindMapNode.fromJson(Map<String, dynamic> json) {
    return MindMapNode(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      type: _parseNodeType(json['type'] as String?),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      priority: json['priority'] as int? ?? 3,
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => MindMapNode.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'description': description,
    'type': type.name,
    'tags': tags,
    'priority': priority,
    'children': children.map((c) => c.toJson()).toList(),
  };
  
  static MindMapNodeType _parseNodeType(String? type) {
    if (type == null) return MindMapNodeType.idea;
    try {
      return MindMapNodeType.values.firstWhere((t) => t.name == type);
    } catch (_) {
      return MindMapNodeType.idea;
    }
  }
  
  /// Compte total des nœuds (incluant enfants)
  int get totalNodes {
    return 1 + children.fold(0, (sum, child) => sum + child.totalNodes);
  }
  
  /// Profondeur maximale
  int get maxDepth {
    if (children.isEmpty) return 1;
    return 1 + children.map((c) => c.maxDepth).reduce((a, b) => a > b ? a : b);
  }
}

/// Mind Map complète
class MindMap {
  final String id;
  final String title;
  final String sourceTranscriptionId;
  final DateTime createdAt;
  final MindMapNode root;
  final Map<String, dynamic> metadata;
  
  MindMap({
    required this.id,
    required this.title,
    required this.sourceTranscriptionId,
    required this.createdAt,
    required this.root,
    this.metadata = const {},
  });
  
  factory MindMap.fromJson(Map<String, dynamic> json) {
    return MindMap(
      id: json['id'] as String,
      title: json['title'] as String,
      sourceTranscriptionId: json['sourceTranscriptionId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      root: MindMapNode.fromJson(json['root'] as Map<String, dynamic>),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sourceTranscriptionId': sourceTranscriptionId,
    'createdAt': createdAt.toIso8601String(),
    'root': root.toJson(),
    'metadata': metadata,
  };
  
  String toJsonString() => jsonEncode(toJson());
  
  factory MindMap.fromJsonString(String jsonStr) {
    return MindMap.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }
  
  int get totalNodes => root.totalNodes;
  int get maxDepth => root.maxDepth;
}
