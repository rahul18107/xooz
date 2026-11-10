class Transcript {
  final String id;
  final String userId;
  final String text;
  final String status;
  final List<Map<String, dynamic>> speakerLabels;
  final Map<String, String> speakerNames;
  final DateTime recordedAt;
  final String? summary;
  final String? title;
  final bool starred;
  final String? audioUrl;

  Transcript({
    required this.id,
    required this.userId,
    required this.text,
    this.status = 'completed',
    required this.speakerLabels,
    this.speakerNames = const {},
    required this.recordedAt,
    this.summary,
    this.title,
    this.starred = false,
    this.audioUrl,
  });

  factory Transcript.fromJson(Map<String, dynamic> json) {
    return Transcript(
      id: json['id'],
      userId: json['user_id'],
      text: json['text'],
      status: json['status'] as String? ?? 'completed',
      speakerLabels: List<Map<String, dynamic>>.from(
        json['speaker_labels'] ?? [],
      ),
      speakerNames: Map<String, String>.from(json['speaker_names'] ?? {}),
      recordedAt: DateTime.parse(json['recorded_at']).toLocal(),
      summary: json['summary'],
      title: json['title'],
      starred: json['starred'] == true,
      audioUrl: json['audio_url'],
    );
  }

  Transcript copyWith({String? title, String? summary, bool? starred, String? audioUrl, Map<String, String>? speakerNames, bool clearSummary = false}) {
    return Transcript(
      id: id,
      userId: userId,
      text: text,
      status: status,
      speakerLabels: speakerLabels,
      speakerNames: speakerNames ?? this.speakerNames,
      recordedAt: recordedAt,
      title: title ?? this.title,
      summary: clearSummary ? null : summary ?? this.summary,
      starred: starred ?? this.starred,
      audioUrl: audioUrl ?? this.audioUrl,
    );
  }

  String speakerDisplayName(String label) => speakerNames[label] ?? 'Speaker $label';

  /// Short one-liner shown as the heading. Prefers the AI-generated title,
  /// falls back to the first sentence of the transcript.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return headline;
  }

  /// One-liner headline: the first sentence (or first ~90 chars).
  String get headline {
    final t = text.trim();
    if (t.isEmpty) return 'Recording';

    final sentenceMatch = RegExp(r'^(.+?[.!?])').firstMatch(t);
    var h = sentenceMatch?.group(1) ?? t;

    if (h.length <= 90) return h;

    final cut = t.substring(0, 90);
    final lastSpace = cut.lastIndexOf(' ');
    return '${cut.substring(0, lastSpace > 40 ? lastSpace : 90)}…';
  }

  /// Chip label like "Sat, Oct 31 10:14 PM".
  String get dateChipLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final d = recordedAt;
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day} $timeLabel';  }

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
