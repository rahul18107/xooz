class ChatReply {
  final String sessionId;
  final String reply;

  ChatReply({required this.sessionId, required this.reply});
}

class ProfileInfo {
  final String id;
  final String? displayName;
  final String? email;
  final String plan;
  final String timezone;

  ProfileInfo({
    required this.id,
    required this.displayName,
    required this.email,
    required this.plan,
    required this.timezone,
  });

  factory ProfileInfo.fromJson(Map<String, dynamic> json) {
    return ProfileInfo(
      id: json['id'],
      displayName: json['display_name'],
      email: json['email'],
      plan: json['plan'] ?? 'free',
      timezone: json['timezone'] ?? 'UTC',
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

  bool get isEmpty =>
      transcripts.isEmpty && digests.isEmpty && tasks.isEmpty;

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
