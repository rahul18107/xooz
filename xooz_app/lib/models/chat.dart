class ChatReply {
  final String sessionId;
  final String reply;
  final List<String> sourceIds;

  ChatReply({
    required this.sessionId,
    required this.reply,
    this.sourceIds = const [],
  });
}

class ProfileInfo {
  final String id;
  final String? displayName;
  final String? email;
  final String plan;
  final String timezone;
  final bool dailyRecapEnabled;
  final int dailyRecapHour;
  final List<String> transcriptionVocabulary;

  ProfileInfo({
    required this.id,
    required this.displayName,
    required this.email,
    required this.plan,
    required this.timezone,
    this.dailyRecapEnabled = false,
    this.dailyRecapHour = 21,
    this.transcriptionVocabulary = const [],
  });

  factory ProfileInfo.fromJson(Map<String, dynamic> json) {
    return ProfileInfo(
      id: json['id'],
      displayName: json['display_name'],
      email: json['email'],
      plan: json['plan'] ?? 'free',
      timezone: json['timezone'] ?? 'UTC',
      dailyRecapEnabled: json['daily_recap_enabled'] == true,
      dailyRecapHour: (json['daily_recap_hour'] as num?)?.toInt() ?? 21,
      transcriptionVocabulary: (json['transcription_vocabulary'] as List? ?? [])
          .whereType<String>()
          .toList(),
    );
  }
}

class UsageInfo {
  final String plan;
  final double minutesUsed;
  final double minutesLimit;
  final int recordingsCount;

  UsageInfo({
    required this.plan,
    required this.minutesUsed,
    required this.minutesLimit,
    required this.recordingsCount,
  });

  factory UsageInfo.fromJson(Map<String, dynamic> json) {
    final used = json['minutes_used'];
    final limit = json['minutes_limit'];
    return UsageInfo(
      plan: json['plan'] ?? 'free',
      minutesUsed: used is num ? used.toDouble() : 0.0,
      minutesLimit: limit is num ? limit.toDouble() : 0.0,
      recordingsCount: json['recordings_count'] ?? 0,
    );
  }

  String get label =>
      'Recorded ${minutesUsed.toStringAsFixed(0)} min of ${minutesLimit.toStringAsFixed(0)}';
}

class SearchResults {
  final List transcripts; // List<Transcript>
  final List digests; // List<Digest>
  final List tasks; // List<Task>

  SearchResults({
    required this.transcripts,
    required this.digests,
    required this.tasks,
  });

  bool get isEmpty => transcripts.isEmpty && digests.isEmpty && tasks.isEmpty;

  int get totalCount => transcripts.length + digests.length + tasks.length;
}

class ActivityFeed {
  final List needsAttention; // List<Transcript>
  final List today; // List<Transcript>

  ActivityFeed({required this.needsAttention, required this.today});

  factory ActivityFeed.fromJson(Map<String, dynamic> json) {
    return ActivityFeed(
      needsAttention: json['needs_attention'] ?? [],
      today: json['today'] ?? [],
    );
  }
}
class ChatThread {
  final String sessionId;
  final String title;
  final DateTime updatedAt;

  const ChatThread({required this.sessionId, required this.title, required this.updatedAt});

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        sessionId: json['session_id'] as String,
        title: json['title'] as String? ?? 'Chat',
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      );
}
