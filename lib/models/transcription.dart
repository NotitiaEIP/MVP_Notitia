// =============================================================================
// NOTITIA — Modèle Transcription
// =============================================================================

/// Tags possibles pour catégoriser les transcriptions.
class TranscriptionTag {
  static const String transcription = 'Transcription';
  static const String reunion = 'Réunion';
  static const String nfc = 'NFC';
  static const String widget = 'Widget';

  static const List<String> all = [transcription, reunion, nfc, widget];
}

class Transcription {
  final String id;
  String title;
  String content;
  final String tag;
  final DateTime createdAt;
  DateTime updatedAt;

  Transcription({
    required this.id,
    required this.title,
    required this.content,
    this.tag = TranscriptionTag.transcription,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Crée une nouvelle transcription avec un ID basé sur le timestamp.
  factory Transcription.create({
    required String content,
    String? title,
    String tag = TranscriptionTag.transcription,
  }) {
    final now = DateTime.now();
    return Transcription(
      id: now.millisecondsSinceEpoch.toString(),
      title: title ?? 'Transcription ${_formatDate(now)}',
      content: content,
      tag: tag,
      createdAt: now,
      updatedAt: now,
    );
  }

  Transcription copyWith({
    String? title,
    String? content,
    String? tag,
    DateTime? updatedAt,
  }) {
    return Transcription(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tag: tag ?? this.tag,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'tag': tag,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Transcription.fromJson(Map<String, dynamic> json) => Transcription(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    tag: json['tag'] as String? ?? TranscriptionTag.transcription,
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
