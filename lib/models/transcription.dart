// =============================================================================
// NOTITIA — Modèle Transcription
// =============================================================================
class Transcription {
  final String id;
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;

  Transcription({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Crée une nouvelle transcription avec un ID basé sur le timestamp.
  factory Transcription.create({required String content, String? title}) {
    final now = DateTime.now();
    return Transcription(
      id: now.millisecondsSinceEpoch.toString(),
      title: title ?? 'Transcription ${_formatDate(now)}',
      content: content,
      createdAt: now,
      updatedAt: now,
    );
  }

  Transcription copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
  }) {
    return Transcription(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Transcription.fromJson(Map<String, dynamic> json) => Transcription(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  static String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDate => _formatDate(createdAt);
  String get formattedUpdateDate => _formatDate(updatedAt);

  String get preview {
    if (content.length <= 120) return content;
    return '${content.substring(0, 120)}…';
  }
}
