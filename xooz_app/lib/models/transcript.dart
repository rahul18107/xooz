class Transcript {
  final String id;
  final String userId;
  final String text;
  final List<Map<String, dynamic>> speakerLabels;
  final DateTime recordedAt;

  Transcript({
    required this.id,
    required this.userId,
    required this.text,
    required this.speakerLabels,
    required this.recordedAt,
  });

  factory Transcript.fromJson(Map<String, dynamic> json) {
    return Transcript(
      id: json['id'],
      userId: json['user_id'],
      text: json['text'],
      speakerLabels: List<Map<String, dynamic>>.from(json['speaker_labels'] ?? []),
      recordedAt: DateTime.parse(json['recorded_at']),
    );
  }

  String get timeLabel {
    final h = recordedAt.hour;
    final m = recordedAt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }

  String get shortText {
    if (text.length <= 50) return text;
    return '${text.substring(0, 50)}...';
  }
}