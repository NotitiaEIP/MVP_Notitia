// =============================================================================
// NOTITIA — Modèle Réunion
// =============================================================================

/// Représente un participant à une réunion.
class MeetingParticipant {
  final String id;
  final String name;
  final String ipAddress;

  MeetingParticipant({
    required this.id,
    required this.name,
    required this.ipAddress,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ipAddress': ipAddress,
  };

  factory MeetingParticipant.fromJson(Map<String, dynamic> json) =>
      MeetingParticipant(
        id: json['id'] as String,
        name: json['name'] as String,
        ipAddress: json['ipAddress'] as String,
      );
}

/// Représente une réunion avec ses métadonnées.
class Meeting {
  final String id;
  final String hostName;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<MeetingParticipant> participants;
  String? transcriptionId;

  Meeting({
    required this.id,
    required this.hostName,
    required this.startedAt,
    this.endedAt,
    required this.participants,
    this.transcriptionId,
  });

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hostName': hostName,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'participants': participants.map((p) => p.toJson()).toList(),
    'transcriptionId': transcriptionId,
  };

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
    id: json['id'] as String,
    hostName: json['hostName'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: json['endedAt'] != null
        ? DateTime.parse(json['endedAt'] as String)
        : null,
    participants: (json['participants'] as List<dynamic>)
        .map((p) => MeetingParticipant.fromJson(p as Map<String, dynamic>))
        .toList(),
    transcriptionId: json['transcriptionId'] as String?,
  );

  static String formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
